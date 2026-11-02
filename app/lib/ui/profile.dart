import 'package:flutter/material.dart';

import '../store.dart';
import 'theme.dart';

/// "My health record": details used on reports. Kept on the phone only, every field optional.
class ProfilePage extends StatelessWidget {
  final int user;
  const ProfilePage({super.key, required this.user});

  static const _choices = <String, List<(String, String)>>{
    'sex': [('Male', ''), ('Female', ''), ('Other', ''), ('Prefer not to say', '')],
    'blood': [('A+', ''), ('A-', ''), ('B+', ''), ('B-', ''), ('AB+', ''), ('AB-', ''), ('O+', ''), ('O-', ''), ('Not known', '')],
    'skin': [
      ('Type I', 'Very pale skin. Always burns, never tans'),
      ('Type II', 'Fair skin. Usually burns, tans a little'),
      ('Type III', 'Medium skin. Sometimes burns, tans slowly'),
      ('Type IV', 'Olive or light brown skin. Rarely burns, tans easily'),
      ('Type V', 'Brown skin. Very rarely burns'),
      ('Type VI', 'Dark brown or black skin. Never burns'),
    ],
    'activity': [
      ('Mostly sitting', 'Desk job, little exercise'),
      ('Lightly active', 'Walking most days'),
      ('Active', 'Exercise 3 or more times a week'),
      ('Very active', 'Hard exercise most days'),
    ],
    'smoking': [('Never', ''), ('Used to', ''), ('Sometimes', ''), ('Every day', ''), ('Vape', '')],
    'alcohol': [('None', ''), ('Now and then', ''), ('Every week', ''), ('Most days', '')],
    'stress': [('Low', ''), ('Some', ''), ('High', '')],
  };

  static const _titles = {
    'sex': 'Sex',
    'blood': 'Blood type',
    'skin': 'Skin type (Fitzpatrick)',
    'activity': 'Activity',
    'smoking': 'Smoking',
    'alcohol': 'Alcohol',
    'stress': 'Stress',
  };

  String _k(String f) => 'p_${user}_$f';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My health record')),
        body: ListenableBuilder(
          listenable: Settings.i,
          builder: (context, _) {
            final st = Settings.i;
            final first = st.text('name_$user'), last = st.text(_k('last'));
            final initials = [first, last].where((s) => s.isNotEmpty).map((s) => s[0].toUpperCase()).join();
            final dob = DateTime.tryParse(st.text(_k('dob')));
            final height = int.tryParse(st.text(_k('height')));
            Widget tile(String label, String value, VoidCallback onTap) => ListTile(
                  visualDensity: VisualDensity.compact,
                  minVerticalPadding: 0,
                  title: Text(label),
                  trailing: Text(value.isEmpty ? 'Not set' : value,
                      style: TextStyle(
                          fontSize: 15,
                          color: value.isEmpty ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600)),
                  onTap: onTap,
                );
            return ListView(padding: const EdgeInsets.all(14), children: [
              Box(
                child: Column(children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(initials.isEmpty ? '?' : initials,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  const SizedBox(height: 10),
                  Text([first, last].where((s) => s.isNotEmpty).join(' ').ifEmpty('Your name'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  if (dob != null) Text('Age ${_age(dob)}', style: muted(context)),
                ]),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  tile('First name', first, () => _text(context, 'First name', 'name_$user')),
                  tile('Last name', last, () => _text(context, 'Last name', _k('last'))),
                  tile('Date of birth', dob == null ? '' : '${dob.day} ${_m[dob.month - 1]} ${dob.year}', () => _date(context, dob)),
                  tile('Height', height == null ? '' : '$height cm (${_ftIn(height)})', () => _text(context, 'Height in cm', _k('height'), number: true)),
                  for (final f in ['sex', 'blood', 'skin']) tile(_titles[f]!, st.text(_k(f)), () => _pick(context, f)),
                ]),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  for (final f in ['activity', 'smoking', 'alcohol', 'stress']) tile(_titles[f]!, st.text(_k(f)), () => _pick(context, f)),
                ]),
              ),
              const SizedBox(height: 12),
              Text('Only kept on this phone. Used on your doctor reports if you choose to include it.', style: muted(context)),
            ]);
          },
        ),
      );

  static const _m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static int _age(DateTime dob) {
    final n = DateTime.now();
    return n.year - dob.year - ((n.month < dob.month || (n.month == dob.month && n.day < dob.day)) ? 1 : 0);
  }

  static String _ftIn(int cm) {
    final inches = (cm / 2.54).round();
    return '${inches ~/ 12} ft ${inches % 12} in';
  }

  Future<void> _text(BuildContext context, String title, String key, {bool number = false}) async {
    final c = TextEditingController(text: Settings.i.text(key));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: number ? TextInputType.number : TextInputType.name,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      if (number && c.text.trim().isNotEmpty && int.tryParse(c.text.trim()) == null) return;
      await Settings.i.setText(key, c.text);
    }
  }

  Future<void> _date(BuildContext context, DateTime? current) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (d != null) await Settings.i.setText(_k('dob'), d.toIso8601String().split('T').first);
  }

  Future<void> _pick(BuildContext context, String f) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(_titles[f]!)),
            body: ListenableBuilder(
              listenable: Settings.i,
              builder: (context, _) {
                final cur = Settings.i.text(_k(f));
                return RadioGroup<String>(
                  groupValue: cur,
                  onChanged: (x) async {
                    await Settings.i.setText(_k(f), x ?? '');
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: ListView(padding: const EdgeInsets.all(14), children: [
                    for (final (v, help) in [('', 'Leave blank'), ..._choices[f]!])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: RadioListTile<String>(
                            value: v,
                            title: Text(v.isEmpty ? 'Not set' : v),
                            subtitle: help.isEmpty ? null : Text(help),
                          ),
                        ),
                      ),
                  ]),
                );
              },
            ),
          ),
        ),
      );
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
