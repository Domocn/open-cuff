import 'dart:math';

import 'package:flutter/material.dart';

import '../analysis.dart';
import '../models.dart';
import '../store.dart';
import 'reading_sheet.dart';
import 'theme.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  int _days = 30;
  final _picked = <String>{};

  Future<void> _move() async {
    final u = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Move ${_picked.length} reading${_picked.length == 1 ? '' : 's'} to'),
        children: [
          for (final u in [1, 2]) SimpleDialogOption(onPressed: () => Navigator.pop(c, u), child: Text(Settings.i.personName(u))),
        ],
      ),
    );
    if (u == null) return;
    await Store.i.transfer(_picked, u);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Moved ${_picked.length} to ${Settings.i.personName(u)}')));
    setState(_picked.clear);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Store.i,
    builder: (context, _) {
      final all = Store.i.readings;
      final from = _days == 0 ? DateTime(2000) : DateTime.now().subtract(Duration(days: _days));
      final shown = all.where((r) => r.time.isAfter(from)).toList();
      final groups = <String, List<Reading>>{};
      for (final r in shown) {
        groups.putIfAbsent(dayLabel(r.time), () => []).add(r);
      }
      return ListView(
        padding: EdgeInsets.fromLTRB(14, MediaQuery.paddingOf(context).top + 12, 14, 24),
        children: [
          if (_picked.isEmpty)
            Row(
              children: [
                Expanded(child: Text('History', style: Theme.of(context).textTheme.headlineSmall)),
                DropdownButton<int>(
                  value: Settings.i.user,
                  underline: const SizedBox(),
                  items: [
                    for (final u in [1, 2]) DropdownMenuItem(value: u, child: Text(Settings.i.personName(u))),
                    const DropdownMenuItem(value: 0, child: Text('Everyone')),
                  ],
                  onChanged: (u) => u == null ? null : Settings.i.setUser(u),
                ),
              ],
            )
          else
            Row(
              children: [
                IconButton(onPressed: () => setState(_picked.clear), icon: const Icon(Icons.close)),
                Expanded(child: Text('${_picked.length} picked', style: Theme.of(context).textTheme.titleMedium)),
                FilledButton.icon(onPressed: _move, icon: const Icon(Icons.swap_horiz), label: const Text('Move to')),
              ],
            ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 7, label: Text('Week')),
              ButtonSegment(value: 30, label: Text('Month')),
              ButtonSegment(value: 90, label: Text('3 mo')),
              ButtonSegment(value: 0, label: Text('All')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() => _days = s.first),
          ),
          const SizedBox(height: 12),
          if (shown.length >= 2) Box(padding: const EdgeInsets.fromLTRB(8, 12, 12, 8), child: TrendChart(shown.reversed.toList())),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No readings in this time.', textAlign: TextAlign.center, style: muted(context)),
            ),
          for (final e in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final r in e.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _Row(
                  r,
                  picked: _picked.contains(r.key),
                  onLongPress: () => setState(() => _picked.contains(r.key) ? _picked.remove(r.key) : _picked.add(r.key)),
                  picking: _picked.isNotEmpty,
                ),
              ),
          ],
        ],
      );
    },
  );
}

class _Row extends StatelessWidget {
  final Reading r;
  final bool picked, picking;
  final VoidCallback onLongPress;
  const _Row(this.r, {required this.picked, required this.onLongPress, required this.picking});

