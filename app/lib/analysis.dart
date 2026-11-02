import 'models.dart';
import 'scales.dart';
import 'store.dart';

/// Averages and checks, all worked out on the phone.
class Avg {
  final int systolic, diastolic, pulse, count;
  const Avg(this.systolic, this.diastolic, this.pulse, this.count);
  String get bp => '$systolic/$diastolic';

  static Avg? of(Iterable<Reading> l) {
    final x = l.toList();
    if (x.isEmpty) return null;
    int a(int Function(Reading) f) => (x.map(f).reduce((p, q) => p + q) / x.length).round();
    return Avg(a((r) => r.systolic), a((r) => r.diastolic), a((r) => r.pulse), x.length);
  }
}

bool isMorning(Reading r) => r.time.hour < 12;

List<Reading> between(List<Reading> rs, DateTime from, DateTime to) =>
    rs.where((r) => !r.time.isBefore(from) && r.time.isBefore(to)).toList();

/// Compares the last 7 days with the 14 days before. Returns plain words when the change is worth knowing, else null.
String? trendMessage(List<Reading> rs) {
  final now = DateTime.now();
  final recent = Avg.of(between(rs, now.subtract(const Duration(days: 7)), now));
  final before = Avg.of(between(rs, now.subtract(const Duration(days: 21)), now.subtract(const Duration(days: 7))));
  if (recent == null || before == null || recent.count < 3 || before.count < 3) return null;
  final ds = recent.systolic - before.systolic, dd = recent.diastolic - before.diastolic, dp = recent.pulse - before.pulse;
  final parts = <String>[];
  if (ds.abs() >= 8) parts.add('top number ${ds > 0 ? 'up' : 'down'} ${ds.abs()}');
  if (dd.abs() >= 5) parts.add('bottom number ${dd > 0 ? 'up' : 'down'} ${dd.abs()}');
  if (dp.abs() >= 10) parts.add('pulse ${dp > 0 ? 'up' : 'down'} ${dp.abs()}');
  if (parts.isEmpty) return null;
  return 'This week\'s average is ${recent.bp}, pulse ${recent.pulse}: ${parts.join(', ')} on the two weeks before (${before.bp}, pulse ${before.pulse}).';
}

/// Limits from Goals (defaults: NHS home limit 135/85, resting pulse 100).
int limit(String k) {
  final (hs, hd) = currentScale.highFrom;
  return int.tryParse(Settings.i.text('limit_$k')) ?? {'sys': hs, 'dia': hd, 'pulse': 100}[k]!;
}

String? overLimit(Reading r) {
  final over = <String>[
    if (r.systolic >= limit('sys')) 'top number ${r.systolic}',
    if (r.diastolic >= limit('dia')) 'bottom number ${r.diastolic}',
    if (r.pulse > limit('pulse')) 'pulse ${r.pulse}',
  ];
  return over.isEmpty ? null : 'Over your limit: ${over.join(', ')}. Sit quietly for 5 minutes and take another reading.';
}

/// Reasons a reading may not be reliable (Quality check).
List<String> qualityFlags(Reading r, List<Reading> all) {
  final out = <String>[];
  final close = all.where((o) => o.key != r.key && r.time.difference(o.time).inSeconds.abs() < 60);
  if (close.isNotEmpty) out.add('Taken less than a minute after another reading');
  for (final t in const ['coffee', 'nicotine', 'exercise']) {
    if (r.tags.contains(t)) out.add('Taken within 30 minutes of ${t == 'exercise' ? 'exercise' : t}');
  }
  return out;
}

/// NHS home check: two readings morning and evening for 7 days, day 1 left out of the average.
class HomeCheck {
  final DateTime start;
  HomeCheck(this.start);

  static HomeCheck? get current {
    final s = DateTime.tryParse(Settings.i.text('homecheck_start'));
    return s == null ? null : HomeCheck(s);
  }

  DateTime day(int i) => DateTime(start.year, start.month, start.day + i);
  bool get finished => DateTime.now().isAfter(day(7));
  int get today => DateTime.now().difference(day(0)).inDays.clamp(0, 6);

  /// Readings in each slot: [day][0 = morning, 1 = evening].
  List<List<List<Reading>>> slots(List<Reading> rs) => [
        for (var d = 0; d < 7; d++)
          [
            for (final m in [true, false])
              between(rs, day(d), day(d + 1)).where((r) => isMorning(r) == m && r.source != 'clinic').toList(),
          ],
      ];

  Avg? result(List<Reading> rs) => Avg.of([
        for (var d = 1; d < 7; d++) ...slots(rs)[d].expand((s) => s),
      ]);
}

/// Gentle streak: how many mornings and evenings this week have at least one reading.
(int, int) weekCounts(List<Reading> rs) {
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  final week = between(rs, monday, now.add(const Duration(days: 1)));
  final mornings = week.where(isMorning).map((r) => r.time.day).toSet().length;
  final evenings = week.where((r) => !isMorning(r)).map((r) => r.time.day).toSet().length;
  return (mornings, evenings);
}

String weeklySummary(List<Reading> rs) {
  final now = DateTime.now();
  final week = Avg.of(between(rs, now.subtract(const Duration(days: 7)), now));
  if (week == null) return 'No readings this week. A couple next week would be great.';
  final trend = trendMessage(rs);
  final irregular = between(rs, now.subtract(const Duration(days: 7)), now).where((r) => r.irregular).length;
  return [
    'This week: ${week.bp}, pulse ${week.pulse}, from ${week.count} reading${week.count == 1 ? '' : 's'}.',
    ?trend,
    if (irregular >= 3) 'The cuff noticed an irregular heartbeat $irregular times. Worth mentioning to your doctor.',
  ].join(' ');
}
