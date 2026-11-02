import 'package:flutter/material.dart';

import 'scales.dart';

class Reading {
  final String key;
  DateTime time; // editable on the Details page
  int systolic, diastolic, pulse;
  int user; // the person in the app this reading belongs to
  final bool irregular;
  final String source; // 'cuff', 'manual' or 'clinic'
  final int cuffUser; // the cuff's own user button (1 or 2), 0 when unknown
  String note;
  List<String> tags; // e.g. coffee, nicotine, exercise, and side effects such as headache

  Reading({
    required this.key,
    required this.time,
    required this.systolic,
    required this.diastolic,
    required this.pulse,
    this.irregular = false,
    this.user = 1,
    this.source = 'cuff',
    this.cuffUser = 0,
    this.note = '',
    List<String>? tags,
  }) : tags = tags ?? [];

  static String makeKey(DateTime t, int s, int d, int p) =>
      '${t.year}${_two(t.month)}${_two(t.day)}${_two(t.hour)}${_two(t.minute)}${_two(t.second)}-$s-$d-$p';

  /// Average arterial pressure: diastolic plus a third of the pulse pressure.
  int get mean => (diastolic + (systolic - diastolic) / 3).round();
  int get pulsePressure => systolic - diastolic;
  Band get band => Band.of(systolic, diastolic);
  /// The name of this reading's step on the chosen scale, e.g. "Raised" or "High (stage 1)".
  String get zone => currentScale.zoneFor(systolic, diastolic).name;

  Map<String, dynamic> toJson() => {
        'key': key,
        'time': time.toIso8601String(),
        'sys': systolic,
        'dia': diastolic,
        'pulse': pulse,
        'irr': irregular,
        'user': user,
        'src': source,
        if (cuffUser != 0) 'cu': cuffUser,
        'note': note,
        if (tags.isNotEmpty) 'tags': tags,
      };

  factory Reading.fromJson(Map<String, dynamic> j) => Reading(
        key: j['key'],
        time: DateTime.parse(j['time']),
        systolic: j['sys'],
        diastolic: j['dia'],
        pulse: j['pulse'],
        irregular: j['irr'] ?? false,
        user: j['user'] ?? 1,
        source: j['src'] ?? 'cuff',
        cuffUser: j['cu'] ?? 0,
        note: j['note'] ?? '',
        tags: (j['tags'] as List?)?.cast<String>(),
      );
}

String _two(int n) => n.toString().padLeft(2, '0');

/// NHS home blood pressure ranges: ideal 90/60 to 120/80, high from 135/85 at home, low under 90/60.
enum Band {
  low('Low', 'Lower than usual'),
  ideal('Ideal', 'In the ideal range'),
  raised('Raised', 'A little high'),
  high('High', 'High');

  final String label, words;
  const Band(this.label, this.words);

  static Band _sev(int severity) => switch (severity) { 0 => Band.low, 1 => Band.ideal, 2 => Band.raised, _ => Band.high };

  /// Uses the scale chosen in Settings (NHS home by default).
  static Band of(int s, int d) => _sev(currentScale.zoneFor(s, d).severity);
  // one number on its own: pair it with the lowest value that isn't "Low" on this scale
  static Band ofTop(int s) => _sev(currentScale.zoneFor(s, currentScale.lowDia).severity);
  static Band ofBottom(int d) => _sev(currentScale.zoneFor(currentScale.lowSys, d).severity);
}

/// Plain words for a reading: which number, if any, is outside the ideal range.
String describe(Reading r) {
  final t = Band.ofTop(r.systolic), b = Band.ofBottom(r.diastolic);
  if (t == Band.ideal && b == Band.ideal) return 'In the ideal range';
  if (t == Band.high || b == Band.high) {
    return t == Band.high && b == Band.high ? 'Both numbers high' : (t == Band.high ? 'Top number high' : 'Bottom number high');
  }
  if (t == Band.low || b == Band.low) return t == Band.low ? 'Top number low' : 'Bottom number low';
  return t == Band.raised && b == Band.raised
      ? 'Both numbers a little high'
      : (t == Band.raised ? 'Top number a little high' : 'Bottom number a little high');
}

String hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String dayLabel(DateTime t) {
  final now = DateTime.now();
  final d = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  if (d == today) return 'Today';
  if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
  final s = '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
  return t.year == now.year ? s : '$s ${t.year}';
}

String when(DateTime t) => '${dayLabel(t)} ${hm(t)}';

Color bandColor(BuildContext c, Band b) {
  final dark = Theme.of(c).brightness == Brightness.dark;
  return switch (b) {
    Band.low => dark ? const Color(0xFF82A9EA) : const Color(0xFF3466B0),
    Band.ideal => dark ? const Color(0xFF5CCB93) : const Color(0xFF21875A),
    Band.raised => dark ? const Color(0xFFF0B04E) : const Color(0xFFB26B00),
    Band.high => dark ? const Color(0xFFF07C70) : const Color(0xFFC23A2E),
  };
}
