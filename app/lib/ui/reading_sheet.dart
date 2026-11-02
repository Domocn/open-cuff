import 'package:flutter/material.dart';

import '../models.dart';
import '../analysis.dart';
import '../outbox.dart';
import '../scales.dart';
import '../store.dart';
import 'scale_page.dart';
import 'theme.dart';

/// Details for one reading, as a full page: arrows (or a swipe) step through readings, edit and delete in the top bar.
Future<void> showReading(BuildContext context, Reading r) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReadingPage(start: r)));

class ReadingPage extends StatefulWidget {
  final Reading start;
  const ReadingPage({super.key, required this.start});

  @override
  State<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<ReadingPage> {
  late Reading _r = widget.start;

  List<Reading> get _list => Store.i.readings; // newest first

  void _step(int by) {
    final l = _list;
    final i = l.indexWhere((x) => x.key == _r.key);
    final j = i + by;
    if (i < 0 || j < 0 || j >= l.length) return;
    setState(() => _r = l[j]);
  }

  @override
  Widget build(BuildContext context) {
    final l = _list;
    final i = l.indexWhere((x) => x.key == _r.key);
    final t = _r.time;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Details'),
        actions: [
          // readings from the cuff are kept exactly as measured; only typed-in ones can be changed
          if (_r.source != 'cuff') IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context)),
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context)),
        ],
      ),
      body: Column(children: [
        Row(children: [
          IconButton(onPressed: i < l.length - 1 ? () => _step(1) : null, icon: const Icon(Icons.chevron_left), tooltip: 'Older'),
          Expanded(
            child: Column(children: [
              Text('${t.day} ${months[t.month - 1]} ${t.year}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(hm(t), style: muted(context)),
            ]),
          ),
          IconButton(onPressed: i > 0 ? () => _step(-1) : null, icon: const Icon(Icons.chevron_right), tooltip: 'Newer'),
        ]),
        Expanded(
          child: GestureDetector(
            // swipe right for older, left for newer
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v > 300) _step(1);
              if (v < -300) _step(-1);
            },
            child: _Sheet(_r, null, key: ValueKey('${_r.key}${_r.systolic}${_r.diastolic}${_r.pulse}${_r.time}')),
          ),
        ),
      ]),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final r = _r;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this reading?'),
        content: Text('${r.systolic}/${r.diastolic}, pulse ${r.pulse}, ${when(r.time)}. It stays on the cuff and in Health Connect.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await Store.i.remove(r);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _edit(BuildContext context) async {
    final r = _r;
    if (r.source == 'cuff') return;
    final s = TextEditingController(text: '${r.systolic}');
    final d = TextEditingController(text: '${r.diastolic}');
    final p = TextEditingController(text: '${r.pulse}');
    var at = r.time;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Edit reading'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: TextField(controller: s, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Top (systolic)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: d, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bottom (diastolic)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: p, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pulse'))),
            ]),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date and time'),
              trailing: Text('${at.day}/${at.month}/${at.year} ${hm(at)}'),
              onTap: () async {
                final dt = await showDatePicker(context: c, initialDate: at, firstDate: DateTime(2000), lastDate: DateTime.now());
                if (dt == null || !c.mounted) return;
                final tm = await showTimePicker(context: c, initialTime: TimeOfDay.fromDateTime(at));
                set(() => at = DateTime(dt.year, dt.month, dt.day, tm?.hour ?? at.hour, tm?.minute ?? at.minute));
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final ns = int.tryParse(s.text.trim()), nd = int.tryParse(d.text.trim()), np = int.tryParse(p.text.trim());
    if (ok != true || ns == null || nd == null || np == null || nd >= ns) return;
    setState(() {
      r
        ..systolic = ns
        ..diastolic = nd
        ..pulse = np
        ..time = at;
    });
    await Store.i.update(r);
  }
}

class _Sheet extends StatefulWidget {
  final Reading r;
  final ScrollController? scroll;
  const _Sheet(this.r, this.scroll, {super.key});

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  late final _note = TextEditingController(text: widget.r.note);

