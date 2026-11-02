from datetime import datetime

from bp2ble import aoj


def test_crc8_maxim_known_value():
    # CRC-8/MAXIM of "123456789" is 0xA1
    assert aoj.crc8_maxim(b"123456789") == 0xA1


def test_frames_match_the_app():
    assert aoj.bt_status()[:4] == bytes([0xBE, 0xB0, 0x01, 0xB2])
    assert aoj.get_data() [:6] == bytes([0xBE, 0xB0, 0x03, 0xD7, 0xFF, 0x01])
    f = aoj.ack()
    assert f[:5] == bytes([0xBE, 0xB0, 0x02, 0x00, 0x00]) and f[5] == aoj.crc8_maxim(f[:5])


def test_get_data_never_builds_delete():
    for user in (0, 1, 2, 0xFF):
        assert aoj.get_data(user)[5] == 0x01


def _reply(cmd, data):
    body = aoj.RX_HEADER + bytes([len(data) + 1, cmd]) + data
    return body + bytes([aoj.crc8_maxim(body)])


def test_parser_reassembles_a_reading():
    data = bytes([121, 79, 66, 0x11]) + (2026).to_bytes(2, "big") + bytes([10, 31, 12, 43, 5])
    frame = _reply(aoj.CMD_READING, data)
    p = aoj.FrameParser()
    assert p.feed(b"\x01\x02" + frame[:7]) == []
    (got,) = p.feed(frame[7:])
    r = aoj.parse_reading(got.data)
    assert (r.systolic, r.diastolic, r.pulse, r.irregular, r.user) == (121, 79, 66, True, 1)
    assert r.time == datetime(2026, 10, 31, 12, 43, 5)


def test_bad_crc_and_errors_are_dropped():
    data = bytes([5, 0, 0, 0]) + (2026).to_bytes(2, "big") + bytes([10, 31, 12, 43, 5])
    frame = bytearray(_reply(aoj.CMD_READING, data))
    assert aoj.parse_reading(aoj.FrameParser().feed(bytes(frame))[0].data) is None
    frame[-1] ^= 0xFF
    assert aoj.FrameParser().feed(bytes(frame)) == []


def test_real_reply_from_the_cuff():
    (f,) = aoj.FrameParser().feed(bytes.fromhex("d0c20ccc794f441007ea010f081e00d3"))
    assert f.cmd in aoj.READING_CMDS
    r = aoj.parse_reading(f.data)
    assert (r.systolic, r.diastolic, r.pulse) == (121, 79, 68)
    assert r.time == datetime(2026, 1, 15, 8, 30, 0)
