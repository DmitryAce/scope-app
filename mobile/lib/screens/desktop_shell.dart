import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/desktop.dart';
import '../widgets/task_sheet.dart';
import 'calendar.dart';
import 'projects.dart';
import 'search.dart';
import 'settings.dart';
import 'tags.dart';
import 'task_editor.dart';
import 'today.dart';

/// Раздел в центре десктопа.
enum _View { today, calendar, inbox, search, projects, project, tags, settings }

/// Широкая раскладка: боковая панель, раздел по центру, задача справа.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  static _View _lastView = _View.today;
  static int? _lastProject;

  _View _view = _lastView;
  int? _projectId = _lastProject;
  final _calendarKey = GlobalKey<CalendarScreenState>();

  void _go(_View v, {int? project}) {
    setState(() {
      _view = _lastView = v;
      _projectId = _lastProject = project;
    });
  }

  void _newTask() {
    final day = _view == _View.calendar ? _calendarKey.currentState?.selected : null;
    showTaskSheet(context, day: day, projectId: _view == _View.project ? _projectId : null);
  }

  Widget _page() {
    Widget narrow(Widget child) => Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: child),
          ),
        );
    switch (_view) {
      case _View.today:
        return narrow(const TodayScreen());
      case _View.calendar:
        return narrow(CalendarScreen(key: _calendarKey));
      case _View.projects:
        return narrow(const ProjectsScreen());
      case _View.settings:
        return narrow(const SettingsScreen());
      case _View.search:
        return narrow(const SearchScreen());
      case _View.tags:
        return narrow(const TagsScreen());
      case _View.inbox:
        return narrow(const ProjectScreen(projectId: null));
      case _View.project:
        return narrow(ProjectScreen(projectId: _projectId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewKey = '${_view.name}-${_projectId ?? ''}';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newTask,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _go(_View.search),
        const SingleActivator(LogicalKeyboardKey.f5): () => StoreScope.read(context).refresh(),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () => _go(_View.today),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () => _go(_View.calendar),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () => _go(_View.projects),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () => _go(_View.settings),
        const SingleActivator(LogicalKeyboardKey.escape): DesktopPanel.close,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(children: [
              _Sidebar(view: _view, projectId: _projectId, onGo: _go, onNewTask: _newTask),
              const VerticalDivider(width: 1, thickness: 1, color: C.borderLight),
              Expanded(
                // Свой навигатор: экраны открываются внутри центра, боковая панель остаётся.
                child: Navigator(
                  key: ValueKey(viewKey),
                  onGenerateRoute: (_) => PageRouteBuilder(
                    pageBuilder: (_, __, ___) => _page(),
                    transitionDuration: Duration.zero,
                  ),
                ),
              ),
              const _TaskPanel(),
            ]),
        ),
      ),
    );
  }
}

class _TaskPanel extends StatelessWidget {
  const _TaskPanel();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PanelContent?>(
      valueListenable: DesktopPanel.content,
      builder: (context, content, _) => AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerLeft,
        child: content == null
            ? const SizedBox(width: 0, height: double.infinity)
            : Container(
                width: 440,
                decoration: const BoxDecoration(
                  color: C.bg,
                  border: Border(left: BorderSide(color: C.borderLight)),
                ),
                child: TaskEditorScreen(
                  key: ValueKey(content.key),
                  task: content.task,
                  draft: content.draft,
                  onClose: DesktopPanel.close,
                ),
              ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.view, required this.projectId, required this.onGo, required this.onNewTask});

  final _View view;
  final int? projectId;
  final void Function(_View, {int? project}) onGo;
  final VoidCallback onNewTask;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final today = dayOnly(DateTime.now());
    final todayOpen = store.tasksOn(today).where((t) => !t.isCompleted).length + store.overdue.length;

    Widget nav(_View v, IconData icon, IconData active, String label, {int? count}) => _NavTile(
          icon: view == v ? active : icon,
          label: label,
          count: count,
          selected: view == v,
          onTap: () => onGo(v),
        );

    return Container(
      width: 264,
      color: C.bg2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 10, 6),
          child: Row(children: [
            const ScopeLogo(size: 30),
            const SizedBox(width: 10),
            const Text('Scope', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(
              tooltip: 'Обновить (F5)',
              onPressed: store.syncing ? null : store.refresh,
              icon: const Icon(PhosphorIconsRegular.arrowsClockwise, size: 19),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Align(alignment: Alignment.centerLeft, child: ConnectionPill(onTap: () => onGo(_View.settings))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            height: 42,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: C.accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: onNewTask,
              child: Row(children: [
                Icon(PhosphorIconsBold.plus, size: 17, color: C.onAccent),
                const SizedBox(width: 10),
                const Expanded(child: Text('Новая задача', style: TextStyle(fontWeight: FontWeight.w800))),
                Text('Ctrl N',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.onAccent.withValues(alpha: 0.6))),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        nav(_View.today, PhosphorIconsRegular.sun, PhosphorIconsFill.sun, 'Сегодня', count: todayOpen),
        nav(_View.calendar, PhosphorIconsRegular.calendarBlank, PhosphorIconsFill.calendarBlank, 'Календарь'),
        nav(_View.inbox, PhosphorIconsRegular.tray, PhosphorIconsFill.tray, 'Входящие', count: store.inbox.length),
        nav(_View.search, PhosphorIconsRegular.magnifyingGlass, PhosphorIconsBold.magnifyingGlass, 'Поиск'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
          child: Row(children: [
            InkWell(
              onTap: () => onGo(_View.projects),
              child: const Text('Проекты',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: C.muted, letterSpacing: 0.3)),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Новый проект',
              visualDensity: VisualDensity.compact,
              onPressed: () => openProjectEditor(context),
              icon: const Icon(PhosphorIconsRegular.plus, size: 16, color: C.muted),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 8), children: [
            for (final (p, depth) in store.projectTree())
              _ProjectTile(
                project: p,
                count: store.openCount(p.id),
                depth: depth,
                selected: view == _View.project && projectId == p.id,
                onTap: () => onGo(_View.project, project: p.id),
              ),
          ]),
        ),
        const Divider(height: 1, color: C.borderLight),
        const SizedBox(height: 6),
        nav(_View.tags, PhosphorIconsRegular.hash, PhosphorIconsBold.hash, 'Теги'),
        nav(_View.settings, PhosphorIconsRegular.gear, PhosphorIconsFill.gear, 'Настройки'),
        const SizedBox(height: 10),
      ]),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: selected ? C.accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Icon(icon, size: 19, color: selected ? C.accent2 : C.text2),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? C.text : C.text2,
                    )),
              ),
              if (count != null && count! > 0)
                Text('$count', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: C.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.project,
    required this.count,
    required this.selected,
    required this.onTap,
    this.depth = 0,
  });

  final Project project;
  final int count;
  final bool selected;
  final int depth;
  final VoidCallback onTap;

  bool get nested => depth > 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(10.0 + depth * 16, 1, 10, 1),
      child: Material(
        color: selected ? C.accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onSecondaryTap: () => showProjectActions(context, project),
          onLongPress: () => showProjectActions(context, project),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              ProjectAvatar(project: project, size: nested ? 20 : 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: nested ? 13 : 13.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? C.text : C.text2,
                    )),
              ),
              if (project.isPinned) ...[
                const Icon(PhosphorIconsFill.pushPin, size: 11, color: C.muted),
                const SizedBox(width: 6),
              ],
              if (count > 0)
                Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
