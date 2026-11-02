import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_cuff/meds.dart';
import 'package:open_cuff/store.dart';

void main() {
  test('a planned step is not the current dose until its day', () {
    final now = DateTime.now();
    final m = Med('1', 'Test', '', [
      DoseStep('18 mg', now.subtract(const Duration(days: 3))),
      DoseStep('36 mg', now.add(const Duration(days: 4))),
      DoseStep('54 mg', now.add(const Duration(days: 11))),
    ]);
    expect(m.current!.dose, '18 mg');
    expect(m.next!.dose, '36 mg');
  });

  test('nothing current before the first step starts', () {
    final m = Med('1', 'Test', '', [DoseStep('18 mg', DateTime.now().add(const Duration(days: 1)))]);
    expect(m.current, isNull);
    expect(m.next!.dose, '18 mg');
  });

  test('restoring a plan updates the same medicine by name and keeps the others', () {
    final have = jsonEncode([
      {'id': 'a', 'name': 'Example XL', 'time': '', 'steps': []},
      {'id': 'b', 'name': 'Other medicine', 'time': '08:00', 'steps': []},
    ]);
    final plan = jsonEncode([
      {'id': 'x', 'name': 'example xl', 'time': '', 'steps': [{'dose': '18 mg', 'from': '2026-01-05T00:00:00.000'}]},
    ]);
    final out = (jsonDecode(Settings.mergeMeds(have, plan)) as List).cast<Map>();
    expect(out.length, 2);
    expect(out[0]['id'], 'a');
    expect((out[0]['steps'] as List).length, 1);
    expect(out[1]['name'], 'Other medicine');
  });
}
