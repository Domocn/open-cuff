import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'background.dart';
import 'cuff.dart';
import 'diag.dart';
import 'outbox.dart';
import 'notify.dart';
import 'store.dart';
import 'widget.dart';
import 'ui/add.dart';
import 'ui/history.dart';
import 'ui/home.dart';
import 'ui/more.dart';
import 'ui/reports_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // crashes and uncaught errors go into the problem log (More > Report a problem)
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    Diag.error('crash', d.exceptionAsString(), d.stack);
  };
  PlatformDispatcher.instance.onError = (e, st) {
    Diag.error('crash', e, st);
    return true;
  };
  Diag.note('app', 'opened');
  await Settings.i.load();
  await Store.i.load();
  Background.init();
  runApp(const OpenCuffApp());
}

class OpenCuffApp extends StatelessWidget {
  const OpenCuffApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Open Cuff',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        // opencuff://measure (an NFC tag or link) opens New reading
        onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => Shell(startTab: s.name == '/measure' ? 2 : 0)),
      );
}

class Shell extends StatefulWidget {
  final int startTab;
  const Shell({super.key, this.startTab = 0});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  late int _tab = widget.startTab;

  @override
  void initState() {
    super.initState();
    Notify.reschedule();
    WidgetsBinding.instance.addObserver(this);
    FlutterForegroundTask.addTaskDataCallback(_fromService);
    Cuff.i.onCollectRemote = Background.collectNow;
    Settings.i.addListener(_tellService);
    WidgetsBinding.instance.addPostFrameCallback((_) => _wake());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.removeTaskDataCallback(_fromService);
    Settings.i.removeListener(_tellService);
    super.dispose();
  }

  void _fromService(Object data) {
    if (data is Map) Cuff.i.mirror(data);
    Store.i.refresh();
    Settings.i.reload();
  }

  int _waiting = 0;

  void _tellService() {
    if (Cuff.i.remote) FlutterForegroundTask.sendDataToTask('reload');
    // new readings waiting for "whose are these?": bring Home to the front so the question is seen
    final n = Settings.i.pendingWho.length;
    if (n > _waiting && _tab != 0 && mounted) setState(() => _tab = 0);
    _waiting = n;
  }

  Future<void> _wake() async {
    if (Background.wanted) {
      Cuff.i.stop();
      Cuff.i.remote = true;
      await Background.start();
    } else {
      Cuff.i.remote = false;
      await Cuff.i.start();
    }
    await Store.i.refresh();
    await Outbox.flush();
    await updateWidget();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _wake();
    } else if (s == AppLifecycleState.paused && !Cuff.i.remote) {
      Cuff.i.stop();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: const [HomePage(), HistoryPage(), AddPage(), ReportsPage(), MorePage()]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.show_chart), label: 'History'),
            NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'Add'),
            NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: 'Reports'),
            NavigationDestination(icon: Icon(Icons.tune), label: 'More'),
          ],
        ),
      );
}
