import 'dart:convert';

import 'package:health/health.dart';
import 'package:http/http.dart' as http;

import 'diag.dart';
import 'models.dart';
import 'store.dart';

/// Copies readings to Health Connect and Home Assistant when those switches are on. Each reading goes once per target;
/// a target that fails is retried on the next sync.
class Outbox {
  static final _health = Health();
  static bool _configured = false;
  static String lastError = '';

  static const healthTypes = [
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.HEART_RATE,
  ];

  static Future<void> _configure() async {
    if (!_configured) await _health.configure();
    _configured = true;
  }

  /// Health Connect status in plain words, or '' when ready.
  static Future<String> healthProblem() async {
    await _configure();
    final s = await _health.getHealthConnectSdkStatus();
    if (s == HealthConnectSdkStatus.sdkAvailable) return '';
    if (s == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) return 'Health Connect needs an update';
    return 'Health Connect is not on this phone';
  }

  static Future<bool> askHealth() async {
    await _configure();
    if (await healthProblem() != '') {
      await _health.installHealthConnect();
      return false;
    }
    return _health.requestAuthorization(healthTypes,
        permissions: healthTypes.map((_) => HealthDataAccess.WRITE).toList());
  }

  static bool _flushing = false;

  static const _contextTypes = [HealthDataType.SLEEP_SESSION, HealthDataType.RESTING_HEART_RATE];

  static Future<bool> askContext() async {
    await _configure();
    if (await healthProblem() != '') return false;
    return _health.requestAuthorization(_contextTypes, permissions: _contextTypes.map((_) => HealthDataAccess.READ).toList());
  }

  /// Sleep in the night before [t] and the latest resting heart rate that day, from a watch via Health Connect.
  static Future<(Duration?, int?)> contextFor(DateTime t) async {
    try {
      await _configure();
      final pts = await _health.getHealthDataFromTypes(
          types: _contextTypes, startTime: t.subtract(const Duration(hours: 20)), endTime: t.add(const Duration(minutes: 1)));
      var sleep = Duration.zero;
      int? rhr;
      for (final p in pts) {
        if (p.type == HealthDataType.SLEEP_SESSION) sleep += p.dateTo.difference(p.dateFrom);
        if (p.type == HealthDataType.RESTING_HEART_RATE && p.value is NumericHealthValue) {
          rhr = (p.value as NumericHealthValue).numericValue.round();
        }
      }
      return (sleep == Duration.zero ? null : sleep, rhr);
    } catch (_) {
      return (null, null);
    }
  }

  static Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await _flush();
    } finally {
      _flushing = false;
    }
  }

  static Future<void> _flush() async {
    lastError = '';
    await Settings.i.reload();
    await Store.i.refresh();
    // only the phone owner's readings (person 1), and never ones still waiting for "whose are these?"
    final waiting = Settings.i.pendingWho.toSet();
    final all = Store.i.everything.where((r) => r.user == 1 && !waiting.contains(r.key)).toList();
    if (Settings.i.flag('health')) await _toHealth(all);
    if (Settings.i.flag('ha')) await _toHa(all);
  }

  static Future<void> _toHealth(List<Reading> all) async {
    try {
      await _configure();
      final done = Settings.i.sent('health');
      final ok = <String>[];
      for (final r in all.where((r) => !done.contains(r.key))) {
        final bp = await _health.writeBloodPressure(
          systolic: r.systolic,
          diastolic: r.diastolic,
          startTime: r.time,
          clientRecordId: 'opencuff-bp-${r.key}',
          recordingMethod: r.source == 'manual' ? RecordingMethod.manual : RecordingMethod.automatic,
        );
        final hr = await _health.writeHealthData(
          value: r.pulse.toDouble(),
          type: HealthDataType.HEART_RATE,
          unit: HealthDataUnit.BEATS_PER_MINUTE,
          startTime: r.time,
          endTime: r.time.add(const Duration(seconds: 1)),
          clientRecordId: 'opencuff-hr-${r.key}',
          recordingMethod: r.source == 'manual' ? RecordingMethod.manual : RecordingMethod.automatic,
        );
        if (bp && hr) ok.add(r.key);
      }
      await Settings.i.markSent('health', ok);
      if (ok.isNotEmpty) Diag.note('send', 'Health Connect: ${ok.length} reading(s) written');
    } catch (e, st) {
      lastError = 'Health Connect: $e';
      Diag.error('send', 'Health Connect: $e', st);
    }
  }

  /// Fires the same `bp2_ble_reading` event the Home Assistant integration fires, so existing automations keep working.
  static Future<void> _toHa(List<Reading> all) async {
    final url = Settings.i.text('ha_url'), token = Settings.i.text('ha_token');
    if (url.isEmpty || token.isEmpty) return;
    final done = Settings.i.sent('ha');
    final ok = <String>[];
    try {
      for (final r in all.where((r) => !done.contains(r.key) && r.time.isAfter(DateTime.now().subtract(const Duration(hours: 3))))) {
        final res = await http
            .post(Uri.parse('${url.replaceAll(RegExp(r'/+$'), '')}/api/events/bp2_ble_reading'),
                headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
                body: jsonEncode({
                  'address': 'open-cuff',
                  'file': r.key,
                  'time': _isoLocal(r.time),
                  'systolic': r.systolic,
                  'diastolic': r.diastolic,
                  'mean': r.mean,
                  'pulse': r.pulse,
                  'irregular': r.irregular,
                }))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          ok.add(r.key);
        } else {
          Diag.note('send', 'Home Assistant answered ${res.statusCode}${res.statusCode == 401 ? ' (token not accepted)' : ''}');
        }
      }
      if (ok.isNotEmpty) Diag.note('send', 'Home Assistant: ${ok.length} reading(s) sent');
      // older readings are history: mark them so they are never announced
      ok.addAll(all.where((r) => !done.contains(r.key) && !r.time.isAfter(DateTime.now().subtract(const Duration(hours: 3)))).map((r) => r.key));
      await Settings.i.markSent('ha', ok);
    } catch (e) {
      lastError = 'Home Assistant: $e';
      Diag.note('send', 'Home Assistant failed: ${e.runtimeType} ${Diag.clean('$e')}');
    }
  }

  static String _isoLocal(DateTime t) {
    final o = t.timeZoneOffset;
    final sign = o.isNegative ? '-' : '+';
    final h = o.inHours.abs().toString().padLeft(2, '0'), m = (o.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${t.toIso8601String().split('.').first}$sign$h:$m';
  }
}
