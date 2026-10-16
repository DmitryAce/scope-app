import 'dart:ui';

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
      extendBody: true,
      body: SyncErrorListener(child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: ScopeNavBar(
        index: _tab,
        onSelect: (i) {
          HapticFeedback.selectionClick();
          setState(() => _tab = i);
        },
        onAdd: _add,
      ),
    );
  }
}

/// Плавающая «капсула» навигации: стекло, выбранный пункт раскрывается
/// цветной плашкой с подписью, по центру — градиентная кнопка «+».
class ScopeNavBar extends StatelessWidget {
  const ScopeNavBar({super.key, required this.index, required this.onSelect, required this.onAdd});

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  static const _items = [
    (Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, 'Сегодня'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Календарь'),
    (Icons.folder_outlined, Icons.folder_rounded, 'Проекты'),
    (Icons.tune_outlined, Icons.tune_rounded, 'Ещё'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    Widget item(int i) => Expanded(
          child: _NavItem(
            icon: _items[i].$1,
            activeIcon: _items[i].$2,
            label: _items[i].$3,
            selected: index == i,
            onTap: () => onSelect(i),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottom + 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: C.bg3.withValues(alpha: 0.78),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [C.elevated.withValues(alpha: 0.85), C.bg2.withValues(alpha: 0.9)],
              ),
            ),
            child: Row(children: [
              item(0),
              item(1),
              _AddButton(onTap: onAdd),
              item(2),
              item(3),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: selected ? 52 : 40,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: selected
                ? LinearGradient(colors: [C.accent.withValues(alpha: 0.45), C.logo.withValues(alpha: 0.35)])
                : null,
            boxShadow: selected ? [BoxShadow(color: C.accent.withValues(alpha: 0.35), blurRadius: 14)] : null,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(
              selected ? activeIcon : icon,
              key: ValueKey(selected),
              size: 23,
              color: selected ? Colors.white : C.text2,
            ),
          ),
        ),
        const SizedBox(height: 4),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? C.text : C.muted,
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
        ),
      ]),
    );
  }
}

class _AddButton extends StatefulWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: _down ? 0.88 : 1,
        child: Container(
          width: 56,
          height: 52,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF9F5AF7), C.accent, C.logo],
            ),
            boxShadow: [
              BoxShadow(color: C.accent.withValues(alpha: 0.55), blurRadius: 18, offset: const Offset(0, 4)),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
        ),
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
