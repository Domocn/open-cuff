import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'analysis.dart';
import 'meds.dart';
import 'models.dart';
import 'store.dart';

/// Calm notifications: no sound, one at a time, plain words. Each kind is behind its own feature switch.
class Notify {
  static final _n = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _alerts = NotificationDetails(
    android: AndroidNotificationDetails('alerts', 'Readings to look at',
        channelDescription: 'Limits, trends and irregular heartbeats', importance: Importance.defaultImportance, playSound: false),
  );
  static const _nudges = NotificationDetails(
    android: AndroidNotificationDetails('nudges', 'Reminders',
        channelDescription: 'Reading and dose reminders, Sunday summary', importance: Importance.low, playSound: false),
  );

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/London'));
    }
    await _n.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  }

  static Future<void> askPermission() async {
    await init();
    await _n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  /// After new readings arrive: limits, trends, irregular heartbeats. Each message is shown once.
  static Future<void> afterSync(List<Reading> fresh) async {
    if (fresh.isEmpty) return;
    await init();
    final all = Store.i.readings;
    if (Settings.i.flag('goals')) {
      for (final r in fresh.where((r) => r.time.isAfter(DateTime.now().subtract(const Duration(hours: 6))))) {
        final m = overLimit(r);
        if (m != null) await _n.show(id: 10, title: '${r.systolic}/${r.diastolic}, pulse ${r.pulse}', body: m, notificationDetails: _alerts);
      }
      final week = between(all, DateTime.now().subtract(const Duration(days: 7)), DateTime.now()).where((r) => r.irregular).length;
      if (week >= 3 && fresh.any((r) => r.irregular) && _once('irr_${DateTime.now().day}')) {
        await _n.show(
            id: 11,
            title: 'Irregular heartbeat noticed $week times this week',
            body: 'One now and then is common. If it keeps happening, mention it to your doctor.',
            notificationDetails: _alerts);
      }
    }
    if (Settings.i.flag('trends')) {
      final t = trendMessage(all);
      if (t != null && _once('trend_$t')) {
        await _n.show(id: 12, title: 'Your blood pressure has changed', body: t, notificationDetails: _alerts);
      }
    }
  }

  static Future<void> whoseReadings(int n) async {
    await init();
    await _n.show(
        id: 13,
        title: '$n new reading${n == 1 ? '' : 's'} from the cuff',
        body: 'Whose ${n == 1 ? 'is it' : 'are they'}? Tap to choose.',
        notificationDetails: _nudges);
  }

  static final _shown = <String>{};
  static bool _once(String k) {
    final seen = Settings.i.text('shown_alerts').split('|').toSet();
    if (seen.contains(k) || _shown.contains(k)) return false;
    _shown.add(k);
    Settings.i.setText('shown_alerts', (seen.toList()..add(k)).reversed.take(30).join('|'));
    return true;
  }

  /// Re-plans the repeating reminders from the current switches. Safe to call any time.
  static Future<void> reschedule() async {
    await init();
    for (final id in [20, 21, 22, 30, 31, 32, 33, 34]) {
      await _n.cancel(id: id);
    }
    if (Settings.i.flag('reminders')) {
      await _daily(20, Settings.i.text('remind_am').ifEmpty('08:30'), 'Time for a reading', 'Sit for 5 minutes first. The cuff\'s reading will appear in Open Cuff by itself.');
      await _daily(21, Settings.i.text('remind_pm').ifEmpty('20:30'), 'Evening reading', 'Sit for 5 minutes first, then press Start on the cuff.');
    }
    if (Settings.i.flag('weekly')) {
      await _weekly(22, DateTime.sunday, '18:00', 'Your week', weeklySummary(Store.i.readings));
    }
    if (Settings.i.flag('meds')) {
      var id = 30;
      for (final m in Meds.all().where((m) => m.time.isNotEmpty).take(5)) {
        await _daily(id++, m.time, 'Time for ${m.name}', '${m.current?.dose ?? ''} · tap Taken in Open Cuff'.trim());
      }
    }
  }

  static tz.TZDateTime _next(String hm, {int? weekday}) {
    final p = hm.split(':');
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
    while (t.isBefore(now) || (weekday != null && t.weekday != weekday)) {
      t = t.add(const Duration(days: 1));
    }
    return t;
  }

  static Future<void> _daily(int id, String hm, String title, String body) => _n.zonedSchedule(
        id: id,
        scheduledDate: _next(hm),
        notificationDetails: _nudges,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        matchDateTimeComponents: DateTimeComponents.time,
      );

  static Future<void> _weekly(int id, int weekday, String hm, String title, String body) => _n.zonedSchedule(
        id: id,
        scheduledDate: _next(hm, weekday: weekday),
        notificationDetails: _nudges,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
