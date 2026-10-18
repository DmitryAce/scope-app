import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/task_sheet.dart';
import '../widgets/desktop.dart';
import 'calendar.dart';
import 'desktop_shell.dart';
import 'projects.dart';
import 'settings.dart';
import 'today.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  // Переживает пересборку приложения при смене акцента.
  static int _lastTab = 0;
  int _tab = _lastTab;
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
    if (isWideLayout(context)) return const SyncErrorListener(child: DesktopShell());
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
          setState(() => _tab = _lastTab = i);
        },
        onAdd: _add,
      ),
    );
  }
}

/// Плавающая капсула: только иконки, выбранный пункт раскрывается в «пилюлю»
/// с подписью. Кнопка «+» — отдельный круг справа.
class ScopeNavBar extends StatelessWidget {
  const ScopeNavBar({super.key, required this.index, required this.onSelect, required this.onAdd});

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  static const _items = [
    (PhosphorIconsRegular.sun, PhosphorIconsFill.sun, 'Сегодня'),
    (PhosphorIconsRegular.calendarBlank, PhosphorIconsFill.calendarBlank, 'Календарь'),
    (PhosphorIconsRegular.folderSimple, PhosphorIconsFill.folderSimple, 'Проекты'),
    (PhosphorIconsRegular.dotsThreeOutline, PhosphorIconsFill.dotsThreeOutline, 'Ещё'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottom + 12),
      child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF17171F).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: LayoutBuilder(builder: (context, c) {
                  // Выбранный пункт шире остальных — места хватает под подпись.
                  final wide = c.maxWidth * 0.46;
                  final narrow = (c.maxWidth - wide) / (_items.length - 1);
                  return Row(children: [
                    for (var i = 0; i < _items.length; i++)
                      _NavItem(
                        width: i == index ? wide : narrow,
                        icon: _items[i].$1,
                        activeIcon: _items[i].$2,
                        label: _items[i].$3,
                        selected: i == index,
                        onTap: () => onSelect(i),
                      ),
                  ]);
                }),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _AddButton(onTap: onAdd),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.width,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final double width;
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        width: width,
        height: double.infinity,
        decoration: BoxDecoration(
          color: selected ? C.accent.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: ClipRect(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(selected ? activeIcon : icon, size: 22, color: selected ? C.accent2 : C.text2.withValues(alpha: 0.75)),
            if (selected)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Text(label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: C.text)),
                ),
              ),
          ]),
        ),
      ),
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
        scale: _down ? 0.9 : 1,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: C.accent,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Icon(PhosphorIconsBold.plus, color: C.onAccent, size: 26),
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
              const Icon(PhosphorIconsRegular.cloudSlash, color: C.high, size: 18),
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
