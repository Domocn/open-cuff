import 'package:flutter/material.dart';

import '../analysis.dart';
import '../cuff.dart';
import '../meds.dart';
import '../models.dart';
import '../store.dart';
import 'history.dart';
import 'homecheck_page.dart';
import 'meds_page.dart';
import 'reading_sheet.dart';
import 'theme.dart';
import 'whose.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([Store.i, Cuff.i, Settings.i]),
        builder: (context, _) {
          final rs = Store.i.readings;
          final r = rs.isEmpty ? null : rs.first;
          return ListView(padding: EdgeInsets.zero, children: [
            _Hero(r),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              child: Column(children: [
                if (Settings.i.pendingWho.isNotEmpty) ...[const WhoseCard(), const SizedBox(height: 10)],
                if (rs.isNotEmpty) _Averages(rs),
                const SizedBox(height: 10),
                if (rs.isNotEmpty) ...[const SizedBox(height: 10), _NextCard(rs)],
                if (rs.length >= 2) ...[const SizedBox(height: 10), _ChartCard(rs)],
                if (rs.isNotEmpty) ...[const SizedBox(height: 10), _WeekCard(rs)],
                if (rs.length >= 2) ...[const SizedBox(height: 10), _RecentCard(rs)],
                const SizedBox(height: 10),
                const _SyncCard(),
                ..._extras(context, rs).expand((w) => [const SizedBox(height: 10), w]),
              ]),
            ),
          ]);
        },
      );
}

List<Widget> _extras(BuildContext context, List<Reading> rs) {
  final st = Settings.i;
  final out = <Widget>[];
  if (st.flag('meds')) {
    for (final m in Meds.all().where((m) => m.current != null)) {
      final t = Meds.takenToday(m);
      out.add(Box(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MedsPage())),
        child: Row(children: [
          const Icon(Icons.medication_outlined),
          const SizedBox(width: 12),
          Expanded(child: Text('${m.name} today', style: const TextStyle(fontWeight: FontWeight.w700))),
          t == null
              ? FilledButton.tonal(onPressed: () => Meds.markTaken(m), child: Text('Taken ${m.current!.dose}'))
              : Pill('✓ ${m.current!.dose}, ${hm(t)}', bandColor(context, Band.ideal)),
        ]),
      ));
    }
  }
  if (st.flag('homecheck')) {
    final hc = HomeCheck.current;
    final done = hc == null ? 0 : hc.slots(rs).skip(1).expand((d) => d).where((s) => s.length >= 2).length;
    out.add(Box(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeCheckPage())),
      child: Row(children: [
        const Icon(Icons.fact_check_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('NHS home check', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(hc == null ? 'Not started. Tap to start a 7-day check' : (hc.finished ? 'Finished. Tap for your average' : 'Day ${hc.today + 1} of 7 · $done of 12 sessions'),
                style: muted(context)),
          ]),
        ),
        const Icon(Icons.chevron_right),
      ]),
    ));
  }
  if (st.flag('streaks') && rs.isNotEmpty) {
    final (am, pm) = weekCounts(rs);
    out.add(Box(
      child: Row(children: [
        const Icon(Icons.wb_sunny_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Text(am + pm == 0 ? 'A new week. Any reading counts.' : '$am morning${am == 1 ? '' : 's'} and $pm evening${pm == 1 ? '' : 's'} this week. Nice.',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ]),
    ));
  }
  if (st.flag('trends')) {
    final t = trendMessage(rs);
    if (t != null) {
      out.add(Box(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.trending_up, color: bandColor(context, Band.raised)),
          const SizedBox(width: 12),
          Expanded(child: Text(t)),
        ]),
      ));
    }
  }
  return out;
}

