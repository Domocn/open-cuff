import 'package:flutter_test/flutter_test.dart';
import 'package:open_cuff/analysis.dart';
import 'package:open_cuff/meds.dart';
import 'package:open_cuff/models.dart';
import 'package:open_cuff/scales.dart';

Reading r(DateTime t, int s, int d, int p, {List<String>? tags}) =>
    Reading(key: Reading.makeKey(t, s, d, p), time: t, systolic: s, diastolic: d, pulse: p, tags: tags);

void main() {
  final now = DateTime.now();

  test('trend spots a real rise and ignores a flat fortnight', () {
    final old = [for (var i = 8; i < 20; i += 2) r(now.subtract(Duration(days: i)), 115, 75, 70)];
    final flat = [for (var i = 1; i < 7; i += 2) r(now.subtract(Duration(days: i)), 117, 76, 72)];
    final up = [for (var i = 1; i < 7; i += 2) r(now.subtract(Duration(days: i)), 126, 82, 85)];
    expect(trendMessage([...old, ...flat]), isNull);
    final m = trendMessage([...old, ...up])!;
    expect(m, contains('top number up 11'));
    expect(m, contains('pulse up 15'));
  });

  test('home check leaves day 1 out', () {
    final start = DateTime(2026, 11, 2);
    final hc = HomeCheck(start);
    final rs = [
      r(DateTime(2026, 11, 2, 8), 150, 95, 90), // practice day
      r(DateTime(2026, 11, 3, 8), 120, 80, 70),
      r(DateTime(2026, 11, 3, 8, 1), 118, 78, 70),
      r(DateTime(2026, 11, 3, 20), 122, 80, 72),
    ];
    expect(hc.slots(rs)[1][0].length, 2);
    expect(hc.result(rs)!.systolic, 120);
  });

  test('quality flags', () {
    final a = r(now, 120, 80, 70, tags: ['coffee']), b = r(now.add(const Duration(seconds: 30)), 121, 80, 70);
    expect(qualityFlags(a, [a, b]), hasLength(2));
  });

  test('blood pressure by dose', () {
    final m = Med('1', 'Example', '08:00', [DoseStep('18 mg', DateTime(2026, 11, 1)), DoseStep('36 mg', DateTime(2026, 11, 8))]);
    final rs = [r(DateTime(2026, 10, 30), 119, 80, 67), r(DateTime(2026, 11, 3), 115, 79, 75), r(DateTime(2026, 11, 9), 112, 81, 80)];
    final rows = Meds.byDose(m, rs);
    expect(rows.map((x) => x.$1), ['Before starting', '18 mg', '36 mg']);
    expect(rows[2].$2, 112);
  });

  test('scales match the published limits', () {
    BpScale sc(String id) => scales.firstWhere((s) => s.id == id);
    expect(sc('nhs_home').zoneFor(116, 80).name, 'Healthy');
    expect(sc('nhs_home').zoneFor(131, 79).name, 'Raised');
    expect(sc('nhs_home').zoneFor(150, 80).name, 'Stage 2 hypertension');
    expect(sc('nhs_home').zoneFor(88, 70).name, 'Low');
    expect(sc('aha').zoneFor(125, 75).name, 'Elevated');
    expect(sc('aha').zoneFor(125, 82).name, 'Stage 1 hypertension');
    expect(sc('esc2024').zoneFor(118, 72).name, 'Elevated');
    expect(sc('nice_clinic').zoneFor(185, 90).name, 'Stage 3 hypertension');
    expect(sc('esh2023').zoneFor(119, 79).name, 'Optimal');
  });
}
