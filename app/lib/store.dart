import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Every reading, kept in one JSON file on the phone. Nothing leaves the phone unless a sync is switched on.
class Store extends ChangeNotifier {
  Store._();
  static final Store i = Store._();

  final List<Reading> _all = [];
  final Set<String> _deleted = {};
  File? _file;

  /// Readings for the chosen person, newest first.
  List<Reading> get readings => _all.where((r) => Settings.i.user == 0 || r.user == Settings.i.user).toList()
    ..sort((a, b) => b.time.compareTo(a.time));
  /// Every reading for every person (for backups).
  List<Reading> get everything => List.unmodifiable(_all);

  /// Which cuff user the most readings belong to (0 when there are none).
  int get mainUser {
    final n = <int, int>{};
    for (final r in _all.where((r) => r.source == 'cuff')) {
      n[r.user] = (n[r.user] ?? 0) + 1;
    }
    return n.isEmpty ? 0 : (n.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  Reading? get latest => readings.isEmpty ? null : readings.first;

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/readings.json');
    _all
      ..clear()
      ..addAll(await _read());
    await _adoptCuffReadings();
    notifyListeners();
  }

  /// One-off: readings first came in under the cuff's user number (often user 2). Unless the cuff's user
  /// buttons are in use, they all belong to the person chosen in the app.
  Future<void> _adoptCuffReadings() async {
    if (Settings.i.flag('cuff_users') || Settings.i.text('adopted_v1') == 'yes') return;
    for (final r in _all.where((r) => r.source == 'cuff')) {
      r.user = Settings.i.person;
    }
    if (Settings.i.user == 2 && !Settings.i.flag('people')) await Settings.i.setUser(1);
    await _save();
    await Settings.i.setText('adopted_v1', 'yes');
  }

  /// Moves the readings with these keys to [person].
  Future<void> transfer(Iterable<String> keys, int person) async {
    await _merge();
    final set = keys.toSet();
    for (final r in _all.where((r) => set.contains(r.key))) {
      r.user = person;
    }
    await _save();
    notifyListeners();
  }

  /// Moves every cuff reading to [person] (used when the cuff's user buttons are switched off again).
  Future<void> assignCuffReadings(int person) async {
    await _merge();
    for (final r in _all.where((r) => r.source == 'cuff')) {
      r.user = person;
    }
    await _save();
    notifyListeners();
  }

  Future<List<Reading>> _read() async {
    final f = _file!;
    if (!await f.exists()) return [];
    try {
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) => Reading.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      // a damaged file is kept aside rather than overwritten
      await f.copy('${f.path}.bad');
      return [];
    }
  }

  /// Picks up readings the other side (app or background service) wrote meanwhile.
  Future<void> refresh() async {
    if (await _merge()) notifyListeners();
  }

  Future<bool> _merge() async {
    if (_file == null) return false;
    final have = _all.map((r) => r.key).toSet();
    final extra = (await _read()).where((r) => !have.contains(r.key) && !_deleted.contains(r.key)).toList();
    _all.addAll(extra);
    return extra.isNotEmpty;
  }

  /// Adds readings not seen before. Returns the new ones.
  Future<List<Reading>> add(Iterable<Reading> rs) async {
    await _merge();
    final have = _all.map((r) => r.key).toSet();
    final fresh = rs.where((r) => have.add(r.key)).toList();
    if (fresh.isEmpty) return fresh;
    _all.addAll(fresh);
    await _save();
    notifyListeners();
    return fresh;
  }

  Future<void> update(Reading r) async {
    await _merge();
    await _save();
    notifyListeners();
  }

  Future<void> remove(Reading r) async {
    await _merge();
    _deleted.add(r.key);
    _all.removeWhere((x) => x.key == r.key);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_all.map((r) => r.toJson()).toList()));
    await tmp.rename(f.path);
  }
}

/// Switches and choices. Everything beyond reading the cuff and the history starts off.
class Settings extends ChangeNotifier {
  Settings._();
  static final Settings i = Settings._();
  late SharedPreferences _p;

  Future<void> load() async => _p = await SharedPreferences.getInstance();

  /// Settings are shared with the background service, which has its own copy in memory.
  Future<void> reload() async {
    await _p.reload();
    notifyListeners();
  }

