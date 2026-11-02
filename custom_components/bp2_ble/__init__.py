"""BP2 blood pressure monitor over Bluetooth (through any Home Assistant Bluetooth adapter or ESPHome proxy).

When the monitor advertises (its Bluetooth comes on after a measurement or when the menu and Start/Stop buttons are
tapped together), Home Assistant connects, lists the stored files, downloads any it has not seen before and fires a
`bp2_ble_reading` event for each new reading. The newest reading is also shown as sensors.
"""
from __future__ import annotations

import asyncio
import logging
import time
from datetime import timedelta

from bleak_retry_connector import BleakClientWithServiceCache, establish_connection
from homeassistant.components import bluetooth
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import CONF_ADDRESS, Platform
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import aoj, protocol as p
from .const import DOMAIN, EVENT_READING, NEW_READING_MAX_AGE_H, NOTIFY_UUID, WRITE_UUID

_LOGGER = logging.getLogger(__name__)
PLATFORMS = [Platform.SENSOR]
SIGNAL_UPDATE = f"{DOMAIN}_update_{{}}"
MIN_GAP_S = 20  # do not reconnect more often than this
RECENT_MAX = 200


class BP2Device:
    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self.hass = hass
        self.entry = entry
        self.address: str = entry.data[CONF_ADDRESS]
        self.store = Store(hass, 1, f"{DOMAIN}.{self.address.replace(':', '').lower()}")
        self.seen: set[str] = set()
        self.latest: dict | None = None
        self.recent: list[dict] = []  # every reading seen (newest last), for phones that copy them to Health Connect
        self.last_sync: str | None = None
        self.last_error: str | None = None
        self._lock = asyncio.Lock()
        self._last_try = 0.0
        self._first_sync_done = False

    async def async_load(self) -> None:
        data = await self.store.async_load() or {}
        self.seen = set(data.get("seen", []))
        self.latest = data.get("latest")
        self.recent = data.get("recent", [])
        self._first_sync_done = bool(data.get("first_sync_done"))

    async def _save(self) -> None:
        await self.store.async_save({"seen": sorted(self.seen), "latest": self.latest, "recent": self.recent,
                                     "first_sync_done": self._first_sync_done})

    @callback
    def on_advertisement(self, service_info: bluetooth.BluetoothServiceInfoBleak, change: bluetooth.BluetoothChange) -> None:
        if self._lock.locked() or time.monotonic() - self._last_try < MIN_GAP_S:
            return
        self._last_try = time.monotonic()
        self.entry.async_create_background_task(self.hass, self.async_sync(), f"{DOMAIN} sync {self.address}")

    async def async_sync(self) -> None:
        async with self._lock:
            device = bluetooth.async_ble_device_from_address(self.hass, self.address, connectable=True)
            if device is None:
                return
            try:
                new = await self._download(device)
                self.last_error = None
            except Exception as err:  # noqa: BLE001
                self.last_error = str(err)
                _LOGGER.warning("BP2 sync failed: %s", err)
                async_dispatcher_send(self.hass, SIGNAL_UPDATE.format(self.entry.entry_id))
                return
            self.last_sync = dt_util.now().isoformat(timespec="seconds")
            cutoff = dt_util.now() - timedelta(hours=NEW_READING_MAX_AGE_H)
            for r in new:
                when = r.time.replace(tzinfo=dt_util.DEFAULT_TIME_ZONE)
                data = {"address": self.address, "file": r.file, "time": when.isoformat(), "systolic": r.systolic,
                        "diastolic": r.diastolic, "mean": r.mean, "pulse": r.pulse, "irregular": r.irregular}
                if self.latest is None or data["time"] >= self.latest["time"]:
                    self.latest = data
                self.recent.append({k: data[k] for k in ("file", "time", "systolic", "diastolic", "pulse", "irregular")})
                # on the very first sync only recent readings count as new; older ones are history
                if self._first_sync_done or when >= cutoff:
                    self.hass.bus.async_fire(EVENT_READING, data)
            self._first_sync_done = True
            self.recent = sorted(self.recent, key=lambda r: r["time"])[-RECENT_MAX:]
            await self._save()
            async_dispatcher_send(self.hass, SIGNAL_UPDATE.format(self.entry.entry_id))

    async def _download(self, device) -> list[p.BpReading]:
        client = await establish_connection(BleakClientWithServiceCache, device, "BP2", max_attempts=3)
        parser = p.FrameParser()
        queue: asyncio.Queue[p.Frame] = asyncio.Queue()
        seq = 0

        raw: list[str] = []

        def notify(_h, data: bytearray) -> None:
            raw.append(bytes(data).hex())
            _LOGGER.debug("BP2 rx %s", bytes(data).hex())
            for frame in parser.feed(bytes(data)):
                queue.put_nowait(frame)

        async def request(cmd: int, payload: bytes = b"") -> p.Frame:
            nonlocal seq
            frame = p.build_frame(cmd, payload, seq)
            seq = (seq + 1) % 255
            for i in range(0, len(frame), 20):
                await client.write_gatt_char(write_uuid, frame[i:i + 20], response=False)
            while True:
                reply = await asyncio.wait_for(queue.get(), 10)
                if reply.cmd == cmd:
                    return reply

        out: list[p.BpReading] = []
        try:
            notify_uuid, write_uuid = _pick_channels(client)
            await client.start_notify(notify_uuid, notify)
            if notify_uuid.lower() != NOTIFY_UUID:
                await client.stop_notify(notify_uuid)
                return await self._download_aoj(client)
            # keep the monitor clock right so readings are stamped correctly
            await request(p.CMD_SYNC_TIME, p.sync_time_payload(dt_util.now().replace(tzinfo=None)))
            names = p.parse_file_list((await request(p.CMD_FILE_LIST)).payload)
            for name in names:
                if name in self.seen:
                    continue
                start = await request(p.CMD_FILE_START, name.encode("ascii")[:15].ljust(16, b"\x00") + bytes(4))
                if not start.ok:
                    continue
                size = int.from_bytes(start.payload[:4], "little")
                buf = bytearray()
                try:
                    while len(buf) < size:
                        chunk = await request(p.CMD_FILE_DATA, len(buf).to_bytes(4, "little"))
                        if not chunk.payload:
                            break
                        buf += chunk.payload
                finally:
                    await request(p.CMD_FILE_END)
                reading = p.parse_bp_file(name, bytes(buf[:size]))
                self.seen.add(name)
                if reading:
                    out.append(reading)
        finally:
            await client.disconnect()
        return sorted(out, key=lambda r: r.time)

    async def _download_aoj(self, client) -> list[p.BpReading]:
        """AOJ-family monitors (OxiPro BP2): read-only (memory is never cleared)."""
        parser = aoj.FrameParser()
        queue: asyncio.Queue[aoj.Frame] = asyncio.Queue()

        def notify(_h, data: bytearray) -> None:
            _LOGGER.debug("BP2 rx %s", bytes(data).hex())
            for frame in parser.feed(bytes(data)):
                queue.put_nowait(frame)

        async def send(frame: bytes) -> None:
            _LOGGER.debug("BP2 tx %s", frame.hex())
            await client.write_gatt_char(aoj.WRITE_UUID, frame, response=False)

        async def drain(seconds: float) -> list[aoj.Frame]:
            got = []
            try:
                while True:
                    got.append(await asyncio.wait_for(queue.get(), seconds))
            except asyncio.TimeoutError:
                return got

        if not any(k.count("-") == 3 for k in self.seen):
            # first AOJ download: the monitor's stored history is not announced as new readings
            self._first_sync_done = False
        await client.start_notify(aoj.NOTIFY_UUID, notify)
        await send(aoj.bt_status())
        await drain(1.5)
        await send(aoj.get_serial())
        await drain(1.5)
        await send(aoj.get_system_info())
        await drain(1.5)
        await send(aoj.get_data())
        out: list[p.BpReading] = []
        replies = 0
        while True:
            try:
                frame = await asyncio.wait_for(queue.get(), 6)
            except asyncio.TimeoutError:
                break
            replies += 1
            if frame.cmd not in aoj.READING_CMDS:
                _LOGGER.debug("BP2 reply %02x %s", frame.cmd, frame.data.hex())
                continue
            await send(aoj.ack())
            r = aoj.parse_reading(frame.data)
            if r is None or r.key in self.seen:
                continue
            self.seen.add(r.key)
            out.append(p.BpReading(file=r.key, time=r.time, systolic=r.systolic, diastolic=r.diastolic, mean=None,
                                   pulse=r.pulse, status=0, irregular=r.irregular))
        _LOGGER.info("BP2 sync: %d replies, %d new reading(s)", replies, len(out))
        return out