  @override
  void dispose() {
    if (_note.text.trim() != widget.r.note) {
      widget.r.note = _note.text.trim();
      Store.i.update(widget.r);
    }
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final top = Band.ofTop(r.systolic), bottom = Band.ofBottom(r.diastolic);
    final pulseBand = r.pulse > 100 ? Band.raised : (r.pulse < 50 ? Band.low : Band.ideal);
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 28), children: [
      Text(r.source == 'clinic' ? 'At the clinic' : (r.source == 'manual' ? 'Typed in' : 'From the cuff'), style: muted(context)),
      const SizedBox(height: 8),
      Row(children: [
        Text('Whose reading', style: muted(context)),
        const Spacer(),
        DropdownButton<int>(
          value: r.user,
          underline: const SizedBox(),
          items: [for (final u in [1, 2]) DropdownMenuItem(value: u, child: Text(Settings.i.personName(u)))],
          onChanged: (u) async {
            if (u == null || u == r.user) return;
            await Store.i.transfer([r.key], u);
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Moved to ${Settings.i.personName(u)}')));
            }
          },
        ),
      ]),
      const SizedBox(height: 6),
      Box(
        child: Row(children: [
          for (final (label, medical, v, unit) in [
            ('Top', 'systolic', '${r.systolic}', 'mmHg'),
            ('Bottom', 'diastolic', '${r.diastolic}', 'mmHg'),
            ('Pulse', 'heart rate', '${r.pulse}', 'bpm'),
          ])
            Expanded(
              child: Column(children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(medical, style: muted(context).copyWith(fontSize: 12)),
                Text(v, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, height: 1.1)),
                Text(unit, style: muted(context)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      Box(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(height: 230, width: double.infinity, child: CustomPaint(painter: ZonePainter(r.systolic, r.diastolic, Theme.of(context)))),
          const SizedBox(height: 6),
          Text('${r.zone}. The dot is this reading: top number up the side, bottom number along the bottom.', style: muted(context)),
          InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScalePage())).then((_) => setState(() {})),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text.rich(TextSpan(style: muted(context), children: [
                const TextSpan(text: 'Zones shown for '),
                TextSpan(text: '${currentScale.name} scale', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
              ])),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      _part(context, 'Top (systolic)', '${r.systolic}', top,
          'The pressure in your arteries while your heart beats and pushes blood out. Also called systolic. Ideal is 90 to 120.'),
      _part(context, 'Bottom (diastolic)', '${r.diastolic}', bottom,
          'The pressure while your heart rests between beats, so it is always the lower number. Also called diastolic. Ideal is 60 to 80.'),
      _part(context, 'Pulse', '${r.pulse}', pulseBand,
          'How many times your heart beats in a minute. 60 to 100 is normal at rest. Some medicines, such as ADHD stimulants, can raise it.',
          labels: const {Band.ideal: 'Normal', Band.raised: 'Above 100', Band.low: 'Below 50'}),
      if (r.irregular)
        _note2(context, 'Irregular heartbeat',
            'The cuff noticed the gaps between beats were uneven during this reading. One on its own is common. If it keeps happening, mention it to your doctor.'),
      if (Settings.i.flag('quality'))
        for (final q in qualityFlags(r, Store.i.readings))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Icon(Icons.info_outline, size: 18, color: bandColor(context, Band.raised)),
              const SizedBox(width: 8),
              Expanded(child: Text(q, style: muted(context))),
            ]),
          ),
      if (Settings.i.flag('tags')) _chips(context, 'Within 30 minutes before', const {'coffee': '☕ Coffee', 'nicotine': '🚬 Nicotine', 'exercise': '🏃 Exercise'}),
      if (Settings.i.flag('effects'))
        _chips(context, 'How you feel', const {
          'headache': 'Headache',
          'racing': 'Racing heart',
          'appetite': 'Poor appetite',
          'sleep': 'Bad sleep',
          'edge': 'On edge',
          'dizzy': 'Dizzy',
        }),
      if (Settings.i.flag('context'))
        FutureBuilder(
          future: Outbox.contextFor(r.time),
          builder: (context, snap) {
            final (sleep, rhr) = snap.data ?? (null, null);
            if (sleep == null && rhr == null) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Box(
                child: Column(children: [
                  if (sleep != null) _row(context, 'Sleep the night before', '${sleep.inHours} h ${sleep.inMinutes % 60} min'),
                  if (rhr != null) _row(context, 'Resting heart rate that day', '$rhr bpm'),
                ]),
              ),
            );
          },
        ),
      Box(
        child: Column(children: [
          _row(context, 'Average arterial pressure', '${r.mean} mmHg'),
          const SizedBox(height: 6),
          _row(context, 'Pulse pressure (top minus bottom)', '${r.pulsePressure} mmHg'),
          const SizedBox(height: 6),
          _row(context, 'Irregular heartbeat', r.irregular ? 'Noticed' : 'Not noticed'),
          const SizedBox(height: 6),
          if (r.cuffUser != 0) ...[_row(context, 'Cuff user button', '${r.cuffUser}'), const SizedBox(height: 6)],
          _row(context, 'Source', r.source == 'cuff' ? (Settings.i.cuffName.isEmpty ? 'Cuff' : Settings.i.cuffName) : (r.source == 'clinic' ? 'Clinic' : 'Typed in')),
        ]),
      ),
      const SizedBox(height: 10),
      Text('How did you feel?', style: muted(context)),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final (k, e) in const [('feel_great', '😄'), ('feel_good', '🙂'), ('feel_ok', '😐'), ('feel_low', '🙁'), ('feel_bad', '😣')])
          ChoiceChip(
            label: Text(e, style: const TextStyle(fontSize: 22)),
            selected: r.tags.contains(k),
            onSelected: (v) => setState(() {
              r.tags.removeWhere((t) => t.startsWith('feel_'));
              if (v) r.tags.add(k);
              Store.i.update(r);
            }),
          ),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _note,
        decoration: const InputDecoration(labelText: 'Note (for example "after coffee")', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
        child: Text(
            'One reading on its own means little. Your average over a few days is what counts, and what your doctor will look at. '
            'This app is not medical advice.',
            style: muted(context)),
      ),
    ]);
  }

  Widget _part(BuildContext c, String name, String value, Band b, String text, {Map<Band, String>? labels}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('$name: $value', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              Pill(labels?[b] ?? (b == Band.raised ? 'A little high' : b.label), bandColor(c, b)),
            ]),
            const SizedBox(height: 6),
            Text(text, style: muted(c)),
          ]),
        ),
      );

  Widget _chips(BuildContext c, String title, Map<String, String> options) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: muted(c)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in options.entries)
              FilterChip(
                label: Text(e.value),
                selected: widget.r.tags.contains(e.key),
                onSelected: (v) => setState(() {
                  v ? widget.r.tags.add(e.key) : widget.r.tags.remove(e.key);
                  Store.i.update(widget.r);
                }),
              ),
          ]),
        ]),
      );

  Widget _note2(BuildContext c, String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(text, style: muted(c)),
          ]),
        ),
      );

  Widget _row(BuildContext c, String k, String v) =>
      Row(children: [Expanded(child: Text(k, style: muted(c))), Text(v, style: const TextStyle(fontWeight: FontWeight.w700))]);
}


