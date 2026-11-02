import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'analysis.dart';
import 'medm_import.dart';
import 'meds.dart';
import 'models.dart';
import 'store.dart';

/// Doctor summary (PDF), spreadsheet (XLSX), CSV, and backup. All files go out through the phone's share menu.
class Reports {
  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _date(DateTime t) => '${_two(t.day)}/${_two(t.month)}/${t.year}';

  static String _who() {
    final u = Settings.i.user == 0 ? 1 : Settings.i.user;
    return [Settings.i.text('name_$u'), Settings.i.text('p_${u}_last')].where((s) => s.isNotEmpty).join(' ');
  }

  static Future<File> _file(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  static Future<void> _share(File f, String text) => SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: text));

  static String _stamp(DateTime from, DateTime to) => '${from.year}${_two(from.month)}${_two(from.day)}-${to.year}${_two(to.month)}${_two(to.day)}';

  static List<String> _row(Reading r) => [
        _date(r.time),
        hm(r.time),
        '${r.systolic}',
        '${r.diastolic}',
        '${r.pulse}',
        r.irregular ? 'yes' : '',
        r.source == 'clinic' ? 'clinic' : (r.source == 'manual' ? 'typed in' : 'cuff'),
        [...r.tags, if (r.note.isNotEmpty) r.note].join('; '),
      ];

  static const _header = ['Date', 'Time', 'Top (systolic)', 'Bottom (diastolic)', 'Pulse', 'Irregular', 'Source', 'Notes'];

  static Future<void> csv(DateTime from, DateTime to) async {
    final rs = between(Store.i.readings, from, to).reversed.toList();
    String q(String s) => s.contains(RegExp('[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    final text = [_header, ...rs.map(_row)].map((r) => r.map(q).join(',')).join('\n');
    await _share(await _file('blood-pressure-${_stamp(from, to)}.csv', utf8.encode(text)), 'Blood pressure readings');
  }

  static Future<void> xlsx(DateTime from, DateTime to) async {
    final rs = between(Store.i.readings, from, to).reversed.toList();
    final book = xl.Excel.createExcel();
    final sheet = book['Readings'];
    sheet.appendRow(_header.map((h) => xl.TextCellValue(h)).toList());
    for (final r in rs) {
      final row = _row(r);
      sheet.appendRow([
        xl.TextCellValue(row[0]),
        xl.TextCellValue(row[1]),
        xl.IntCellValue(r.systolic),
        xl.IntCellValue(r.diastolic),
        xl.IntCellValue(r.pulse),
        xl.TextCellValue(row[5]),
        xl.TextCellValue(row[6]),
        xl.TextCellValue(row[7]),
      ]);
    }
    final sum = book['Summary'];
    for (final (label, a) in _summary(rs)) {
      sum.appendRow([xl.TextCellValue(label), xl.TextCellValue(a == null ? 'none' : '${a.bp}, pulse ${a.pulse} (${a.count})')]);
    }
    book.delete('Sheet1');
    await _share(await _file('blood-pressure-${_stamp(from, to)}.xlsx', book.save()!), 'Blood pressure readings');
  }

  static List<(String, Avg?)> _summary(List<Reading> rs) {
    final home = rs.where((r) => r.source != 'clinic');
    return [
      ('All home readings', Avg.of(home)),
      ('Mornings (before 12:00)', Avg.of(home.where(isMorning))),
      ('Evenings', Avg.of(home.where((r) => !isMorning(r)))),
      if (rs.any((r) => r.source == 'clinic')) ('At the clinic', Avg.of(rs.where((r) => r.source == 'clinic'))),
    ];
  }

  static Future<void> pdf(DateTime from, DateTime to) async {
    final rs = between(Store.i.readings, from, to)..sort((a, b) => a.time.compareTo(b.time));
    final home = rs.where((r) => r.source != 'clinic').toList();
    final u = Settings.i.user == 0 ? 1 : Settings.i.user;
    final dob = DateTime.tryParse(Settings.i.text('p_${u}_dob'));
    final age = dob == null ? null : DateTime.now().difference(dob).inDays ~/ 365.25;
    final teal = PdfColor.fromHex('#147C92');
    final doc = pw.Document(title: 'Blood pressure summary', author: _who());
    final maxR = home.isEmpty ? null : home.reduce((a, b) => a.systolic >= b.systolic ? a : b);
    final minR = home.isEmpty ? null : home.reduce((a, b) => a.systolic <= b.systolic ? a : b);
    final irregular = home.where((r) => r.irregular).length;
    final meds = Settings.i.flag('meds') ? Meds.all() : <Med>[];

    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [pw.SizedBox(width: 170, child: pw.Text(k, style: const pw.TextStyle(color: PdfColors.grey700))), pw.Text(v)]),
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Open Cuff · page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (c) => [
        pw.Text('Home blood pressure summary', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: teal)),
        pw.SizedBox(height: 4),
        pw.Text([
          if (_who().isNotEmpty) _who(),
          if (dob != null) 'born ${_date(dob)} (age $age)',
          '${_date(from)} to ${_date(to.subtract(const Duration(seconds: 1)))}',
        ].join(' · ')),
        pw.SizedBox(height: 12),
        if (home.isEmpty) pw.Text('No home readings in this period.'),
        if (home.isNotEmpty) ...[
          for (final (label, a) in _summary(rs)) kv(label, a == null ? 'none' : '${a.bp} mmHg, pulse ${a.pulse} (${a.count} readings)'),
          kv('Highest', '${maxR!.systolic}/${maxR.diastolic}, pulse ${maxR.pulse} on ${_date(maxR.time)} ${hm(maxR.time)}'),
          kv('Lowest', '${minR!.systolic}/${minR.diastolic}, pulse ${minR.pulse} on ${_date(minR.time)} ${hm(minR.time)}'),
          kv('Irregular heartbeat flagged', '$irregular of ${home.length} readings'),
          pw.SizedBox(height: 14),
          pw.SizedBox(height: 170, child: _chart(home)),
          pw.SizedBox(height: 4),
          pw.Text('Red: top (systolic) · blue: bottom (diastolic) · green: pulse. Shaded band 80 to 120 mmHg.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ],
        for (final m in meds.where((m) => m.steps.isNotEmpty)) ...[
          pw.SizedBox(height: 14),
          pw.Text('${m.name}: blood pressure by dose', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: teal)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['Dose', 'From', 'Average', 'Pulse', 'Readings'],
            data: [
              for (final (label, s, d, p, n) in Meds.byDose(m, home))
                [
                  label,
                  label == 'Before starting' ? '' : _date(m.steps.firstWhere((x) => x.dose == label).from),
                  '$s/$d',
                  '$p',
                  '$n',
                ],
            ],
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
        pw.SizedBox(height: 14),
        pw.Text('All readings', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: teal)),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: _header,
          data: rs.map(_row).toList(),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          columnWidths: {7: const pw.FlexColumnWidth(3)},
        ),
        pw.SizedBox(height: 10),
        pw.Text('Readings taken at home with an OxiPro BP2 upper-arm monitor unless marked typed in or clinic. '
            'Home readings are usually lower than clinic readings; the NHS home threshold is 135/85.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    ));
    await _share(await _file('blood-pressure-summary-${_stamp(from, to)}.pdf', await doc.save()), 'Blood pressure summary');
  }

  static pw.Widget _chart(List<Reading> rs) {
    final t0 = rs.first.time.millisecondsSinceEpoch.toDouble();
    final span = (rs.last.time.millisecondsSinceEpoch - t0).toDouble().clamp(1, double.infinity);
    double x(Reading r) => (r.time.millisecondsSinceEpoch - t0) / span * 10;
    final lo = 40, hi = 180;
    pw.LineDataSet<pw.PointChartValue> line(int Function(Reading) f, PdfColor c, double w) => pw.LineDataSet(
          data: rs.map((r) => pw.PointChartValue(x(r), f(r).toDouble())).toList(),
          color: c,
          lineColor: c,
          lineWidth: w,
          pointSize: 1.6,
        );
    return pw.Stack(children: [
      pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis([0, 10], buildLabel: (v) => pw.Text(v == 0 ? _date(rs.first.time) : _date(rs.last.time), style: const pw.TextStyle(fontSize: 7))),
          yAxis: pw.FixedAxis([lo, 60, 80, 100, 120, 140, 160, hi], divisions: true, textStyle: const pw.TextStyle(fontSize: 7)),
        ),
        datasets: [
          line((r) => r.systolic, PdfColors.red600, 1.6),
          line((r) => r.diastolic, PdfColors.blue600, 1.6),
          line((r) => r.pulse, PdfColors.green600, 0.8),
        ],
      ),
    ]);
  }

  // ---- backup ----

  /// Everything except the Home Assistant token, as one JSON file.
  static Future<void> backup() async {
    final data = {
      'app': 'open_cuff',
      'version': 1,
      'made': DateTime.now().toIso8601String(),
      'readings': Store.i.everything.map((r) => r.toJson()).toList(),
      'settings': Settings.i.exportable(),
    };
    final t = DateTime.now();
    await _share(await _file('open-cuff-backup-${t.year}${_two(t.month)}${_two(t.day)}.json', utf8.encode(jsonEncode(data))), 'Open Cuff backup');
  }

  /// MedM Health "export all data" (zip) or its BLOOD_PRESSURE.csv. Null when nothing was picked.
  static Future<String?> importMedm() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    final path = picked.isEmpty ? null : picked.single.path;
    if (path == null) return null;
    try {
      final (added, dup) = await MedmImport.importFile(path, Settings.i.person);
      return 'Added $added reading${added == 1 ? '' : 's'} from MedM${dup == 0 ? '' : ', $dup already here'}';
    } catch (e) {
      return 'Could not read that file: $e';
    }
  }

  /// Returns how many readings were added, or null when nothing was picked or the file is not a backup.
  static Future<int?> restore() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    final path = picked.isEmpty ? null : picked.single.path;
    if (path == null) return null;
    try {
      final j = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      if (j['app'] != 'open_cuff') return null;
      final rs = (j['readings'] as List).map((e) => Reading.fromJson(Map<String, dynamic>.from(e)));
      final added = await Store.i.add(rs);
      await Settings.i.importFrom(Map<String, dynamic>.from(j['settings'] ?? {}));
      return added.length;
    } catch (_) {
      return null;
    }
  }
}
