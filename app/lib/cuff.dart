import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'aoj.dart' as aoj;
import 'diag.dart';
import 'models.dart';
import 'notify.dart';
import 'outbox.dart';
import 'store.dart';
import 'widget.dart';

enum CuffState { off, noPermission, looking, connecting, syncing, done, failed }

/// Watches for the cuff while the app is open and copies its readings the moment its Bluetooth comes on.
/// Read-only: the only commands sent are status, serial, system info, read data and acknowledge.
class Cuff extends ChangeNotifier {
  Cuff._();
  static final Cuff i = Cuff._();

  final _ble = FlutterReactiveBle();
  CuffState state = CuffState.off;
  String message = '';
  DateTime? lastSync, changedAt;
  StreamSubscription? _scan, _status;

  /// True inside the background service. In the app, [remote] is true while that service is running: the app then
  /// only shows the service's status and forwards Collect now to it, so the two never fight over the cuff.
  bool background = false, remote = false;
  bool _busy = false, _pairing = false;
  DateTime _cooldownUntil = DateTime(2000);

  void _set(CuffState s, [String m = '']) {
    if (s != state || m != message) {
      // a cuff label the person typed could be a name, so it never goes in the log
      final label = Settings.i.cuffName, safe = label.isEmpty || label == Settings.i.cuffBtName ? m : m.replaceAll(label, 'the cuff');
      Diag.note('cuff', '${s.name}${safe.isEmpty ? '' : ': $safe'}');
    }
    state = s;
    message = m;
    changedAt = DateTime.now();
    notifyListeners();
  }

  /// Status sent over from the background service.
  void mirror(Map data) {
    state = CuffState.values[data['state'] as int];
    message = data['message'] as String;
    lastSync = data['lastSync'] == null ? null : DateTime.parse(data['lastSync'] as String);
    notifyListeners();
  }

  Future<bool> askPermission() async {
    final res = await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
    final ok = res[Permission.bluetoothScan]!.isGranted && res[Permission.bluetoothConnect]!.isGranted;
    if (!ok) _set(CuffState.noPermission, 'Allow Nearby devices so the app can find your cuff');
    return ok;
  }

  Future<void> start({bool ask = true}) async {
    if (remote) return;
    if (ask) {
      if (!await askPermission()) return;
    } else if (!await Permission.bluetoothScan.isGranted || !await Permission.bluetoothConnect.isGranted) {
      return _set(CuffState.noPermission, 'Open Cuff needs the Nearby devices permission');
    }
    _status ??= _ble.statusStream.listen((s) {
      Diag.note('bluetooth', s.name);
      if (s == BleStatus.ready) return _startScan();
      _stopScan();
      switch (s) {
        case BleStatus.poweredOff:
          _set(CuffState.off, 'Bluetooth is off on this phone. Turn it on to sync');
        case BleStatus.unauthorized:
          _set(CuffState.noPermission, 'Allow Nearby devices so the app can find your cuff. Tap here');
        case BleStatus.locationServicesDisabled:
          _set(CuffState.off, 'Turn Location on. This phone needs it to search for Bluetooth devices');
        case BleStatus.unsupported:
          _set(CuffState.failed, 'This phone has no Bluetooth LE');
        default:
          _set(CuffState.off, 'Starting Bluetooth');
      }
    });
  }

  void stop() {
    _stopScan();
    _status?.cancel();
    _status = null;
  }

  /// Every nearby Bluetooth device with a name, for the Add device list. Pauses the automatic search meanwhile.
  Stream<DiscoveredDevice> discover() {
    _stopScan();
    _pairing = true;
    return _ble.scanForDevices(withServices: const [], scanMode: ScanMode.lowLatency).where((d) => d.name.isNotEmpty);
  }

  void endDiscover() {
    _pairing = false;
    _startScan();
  }

  /// "Collect now": connect straight to the paired cuff (its Bluetooth must be on).
  Future<void> collectNow() async {
    if (Settings.i.cuffId.isEmpty) return;
    if (remote) {
      _set(CuffState.connecting, 'Connecting to ${Settings.i.cuffName}');
      return onCollectRemote?.call();
    }
    _stopScan();
    await sync(Settings.i.cuffId, Settings.i.cuffName);
  }

  void Function()? onCollectRemote;

  void _startScan() {
    if (_scan != null || _busy || _pairing || remote) return;
    if (state != CuffState.done) _set(CuffState.looking, 'Turn the cuff on or take a reading');
    // With the screen off, Android only delivers scan results that match a filter, so the background service filters
    // on the services the cuff was seen advertising (recorded the first time it is found).
    final svcs = background ? Settings.i.cuffServices.map(Uuid.parse).toList() : const <Uuid>[];
    _scan = _ble.scanForDevices(withServices: svcs, scanMode: background ? ScanMode.balanced : ScanMode.lowLatency).listen((d) {
      final known = Settings.i.cuffId;
      final match = known.isNotEmpty ? d.id == known : (d.name.contains('OxiPro') || d.name.startsWith('BP2'));
      if (match && Settings.i.cuffServices.isEmpty) {
        Diag.note('scan', 'cuff found (${d.name}), advertises ${d.serviceUuids.length} service(s), signal ${d.rssi} dBm');
      }
      if (match && d.serviceUuids.isNotEmpty && Settings.i.cuffServices.isEmpty) {
        Settings.i.setCuffServices(d.serviceUuids.map((u) => u.toString()).toList());
      }
      if (match && DateTime.now().isAfter(_cooldownUntil)) {
        _stopScan();
        sync(d.id, d.name);
      }
    }, onError: (Object e, StackTrace st) {
      _scan = null;
      Diag.error('scan', e, st);
      _set(CuffState.failed, 'Could not search for the cuff');
    });
  }

