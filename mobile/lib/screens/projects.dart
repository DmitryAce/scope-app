import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/task_sheet.dart';
import '../widgets/task_tile.dart';
import 'search.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final inbox = store.inbox;
    return RefreshIndicator(
      color: C.accent2,
      backgroundColor: C.bg3,
      onRefresh: store.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                child: Row(children: [
                  const Text('Проекты',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  const Spacer(),
                  IconButton(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                    icon: const Icon(Icons.search_rounded),
                  ),
                  IconButton(
                    tooltip: 'Новый проект',
                    onPressed: () => showProjectEditor(context),
                    icon: const Icon(Icons.create_new_folder_outlined),
                  ),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: _InboxCard(count: inbox.length),
            ),
          ),
          if (store.projects.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.folder_open_rounded,
                title: 'Проектов пока нет',
                subtitle: 'Создайте первый — кнопка вверху справа',
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
              ),
              itemCount: store.projects.length,
              itemBuilder: (_, i) => _ProjectCard(project: store.projects[i]),
            ),
          ),
          if (store.archivedProjects.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                'Архив',
                count: store.archivedProjects.length,
                trailing: IconButton(
                  onPressed: () => setState(() => _showArchived = !_showArchived),
                  icon: Icon(_showArchived ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: C.text2),
                ),
              ),
            ),
            if (_showArchived)
              SliverList.builder(
                itemCount: store.archivedProjects.length,
                itemBuilder: (_, i) {
                  final p = store.archivedProjects[i];
                  return ListTile(
                    leading: Icon(Icons.inventory_2_outlined, color: p.tint),
                    title: Text(p.name, style: const TextStyle(color: C.text2)),
                    trailing: TextButton(
                      onPressed: () => store.updateProject(p.id, {'is_archived': false}),
                      child: const Text('Вернуть'),
                    ),
                    onTap: () => openProject(context, p),
                  );
                },
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 130)),
        ],
      ),
    );
  }
}

void openProject(BuildContext context, Project? p) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(projectId: p?.id)));
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: C.bg2,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => openProject(context, null),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: C.borderLight),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: C.medium.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.inbox_rounded, color: C.medium),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Входящие', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text('Задачи без даты', style: TextStyle(color: C.text2, fontSize: 13)),
              ]),
            ),
            Text('$count', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.text2)),
            const Icon(Icons.chevron_right_rounded, color: C.muted),
          ]),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final open = store.openCount(project.id);
    final done = store.doneCount(project.id);
    final total = open + done;
    final c = project.tint;
    return Material(
      color: C.bg2,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openProject(context, project),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          showProjectEditor(context, project: project);
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.withValues(alpha: 0.28)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.withValues(alpha: 0.22), C.bg2],
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.folder_rounded, color: c),
            ),
            const Spacer(),
            Text(project.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 4),
            Text(open == 0 ? 'Нет активных' : '$open активных',
                style: const TextStyle(color: C.text2, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.07),
                color: c,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Список задач проекта (или «Входящих», если projectId == null).
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.projectId});

  final int? projectId;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = store.projectById(widget.projectId);
    final isInbox = widget.projectId == null;
    final open = isInbox ? store.inbox : store.projectTasks(p?.id ?? -1);
    final done = isInbox ? const <Task>[] : store.projectTasks(p?.id ?? -1, completed: true);
    final color = p?.tint ?? C.medium;

    // Группы по дню: просрочено, конкретные даты, без даты.
    final groups = <String, List<Task>>{};
    for (final t in open) {
      final key = t.dueDate == null ? 'Без даты' : (t.isOverdue ? 'Просрочено' : fmtRelDay(t.dueDate!));
      groups.putIfAbsent(key, () => []).add(t);
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(isInbox ? 'Входящие' : (p?.name ?? 'Проект'), overflow: TextOverflow.ellipsis)),
        ]),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.18), C.bg],
            ),
          ),
        ),
        actions: [
          if (p != null)
            IconButton(
              onPressed: () => showProjectEditor(context, project: p),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showTaskSheet(context, projectId: p?.id),
        backgroundColor: isInbox ? C.accent : color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        color: C.accent2,
        backgroundColor: C.bg3,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          children: [
            if (p != null && p.description.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text(p.description, style: const TextStyle(color: C.text2)),
              ),
            if (open.isEmpty)
              const EmptyState(
                icon: Icons.task_alt_rounded,
                title: 'Активных задач нет',
                subtitle: 'Добавьте задачу кнопкой «+»',
              ),
            for (final e in groups.entries) ...[
              SectionHeader(e.key, count: e.value.length, color: e.key == 'Просрочено' ? C.urgent : null),
              for (final t in e.value) TaskTile(task: t, showProject: false),
            ],
            if (done.isNotEmpty) ...[
              SectionHeader(
                'Выполнено',
                count: done.length,
                color: C.low,
                trailing: IconButton(
                  onPressed: () => setState(() => _showDone = !_showDone),
                  icon: Icon(_showDone ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: C.text2),
                ),
              ),
              if (_showDone)
                for (final t in done.reversed.take(50)) TaskTile(task: t, showProject: false, showDate: true),
            ],
            const SizedBox(height: 130),
          ],
        ),
      ),
    );
  }
}

/// Создание/правка проекта: имя и цвет; у существующего — архив и удаление.
Future<void> showProjectEditor(BuildContext context, {Project? project}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ProjectEditor(project: project),
  );
}

class _ProjectEditor extends StatefulWidget {
  const _ProjectEditor({this.project});

  final Project? project;

  @override
  State<_ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends State<_ProjectEditor> {
  late final _name = TextEditingController(text: widget.project?.name ?? '');
  late Color _color = widget.project?.tint ?? C.projectPalette.first;
  bool _busy = false;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final store = StoreScope.read(context);
    try {
      if (widget.project == null) {
        await store.createProject(name, hexOf(_color));
      } else {
        await store.updateProject(widget.project!.id, {'name': name, 'color': hexOf(_color)});
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  Future<void> _archive() async {
    final store = StoreScope.read(context);
    final nav = Navigator.of(context);
    await store.updateProject(widget.project!.id, {'is_archived': !widget.project!.isArchived});
    nav.pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить проект?'),
        content: Text('«${widget.project!.name}» и все его задачи будут удалены безвозвратно.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Удалить', style: TextStyle(color: C.urgent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final store = StoreScope.read(context);
    final nav = Navigator.of(context);
    try {
      await store.deleteProject(widget.project!.id);
      nav.popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.project != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(editing ? 'Проект' : 'Новый проект',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          autofocus: !editing,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(hintText: 'Название'),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in C.projectPalette)
            GestureDetector(
              onTap: () => setState(() => _color = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.toARGB32() == _color.toARGB32() ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          if (editing) ...[
            IconButton.filledTonal(
              tooltip: widget.project!.isArchived ? 'Из архива' : 'В архив',
              onPressed: _archive,
              icon: Icon(widget.project!.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Удалить',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: C.urgent),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _color,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _busy ? null : _save,
                child: Text(editing ? 'Сохранить' : 'Создать',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
