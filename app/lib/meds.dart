import 'dart:convert';

import 'models.dart';
import 'store.dart';

/// A medicine with its dose history. A dose change starts a new "step", so readings can be grouped by dose.
class Med {
  String id, name, time; // time = usual dose time HH:MM, '' when none
  List<DoseStep> steps;
  Med(this.id, this.name, this.time, this.steps);

  /// The dose in effect today (a plan can hold future steps, e.g. a 4-week titration). Null before the first step starts.
  DoseStep? get current {
    final now = DateTime.now();
    final started = steps.where((s) => !s.from.isAfter(now));
    return started.isEmpty ? null : started.last;
  }

  /// The next planned dose change, if any.
  DoseStep? get next {
    final now = DateTime.now();
    final later = steps.where((s) => s.from.isAfter(now));
    return later.isEmpty ? null : later.first;
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'time': time, 'steps': steps.map((s) => s.toJson()).toList()};
  factory Med.fromJson(Map<String, dynamic> j) =>
      Med(j['id'], j['name'], j['time'] ?? '', (j['steps'] as List).map((e) => DoseStep.fromJson(Map<String, dynamic>.from(e))).toList());
}

class DoseStep {
  final String dose; // e.g. "36 mg"
  final DateTime from;
  DoseStep(this.dose, this.from);
  Map<String, dynamic> toJson() => {'dose': dose, 'from': from.toIso8601String()};
  factory DoseStep.fromJson(Map<String, dynamic> j) => DoseStep(j['dose'], DateTime.parse(j['from']));
}

/// Medicines and the "taken" log, kept in settings (small) for the current person.
class Meds {
  static String get _k => 'meds_${Settings.i.user}';
  static String get _t => 'taken_${Settings.i.user}';

  static List<Med> all() {
    final raw = Settings.i.text(_k);
    if (raw.isEmpty) return [];
    return (jsonDecode(raw) as List).map((e) => Med.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<void> save(List<Med> meds) => Settings.i.setText(_k, jsonEncode(meds.map((m) => m.toJson()).toList()));

  /// Times a dose was taken, per medicine id.
  static Map<String, List<DateTime>> taken() {
    final raw = Settings.i.text(_t);
    if (raw.isEmpty) return {};
    return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, (v as List).map((e) => DateTime.parse(e)).toList()));
  }

  static Future<void> markTaken(Med m, [DateTime? at]) async {
    final t = taken();
    final list = t.putIfAbsent(m.id, () => [])..add(at ?? DateTime.now());
    // keep a year
    list.removeWhere((d) => d.isBefore(DateTime.now().subtract(const Duration(days: 366))));
    await Settings.i.setText(_t, jsonEncode(t.map((k, v) => MapEntry(k, v.map((d) => d.toIso8601String()).toList()))));
  }

  static DateTime? takenToday(Med m) {
    final now = DateTime.now();
    final list = taken()[m.id] ?? const [];
    final today = list.where((d) => d.year == now.year && d.month == now.month && d.day == now.day);
    return today.isEmpty ? null : today.last;
  }

  /// Average reading for each dose step of [m] (plus "Before starting"), oldest first.
  static List<(String, int, int, int, int)> byDose(Med m, List<Reading> rs) {
    final out = <(String, int, int, int, int)>[];
    if (m.steps.isEmpty) return out;
    void add(String label, Iterable<Reading> l) {
      final x = l.toList();
      if (x.isEmpty) return;
      int avg(int Function(Reading) f) => (x.map(f).reduce((a, b) => a + b) / x.length).round();
      out.add((label, avg((r) => r.systolic), avg((r) => r.diastolic), avg((r) => r.pulse), x.length));
    }

    add('Before starting', rs.where((r) => r.time.isBefore(m.steps.first.from)));
    for (var i = 0; i < m.steps.length; i++) {
      final from = m.steps[i].from, to = i + 1 < m.steps.length ? m.steps[i + 1].from : DateTime(3000);
      add(m.steps[i].dose, rs.where((r) => !r.time.isBefore(from) && r.time.isBefore(to)));
    }
    return out;
  }
}
