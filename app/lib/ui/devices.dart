import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../background.dart';
import '../cuff.dart';
import '../models.dart';
import '../store.dart';
import 'theme.dart';

/// The paired cuff: its name, whose readings to show, and Collect now.
class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late final _name = TextEditingController(text: Settings.i.cuffName);

  @override
  void dispose() {
    if (_name.text.trim() != Settings.i.cuffName) Settings.i.setCuffLabel(_name.text);
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Your cuff')),
        body: ListenableBuilder(
          listenable: Listenable.merge([Settings.i, Cuff.i]),
          builder: (context, _) {
            final st = Settings.i, c = Cuff.i;
            if (st.cuffId.isEmpty) return const _Finder();
            final busy = c.state == CuffState.connecting || c.state == CuffState.syncing;
            return ListView(padding: const EdgeInsets.all(14), children: [
              Box(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  _row(context, 'Model', 'OxiPro BP2 (AOJ-33A)'),
                  _row(context, 'Bluetooth name', st.cuffBtName),
                  _row(context, 'Status', [c.message, if (c.lastSync != null) 'last sync ${hm(c.lastSync!)}'].where((s) => s.isNotEmpty).join(' · ')),
                ]),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  SwitchListTile(
                    title: const Text("Use the cuff's user buttons"),
                    subtitle: Text(st.flag('cuff_users')
                        ? 'Readings go to user 1 or user 2 depending on the button pressed on the cuff'
                        : 'Every reading goes to ${_personName(st.person)}, whatever the cuff says. Turn on only if two people share the cuff and use its user buttons'),
                    value: st.flag('cuff_users'),
                    onChanged: (v) async {
                      await st.setFlag('cuff_users', v);
                      if (!v) await Store.i.assignCuffReadings(st.person);
                    },
                  ),
                  if (!st.flag('cuff_users'))
                    SwitchListTile(
                      title: const Text('Ask whose readings they are'),
                      subtitle: const Text('After each sync, choose who new readings belong to'),
                      value: !st.flag('never_ask_who'),
                      onChanged: (v) => st.setFlag('never_ask_who', !v),
                    ),
                  if (st.flag('cuff_users'))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: 1, label: Text(_personName(1))),
                          ButtonSegment(value: 2, label: Text(_personName(2))),
                          const ButtonSegment(value: 0, label: Text('Both')),
                        ],
                        selected: {st.user},
                        onSelectionChanged: (s) => st.setUser(s.first),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  title: const Text('Collect in the background'),
                  subtitle: const Text('Readings arrive with the app closed or the phone locked. A small notification shows while it watches'),
                  value: st.flag('background'),
                  onChanged: (v) async {
                    if (v) {
                      await Background.askPermissions();
                      await st.setFlag('background', true);
                      Cuff.i.stop();
                      Cuff.i.remote = true;
                      await Background.start();
                    } else {
                      await st.setFlag('background', false);
                      await Background.stop();
                      Cuff.i.remote = false;
                      await Cuff.i.start();
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              Box(
                child: Row(children: [
                  Icon(Icons.lock_outline, color: bandColor(context, Band.ideal)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Readings stay on the cuff too. Open Cuff never clears its memory.', style: muted(context)),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: busy ? null : () => c.collectNow(),
                icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
                label: Text(busy ? 'Collecting' : 'Collect now'),
              ),
              const SizedBox(height: 4),
              Text('Turn the cuff on first (press its left button).', textAlign: TextAlign.center, style: muted(context)),
              const SizedBox(height: 20),
              TextButton(onPressed: () => st.setCuff('', ''), child: const Text('Forget this cuff and find another')),
            ]);
          },
        ),
      );

  String _personName(int u) => Settings.i.text('name_$u').isEmpty ? (u == 1 ? 'you' : 'user $u') : Settings.i.text('name_$u');

  Widget _row(BuildContext c, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: muted(c))),
          Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

/// Add device: lists what is nearby with its signal, cuffs first. Tap one to pair.
class _Finder extends StatefulWidget {
  const _Finder();

  @override
  State<_Finder> createState() => _FinderState();
}

class _FinderState extends State<_Finder> {
  final _found = <String, DiscoveredDevice>{};
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Cuff.i.discover().listen((d) => setState(() => _found[d.id] = d));
  }

  @override
  void dispose() {
    _sub?.cancel();
    Cuff.i.endDiscover();
    super.dispose();
  }

  static bool _isCuff(DiscoveredDevice d) => d.name.contains('OxiPro') || d.name.startsWith('BP2');

  static String _signal(int rssi) =>
      '${rssi >= -60 ? 'excellent' : rssi >= -75 ? 'good' : rssi >= -88 ? 'weak' : 'very weak'} ($rssi dBm)';

  @override
  Widget build(BuildContext context) {
    final list = _found.values.toList()
      ..sort((a, b) => _isCuff(a) == _isCuff(b) ? b.rssi.compareTo(a.rssi) : (_isCuff(a) ? -1 : 1));
    return ListView(padding: const EdgeInsets.all(14), children: [
      Row(children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(child: Text(list.isEmpty ? 'Searching. Press the cuff\'s left button.' : '${list.length} found')),
      ]),
      const SizedBox(height: 12),
      for (final d in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Box(
            onTap: _isCuff(d)
                ? () async {
                    await _sub?.cancel();
                    await Settings.i.setCuff(d.id, d.name);
                    Cuff.i.endDiscover();
                    unawaited(Cuff.i.collectNow());
                  }
                : null,
            child: Row(children: [
              Icon(_isCuff(d) ? Icons.monitor_heart_outlined : Icons.bluetooth, color: _isCuff(d) ? Theme.of(context).colorScheme.primary : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.name, style: TextStyle(fontWeight: _isCuff(d) ? FontWeight.w800 : FontWeight.w500)),
                  Text('Signal: ${_signal(d.rssi)}', style: muted(context)),
                  if (!_isCuff(d)) Text('Not a supported device', style: muted(context).copyWith(fontSize: 12)),
                ]),
              ),
              if (_isCuff(d)) const Text('Pair', style: TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
    ]);
  }
}
