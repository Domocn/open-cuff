/// Wire protocol for AOJ Medical blood pressure monitors (OxiPro BP2 = AOJ-33A), service 0xFFE0.
/// Same as bp2ble/aoj.py in this repo; see docs/adding-devices.md for how it was learned.
///
/// Frame: header (2) | len | cmd | data | CRC-8/MAXIM over everything before it. `len` = 1 + data length.
/// We send with header BE B0, the monitor replies with D0 C2.
library;

import 'dart:typed_data';

const serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
const notifyUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';
const writeUuid = '0000ffe2-0000-1000-8000-00805f9b34fb';

const _tx = [0xBE, 0xB0];
const _rx = [0xD0, 0xC2];

const cmdAck = 0x00;
const cmdBtStatus = 0xB2;
const cmdLiveReading = 0xB3;
const cmdReading = 0xCC;
const cmdSerial = 0xD6;
const cmdData = 0xD7;
const cmdSystemInfo = 0xD8;
const readingCmds = {cmdReading, cmdLiveReading};

const allUsers = 0xFF;
// D7 with a last data byte of 0x00 clears the monitor's memory, so only the read form (0x01) is ever built.
const _dataRead = 0x01;

int crc8Maxim(List<int> data) {
  var c = 0;
  for (final b in data) {
    c ^= b;
    for (var i = 0; i < 8; i++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0x8C : c >> 1;
    }
  }
  return c;
}

Uint8List buildFrame(int cmd, [List<int> data = const []]) {
  final body = [..._tx, data.length + 1, cmd, ...data];
  return Uint8List.fromList([...body, crc8Maxim(body)]);
}

Uint8List btStatus() => buildFrame(cmdBtStatus);
Uint8List getSerial() => buildFrame(cmdSerial, [0x00]);
Uint8List getSystemInfo() => buildFrame(cmdSystemInfo);
Uint8List getData([int user = allUsers]) => buildFrame(cmdData, [user & 0xFF, _dataRead]);
Uint8List ack() => buildFrame(cmdAck, [0x00]);

class Frame {
  final int cmd;
  final List<int> data;
  Frame(this.cmd, this.data);
}

/// Collects notification chunks and returns whole, CRC-checked reply frames.
class FrameParser {
  final _buf = <int>[];

  List<Frame> feed(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <Frame>[];
    while (true) {
      final i = _find();
      if (i < 0) {
        if (_buf.length > 1) _buf.removeRange(0, _buf.length - 1);
        return out;
      }
      _buf.removeRange(0, i);
      if (_buf.length < 3) return out;
      final total = _buf[2] + 4;
      if (_buf.length < total) return out;
      final frame = _buf.sublist(0, total);
      if (_buf[2] >= 1 && crc8Maxim(frame.sublist(0, total - 1)) == frame.last) {
        out.add(Frame(frame[3], frame.sublist(4, total - 1)));
        _buf.removeRange(0, total);
      } else {
        _buf.removeAt(0);
      }
    }
  }

  int _find() {
    for (var i = 0; i + 1 < _buf.length; i++) {
      if (_buf[i] == _rx[0] && _buf[i + 1] == _rx[1]) return i;
    }
    return -1;
  }
}

class CuffReading {
  final DateTime time;
  final int systolic, diastolic, pulse, user;
  final bool irregular;
  CuffReading(this.time, this.systolic, this.diastolic, this.pulse, this.irregular, this.user);
}

/// Systolic, diastolic, pulse, flags (bit 0 irregular, high nibble user), year (big-endian), month, day, h, m, s.
/// A reading whose diastolic, pulse and flags are all zero is a measurement error; returns null for those.
CuffReading? parseReading(List<int> d) {
  if (d.length < 11) return null;
  if (d[1] == 0 && d[2] == 0 && d[3] == 0) return null;
  final y = (d[4] << 8) | d[5];
  if (y < 2000 || d[6] < 1 || d[6] > 12 || d[7] < 1 || d[7] > 31 || d[8] > 23 || d[9] > 59 || d[10] > 59) return null;
  return CuffReading(DateTime(y, d[6], d[7], d[8], d[9], d[10]), d[0], d[1], d[2], (d[3] & 1) == 1, d[3] >> 4);
}

/// Error code from a failed measurement (first byte), or null when it is a normal reading.
int? errorCode(List<int> d) => d.length >= 4 && d[1] == 0 && d[2] == 0 && d[3] == 0 ? d[0] : null;
