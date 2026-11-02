import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cuff.dart';
import '../models.dart';
import '../outbox.dart';
import '../store.dart';
import '../widget.dart';
import 'theme.dart';

class AddPage extends StatefulWidget {
  const AddPage({super.key});

  @override
  State<AddPage> createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  final _s = TextEditingController(), _d = TextEditingController(), _p = TextEditingController(), _n = TextEditingController();
  String _error = '';
  bool _clinic = false;
  Timer? _timer;
  int _left = 0;

  void _rest() {
    _timer?.cancel();
    setState(() => _left = 300);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_s, _d, _p, _n]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final s = int.tryParse(_s.text), d = int.tryParse(_d.text), p = int.tryParse(_p.text);
    if (s == null || d == null || p == null) return setState(() => _error = 'Fill in all three numbers');
    if (s < 60 || s > 260 || d < 30 || d > 160 || p < 30 || p > 220 || d >= s) {
      return setState(() => _error = 'Those numbers look wrong. Check them against the monitor');
    }
    final t = DateTime.now();
    await Store.i.add([
      Reading(
        key: '${Reading.makeKey(t, s, d, p)}-m',
        time: t,
        systolic: s,
        diastolic: d,
        pulse: p,
        user: Settings.i.user,
        source: _clinic ? 'clinic' : 'manual',
        note: _n.text.trim(),
      ),
    ]);
    await Outbox.flush();
    await updateWidget();
    if (!mounted) return;
    for (final c in [_s, _d, _p, _n]) {
      c.clear();
    }
    setState(() => _error = '');
    setState(() => _clinic = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  @override
  Widget build(BuildContext context) {
    Widget num(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          ),
        );
    return ListView(padding: EdgeInsets.fromLTRB(14, MediaQuery.paddingOf(context).top + 12, 14, 24), children: [
      Text('New reading', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Box(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Before you start', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(
              '1. Sit with your back supported for 5 minutes.\n'
              '2. Feet flat, arm resting at heart height.\n'
              '3. No coffee, smoking or exercise for 30 minutes.\n'
              '4. Press the cuff\'s Start button. The reading appears here by itself.',
              style: muted(context).copyWith(height: 1.5)),
          if (Settings.i.flag('guided')) ...[
            const SizedBox(height: 12),
            Row(children: [
              Text(_left > 0 ? '${_left ~/ 60}:${(_left % 60).toString().padLeft(2, '0')}' : (_timer == null ? '5:00' : 'Ready'),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_left > 0 ? 'Sit back, feet flat, breathe slowly' : (_timer == null ? 'Resting timer' : 'Press Start on the cuff now'),
                    style: muted(context)),
              ),
              FilledButton.tonal(onPressed: _rest, child: Text(_timer == null ? 'Start' : 'Again')),
            ]),
          ],
          const SizedBox(height: 10),
          ListenableBuilder(listenable: Cuff.i, builder: (context, _) => Text(Cuff.i.message, style: muted(context))),
        ]),
      ),
      const SizedBox(height: 12),
      Box(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Or type one in', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text('From any other monitor, or a reading at the GP.', style: muted(context)),
          const SizedBox(height: 12),
          Row(children: [num(_s, 'Top (sys)'), const SizedBox(width: 8), num(_d, 'Bottom (dia)'), const SizedBox(width: 8), num(_p, 'Pulse')]),
          const SizedBox(height: 10),
          TextField(controller: _n, decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder())),
          if (Settings.i.flag('clinic'))
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Taken at the GP or clinic'),
              subtitle: const Text('Kept apart from home readings and compared in reports'),
              value: _clinic,
              onChanged: (v) => setState(() => _clinic = v),
            ),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error, style: TextStyle(color: bandColor(context, Band.high)))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('Save reading'))),
        ]),
      ),
    ]);
  }
}