  @override
  Widget build(BuildContext context) {
    final c = bandColor(context, r.band);
    return GestureDetector(
      onLongPress: onLongPress,
      child: Box(
        padding: const EdgeInsets.fromLTRB(0, 0, 12, 0),
        onTap: picking ? onLongPress : () => showReading(context, r),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, color: c),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${r.systolic}/${r.diastolic}  ',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                            ),
                            TextSpan(text: '♥ ${r.pulse}', style: muted(context)),
                          ],
                        ),
                      ),
                      Text(
                        [
                          hm(r.time),
                          if (r.source == 'clinic') 'at the clinic',
                          if (r.irregular) 'irregular heartbeat',
                          if (Settings.i.flag('quality') && qualityFlags(r, Store.i.readings).isNotEmpty) 'check this one',
                          if (r.note.isNotEmpty) '"${r.note}"',
                        ].join(' · '),
                        style: muted(context).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              picking
                  ? Icon(picked ? Icons.check_circle : Icons.radio_button_unchecked, color: Theme.of(context).colorScheme.primary)
                  : Pill(r.zone, c),
            ],
          ),
        ),
      ),
    );
  }
}

class TrendChart extends StatelessWidget {
  final List<Reading> rs; // oldest first
  final double height;
  const TrendChart(this.rs, {super.key, this.height = 170});

  @override
  Widget build(BuildContext context) {
    final s = bandColor(context, Band.high), d = bandColor(context, Band.low), p = bandColor(context, Band.ideal);
    return Column(
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            size: Size.infinite,
            painter: _Painter(
              rs,
              s,
              d,
              p,
              bandColor(context, Band.ideal).withValues(alpha: .14),
              Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _key(context, s, 'Top (sys)'),
            _key(context, d, 'Bottom (dia)'),
            _key(context, p, 'Pulse'),
            Text('Shaded: ideal', style: muted(context).copyWith(fontSize: 11.5)),
          ],
        ),
      ],
    );
  }

  Widget _key(BuildContext c, Color col, String t) => Row(
    children: [
      Icon(Icons.circle, size: 9, color: col),
      const SizedBox(width: 4),
      Text(t, style: muted(c).copyWith(fontSize: 11.5)),
    ],
  );
}

class _Painter extends CustomPainter {
  final List<Reading> rs;
  final Color sys, dia, pulse, band, label;
  _Painter(this.rs, this.sys, this.dia, this.pulse, this.band, this.label);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0;
    final lo = min(50, rs.map((r) => min(r.diastolic, r.pulse)).reduce(min) - 5).toDouble();
    final hi = max(150, rs.map((r) => max(r.systolic, r.pulse)).reduce(max) + 5).toDouble();
    double y(num v) => size.height - (v - lo) / (hi - lo) * size.height;
    final t0 = rs.first.time.millisecondsSinceEpoch.toDouble(), t1 = rs.last.time.millisecondsSinceEpoch.toDouble();
    double x(Reading r) => left + (t1 == t0 ? .5 : (r.time.millisecondsSinceEpoch - t0) / (t1 - t0)) * (size.width - left - 4);

    canvas.drawRect(Rect.fromLTRB(left, y(120), size.width, y(80)), Paint()..color = band);
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final v in [60, 80, 120, 140]) {
      tp.text = TextSpan(
        text: '$v',
        style: TextStyle(color: label, fontSize: 10),
      );
      tp.layout();
      tp.paint(canvas, Offset(0, y(v) - tp.height / 2));
    }
    void line(int Function(Reading) f, Color c, {bool dashed = false}) {
      final paint = Paint()
        ..color = c
        ..strokeWidth = dashed ? 1.6 : 2.4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(x(rs.first), y(f(rs.first)));
      for (final r in rs.skip(1)) {
        path.lineTo(x(r), y(f(r)));
      }
      if (dashed) {
        for (final m in path.computeMetrics()) {
          for (var d = 0.0; d < m.length; d += 7) {
            canvas.drawPath(m.extractPath(d, d + 3.5), paint);
          }
        }
      } else {
        canvas.drawPath(path, paint);
      }
      for (final r in rs) {
        canvas.drawCircle(Offset(x(r), y(f(r))), dashed ? 1.8 : 2.6, Paint()..color = c);
      }
    }

    line((r) => r.pulse, pulse, dashed: true);
    line((r) => r.diastolic, dia);
    line((r) => r.systolic, sys);
  }

  @override
  bool shouldRepaint(covariant _Painter old) => old.rs != rs;
}