class _Hero extends StatelessWidget {
  final Reading? r;
  const _Hero(this.r);

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    final soft = white.withValues(alpha: .75);
    final r = this.r;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [tealDark, teal], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      padding: EdgeInsets.fromLTRB(18, MediaQuery.paddingOf(context).top + 14, 18, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_greeting(), style: const TextStyle(color: white, fontSize: 20, fontWeight: FontWeight.w800))),
          if (Settings.i.flag('people'))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: white.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
              child: Text(Settings.i.text('name_${Settings.i.user}').isEmpty ? 'User ${Settings.i.user}' : Settings.i.text('name_${Settings.i.user}'),
                  style: const TextStyle(color: white, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 16),
        if (r == null) ...[
          Text('No readings yet', style: TextStyle(color: soft, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('Take a reading, or press the cuff\'s left button. Your readings appear here.',
              style: TextStyle(color: white, fontSize: 18, fontWeight: FontWeight.w600)),
        ] else
          GestureDetector(
            onTap: () => showReading(context, r),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('LATEST · ${when(r.time).toUpperCase()}', style: TextStyle(color: soft, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .5)),
              const SizedBox(height: 6),
              if (Settings.i.flag('calm'))
                Text(r.band == Band.ideal ? 'In your healthy range' : describe(r),
                    style: const TextStyle(color: white, fontSize: 30, fontWeight: FontWeight.w800, height: 1.15))
              else ...[
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text('${r.systolic}/${r.diastolic}',
                      style: const TextStyle(color: white, fontSize: 56, fontWeight: FontWeight.w800, letterSpacing: -2, height: 1)),
                  const SizedBox(width: 6),
                  Text('mmHg', style: TextStyle(color: soft, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _tag('♥ ${r.pulse} bpm'),
                  _tag(describe(r), warn: r.band != Band.ideal),
                  if (r.irregular) _tag('Irregular heartbeat'),
                ]),
              ],
              const SizedBox(height: 14),
              _Scale(r),
              const SizedBox(height: 4),
              Text(Settings.i.flag('calm') ? 'Tap to see the numbers' : 'Tap for what this means', style: TextStyle(color: soft, fontSize: 12)),
            ]),
          ),
      ]),
    );
  }

  String _greeting() {
    final name = Settings.i.text('name_${Settings.i.user}');
    if (name.isEmpty) return 'Open Cuff';
    final h = DateTime.now().hour;
    return '${h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'}, $name';
  }

  Widget _tag(String t, {bool warn = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: warn ? const Color(0xFFFDECCC) : Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
        child: Text(t, style: TextStyle(color: warn ? const Color(0xFF8A5200) : Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
}

/// Low / ideal / raised / high bar with a marker for the reading (the worse of the two numbers decides the position).
class _Scale extends StatelessWidget {
  final Reading r;
  const _Scale(this.r);

  @override
  Widget build(BuildContext context) {
    double pos(Band b, double within) => switch (b) { Band.low => .07, Band.ideal => .15 + .35 * within, Band.raised => .5 + .25 * within, Band.high => .88 };
    final d = r.diastolic, s = r.systolic;
    final p = [
      pos(Band.ofBottom(d), ((d - 60) / 20).clamp(0, 1)),
      pos(Band.ofTop(s), ((s - 90) / 30).clamp(0, 1)),
    ].reduce((a, b) => a > b ? a : b);
    return LayoutBuilder(builder: (context, c) {
      return Column(children: [
        SizedBox(
          width: double.infinity,
          height: 16,
          child: Stack(children: [
            Positioned.fill(
              top: 4,
              bottom: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                // stretch: a ColoredBox with no child has no height of its own
                child: const Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(flex: 15, child: ColoredBox(color: Color(0xFF82A9EA))),
                  Expanded(flex: 35, child: ColoredBox(color: Color(0xFF5CCB93))),
                  Expanded(flex: 25, child: ColoredBox(color: Color(0xFFF0B04E))),
                  Expanded(flex: 25, child: ColoredBox(color: Color(0xFFF07C70))),
                ]),
              ),
            ),
            Positioned(
              left: (c.maxWidth - 4) * p,
              top: 0,
              bottom: 0,
              child: Container(width: 4, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
            ),
          ]),
        ),
        const SizedBox(height: 3),
        DefaultTextStyle(
          style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 10.5),
          child: const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Low'), Text('Ideal'), Text('Raised'), Text('High')]),
        ),
      ]);
    });
  }
}

class _Averages extends StatelessWidget {
  final List<Reading> rs;
  const _Averages(this.rs);

  @override
  Widget build(BuildContext context) {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final week = rs.where((r) => r.time.isAfter(since)).toList();
    final today = rs.where((r) => dayLabel(r.time) == 'Today').toList();
    String avg(List<Reading> l) =>
        '${(l.map((r) => r.systolic).reduce((a, b) => a + b) / l.length).round()}/${(l.map((r) => r.diastolic).reduce((a, b) => a + b) / l.length).round()}';
    int pulse(List<Reading> l) => (l.map((r) => r.pulse).reduce((a, b) => a + b) / l.length).round();
    Widget tile(String label, List<Reading> l) => Expanded(
          child: Box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: muted(context)),
              const SizedBox(height: 2),
              Text(l.isEmpty ? 'None yet' : avg(l), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(l.isEmpty ? '' : '♥ ${pulse(l)} · ${l.length} reading${l.length == 1 ? '' : 's'}', style: muted(context)),
            ]),
          ),
        );
    return Row(children: [tile('Today\'s average', today), const SizedBox(width: 10), tile('7-day average', week)]);
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard();

  @override
  Widget build(BuildContext context) {
    final c = Cuff.i;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (c.state) {
      CuffState.done => (Icons.check_circle, bandColor(context, Band.ideal)),
      CuffState.failed || CuffState.noPermission => (Icons.error_outline, bandColor(context, Band.raised)),
      CuffState.off => c.message.isEmpty ? (Icons.bluetooth, scheme.primary) : (Icons.error_outline, bandColor(context, Band.raised)),
      CuffState.connecting || CuffState.syncing => (Icons.sync, scheme.primary),
      CuffState.looking => (Icons.bluetooth_searching, scheme.primary),
    };
    final name = Settings.i.cuffName.isEmpty ? 'Your cuff' : Settings.i.cuffName;
    return Box(
      onTap: c.state == CuffState.noPermission ? () => Cuff.i.start() : null,
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
                [
                  c.message.isNotEmpty
                      ? c.message
                      : (c.remote ? 'Collecting in the background' : "Press the cuff's left button to sync"),
                  if (c.lastSync != null) 'last sync ${hm(c.lastSync!)}',
                ].join(' · '),
                style: muted(context)),
          ]),
        ),
        if (c.state == CuffState.connecting || c.state == CuffState.syncing)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
    );
  }
}