/// NHS home zones as nested boxes (like a nomogram): low, ideal, raised, high, very high, with this reading as a dot.
class ZonePainter extends CustomPainter {
  final int? sys, dia; // null: chart only, no dot
  final ThemeData theme;
  final BpScale? scale;
  ZonePainter(this.sys, this.dia, this.theme, {this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 34.0;
    final w = size.width - left - 4, h = size.height - bottom - 16;
    const dMin = 40.0, dMax = 105.0, sMin = 70.0, sMax = 170.0;
    double x(num d) => left + (d.clamp(dMin, dMax) - dMin) / (dMax - dMin) * w;
    double y(num s) => 16 + h - (s.clamp(sMin, sMax) - sMin) / (sMax - sMin) * h;
    final dark = theme.brightness == Brightness.dark;
    const light = [Color(0xFF79B7E8), Color(0xFF7FDB9A), Color(0xFFF8B260), Color(0xFFF2877C), Color(0xFFF06B8E)];
    const deep = [Color(0xFF3A5E93), Color(0xFF2F7A52), Color(0xFF9A6A20), Color(0xFFA2433A), Color(0xFF9E3B52)];
    final sc = scale ?? currentScale;
    // drawn largest first so smaller boxes sit on top; Low is the box under the low limits
    final zones = [
      for (final z in sc.upper.reversed)
        (z.maxSys >= 999 ? dMax : z.maxDia.toDouble(), z.maxSys >= 999 ? sMax : z.maxSys.toDouble(), z.name, (dark ? deep : light)[z.severity]),
      if (sc.hasLow) (sc.lowDia.toDouble(), sc.lowSys.toDouble(), sc.zones.first.name, (dark ? deep : light)[0]),
    ];
    final line = Paint()
      ..color = theme.colorScheme.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void text(String t, Offset o, {double size = 10, Color? color, bool bold = false}) {
      tp.text = TextSpan(text: t, style: TextStyle(fontSize: size, color: color ?? theme.colorScheme.onSurfaceVariant, fontWeight: bold ? FontWeight.w700 : null));
      tp.layout();
      tp.paint(canvas, o);
    }

    for (final (d, s, label, c) in zones) {
      final rect = Rect.fromLTRB(x(dMin), y(s), x(d), y(sMin));
      canvas.drawRect(rect, Paint()..color = c);
      canvas.drawRect(rect, line);
      text(label, Offset(rect.left + 6, rect.top + 4), size: 11, color: Colors.black.withValues(alpha: .7), bold: true);
    }
    for (final z in [if (sc.hasLow) Zone('', sc.lowSys, sc.lowDia, 0), ...sc.upper.where((z) => z.maxSys < 999)]) {
      text('${z.maxSys}', Offset(0, y(z.maxSys) - 6));
      text('${z.maxDia}', Offset(x(z.maxDia) - 8, size.height - bottom + 6));
    }
    text('Top (systolic)', Offset(left, 0), size: 10, bold: true);
    text('Bottom (diastolic)', Offset(size.width - 100, size.height - 11), size: 10, bold: true);
    if (sys == null || dia == null) return;
    final dot = Offset(x(dia!), y(sys!));
    canvas.drawCircle(dot, 8, Paint()..color = Colors.white);
    canvas.drawCircle(dot, 8, Paint()
      ..color = Colors.black.withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant ZonePainter old) => old.sys != sys || old.dia != dia || old.scale != scale;
}
