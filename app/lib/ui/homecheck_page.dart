import 'package:flutter/material.dart';

import '../analysis.dart';
import '../models.dart';
import '../store.dart';
import 'theme.dart';

/// NHS home check: 2 readings a minute apart, morning and evening, for 7 days. Day 1 is left out of the average.
class HomeCheckPage extends StatelessWidget {
  const HomeCheckPage({super.key});

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('NHS home check')),
        body: ListenableBuilder(
          listenable: Listenable.merge([Store.i, Settings.i]),
          builder: (context, _) {
            final hc = HomeCheck.current;
            if (hc == null) {
              return ListView(padding: const EdgeInsets.all(14), children: [
                Box(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('How it works', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                        'For 7 days, take 2 readings a minute apart every morning and every evening. '
                        'The first day is practice and is left out. The average of the rest is the number your GP uses.',
                        style: muted(context).copyWith(height: 1.5)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        final n = DateTime.now();
                        Settings.i.setText('homecheck_start', DateTime(n.year, n.month, n.day).toIso8601String());
                      },
                      child: const Text('Start today'),
                    ),
                  ]),
                ),
              ]);
            }
            final slots = hc.slots(Store.i.readings);
            final result = hc.result(Store.i.readings);
            final done = slots.skip(1).expand((d) => d).where((s) => s.length >= 2).length;
            return ListView(padding: const EdgeInsets.all(14), children: [
              Box(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(hc.finished ? 'Finished' : 'Day ${hc.today + 1} of 7', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text('$done of 12 sessions done (days 2 to 7). Each needs 2 readings.', style: muted(context)),
                  const SizedBox(height: 12),
                  Table(
                    columnWidths: const {0: FixedColumnWidth(70)},
                    children: [
                      const TableRow(children: [SizedBox(), Center(child: Text('Morning')), Center(child: Text('Evening'))]),
                      for (var d = 0; d < 7; d++)
                        TableRow(children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text('${_days[hc.day(d).weekday - 1]}${d == 0 ? ' (practice)' : ''}', style: muted(context)),
                          ),
                          for (final s in slots[d]) _cell(context, s.length, d == hc.today && !hc.finished),
                        ]),
                    ],
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              if (result != null)
                Box(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(hc.finished ? 'Your home average' : 'Average so far', style: muted(context)),
                    Text('${result.bp} mmHg', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    Text('Pulse ${result.pulse} · ${result.count} readings', style: muted(context)),
                    const SizedBox(height: 8),
                    Pill(Band.of(result.systolic, result.diastolic).words, bandColor(context, Band.of(result.systolic, result.diastolic))),
                    const SizedBox(height: 8),
                    Text('The NHS home limit is 135/85. Share this with your GP from Reports.', style: muted(context)),
                  ]),
                ),
              const SizedBox(height: 12),
              TextButton(onPressed: () => Settings.i.setText('homecheck_start', ''), child: Text(hc.finished ? 'Clear and start another later' : 'Stop this check')),
            ]);
          },
        ),
      );

  Widget _cell(BuildContext c, int n, bool today) {
    final ok = n >= 2;
    final color = ok ? bandColor(c, Band.ideal) : (n == 1 ? bandColor(c, Band.raised) : Theme.of(c).colorScheme.outlineVariant);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Container(
        height: 30,
        decoration: BoxDecoration(
          color: color.withValues(alpha: ok ? .2 : .12),
          borderRadius: BorderRadius.circular(8),
          border: today ? Border.all(color: Theme.of(c).colorScheme.primary, width: 2) : null,
        ),
        alignment: Alignment.center,
        child: Text(ok ? '✓' : '$n of 2', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
      ),
    );
  }
}
