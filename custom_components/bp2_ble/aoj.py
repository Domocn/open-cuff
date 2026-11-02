"""Wire protocol for AOJ Medical blood pressure monitors (OxiPro BP2 = AOJ-33A), service 0xFFE0.

Documented for interoperability. Read-only: nothing here clears the monitor's memory or changes its settings.

Frame layout:

    0..1         2      3     4..         last
    header       len    cmd   data        CRC-8/MAXIM

`len` counts the command byte plus the data. The CRC (reflected polynomial 0x8C, initial value 0) covers every byte
before it. The app sends with header BE B0 and the monitor replies with header D0 C2.

Readings arrive as CC frames (live B3 frames are handled the same way) with 11 data bytes: systolic, diastolic, pulse, flags (bit 0 irregular pulse, high
nibble user), then the time as year (2 bytes, big-endian), month, day, hour, minute, second. A reading whose
diastolic, pulse and flags are all zero is a measurement error, and its first byte is the error code.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

NOTIFY_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb"
WRITE_UUID = "0000ffe2-0000-1000-8000-00805f9b34fb"

TX_HEADER = b"\xbe\xb0"
RX_HEADER = b"\xd0\xc2"

CMD_ACK = 0x00
CMD_HANDSHAKE = 0xB0
CMD_SET_TIME = 0xB1
CMD_BT_STATUS = 0xB2
CMD_READING = 0xCC  # stored and new readings (seen on the OxiPro BP2)
CMD_LIVE_READING = 0xB3
READING_CMDS = (CMD_READING, CMD_LIVE_READING)
CMD_START = 0xC0
CMD_STOP = 0xC1
CMD_TURN_OFF = 0xD0
CMD_SERIAL = 0xD6
CMD_DATA = 0xD7
CMD_SYSTEM_INFO = 0xD8

ALL_USERS = 0xFF
# D7 with a last data byte of 0x00 deletes the monitor's memory, so only this one is ever built
_DATA_READ = 0x01


def crc8_maxim(data: bytes) -> int:
    c = 0
    for b in data:
        c ^= b
        for _ in range(8):
            c = (c >> 1) ^ 0x8C if c & 1 else c >> 1
    return c


def build_frame(cmd: int, data: bytes = b"") -> bytes:
    body = TX_HEADER + bytes([len(data) + 1, cmd]) + data
    return body + bytes([crc8_maxim(body)])


def bt_status() -> bytes:
    return build_frame(CMD_BT_STATUS)


def get_serial() -> bytes:
    return build_frame(CMD_SERIAL, b"\x00")


def get_system_info() -> bytes:
    return build_frame(CMD_SYSTEM_INFO)


def get_data(user: int = ALL_USERS) -> bytes:
    return build_frame(CMD_DATA, bytes([user & 0xFF, _DATA_READ]))


def ack() -> bytes:
    return build_frame(CMD_ACK, b"\x00")


@dataclass
class Frame:
    cmd: int
    data: bytes


class FrameParser:
    """Collects notification chunks and yields whole, CRC-checked reply frames."""

    def __init__(self) -> None:
        self.buf = bytearray()

    def feed(self, chunk: bytes) -> list[Frame]:
        self.buf += chunk
        out: list[Frame] = []
        while True:
            i = self.buf.find(RX_HEADER)
            if i < 0:
                del self.buf[:-1]
                return out
            del self.buf[:i]
            if len(self.buf) < 3:
                return out
            total = self.buf[2] + 4  # header, len, cmd + data, crc
            if len(self.buf) < total:
                return out
            frame = bytes(self.buf[:total])
            if self.buf[2] >= 1 and crc8_maxim(frame[:-1]) == frame[-1]:
                out.append(Frame(frame[3], frame[4:-1]))
                del self.buf[:total]
            else:
                del self.buf[:1]


@dataclass
class AojReading:
    time: datetime
    systolic: int
    diastolic: int
    pulse: int
    irregular: bool
    user: int

    @property
    def key(self) -> str:
        return f"{self.time:%Y%m%d%H%M%S}-{self.systolic}-{self.diastolic}-{self.pulse}"


def parse_reading(data: bytes) -> AojReading | None:
    """Returns None for measurement errors and malformed frames."""
    if len(data) < 11:
        return None
    sys_, dia, pulse, flags = data[0], data[1], data[2], data[3]
    if dia == 0 and pulse == 0 and flags == 0:
        return None
    try:
        when = datetime(int.from_bytes(data[4:6], "big"), data[6], data[7], data[8], data[9], data[10])
    except ValueError:
        return None
    return AojReading(when, sys_, dia, pulse, bool(flags & 1), flags >> 4)
