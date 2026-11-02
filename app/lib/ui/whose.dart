import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'theme.dart';

/// "Whose are these?" after a sync: everyone in one tap, or one by one.
class WhoseCard extends StatelessWidget {
  const WhoseCard({super.key});

  @override
  Widget build(BuildContext context) {
    final st = Settings.i;
    final keys = st.pendingWho.toSet();
    final rs = Store.i.everything.where((r) => keys.contains(r.key)).toList()..sort((a, b) => a.time.compareTo(b.time));
    if (rs.isEmpty) return const SizedBox();
    final n = rs.length;
    return Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$n new reading${n == 1 ? '' : 's'}. Whose ${n == 1 ? 'is it' : 'are they'}?',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        for (final r in rs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r.systolic}/${r.diastolic}  ♥ ${r.pulse}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(when(r.time), style: muted(context)),
                ]),
              ),
              for (final u in [1, 2]) ...[
                const SizedBox(width: 6),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => _give([r.key], u),
                  child: Text(st.personName(u)),
                ),
              ],
            ]),
          ),
        if (n > 1) ...[
          const Divider(),
          Wrap(spacing: 8, children: [
            for (final u in [1, 2]) TextButton(onPressed: () => _give(rs.map((r) => r.key), u), child: Text('All ${st.personName(u)}')),
          ]),
        ],
        TextButton(
          onPressed: () async {
            await _give(rs.map((r) => r.key), 1);
            await st.setFlag('never_ask_who', true);
          },
          child: Text("They're always ${st.personName(1)}. Stop asking"),
        ),
      ]),
    );
  }

  static Future<void> _give(Iterable<String> keys, int u) async {
    final k = keys.toList();
    await Store.i.transfer(k, u);
    await Settings.i.clearPendingWho(k);
  }
}