_STANDARD = ("00001800", "00001801", "0000180a", "0000180f")


def _pick_channels(client) -> tuple[str, str]:
    """Use the documented UUIDs when present, otherwise the first vendor service with a notify and a write characteristic.

    Firmware varies between brands of the same monitor, so the full layout is logged to help support new variants.
    """
    notify = write = None
    for service in client.services:
        chars = ", ".join(f"{c.uuid}[{'/'.join(c.properties)}]" for c in service.characteristics)
        _LOGGER.debug("BP2 service %s: %s", service.uuid, chars)
    for service in client.services:
        for c in service.characteristics:
            if c.uuid.lower() == NOTIFY_UUID:
                notify = c.uuid
            if c.uuid.lower() == WRITE_UUID:
                write = c.uuid
    if notify and write:
        return notify, write
    for service in client.services:
        if service.uuid.lower().startswith(_STANDARD):
            continue
        n = next((c.uuid for c in service.characteristics if "notify" in c.properties or "indicate" in c.properties), None)
        w = next((c.uuid for c in service.characteristics if "write-without-response" in c.properties or "write" in c.properties), None)
        if n and w:
            _LOGGER.info("BP2 using vendor service %s (notify %s, write %s)", service.uuid, n, w)
            return n, w
    raise RuntimeError("no usable notify/write characteristics found on this monitor")


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    dev = BP2Device(hass, entry)
    await dev.async_load()
    entry.runtime_data = dev
    entry.async_on_unload(
        bluetooth.async_register_callback(
            hass, dev.on_advertisement,
            bluetooth.BluetoothCallbackMatcher(address=dev.address, connectable=True),
            bluetooth.BluetoothScanningMode.ACTIVE,
        )
    )
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
