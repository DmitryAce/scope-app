import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/task_sheet.dart';
import 'calendar.dart';
import 'projects.dart';
import 'settings.dart';
import 'today.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  final _calendarKey = GlobalKey<CalendarScreenState>();
  DateTime _pausedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    // Вернулись в приложение: могли прийти домой или уйти — перевыбираем сервер.
    if (state == AppLifecycleState.resumed &&
        DateTime.now().difference(_pausedAt) > const Duration(seconds: 20)) {
      StoreScope.read(context).refresh();
    }
  }

  void _add() {
    HapticFeedback.lightImpact();
    final day = _tab == 1 ? _calendarKey.currentState?.selected : null;
    showTaskSheet(context, day: day);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TodayScreen(),
      CalendarScreen(key: _calendarKey),
      const ProjectsScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: SyncErrorListener(child: IndexedStack(index: _tab, children: pages)),
      floatingActionButton: _tab == 3
          ? null
          : FloatingActionButton(
              onPressed: _add,
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.add_rounded, size: 30),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny_rounded), label: 'Сегодня'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month_rounded),
              label: 'Календарь'),
          NavigationDestination(
              icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder_rounded), label: 'Проекты'),
          NavigationDestination(
              icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'Ещё'),
        ],
      ),
    );
  }
}

/// Ошибку синхронизации показываем снекбаром один раз.
class SyncErrorListener extends StatefulWidget {
  const SyncErrorListener({super.key, required this.child});

  final Widget child;

  @override
  State<SyncErrorListener> createState() => _SyncErrorListenerState();
}

class _SyncErrorListenerState extends State<SyncErrorListener> {
  String? _shown;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final err = store.error;
    if (err != null && err != _shown) {
      _shown = err;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.cloud_off_rounded, color: C.high, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(err)),
            ]),
            action: SnackBarAction(label: 'Повторить', onPressed: store.refresh),
          ));
      });
    }
    if (err == null) _shown = null;
    return widget.child;
  }
}