  void _stopScan() {
    _scan?.cancel();
    _scan = null;
  }

  Future<void> sync(String id, String name) async {
    if (_busy) return;
    _busy = true;
    Diag.note('sync', 'start (${background ? 'background' : 'app'}, ${Settings.i.cuffId.isEmpty ? 'first pairing' : 'paired cuff'})');
    _set(CuffState.connecting, 'Connecting to $name');
    StreamSubscription? conn, notes;
    final parser = aoj.FrameParser();
    final frames = StreamController<aoj.Frame>();
    var count = 0;
    try {
      // Android often refuses a connection made the instant a scan stops, or one to a device it still holds a stale
      // link to. So: a short pause, then up to 3 tries, clearing the cached connection between them.
      await Future.delayed(const Duration(milliseconds: 500));
      Object? lastError;
      for (var attempt = 1; attempt <= 3; attempt++) {
        final connected = Completer<void>();
        conn = _ble.connectToDevice(id: id, connectionTimeout: const Duration(seconds: 10)).listen((u) {
          if (u.connectionState == DeviceConnectionState.connected && !connected.isCompleted) connected.complete();
          if (u.connectionState == DeviceConnectionState.disconnected && !connected.isCompleted) {
            connected.completeError('disconnected');
          }
        }, onError: (Object e) {
          if (!connected.isCompleted) connected.completeError(e);
        });
        try {
          await connected.future.timeout(const Duration(seconds: 12));
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          Diag.note('sync', 'connect try $attempt of 3 failed: $e');
          await conn.cancel();
          conn = null;
          if (attempt < 3) {
            _set(CuffState.connecting, 'Connecting to $name (try ${attempt + 1} of 3)');
            try {
              await _ble.clearGattCache(id);
            } catch (_) {}
            await Future.delayed(const Duration(milliseconds: 800));
          }
        }
      }
      if (lastError != null) throw 'The cuff went to sleep before it connected. Press its left button and tap Collect now';
      if (Settings.i.cuffId.isEmpty) await Settings.i.setCuff(id, name);
      _set(CuffState.syncing, 'Copying readings');

      QualifiedCharacteristic ch(String c) =>
          QualifiedCharacteristic(serviceId: Uuid.parse(aoj.serviceUuid), characteristicId: Uuid.parse(c), deviceId: id);
      await _ble.discoverAllServices(id);
      notes = _ble.subscribeToCharacteristic(ch(aoj.notifyUuid)).listen((data) {
        for (final f in parser.feed(data)) {
          frames.add(f);
        }
      });
      final q = StreamQueue(frames.stream);
      Future<void> send(List<int> f) => _ble.writeCharacteristicWithoutResponse(ch(aoj.writeUuid), value: f);
      Future<void> settle() async {
        while (await q.next(const Duration(milliseconds: 1500)) != null) {}
      }

      await Future.delayed(const Duration(milliseconds: 400));
      await send(aoj.btStatus());
      await settle();
      await send(aoj.getSerial());
      await settle();
      await send(aoj.getSystemInfo());
      await settle();
      await send(aoj.getData());
      final got = <Reading>[];
      while (true) {
        final f = await q.next(const Duration(seconds: 6));
        if (f == null) break;
        if (!aoj.readingCmds.contains(f.cmd)) continue;
        await send(aoj.ack());
        final r = aoj.parseReading(f.data);
        if (r == null) continue;
        got.add(Reading(
          key: Reading.makeKey(r.time, r.systolic, r.diastolic, r.pulse),
          time: r.time,
          systolic: r.systolic,
          diastolic: r.diastolic,
          pulse: r.pulse,
          irregular: r.irregular,
          // whoever is chosen in the app, unless the cuff's own user buttons are switched on in Your cuff
          cuffUser: r.user,
          user: Settings.i.flag('cuff_users') ? (r.user == 0 ? 1 : r.user) : Settings.i.person,
        ));
      }
      final fresh = await Store.i.add(got);
      count = fresh.length;
      Diag.note('sync', 'cuff sent ${got.length} reading(s), ${fresh.length} new');
      if (fresh.isNotEmpty && Settings.i.askWho) {
        await Settings.i.addPendingWho(fresh.map((r) => r.key));
        if (background) unawaited(Notify.whoseReadings(Settings.i.pendingWho.length));
      }
      unawaited(Notify.afterSync(fresh));
      unawaited(updateWidget());
      lastSync = DateTime.now();
      _set(CuffState.done, count == 0 ? 'Up to date' : '$count new reading${count == 1 ? '' : 's'}');
      unawaited(Outbox.flush());
    } catch (e, st) {
      Diag.error('sync', e, e is String ? null : st);
      _set(CuffState.failed, e is TimeoutException ? 'The cuff went to sleep. Press its left button and try again' : '$e');
    } finally {
      await notes?.cancel();
      await conn?.cancel(); // cancelling the connection stream disconnects
      await frames.close();
      _busy = false;
      _cooldownUntil = DateTime.now().add(const Duration(seconds: 20));
      Future.delayed(const Duration(seconds: 21), _startScan);
    }
  }
}

/// Minimal pull-style reader over a stream, with a per-item timeout.
class StreamQueue<T> {
  final _items = <T>[];
  Completer<void>? _wait;
  StreamQueue(Stream<T> s) {
    s.listen((e) {
      _items.add(e);
      _wait?.complete();
      _wait = null;
    });
  }

  Future<T?> next(Duration timeout) async {
    if (_items.isEmpty) {
      _wait = Completer<void>();
      try {
        await _wait!.future.timeout(timeout);
      } on TimeoutException {
        _wait = null;
        return null;
      }
    }
    return _items.isEmpty ? null : _items.removeAt(0);
  }
}
