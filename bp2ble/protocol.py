"""Wire protocol for BP2-family monitors.

Frame layout (all multi-byte numbers little-endian):

    0      1     2      3         4      5..6     7..7+len-1   last
    0xA5   cmd   ~cmd   pkg_type  seq    length   payload      CRC-8

CRC-8 uses polynomial 0x07, initial value 0, over every byte except the CRC itself.
In replies, pkg_type 0x01 means success.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
from datetime import datetime, timezone

HEADER = 0xA5

CMD_GET_INFO = 0xE1
CMD_SYNC_TIME = 0xEC
CMD_FILE_LIST = 0xF1
CMD_FILE_START = 0xF2
CMD_FILE_DATA = 0xF3
CMD_FILE_END = 0xF4

FILE_TYPE_BP = 1
FILE_TYPE_ECG = 2


def _make_table() -> list[int]:
    table = []
    for i in range(256):
        c = i
        for _ in range(8):
            c = ((c << 1) ^ 0x07) & 0xFF if c & 0x80 else (c << 1) & 0xFF
        table.append(c)
    return table


_CRC_TABLE = _make_table()


def crc8(data: bytes) -> int:
    crc = 0
    for b in data:
        crc = _CRC_TABLE[(crc ^ b) & 0xFF]
    return crc


def build_frame(cmd: int, payload: bytes = b"", seq: int = 0) -> bytes:
    n = len(payload)
    head = bytes([HEADER, cmd & 0xFF, (~cmd) & 0xFF, 0x00, seq & 0xFF, n & 0xFF, (n >> 8) & 0xFF]) + payload
    return head + bytes([crc8(head)])


@dataclass
class Frame:
    cmd: int
    pkg_type: int
    seq: int
    payload: bytes

    @property
    def ok(self) -> bool:
        return self.pkg_type == 0x01


class FrameParser:
    """Collects notification chunks and returns complete, checksum-valid frames."""

    def __init__(self) -> None:
        self.buf = bytearray()

    def feed(self, chunk: bytes) -> list[Frame]:
        self.buf += chunk
        out: list[Frame] = []
        while True:
            start = self._find_start()
            if start < 0:
                # keep a trailing header byte in case the rest arrives in the next chunk
                if self.buf and self.buf[-1] == HEADER:
                    del self.buf[:-1]
                elif len(self.buf) >= 2 and self.buf[-2] == HEADER:
                    del self.buf[:-2]
                else:
                    self.buf.clear()
                return out
            if start:
                del self.buf[:start]
            if len(self.buf) < 8:
                return out
            n = self.buf[5] | (self.buf[6] << 8)
            total = 8 + n
            if len(self.buf) < total:
                return out
            frame = bytes(self.buf[:total])
            if crc8(frame[:-1]) == frame[-1]:
                out.append(Frame(frame[1], frame[3], frame[4], frame[7:7 + n]))
                del self.buf[:total]
            else:
                del self.buf[:1]  # bad checksum: resync on the next header

    def _find_start(self) -> int:
        b = self.buf
        for i in range(len(b) - 2):
            if b[i] == HEADER and b[i + 1] == (~b[i + 2]) & 0xFF:
                return i
        return -1


@dataclass
class BpReading:
    file: str
    time: datetime
    systolic: int
    diastolic: int
    mean: int
    pulse: int
    status: int
    irregular: bool

    def as_dict(self) -> dict:
        d = asdict(self)
        d["time"] = self.time.isoformat(timespec="seconds")
        return d


def parse_file_list(payload: bytes) -> list[str]:
    if not payload:
        return []
    count = payload[0]
    names = []
    for i in range(count):
        raw = payload[1 + i * 16: 17 + i * 16]
        name = raw.split(b"\x00", 1)[0].decode("ascii", "ignore").strip()
        if name and not name.startswith("MKFS"):
            names.append(name)
    return names


def parse_bp_file(name: str, data: bytes) -> BpReading | None:
    """Parse one stored file. Returns None for ECG or unknown files.

    Layout: version(1) type(1) time(4, seconds) reserved(4) status(1) sys(2) dia(2) mean(2) pulse(1) diagnosis(1) ...
    The monitor keeps its own wall-clock time and stores it as if it were UTC, so the time is returned as a
    naive local time exactly as the monitor showed it.
    """
    if len(data) < 19 or data[1] != FILE_TYPE_BP:
        return None
    ts = int.from_bytes(data[2:6], "little")
    when = datetime.fromtimestamp(ts, tz=timezone.utc).replace(tzinfo=None)
    return BpReading(
        file=name,
        time=when,
        status=data[10],
        systolic=int.from_bytes(data[11:13], "little"),
        diastolic=int.from_bytes(data[13:15], "little"),
        mean=int.from_bytes(data[15:17], "little"),
        pulse=data[17],
        irregular=bool(data[18] & 0x01),
    )


def sync_time_payload(now: datetime | None = None) -> bytes:
    now = now or datetime.now()
    return bytes([now.year & 0xFF, now.year >> 8, now.month, now.day, now.hour, now.minute, now.second])
