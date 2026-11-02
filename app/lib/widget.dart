import 'package:home_widget/home_widget.dart';

import 'models.dart';
import 'store.dart';

/// Keeps the home screen widget in step with the latest reading. Harmless when no widget is placed.
Future<void> updateWidget() async {
  try {
    final r = Store.i.latest;
    final calm = Settings.i.flag('calm');
    await HomeWidget.saveWidgetData<String>('bp', r == null ? 'No reading yet' : (calm ? r.band.words : '${r.systolic}/${r.diastolic}'));
    await HomeWidget.saveWidgetData<String>('detail', r == null ? 'Open Cuff' : '${calm ? '' : '♥ ${r.pulse} · '}${when(r.time)}');
    await HomeWidget.updateWidget(qualifiedAndroidName: 'io.github.domocn.open_cuff.CuffWidget');
  } catch (_) {}
}
