import 'package:flutter/material.dart';

import '../scales.dart';
import '../store.dart';
import 'reading_sheet.dart';
import 'theme.dart';

/// Pick the blood pressure scale used for colours, words, alerts and reports. Swipe through, tap Use this scale.
class ScalePage extends StatefulWidget {
  const ScalePage({super.key});

  @override
  State<ScalePage> createState() => _ScalePageState();
}

class _ScalePageState extends State<ScalePage> {
  late final _pager = PageController(initialPage: scales.indexOf(currentScale));
  late int _at = scales.indexOf(currentScale);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Blood pressure scale')),
        body: ListenableBuilder(
          listenable: Settings.i,
          builder: (context, _) => Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(onPressed: _at == 0 ? null : () => _pager.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut), icon: const Icon(Icons.chevron_left)),
              for (var i = 0; i < scales.length; i++)
                Container(
                  margin: const EdgeInsets.all(4),
                  width: i == _at ? 12 : 8,
                  height: i == _at ? 12 : 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _at ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              IconButton(
                  onPressed: _at == scales.length - 1 ? null : () => _pager.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                  icon: const Icon(Icons.chevron_right)),
            ]),
            Expanded(
              child: PageView(
                controller: _pager,
                onPageChanged: (i) => setState(() => _at = i),
                children: [
                  for (final sc in scales)
                    ListView(padding: const EdgeInsets.all(14), children: [
                      Box(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(sc.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          SizedBox(height: 240, width: double.infinity, child: CustomPaint(painter: ZonePainter(null, null, Theme.of(context), scale: sc))),
                          const SizedBox(height: 10),
                          Text(sc.about, style: muted(context)),
                          const SizedBox(height: 10),
                          if (sc.hasLow) Text('${sc.zones.first.name}: under ${sc.lowSys}/${sc.lowDia}', style: muted(context)),
                          for (final z in sc.upper)
                            Text(z.maxSys >= 999 ? '${z.name}: above that' : '${z.name}: up to ${z.maxSys}/${z.maxDia}', style: muted(context)),
                        ]),
                      ),
                    ]),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  width: double.infinity,
                  child: scales[_at] == currentScale
                      ? const OutlinedButton(onPressed: null, child: Text('In use'))
                      : FilledButton(onPressed: () => Settings.i.setText('scale', scales[_at].id), child: const Text('Use this scale')),
                ),
              ),
            ),
          ]),
        ),
      );
}
