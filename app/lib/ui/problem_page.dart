import 'dart:io';

import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../background.dart';
import '../cuff.dart';
import '../diag.dart';
import '../features.dart';
import '../outbox.dart';
import '../store.dart';
import 'theme.dart';

/// More > Report a problem. Shows the problem log and sends it to the project's GitHub issues (or anywhere, as a file).
class ProblemPage extends StatefulWidget {
  const ProblemPage({super.key});

  static const issuesUrl = 'https://github.com/Domocn/open-cuff/issues/new';
  static const newCuffUrl = 'https://github.com/Domocn/open-cuff/issues/new?template=new-cuff.yml';

  @override
  State<ProblemPage> createState() => _ProblemPageState();
}

class _ProblemPageState extends State<ProblemPage> {
  String _log = '', _about = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final log = await Diag.read();
    final about = await _details();
    if (mounted) {
      setState(() {
        _log = log;
        _about = about;
      });
    }
  }

  /// Phone and app facts that help with a fix. Nothing personal: no names, readings, addresses or tokens.
  Future<String> _details() async {
    final p = await PackageInfo.fromPlatform();
    final st = Settings.i;
    final on = features.where((f) => st.flag(f.key)).map((f) => f.key).join(', ');
    return [
      'Open Cuff ${p.version} (${p.buildNumber})',
      await _phone(),
      'Cuff paired: ${st.cuffId.isEmpty ? 'no' : 'yes (${st.cuffBtName.isEmpty ? 'unknown model' : st.cuffBtName})'}',
      'Cuff now: ${Cuff.i.state.name}${Cuff.i.message.isEmpty ? '' : ', "${Cuff.i.message}"'}',
      'Background collecting: ${st.flag('background') ? 'on' : 'off'}, service ${await Background.running ? 'running' : 'not running'}',
      'Health Connect: ${st.flag('health') ? 'on' : 'off'}, Home Assistant: ${st.flag('ha') ? 'on' : 'off'}',
      if (Outbox.lastError.isNotEmpty) 'Last sending error: ${Diag.clean(Outbox.lastError)}',
      'Features on: ${on.isEmpty ? 'none' : on}',
      'Readings stored: ${Store.i.everything.length}',
    ].join('\n');
  }

  /// Phone make, model and Android version: cuff bugs are often specific to one phone's Bluetooth.
  Future<String> _phone() async {
    try {
      final a = await DeviceInfoPlugin().androidInfo;
      return 'Phone: ${a.manufacturer} ${a.model}, Android ${a.version.release} (API ${a.version.sdkInt})';
    } catch (_) {
      return 'Phone: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    }
  }

  /// GitHub can't take a file through a link, so the issue gets the details and the most recent lines, and the full
  /// log goes on the clipboard to paste underneath if it's needed.
  Future<void> _github() async {
    final lines = _log.trim().split('\n');
    var tail = <String>[];
    for (final l in lines.reversed) {
      if (tail.join('\n').length + l.length > 4500) break;
      tail.insert(0, l);
    }
    final body = 'What happened?\n\n(Write what you were doing and what went wrong.)\n\n'
        '**Details**\n```\n$_about\n```\n\n'
        '**Problem log (last ${tail.length} of ${lines.length} lines)**\n```\n${tail.join('\n')}\n```\n';
    await Clipboard.setData(ClipboardData(text: '$_about\n\n$_log'));
    final uri = Uri.parse(ProblemPage.issuesUrl).replace(queryParameters: {'title': 'Problem: ', 'body': body, 'labels': 'bug'});
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? 'The full log is also copied. Paste it into the issue if they ask for more'
              : 'Could not open GitHub. The log is copied, so you can paste it anywhere')));
    }
  }

  Future<void> _share() async {
    final f = File('${(await Diag.file()).parent.path}/open-cuff-problem-log.txt');
    await f.writeAsString('$_about\n\n$_log');
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Open Cuff problem log'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Report a problem')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(
              'Open Cuff keeps a short diary of what it does: finding and connecting to the cuff, copying readings, '
              'sending them on, and any errors. It never includes your readings, names, addresses or tokens, so it is '
              'safe to share.',
              style: muted(context)),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: _github, icon: const Icon(Icons.bug_report_outlined), label: const Text('Report on GitHub')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _share, icon: const Icon(Icons.share_outlined), label: const Text('Send the file'))),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: '$_about\n\n$_log'));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          const _NewCuff(),
          const SizedBox(height: 16),
          Text('Details', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Box(child: SelectableText(_about, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('Problem log', style: Theme.of(context).textTheme.titleSmall)),
            TextButton(
              onPressed: () async {
                await Diag.clear();
                await _load();
              },
              child: const Text('Clear'),
            ),
          ]),
          Box(
            child: SelectableText(
              _log.trim().isEmpty ? 'Nothing logged yet.' : _log.trim().split('\n').reversed.take(300).join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          const SizedBox(height: 6),
          Text('Newest first. The file keeps about the last 1,500 lines.', style: muted(context)),
        ]),
      );
}

/// A cuff Open Cuff doesn't know, or one it can't connect to: how to look at it with nRF Connect and ask for it.
class _NewCuff extends StatelessWidget {
  const _NewCuff();

  @override
  Widget build(BuildContext context) {
    final steps = [
      'Install nRF Connect (free) and open its Scanner.',
      "Switch the cuff's Bluetooth on (take a reading, or press its Bluetooth button) and find it in the list.",
      'Tap its row and note the name and service UUIDs. FFE0 means Open Cuff should read it. 1810 is the standard '
          'blood pressure format, which can be added.',
      'Tap Connect and take a screenshot of the services list.',
      'Turn on the arrows for the NOTIFY or INDICATE parts (for 1810: Blood Pressure Measurement), take a reading, '
          'then save the log from the menu. Note the numbers the cuff showed.',
      'Tap Ask for my cuff below and attach the screenshot and the log.',
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: const Icon(Icons.bluetooth_searching),
        title: const Text("New cuff, or one that won't connect?"),
        subtitle: const Text('Check it with a free Bluetooth app and ask for it to be added'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 22, child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w700))),
                Expanded(child: Text(steps[i])),
              ]),
            ),
          const SizedBox(height: 6),
          Text("Only read, never write: don't tap the up-arrow buttons in nRF Connect. The wrong bytes can clear a "
              "cuff's memory, and nothing here needs them.",
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () => launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=no.nordicsemi.android.mcp'),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Get nRF Connect'),
            ),
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse(ProblemPage.newCuffUrl), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Ask for my cuff'),
            ),
          ]),
        ],
      ),
    );
  }
}