/// What to do next: a gentle "next reading" hint based on the time of day.
class _NextCard extends StatelessWidget {
  final List<Reading> rs;
  const _NextCard(this.rs);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = rs.where((r) => dayLabel(r.time) == 'Today');
    final am = today.any(isMorning), pm = today.any((r) => !isMorning(r));
    final (icon, text) = now.hour < 12
        ? (am ? (Icons.check_circle_outline, 'Morning reading done. Next one this evening.') : (Icons.wb_sunny_outlined, 'No morning reading yet. Sit for 5 minutes, then press Start on the cuff.'))
        : now.hour < 18
            ? (Icons.schedule, am ? 'Morning done. An evening reading after 6 pm would be ideal.' : 'An evening reading after 6 pm would be ideal.')
            : (pm ? (Icons.check_circle_outline, 'Evening reading done. Nice work today.') : (Icons.nightlight_outlined, 'Time for an evening reading. Sit for 5 minutes first.'));
    return Box(
      child: Row(children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final List<Reading> rs;
  const _ChartCard(this.rs);

  @override
  Widget build(BuildContext context) {
    final from = DateTime.now().subtract(const Duration(days: 14));
    var shown = rs.where((r) => r.time.isAfter(from)).toList();
    final label = shown.length >= 2 ? 'Last 2 weeks' : 'All readings';
    if (shown.length < 2) shown = rs;
    return Box(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(left: 6, bottom: 6), child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
        TrendChart(shown.reversed.toList(), height: 130),
      ]),
    );
  }
}

class _WeekCard extends StatelessWidget {
  final List<Reading> rs;
  const _WeekCard(this.rs);

  @override
  Widget build(BuildContext context) {
    final week = between(rs, DateTime.now().subtract(const Duration(days: 7)), DateTime.now().add(const Duration(minutes: 1)));
    if (week.isEmpty) return const SizedBox();
    final hi = week.reduce((a, b) => a.systolic >= b.systolic ? a : b);
    final lo = week.reduce((a, b) => a.systolic <= b.systolic ? a : b);
    final pulseHi = week.reduce((a, b) => a.pulse >= b.pulse ? a : b);
    final irr = week.where((r) => r.irregular).length;
    final inRange = week.where((r) => r.band == Band.ideal).length;
    Widget stat(String label, String value, String sub) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: muted(context).copyWith(fontSize: 12)),
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(sub, style: muted(context).copyWith(fontSize: 11.5)),
          ]),
        );
    return Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('This week', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          stat('Highest', '${hi.systolic}/${hi.diastolic}', dayLabel(hi.time)),
          stat('Lowest', '${lo.systolic}/${lo.diastolic}', dayLabel(lo.time)),
          stat('Top pulse', '${pulseHi.pulse}', dayLabel(pulseHi.time)),
        ]),
        const SizedBox(height: 10),
        Text(
            '$inRange of ${week.length} in the ideal range'
            '${irr == 0 ? '' : ' · irregular heartbeat $irr time${irr == 1 ? '' : 's'}'}',
            style: muted(context)),
      ]),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final List<Reading> rs;
  const _RecentCard(this.rs);

  @override
  Widget build(BuildContext context) => Box(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Recent readings', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final r in rs.take(5))
            InkWell(
              onTap: () => showReading(context, r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Container(width: 4, height: 28, decoration: BoxDecoration(color: bandColor(context, r.band), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(when(r.time), style: muted(context))),
                  Text('${r.systolic}/${r.diastolic}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  SizedBox(width: 58, child: Text('  ♥ ${r.pulse}', style: muted(context))),
                  if (r.irregular) Icon(Icons.favorite, size: 14, color: bandColor(context, Band.raised)) else const SizedBox(width: 14),
                ]),
              ),
            ),
        ]),
      );
}
