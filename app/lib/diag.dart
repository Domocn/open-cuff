import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The problem log behind More > Report a problem: what the app did (cuff states, connect tries, syncs, sending,
/// background service, crashes) as plain dated lines, kept in the app's own files.
///
/// It is meant to be pasted into a public GitHub issue, so it never holds readings, names, the cuff's full Bluetooth
/// address, web addresses or tokens. Callers log events, not values, and [clean] strips anything that slips through.
class Diag {
  /// 'app' in the app, 'bg' in the background service (separate isolate, same file).
  static String tag = 'app';
  static File? _f;
  static const _maxBytes = 200000, _keepLines = 1500;

  static Future<File> _file() async => _f ??= File('${(await getApplicationSupportDirectory()).path}/problem_log.txt');

  static String clean(String s) => s
      .replaceAllMapped(RegExp(r'(?:[0-9A-Fa-f]{2}:){5}([0-9A-Fa-f]{2})'), (m) => 'cuff..${m.group(1)}')
      .replaceAll(RegExp(r'Bearer\s+\S+'), 'Bearer <hidden>')
      .replaceAll(RegExp(r'https?://\S+'), '<address>')
      .replaceAll(RegExp(r'\b\d{2,3}\s*/\s*\d{2,3}\b'), '<reading>');

  static Future<void> log(String area, String msg) async {
    final line = '${DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ')} [$tag/$area] ${clean(msg)}';
    debugPrint('OpenCuff: $line');
    try {
      final f = await _file();
      await f.writeAsString('$line\n', mode: FileMode.append, flush: true);
      if (await f.length() > _maxBytes) {
        final lines = await f.readAsLines();
        await f.writeAsString('${lines.skip(lines.length - _keepLines).join('\n')}\n', flush: true);
      }
    } catch (_) {}
  }

  /// Fire and forget, for places that can't wait.
  static void note(String area, String msg) => unawaited(log(area, msg));

  /// Errors and crashes: the message plus the first few stack lines.
  static void error(String area, Object e, [StackTrace? s]) {
    final stack = (s?.toString() ?? '').split('\n').where((l) => l.trim().isNotEmpty).take(6).join('\n    ');
    note(area, 'ERROR $e${stack.isEmpty ? '' : '\n    $stack'}');
  }

  static Future<String> read() async {
    try {
      final f = await _file();
      return await f.exists() ? await f.readAsString() : '';
    } catch (_) {
      return '';
    }
  }

  static Future<File> file() => _file();

  static Future<void> clear() async {
    try {
      await (await _file()).writeAsString('');
    } catch (_) {}
  }
}
