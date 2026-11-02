import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'models.dart';
import 'store.dart';

/// Reads MedM Health's "export all data": the zip, or its BLOOD_PRESSURE.csv on its own.
/// Columns: "Date","Time","Sys","Dia","Pulse","Irregular pulse","Source".
class MedmImport {
  static List<Reading> parse(String csv, int person) {
    final out = <Reading>[];
    final lines = const LineSplitter().convert(csv.replaceFirst('\uFEFF', ''));
    if (lines.isEmpty) return out;
    final head = _cells(lines.first).map((c) => c.toLowerCase()).toList();
    int col(String name) => head.indexWhere((h) => h.startsWith(name));
    final iDate = col('date'), iTime = col('time'), iSys = col('sys'), iDia = col('dia'), iPulse = col('pulse'), iIrr = col('irregular'), iSrc = col('source');
    if ([iDate, iTime, iSys, iDia].contains(-1)) return out;
    for (final line in lines.skip(1)) {
      final c = _cells(line);
      if (c.length <= iDia) continue;
      final t = DateTime.tryParse('${c[iDate]}T${c[iTime].padLeft(5, '0')}:00');
      final s = int.tryParse(c[iSys]), d = int.tryParse(c[iDia]), p = iPulse < 0 ? 0 : int.tryParse(c[iPulse]) ?? 0;
      if (t == null || s == null || d == null) continue;
      final src = iSrc < 0 ? '' : c[iSrc];
      out.add(Reading(
        key: '${Reading.makeKey(t, s, d, p)}-medm',
        time: t,
        systolic: s,
        diastolic: d,
        pulse: p,
        irregular: iIrr >= 0 && c[iIrr].toLowerCase() == 'detected',
        user: person,
        source: src.contains('OxiPro') || src.contains('BP2') ? 'cuff' : 'manual',
        note: src.isEmpty ? 'From MedM' : 'From MedM ($src)',
      ));
    }
    return out;
  }

  static List<String> _cells(String line) {
    final out = <String>[];
    final b = StringBuffer();
    var q = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (q && i + 1 < line.length && line[i + 1] == '"') {
          b.write('"');
          i++;
        } else {
          q = !q;
        }
      } else if (ch == ',' && !q) {
        out.add(b.toString());
        b.clear();
      } else {
        b.write(ch);
      }
    }
    out.add(b.toString());
    return out;
  }

  /// Adds the readings that aren't already in the app (same numbers within 2 minutes counts as the same reading).
  /// Returns (added, already there).
  static Future<(int, int)> importFile(String path, int person) async {
    final bytes = await File(path).readAsBytes();
    String csv;
    if (path.toLowerCase().endsWith('.zip')) {
      final zip = ZipDecoder().decodeBytes(bytes);
      final f = zip.files.firstWhere((f) => f.name.toUpperCase().endsWith('BLOOD_PRESSURE.CSV'), orElse: () => throw 'No BLOOD_PRESSURE.csv in that zip');
      csv = utf8.decode(f.content as List<int>, allowMalformed: true);
    } else {
      csv = utf8.decode(bytes, allowMalformed: true);
    }
    final found = parse(csv, person);
    final have = Store.i.everything;
    bool dup(Reading r) => have.any((h) =>
        h.systolic == r.systolic && h.diastolic == r.diastolic && h.pulse == r.pulse && h.time.difference(r.time).inSeconds.abs() < 120);
    final fresh = found.where((r) => !dup(r)).toList();
    final added = await Store.i.add(fresh);
    return (added.length, found.length - fresh.length);
  }
}
