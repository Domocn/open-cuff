import 'store.dart';

/// One step of a blood pressure scale. A reading is in the first zone whose limits it does not go over
/// (both numbers), so the higher of the two numbers decides. [severity]: 0 low, 1 ideal, 2 raised, 3 high, 4 very high.
class Zone {
  final String name;
  final int maxSys, maxDia, severity;
  const Zone(this.name, this.maxSys, this.maxDia, this.severity);
}

class BpScale {
  final String id, name, about;
  final int lowSys, lowDia; // under either of these is "Low"; 0 when the scale has no Low step
  final List<Zone> zones; // ascending, including Low first when there is one; the last one is open-ended
  const BpScale(this.id, this.name, this.about, this.lowSys, this.lowDia, this.zones);

  bool get hasLow => lowSys > 0;
  List<Zone> get upper => hasLow ? zones.skip(1).toList() : zones;

  Zone zoneFor(int s, int d) {
    if (hasLow && (s < lowSys || d < lowDia)) return zones.first;
    for (final z in upper) {
      if (s <= z.maxSys && d <= z.maxDia) return z;
    }
    return zones.last;
  }

  /// Where "high" starts on this scale; used as the default alert limit.
  (int, int) get highFrom {
    final i = upper.indexWhere((z) => z.severity >= 3);
    final prev = upper[i - 1];
    return (prev.maxSys + 1, prev.maxDia + 1);
  }
}

const _open = 999;

/// Nine blood pressure scales, with the limits from each published guideline.
const scales = <BpScale>[
  BpScale('esh2023', 'ESH 2023 (Europe)', '2023 European Society of Hypertension guidelines.', 0, 0, [
    Zone('Optimal', 119, 79, 1),
    Zone('Normal', 129, 84, 1),
    Zone('High normal', 139, 89, 2),
    Zone('Grade 1 hypertension', 159, 99, 3),
    Zone('Grade 2 hypertension', 179, 109, 4),
    Zone('Grade 3 hypertension', _open, _open, 4),
  ]),
  BpScale('esc2024', 'ESC 2024 (Europe)', '2024 European Society of Cardiology guidelines.', 0, 0, [
    Zone('Not raised', 119, 69, 1),
    Zone('Elevated', 139, 89, 2),
    Zone('Hypertension', _open, _open, 3),
  ]),
  BpScale('jnc7', 'JNC 7 (USA)', 'The Seventh Report of the Joint National Committee on high blood pressure.', 90, 60, [
    Zone('Low', 89, 59, 0),
    Zone('Normal', 119, 79, 1),
    Zone('Prehypertension', 139, 89, 2),
    Zone('Stage 1 hypertension', 159, 99, 3),
    Zone('Stage 2 hypertension', _open, _open, 4),
  ]),
  BpScale('aha', 'ACC/AHA (USA)', 'American College of Cardiology and American Heart Association guideline for adults.', 0, 0, [
    Zone('Normal', 119, 79, 1),
    Zone('Elevated', 129, 79, 2),
    Zone('Stage 1 hypertension', 139, 89, 3),
    Zone('Stage 2 hypertension', _open, _open, 4),
  ]),
  BpScale('ish2020', 'ISH 2020', 'International Society of Hypertension global practice guidelines.', 0, 0, [
    Zone('Normal', 129, 84, 1),
    Zone('High normal', 139, 89, 2),
    Zone('Grade 1 hypertension', 159, 99, 3),
    Zone('Grade 2 hypertension', _open, _open, 4),
  ]),
  BpScale('nice_home', 'NICE 2019 home', 'NICE guideline for diagnosing and managing high blood pressure, home readings.', 0, 0, [
    Zone('Normal', 134, 84, 1),
    Zone('Stage 1 hypertension', 149, 94, 3),
    Zone('Stage 2 hypertension', _open, _open, 4),
  ]),
  BpScale('nice_clinic', 'NICE 2019 clinic', 'NICE guideline for diagnosing and managing high blood pressure, clinic readings.', 0, 0, [
    Zone('Normal', 139, 89, 1),
    Zone('Stage 1 hypertension', 159, 99, 3),
    Zone('Stage 2 hypertension', 179, 119, 4),
    Zone('Stage 3 hypertension', _open, _open, 4),
  ]),
  BpScale('nhs_home', 'NHS (UK) home', 'NHS guidance for readings taken at home. Home readings run a little lower than at the GP, so the limits are lower.', 90, 60, [
    Zone('Low', 89, 59, 0),
    Zone('Healthy', 120, 80, 1),
    Zone('Raised', 134, 84, 2),
    Zone('Stage 1 hypertension', 149, 94, 3),
    Zone('Stage 2 hypertension', _open, _open, 4),
  ]),
  BpScale('nhs_clinic', 'NHS (UK) clinic', 'NHS guidance for readings taken by a nurse or GP.', 90, 60, [
    Zone('Low', 89, 59, 0),
    Zone('Healthy', 120, 80, 1),
    Zone('Raised', 139, 89, 2),
    Zone('Stage 1 hypertension', 159, 99, 3),
    Zone('Stage 2 hypertension', 179, 119, 4),
    Zone('Stage 3 hypertension', _open, _open, 4),
  ]),
];

BpScale get currentScale {
  String id;
  try {
    id = Settings.i.text('scale');
  } catch (_) {
    id = ''; // settings not loaded yet (tests, first frame): NHS home
  }
  return scales.firstWhere((s) => s.id == id, orElse: () => scales.firstWhere((s) => s.id == 'nhs_home'));
}
