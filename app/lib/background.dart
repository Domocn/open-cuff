import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'cuff.dart';
import 'diag.dart';
import 'models.dart';
import 'outbox.dart';
import 'store.dart';

/// Background collecting: an Android foreground service (small ongoing notification) that keeps watching for the cuff
/// with the app closed or the screen locked. It runs its own copy of the cuff logic in a separate isolate and tells
/// the app when readings arrive; the app then reloads the shared readings file.
class Background {
  static bool get wanted => Settings.i.flag('background');

  static void init() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'open_cuff_watch',
        channelName: 'Watching for your cuff',
        channelDescription: 'Shown while Open Cuff collects readings in the background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5 * 60 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowAutoRestart: true,
      ),
    );
  }

  static Future<bool> get running => FlutterForegroundTask.isRunningService;

  /// Asks for the notification permission (so the ongoing notice can show) and to be left alone by battery saving.
  static Future<void> askPermissions() async {
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  static Future<void> start() async {
    if (await running) return;
    Diag.note('service', 'starting');
    await FlutterForegroundTask.startService(
      serviceId: 2604,
      serviceTypes: [ForegroundServiceTypes.connectedDevice],
      notificationTitle: 'Open Cuff',
      notificationText: 'Watching for your cuff',
      notificationIcon: null,
      callback: startCallback,
    );
  }

  static Future<void> stop() async {
    if (await running) await FlutterForegroundTask.stopService();
  }

  static void collectNow() => FlutterForegroundTask.sendDataToTask('collect');
}

@pragma('vm:entry-point')
void startCallback() => FlutterForegroundTask.setTaskHandler(_Watcher());

class _Watcher extends TaskHandler {
  void _report() {
    final c = Cuff.i;
    FlutterForegroundTask.sendDataToMain({
      'state': c.state.index,
      'message': c.message,
      'lastSync': c.lastSync?.toIso8601String(),
      'changed': c.changedAt?.toIso8601String(),
    });
    final r = Store.i.latest;
    FlutterForegroundTask.updateService(
      notificationText: r == null
          ? 'Watching for your cuff'
          : 'Latest ${r.systolic}/${r.diastolic}, pulse ${r.pulse} · ${when(r.time)}',
    );
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    Diag.tag = 'bg';
    Diag.note('service', 'started (${starter.name})');
    await Settings.i.load();
    await Store.i.load();
    Cuff.i.background = true;
    Cuff.i.addListener(_report);
    await Cuff.i.start(ask: false);
    _report();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // a heartbeat: picks up setting changes from the app and restarts the search if Bluetooth was off
    Settings.i.reload().then((_) => Cuff.i.start(ask: false));
    unawaited(Outbox.flush());
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'collect') {
      Settings.i.reload().then((_) => Cuff.i.collectNow());
    } else if (data == 'reload') {
      Settings.i.reload();
    }
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    Diag.note('service', 'stopped${isTimeout ? ' (Android time limit)' : ''}');
    Cuff.i.removeListener(_report);
    Cuff.i.stop();
  }
}
