import 'package:flutter_test/flutter_test.dart';
import 'package:open_cuff/aoj.dart' as aoj;
import 'package:open_cuff/models.dart';

List<int> hex(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

void main() {
  test('CRC-8/MAXIM check value', () => expect(aoj.crc8Maxim('123456789'.codeUnits), 0xA1));

  test('frames match what the app sent the cuff', () {
    expect(aoj.btStatus(), hex('beb001b272'));
    expect(aoj.getSerial(), hex('beb002d600c1'));
    expect(aoj.getSystemInfo(), hex('beb001d869'));
    expect(aoj.getData(), hex('beb003d7ff016f'));
  });

  test('read request never becomes the delete request', () {
    for (final u in [0, 1, 2, 0xFF]) {
      expect(aoj.getData(u)[5], 0x01);
    }
  });

  test('a reading frame, split across notifications', () {
    final p = aoj.FrameParser();
    final f = hex('d0c20ccc794f441007ea010f081e00d3');
    expect(p.feed([0x01, ...f.sublist(0, 7)]), isEmpty);
    final got = p.feed(f.sublist(7));
    expect(got.single.cmd, aoj.cmdReading);
    final r = aoj.parseReading(got.single.data)!;
    expect([r.systolic, r.diastolic, r.pulse, r.user], [121, 79, 68, 1]);
    expect(r.time, DateTime(2026, 1, 15, 8, 30, 0));
  });

  test('bad CRC is dropped', () {
    final f = hex('d0c20ccc794f441007ea010f081e00d3')..[15] ^= 0xFF;
    expect(aoj.FrameParser().feed(f), isEmpty);
  });

  test('NHS home bands', () {
    expect(Band.of(119, 76), Band.ideal);
    expect(Band.of(102, 82), Band.raised);
    expect(Band.of(131, 79), Band.raised);
    expect(Band.of(136, 70), Band.high);
    expect(Band.of(88, 70), Band.low);
  });
}
