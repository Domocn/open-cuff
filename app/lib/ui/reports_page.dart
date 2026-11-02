import 'package:flutter/material.dart';

import '../analysis.dart';
import '../reports.dart';
import '../store.dart';
import 'theme.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  int _days = 28;
  DateTimeRange? _custom;
  bool _busy = false;

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day + 1);
    if (_days == 0 && _custom != null) {
      return (_custom!.start, DateTime(_custom!.end.year, _custom!.end.month, _custom!.end.day + 1));
    }
    return (end.subtract(Duration(days: _days == 0 ? 28 : _days)), end);
  }

  Future<void> _run(Future<void> Function(DateTime, DateTime) f) async {
    setState(() => _busy = true);
    try {
      final (a, b) = _range;
      await f(a, b);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not make the file: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) {
          final (from, to) = _range;
          final n = between(Store.i.readings, from, to).length;
          return ListView(padding: EdgeInsets.fromLTRB(14, MediaQuery.paddingOf(context).top + 12, 14, 24), children: [
            Text('Reports', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 14, label: Text('2 wks')),
                ButtonSegment(value: 28, label: Text('4 wks')),
                ButtonSegment(value: 91, label: Text('3 mo')),
                ButtonSegment(value: 0, label: Text('Dates')),
              ],
              selected: {_days},
              onSelectionChanged: (s) async {
                if (s.first == 0) {
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: _custom,
                  );
                  if (r == null) return;
                  _custom = r;
                }
                setState(() => _days = s.first);
              },
            ),
            const SizedBox(height: 6),
            Text('$n reading${n == 1 ? '' : 's'} in this period', style: muted(context)),
            const SizedBox(height: 12),
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Row(children: [Icon(Icons.picture_as_pdf_outlined), SizedBox(width: 10), Text('Doctor summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]),
                const SizedBox(height: 6),
                Text(
                    'Morning and evening averages, highest and lowest, irregular heartbeats, blood pressure at each dose, '
                    'a chart and every reading with your notes.',
                    style: muted(context)),
                const SizedBox(height: 10),
                FilledButton(onPressed: _busy || n == 0 ? null : () => _run(Reports.pdf), child: const Text('Make PDF')),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Box(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('Excel', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text('Readings and a summary sheet', style: muted(context)),
                    const SizedBox(height: 8),
                    FilledButton.tonal(onPressed: _busy || n == 0 ? null : () => _run(Reports.xlsx), child: const Text('Make XLSX')),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Box(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('CSV', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text('For any spreadsheet or app', style: muted(context)),
                    const SizedBox(height: 8),
                    FilledButton.tonal(onPressed: _busy || n == 0 ? null : () => _run(Reports.csv), child: const Text('Make CSV')),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text('Files go through your phone\'s share menu: email, WhatsApp, Drive or Files.', style: muted(context)),
            const SizedBox(height: 22),
            const Text('Bring in old readings', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('From MedM Health: Export > all data gives a zip. Pick the zip (or BLOOD_PRESSURE.csv). '
                    'Readings already in Open Cuff are skipped.', style: muted(context)),
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: _busy
                      ? null
                      : () async {
                          final m = await Reports.importMedm();
                          if (m != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
                        },
                  child: const Text('Import from MedM'),
                ),
              ]),
            ),
            const SizedBox(height: 22),
            const Text('Backup', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('One file with every reading, your health record, medicines and settings (not your Home Assistant token). '
                    'Save it to Google Drive or Files.', style: muted(context)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: FilledButton.tonal(onPressed: _busy ? null : () => _run((_, _) => Reports.backup()), child: const Text('Back up'))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              final n = await Reports.restore();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(n == null ? 'That file is not an Open Cuff backup' : 'Restored. $n new reading${n == 1 ? '' : 's'} added')));
                            },
                      child: const Text('Restore'),
                    ),
                  ),
                ]),
              ]),
            ),
          ]);
        },
      );
}
