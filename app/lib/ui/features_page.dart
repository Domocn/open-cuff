import 'package:flutter/material.dart';

import '../features.dart';
import '../notify.dart';
import '../outbox.dart';
import '../store.dart';
import 'theme.dart';

/// Every extra in one place, grouped. All start off; each shows its own small settings when switched on.
class FeaturesPage extends StatelessWidget {
  const FeaturesPage({super.key});

  static const _needNotifications = {'trends', 'goals', 'reminders', 'weekly', 'meds'};

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: featureGroups.length,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Features'),
            bottom: TabBar(isScrollable: true, tabs: [for (final g in featureGroups) Tab(text: g.split(' ').first)]),
          ),
          body: ListenableBuilder(
            listenable: Settings.i,
            builder: (context, _) => TabBarView(children: [
              for (final g in featureGroups)
                ListView(padding: const EdgeInsets.all(14), children: [
                  Card(
                    child: Column(children: [
                      for (final f in features.where((f) => f.group == g)) ...[
                        SwitchListTile(
                          title: Text(f.title),
                          subtitle: Text(f.subtitle),
                          value: Settings.i.flag(f.key),
                          onChanged: (v) async {
                            if (v && _needNotifications.contains(f.key)) await Notify.askPermission();
                            if (v && f.key == 'context' && !await Outbox.askContext()) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text('Health Connect did not allow reading sleep and heart rate')));
                              }
                              return;
                            }
                            await Settings.i.setFlag(f.key, v);
                            await Notify.reschedule();
                          },
                        ),
                        if (Settings.i.flag(f.key)) ..._extra(context, f.key),
                      ],
                    ]),
                  ),
                  if (g == 'House') ...[
                    const SizedBox(height: 10),
                    Text(
                        'Home Assistant and Health Connect are in More > Send readings to. '
                        'Spoken results, desk tablet nudges and showing Chris your readings are set up in Home Assistant, using the readings Open Cuff sends.',
                        style: muted(context)),
                  ],
                ]),
            ]),
          ),
        ),
      );

  List<Widget> _extra(BuildContext context, String key) {
    Widget timeTile(String label, String k, String def) => ListTile(
          contentPadding: const EdgeInsets.only(left: 32, right: 16),
          title: Text(label),
          trailing: Text(Settings.i.text(k).isEmpty ? def : Settings.i.text(k), style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () async {
            final cur = (Settings.i.text(k).isEmpty ? def : Settings.i.text(k)).split(':');
            final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(cur[0]), minute: int.parse(cur[1])));
            if (t == null) return;
            await Settings.i.setText(k, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
            await Notify.reschedule();
          },
        );
    Widget numTile(String label, String k, int def) => ListTile(
          contentPadding: const EdgeInsets.only(left: 32, right: 16),
          title: Text(label),
          trailing: Text(Settings.i.text(k).isEmpty ? '$def' : Settings.i.text(k), style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () async {
            final c = TextEditingController(text: Settings.i.text(k).isEmpty ? '$def' : Settings.i.text(k));
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: Text(label),
                content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
                ],
              ),
            );
            if (ok == true && int.tryParse(c.text.trim()) != null) await Settings.i.setText(k, c.text.trim());
          },
        );
    return switch (key) {
      'reminders' => [timeTile('Morning', 'remind_am', '08:30'), timeTile('Evening', 'remind_pm', '20:30')],
      'goals' => [
          numTile('Top number limit', 'limit_sys', 135),
          numTile('Bottom number limit', 'limit_dia', 85),
          numTile('Pulse limit', 'limit_pulse', 100),
        ],
      _ => const [],
    };
  }
}
