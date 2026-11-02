import 'package:flutter/material.dart';

import '../cuff.dart';
import '../outbox.dart';
import '../store.dart';
import '../scales.dart';
import 'devices.dart';
import 'scale_page.dart';
import 'features_page.dart';
import 'homecheck_page.dart';
import 'meds_page.dart';
import 'problem_page.dart';
import 'profile.dart';
import 'theme.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Settings.i,
        builder: (context, _) {
          final st = Settings.i;
          return ListView(padding: EdgeInsets.fromLTRB(14, MediaQuery.paddingOf(context).top + 12, 14, 24), children: [
            Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            _section(context, 'You', [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                      [st.text('name_${st.user == 0 ? 1 : st.user}'), st.text('p_${st.user == 0 ? 1 : st.user}_last')]
                          .where((s) => s.isNotEmpty)
                          .map((s) => s[0].toUpperCase())
                          .join()
                          .padRight(1, '?'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                title: const Text('My health record'),
                subtitle: Text(st.text('name_${st.user == 0 ? 1 : st.user}').isEmpty
                    ? 'Your name, age and details for reports'
                    : st.text('name_${st.user == 0 ? 1 : st.user}')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(user: st.user == 0 ? 1 : st.user))),
              ),
            ]),
            _section(context, 'Cuff', [
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: Text(st.cuffName.isEmpty ? 'Add your cuff' : st.cuffName),
                subtitle: Text(st.cuffName.isEmpty
                    ? 'Find it and pair it'
                    : 'Tap for Collect now, background collecting and more'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DevicePage())),
              ),
            ]),
            _section(context, 'Send readings to', [
              SwitchListTile(
                title: const Text('Health Connect'),
                subtitle: const Text('Blood pressure and pulse. Samsung Health, Fitbit and others read it from here'),
                value: st.flag('health'),
                onChanged: (v) async {
                  if (v && !await Outbox.askHealth()) {
                    final p = await Outbox.healthProblem();
                    if (context.mounted) _toast(context, p.isEmpty ? 'Health Connect permission was not given' : p);
                    return;
                  }
                  await st.setFlag('health', v);
                  if (v) await Outbox.flush();
                },
              ),
              SwitchListTile(
                title: const Text('Home Assistant'),
                subtitle: const Text('Each reading is sent to Home Assistant as a bp2_ble_reading event'),
                value: st.flag('ha'),
                onChanged: (v) async {
                  if (v && (st.text('ha_url').isEmpty || st.text('ha_token').isEmpty)) {
                    await _haDialog(context);
                    if (st.text('ha_url').isEmpty || st.text('ha_token').isEmpty) return;
                  }
                  await st.setFlag('ha', v);
                  if (v) await Outbox.flush();
                },
              ),
              if (st.flag('ha'))
                ListTile(title: const Text('Home Assistant address and token'), subtitle: Text(st.text('ha_url')), onTap: () => _haDialog(context)),
              if (Outbox.lastError.isNotEmpty) ListTile(title: Text(Outbox.lastError, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ]),
            _section(context, 'Features', [
              SwitchListTile(
                title: const Text('More than one person'),
                subtitle: const Text('Show whose readings are on screen, with a name each'),
                value: st.flag('people'),
                onChanged: (v) => st.setFlag('people', v),
              ),
              if (st.flag('people'))
                for (final u in [1, 2].where((u) => u != st.user))
                  ListTile(
                    title: Text('Name for cuff user $u'),
                    subtitle: Text(st.text('name_$u').isEmpty ? 'Not set' : st.text('name_$u')),
                    onTap: () => _nameDialog(context, u),
                  ),
              ListTile(
                leading: const Icon(Icons.grid_view),
                title: const Text('Blood pressure scale'),
                subtitle: Text(currentScale.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScalePage())),
              ),
              ListTile(
                leading: const Icon(Icons.toggle_on_outlined),
                title: const Text('All features'),
                subtitle: const Text('Medications, NHS home check, alerts, calm mode, reminders and more. Each has its own switch'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FeaturesPage())),
              ),
              if (st.flag('meds'))
                ListTile(
                  leading: const Icon(Icons.medication_outlined),
                  title: const Text('Medications'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MedsPage())),
                ),
              if (st.flag('homecheck'))
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('NHS home check'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HomeCheckPage())),
                ),
            ]),
            const SizedBox(height: 10),
            Text(
                'Open Cuff only reads from your cuff. It never sends the command that clears its memory. '
                'Readings stay on this phone unless you switch a destination on. Not medical advice.',
                style: muted(context)),
            const SizedBox(height: 10),
            Center(child: TextButton(onPressed: () => Cuff.i.start(), child: const Text('Search for the cuff again'))),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Report a problem'),
              subtitle: const Text('See what the app has been doing and send it for a fix'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProblemPage())),
            ),
          ]);
        },
      );

  Widget _section(BuildContext c, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 6), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          Card(child: Column(children: children)),
        ]),
      );

  void _toast(BuildContext c, String t) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _haDialog(BuildContext context) async {
    final url = TextEditingController(text: Settings.i.text('ha_url').isEmpty ? 'http://homeassistant.local:8123' : Settings.i.text('ha_url'));
    final token = TextEditingController(text: Settings.i.text('ha_token'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Home Assistant'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: url, decoration: const InputDecoration(labelText: 'Address')),
          TextField(
            controller: token,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Long-lived access token', helperText: 'Profile > Security in Home Assistant'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      await Settings.i.setText('ha_url', url.text);
      await Settings.i.setText('ha_token', token.text);
    }
  }

  Future<void> _nameDialog(BuildContext context, int u) async {
    final name = TextEditingController(text: Settings.i.text('name_$u'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(u == Settings.i.user ? 'Your name' : 'Name for cuff user $u'),
        content: TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) await Settings.i.setText('name_$u', name.text);
  }
}
