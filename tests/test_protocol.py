from datetime import datetime

from bp2ble.protocol import (CMD_FILE_LIST, FrameParser, build_frame, crc8, parse_bp_file, parse_file_list)


def test_crc8_known_value():
    # CRC-8 (poly 0x07, init 0) of "123456789" is 0xF4
    assert crc8(b"123456789") == 0xF4


def test_build_frame_layout():
    f = build_frame(CMD_FILE_LIST, b"", seq=3)
    assert f[:7] == bytes([0xA5, 0xF1, 0x0E, 0x00, 0x03, 0x00, 0x00])
    assert f[7] == crc8(f[:7])


def _reply(cmd, payload, pkg=0x01, seq=0):
    n = len(payload)
    head = bytes([0xA5, cmd, (~cmd) & 0xFF, pkg, seq, n & 0xFF, n >> 8]) + payload
    return head + bytes([crc8(head)])


def test_parser_handles_split_and_noise():
    a = _reply(0xF1, b"\x01" + b"20261031090102\x00\x00")
    b = _reply(0xE1, b"\x10\x20")
    stream = b"\x00\x11" + a + b
    parser = FrameParser()
    frames = []
    for i in range(0, len(stream), 7):  # deliver in awkward 7-byte chunks
        frames += parser.feed(stream[i:i + 7])
    assert [f.cmd for f in frames] == [0xF1, 0xE1]
    assert frames[0].ok
    assert parse_file_list(frames[0].payload) == ["20261031090102"]


def test_parser_skips_bad_checksum():
    good = _reply(0xF1, b"\x00")
    bad = bytearray(good)
    bad[-1] ^= 0xFF
    frames = FrameParser().feed(bytes(bad) + good)
    assert len(frames) == 1


def test_parse_bp_file():
    ts = int(datetime(2026, 1, 15, 8, 30).replace().timestamp())  # any value; we check the round trip below
    data = bytearray(40)
    data[0] = 1
    data[1] = 1
    data[2:6] = (1768465800).to_bytes(4, "little")  # 2026-01-15 08:30:00 as wall-clock
    data[10] = 0
    data[11:13] = (124).to_bytes(2, "little")
    data[13:15] = (77).to_bytes(2, "little")
    data[15:17] = (93).to_bytes(2, "little")
    data[17] = 72
    data[18] = 0
    r = parse_bp_file("20260115083000", bytes(data))
    assert (r.systolic, r.diastolic, r.pulse, r.irregular) == (124, 77, 72, False)
    assert r.time == datetime(2026, 1, 15, 8, 30)
    assert ts  # keep linters quiet


def test_ecg_file_is_ignored():
    data = bytearray(40)
    data[1] = 2
    assert parse_bp_file("x", bytes(data)) is None
