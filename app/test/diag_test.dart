import 'package:flutter_test/flutter_test.dart';
import 'package:open_cuff/diag.dart';

void main() {
  test('the problem log never keeps addresses, tokens or readings', () {
    final s = Diag.clean('connect to C4:7F:51:0A:1B:2C failed; POST http://10.0.0.5:8123/api/events Bearer abc.def.ghi; got 121/79');
    expect(s, isNot(contains('C4:7F:51')));
    expect(s, contains('cuff..2C'));
    expect(s, isNot(contains("10.0.0.5")));
    expect(s, isNot(contains('abc.def')));
    expect(s, isNot(contains('121/79')));
  });

  test('ordinary messages pass through', () {
    expect(Diag.clean('connect try 2 of 3 failed: disconnected'), 'connect try 2 of 3 failed: disconnected');
  });
}
