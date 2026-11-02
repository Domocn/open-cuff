"""Async Bluetooth LE client for BP2-family monitors.

Uses bleak, so it runs on Windows, macOS, Linux and a Raspberry Pi.
"""
from __future__ import annotations

import asyncio
import logging

from bleak import BleakClient, BleakScanner
from bleak.backends.device import BLEDevice

from . import protocol as p

SERVICE_UUID = "14839ac4-7d7e-415c-9a42-167340cf2339"
WRITE_UUID = "8b00ace7-eb0b-49b0-bbe9-9aee0a26e1a3"
NOTIFY_UUID = "0734594a-a8e7-4b1a-a6b1-cd5243059a57"
NAME_PREFIXES = ("BP2",)

log = logging.getLogger(__name__)


async def find_bp2(timeout: float = 15.0, address: str | None = None) -> BLEDevice | None:
    """Find a monitor by address, or the first device named BP2... or advertising the BP2 service."""
    if address:
        return await BleakScanner.find_device_by_address(address, timeout=timeout)

    def match(dev, adv):
        name = dev.name or adv.local_name or ""
        return "BP2" in name.upper() or SERVICE_UUID in [u.lower() for u in adv.service_uuids]

    return await BleakScanner.find_device_by_filter(match, timeout=timeout)


class BP2Client:
    def __init__(self, device: BLEDevice | str, timeout: float = 10.0) -> None:
        self.device = device
        self.timeout = timeout
        self._client: BleakClient | None = None
        self._parser = p.FrameParser()
        self._queue: asyncio.Queue[p.Frame] = asyncio.Queue()
        self._seq = 0

    async def __aenter__(self) -> "BP2Client":
        self._client = BleakClient(self.device, timeout=20.0)
        await self._client.connect()
        await self._client.start_notify(NOTIFY_UUID, self._on_notify)
        return self

    async def __aexit__(self, *exc) -> None:
        if self._client and self._client.is_connected:
            try:
                await self._client.stop_notify(NOTIFY_UUID)
            except Exception:  # noqa: BLE001
                pass
            await self._client.disconnect()

    def _on_notify(self, _handle, data: bytearray) -> None:
        log.debug("rx %s", bytes(data).hex())
        for frame in self._parser.feed(bytes(data)):
            self._queue.put_nowait(frame)

    async def request(self, cmd: int, payload: bytes = b"") -> p.Frame:
        assert self._client is not None
        frame = p.build_frame(cmd, payload, self._seq)
        self._seq = (self._seq + 1) % 255
        log.debug("tx %s", frame.hex())
        # many adapters only take 20 bytes per write
        for i in range(0, len(frame), 20):
            await self._client.write_gatt_char(WRITE_UUID, frame[i:i + 20], response=False)
        loop = asyncio.get_running_loop()
        deadline = loop.time() + self.timeout
        while True:
            left = deadline - loop.time()
            if left <= 0:
                raise TimeoutError(f"no reply to command 0x{cmd:02X}")
            reply = await asyncio.wait_for(self._queue.get(), left)
            if reply.cmd == cmd:
                return reply
            log.debug("ignoring reply to 0x%02X while waiting for 0x%02X", reply.cmd, cmd)

    async def get_info(self) -> bytes:
        return (await self.request(p.CMD_GET_INFO)).payload

    async def sync_time(self) -> bool:
        return (await self.request(p.CMD_SYNC_TIME, p.sync_time_payload())).ok

    async def list_files(self) -> list[str]:
        reply = await self.request(p.CMD_FILE_LIST)
        return p.parse_file_list(reply.payload)

    async def read_file(self, name: str) -> bytes:
        raw = name.encode("ascii")[:15].ljust(16, b"\x00") + (0).to_bytes(4, "little")
        start = await self.request(p.CMD_FILE_START, raw)
        if not start.ok:
            raise IOError(f"monitor refused to open {name} (code {start.pkg_type})")
        size = int.from_bytes(start.payload[:4], "little")
        data = bytearray()
        try:
            while len(data) < size:
                chunk = await self.request(p.CMD_FILE_DATA, len(data).to_bytes(4, "little"))
                if not chunk.payload:
                    break
                data += chunk.payload
        finally:
            await self.request(p.CMD_FILE_END)
        return bytes(data[:size])

    async def readings(self) -> list[p.BpReading]:
        out = []
        for name in await self.list_files():
            reading = p.parse_bp_file(name, await self.read_file(name))
            if reading:
                out.append(reading)
        return sorted(out, key=lambda r: r.time)