  /// Settings that belong in a backup: switches, names, profile, medicines. Never the Home Assistant token.
  Map<String, dynamic> exportable() => {
        for (final k in _p.getKeys())
          if ((k.startsWith('f_') || k.startsWith('t_') || k == 'user') && k != 't_ha_token') k: _p.get(k),
      };

  Future<void> importFrom(Map<String, dynamic> m) async {
    for (final e in m.entries) {
      final v = e.value;
      if (e.key == 't_ha_token') continue;
      // medicines merge by name: a plan file adds or updates one medicine and leaves the others alone
      if (e.key.startsWith('t_meds_') && v is String) {
        await _p.setString(e.key, mergeMeds(_p.getString(e.key) ?? '', v));
        continue;
      }
      if (v is bool) await _p.setBool(e.key, v);
      if (v is String) await _p.setString(e.key, v);
      if (v is int) await _p.setInt(e.key, v);
    }
    notifyListeners();
  }

  /// Medicine lists are JSON arrays of {id, name, time, steps}. Same name (any case) = replaced by the incoming one.
  static String mergeMeds(String have, String incoming) {
    List<Map<String, dynamic>> parse(String s) {
      if (s.trim().isEmpty) return [];
      try {
        return (jsonDecode(s) as List).map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {
        return [];
      }
    }

    final out = parse(have), add = parse(incoming);
    for (final m in add) {
      final i = out.indexWhere((x) => '${x['name']}'.toLowerCase().trim() == '${m['name']}'.toLowerCase().trim());
      if (i >= 0) {
        out[i] = {...m, 'id': out[i]['id']};
      } else {
        out.add(m);
      }
    }
    return jsonEncode(out);
  }

  List<String> get cuffServices => _p.getStringList('cuff_svcs') ?? const [];
  Future<void> setCuffServices(List<String> v) => _p.setStringList('cuff_svcs', v);

  bool flag(String k) => _p.getBool('f_$k') ?? false;
  Future<void> setFlag(String k, bool v) async {
    await _p.setBool('f_$k', v);
    notifyListeners();
  }

  String text(String k) => _p.getString('t_$k') ?? '';
  Future<void> setText(String k, String v) async {
    await _p.setString('t_$k', v.trim());
    notifyListeners();
  }

  int get user => _p.getInt('user') ?? 1;
  String personName(int u) => text('name_$u').isEmpty ? (u == 1 ? 'Person 1' : 'Person $u') : text('name_$u');

  /// The person new readings go to: the one on screen, or person 1 when "Both" is showing.
  int get person => user == 0 ? 1 : user;
  Future<void> setUser(int u) async {
    await _p.setInt('user', u);
    notifyListeners();
    Store.i.notifyListeners();
  }

  String get cuffId => _p.getString('cuff_id') ?? '';
  String get cuffName => _p.getString('cuff_label') ?? _p.getString('cuff_name') ?? '';
  String get cuffBtName => _p.getString('cuff_name') ?? '';
  Future<void> setCuffLabel(String v) async {
    await _p.setString('cuff_label', v.trim().isEmpty ? cuffBtName : v.trim());
    notifyListeners();
  }
  Future<void> setCuff(String id, String name) async {
    await _p.setString('cuff_id', id);
    await _p.setString('cuff_name', name);
    await _p.remove('cuff_label');
    notifyListeners();
  }

  Set<String> sent(String target) => (_p.getStringList('sent_$target') ?? const []).toSet();
  /// New cuff readings waiting for "whose are these?". Empty when nothing is waiting.
  List<String> get pendingWho => _p.getStringList('pending_who') ?? const [];
  bool get askWho => !flag('cuff_users') && !flag('never_ask_who');
  Future<void> addPendingWho(Iterable<String> keys) async {
    await _p.setStringList('pending_who', {...pendingWho, ...keys}.toList());
    notifyListeners();
  }

  Future<void> clearPendingWho(Iterable<String> keys) async {
    final drop = keys.toSet();
    await _p.setStringList('pending_who', pendingWho.where((k) => !drop.contains(k)).toList());
    notifyListeners();
  }

  Future<void> markSent(String target, Iterable<String> keys) async {
    final s = sent(target)..addAll(keys);
    await _p.setStringList('sent_$target', s.toList());
  }
}
