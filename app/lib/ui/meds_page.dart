import 'package:flutter/material.dart';

import '../meds.dart';
import '../models.dart';
import '../notify.dart';
import '../store.dart';
import 'theme.dart';

class MedsPage extends StatelessWidget {
  const MedsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Medications')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.add),
          label: const Text('Add a medicine'),
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([Settings.i, Store.i]),
          builder: (context, _) {
            final meds = Meds.all();
            if (meds.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Add a medicine to log doses and see your blood pressure at each dose.', style: muted(context)),
              );
            }
            return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 90), children: [
              for (final m in meds) ...[_MedCard(m), const SizedBox(height: 12)],
            ]);
          },
        ),
      );
}

class _MedCard extends StatelessWidget {
  final Med m;
  const _MedCard(this.m);

  @override
  Widget build(BuildContext context) {
    final taken = Meds.takenToday(m);
    final rows = Meds.byDose(m, Store.i.readings);
    return Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text([m.current?.dose ?? (m.next != null ? 'Starts ${_day(m.next!.from)}' : 'No dose set'), if (m.time.isNotEmpty) 'usually ${m.time}'].join(' · '), style: muted(context)),
              if (m.current != null && m.next != null) Text('Next: ${m.next!.dose} from ${_day(m.next!.from)}', style: muted(context)),
            ]),
          ),
          taken == null
              ? FilledButton(onPressed: () => Meds.markTaken(m), child: const Text('Taken'))
              : Pill('Taken ${hm(taken)}', bandColor(context, Band.ideal)),
        ]),
        if (m.steps.length > 1 || m.steps.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in m.steps)
              Chip(
                label: Text('${s.dose} from ${s.from.day}/${s.from.month}${s.from.isAfter(DateTime.now()) ? ' (planned)' : ''}'),
                visualDensity: VisualDensity.compact,
                backgroundColor: s == m.current ? Theme.of(context).colorScheme.primary.withValues(alpha: .15) : null,
                side: s.from.isAfter(DateTime.now()) ? BorderSide(color: Theme.of(context).colorScheme.outline, style: BorderStyle.solid) : null,
              ),
          ]),
        ],
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Blood pressure by dose', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final (label, s, d, p, n) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text(label, style: muted(context))),
                Text('$s/$d', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('  ♥ $p  ($n)', style: muted(context)),
              ]),
            ),
        ],
        const SizedBox(height: 6),
        Row(children: [
          TextButton(onPressed: () => _changeDose(context, m), child: const Text('Change dose')),
          TextButton(onPressed: () => _edit(context, m), child: const Text('Edit')),
        ]),
      ]),
    );
  }
}

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _day(DateTime d) => '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';

Future<void> _changeDose(BuildContext context, Med m) async {
  final dose = TextEditingController();
  DateTime from = DateTime.now();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text('New dose of ${m.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: dose, autofocus: true, decoration: const InputDecoration(labelText: 'Dose, for example 54 mg')),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Starting'),
            trailing: Text('${from.day}/${from.month}/${from.year}'),
            onTap: () async {
              final d = await showDatePicker(context: c, initialDate: from, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (d != null) set(() => from = d);
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
  if (ok != true || dose.text.trim().isEmpty) return;
  final meds = Meds.all();
  final x = meds.firstWhere((e) => e.id == m.id);
  x.steps
    ..add(DoseStep(dose.text.trim(), DateTime(from.year, from.month, from.day)))
    ..sort((a, b) => a.from.compareTo(b.from));
  await Meds.save(meds);
}

Future<void> _edit(BuildContext context, Med? m) async {
  final name = TextEditingController(text: m?.name ?? '');
  final dose = TextEditingController(text: m?.current?.dose ?? '');
  final time = TextEditingController(text: m?.time ?? '');
  final res = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(m == null ? 'Add a medicine' : 'Edit ${m.name}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, autofocus: m == null, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name, for example Amlodipine')),
        if (m == null) TextField(controller: dose, decoration: const InputDecoration(labelText: 'Dose, for example 36 mg')),
        TextField(controller: time, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'Usual time (HH:MM, optional)', helperText: 'Used for a reminder')),
      ]),
      actions: [
        if (m != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Remove')),
        TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save')),
      ],
    ),
  );
  if (res == null || res.isEmpty) return;
  final meds = Meds.all();
  if (res == 'delete') {
    meds.removeWhere((e) => e.id == m!.id);
  } else {
    if (name.text.trim().isEmpty) return;
    final t = RegExp(r'^\d{1,2}:\d{2}$').hasMatch(time.text.trim()) ? time.text.trim().padLeft(5, '0') : '';
    if (m == null) {
      meds.add(Med(DateTime.now().millisecondsSinceEpoch.toString(), name.text.trim(), t,
          [if (dose.text.trim().isNotEmpty) DoseStep(dose.text.trim(), DateTime.now())]));
    } else {
      final x = meds.firstWhere((e) => e.id == m.id);
      x
        ..name = name.text.trim()
        ..time = t;
    }
  }
  await Meds.save(meds);
  await Notify.reschedule();
}
