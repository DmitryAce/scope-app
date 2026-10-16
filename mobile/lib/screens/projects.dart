import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
    final roots = store.rootProjects;
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
                padding: const EdgeInsets.fromLTRB(22, 18, 8, 6),
                child: Row(children: [
                  const Text('Проекты',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                  const Spacer(),
                  IconButton(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                    icon: const Icon(PhosphorIconsRegular.magnifyingGlass, size: 24),
                  ),
                  IconButton(
                    tooltip: 'Новый проект',
                    onPressed: () => showProjectEditor(context),
                    icon: const Icon(PhosphorIconsRegular.plusCircle, size: 25),
                  ),
                ]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Group(children: [
                _ProjectRow(project: null, count: store.inbox.length),
              ]),
            ),
          ),
          if (roots.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: PhosphorIconsLight.folderSimple,
                title: 'Проектов пока нет',
                subtitle: 'Создайте первый — плюс вверху справа',
              ),
            )
          else ...[
            const SliverToBoxAdapter(child: SectionHeader('Мои проекты')),
            SliverToBoxAdapter(
              child: Group(children: [
                for (final p in roots) ...[
                  _ProjectRow(project: p, count: store.openCount(p.id)),
                  for (final c in store.childrenOf(p.id))
                    _ProjectRow(project: c, count: store.openCount(c.id), nested: true),
                ],
              ]),
            ),
          ],
          if (store.archivedProjects.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                'Архив',
                count: store.archivedProjects.length,
                color: C.text2,
                onTap: () => setState(() => _showArchived = !_showArchived),
                trailing: Caret(open: _showArchived),
              ),
            ),
            if (_showArchived)
              SliverToBoxAdapter(
                child: Group(children: [
                  for (final p in store.archivedProjects)
                    _ProjectRow(project: p, count: store.openCount(p.id), archived: true),
                ]),
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

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project, required this.count, this.nested = false, this.archived = false});

  final Project? project;
  final int count;
  final bool nested;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final store = StoreScope.of(context);
    final subs = p == null || nested ? 0 : store.childrenOf(p.id).length;
    return InkWell(
      onTap: () => openProject(context, p),
      onLongPress: p == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              showProjectEditor(context, project: p);
            },
      child: Padding(
        padding: EdgeInsets.fromLTRB(nested ? 34 : 12, nested ? 8 : 10, 12, nested ? 8 : 10),
        child: Row(children: [
          Opacity(opacity: archived ? 0.5 : 1, child: ProjectAvatar(project: p, size: nested ? 30 : 38)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p?.name ?? 'Входящие',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: nested ? 14.5 : 15.5,
                    fontWeight: FontWeight.w700,
                    color: archived ? C.text2 : C.text,
                  )),
              if (p == null || subs > 0)
                Text(p == null ? 'Задачи без даты' : '$subs ${_subs(subs)}',
                    style: const TextStyle(fontSize: 12.5, color: C.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (archived)
            TextButton(
              onPressed: () => store.updateProject(p!.id, {'is_archived': false}),
              child: const Text('Вернуть'),
            )
          else ...[
            if (count > 0)
              Text('$count', style: const TextStyle(color: C.text2, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(width: 6),
            const Icon(PhosphorIconsBold.caretRight, size: 14, color: C.muted),
          ],
        ]),
      ),
    );
  }

  static String _subs(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'подпроект';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'подпроекта';
    return 'подпроектов';
  }
}

/// Задачи проекта вместе с подпроектами (или «Входящих», если projectId == null).
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
    final parent = store.projectById(p?.parentId);
    final children = p == null ? <Project>[] : store.childrenOf(p.id);
    final ids = {if (p != null) p.id, for (final c in children) c.id};

    final open = isInbox
        ? store.inbox
        : [for (final id in ids) ...store.projectTasks(id)]
      ..sort((a, b) {
        final ad = a.dueDate, bd = b.dueDate;
        if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
        if (ad == null && bd != null) return 1;
        if (ad != null && bd == null) return -1;
        return (a.startMinute ?? 9999).compareTo(b.startMinute ?? 9999);
      });
    final done = isInbox ? const <Task>[] : [for (final id in ids) ...store.projectTasks(id, completed: true)];

    // Группы по дню: просрочено, конкретные даты, без даты.
    final groups = <String, List<Task>>{};
    for (final t in open) {
      final key = t.dueDate == null ? 'Без даты' : (t.isOverdue ? 'Просрочено' : fmtRelDay(t.dueDate!));
      groups.putIfAbsent(key, () => []).add(t);
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (p != null)
            IconButton(
              onPressed: () => showProjectEditor(context, project: p),
              icon: const Icon(PhosphorIconsRegular.pencilSimple),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showTaskSheet(context, projectId: p?.id),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Icon(PhosphorIconsBold.plus, size: 24),
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        color: C.accent2,
        backgroundColor: C.bg3,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
              child: Row(children: [
                GestureDetector(
                  onTap: p == null ? null : () => showProjectEditor(context, project: p),
                  child: ProjectAvatar(project: p, size: 56),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (parent != null)
                      GestureDetector(
                        onTap: () => Navigator.pushReplacement(
                            context, MaterialPageRoute(builder: (_) => ProjectScreen(projectId: parent.id))),
                        child: Text(parent.name,
                            style: const TextStyle(color: C.text2, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    Text(isInbox ? 'Входящие' : (p?.name ?? 'Проект'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    Text(
                      '${open.length} активных',
                      style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ]),
                ),
              ]),
            ),
            if (p != null && p.description.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                child: Text(p.description, style: const TextStyle(color: C.text2)),
              ),
            if (children.isNotEmpty) ...[
              SectionHeader('Подпроекты', count: children.length),
              Group(children: [
                for (final c in children) _ProjectRow(project: c, count: store.openCount(c.id)),
              ]),
            ],
            if (open.isEmpty)
              const EmptyState(
                icon: PhosphorIconsLight.checkCircle,
                title: 'Активных задач нет',
                subtitle: 'Добавьте задачу кнопкой «+»',
              ),
            for (final e in groups.entries) ...[
              SectionHeader(e.key, count: e.value.length, color: e.key == 'Просрочено' ? C.urgent : null),
              Group(children: [
                for (final t in e.value) TaskTile(task: t, showProject: children.isNotEmpty || isInbox),
              ]),
            ],
            if (done.isNotEmpty) ...[
              SectionHeader(
                'Сделано',
                count: done.length,
                color: C.text2,
                onTap: () => setState(() => _showDone = !_showDone),
                trailing: Caret(open: _showDone),
              ),
              if (_showDone)
                Group(children: [
                  for (final t in done.reversed.take(50))
                    TaskTile(task: t, showProject: children.isNotEmpty, showDate: true),
                ]),
            ],
            const SizedBox(height: 110),
          ],
        ),
      ),
    );
  }
}

/// Создание/правка проекта: аватарка, имя, родитель, цвет; архив и удаление.
Future<void> showProjectEditor(BuildContext context, {Project? project, int? parentId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ProjectEditor(project: project, parentId: parentId),
  );
}

class _ProjectEditor extends StatefulWidget {
  const _ProjectEditor({this.project, this.parentId});

  final Project? project;
  final int? parentId;

  @override
  State<_ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends State<_ProjectEditor> {
  late final _name = TextEditingController(text: widget.project?.name ?? '');
  late Color _color = widget.project?.tint ?? C.projectPalette.first;
  late int? _parentId = widget.project?.parentId ?? widget.parentId;
  List<int>? _newAvatar;
  String _newAvatarName = 'a.jpg';
  bool _removeAvatar = false;
  bool _busy = false;

  bool get _editing => widget.project != null;

  Future<void> _pickAvatar() async {
    final has = (widget.project?.avatar != null && !_removeAvatar) || _newAvatar != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(PhosphorIconsRegular.image),
            title: const Text('Выбрать из галереи'),
            onTap: () => Navigator.pop(c, 'gallery'),
          ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.camera),
            title: const Text('Сфотографировать'),
            onTap: () => Navigator.pop(c, 'camera'),
          ),
          if (has)
            ListTile(
              leading: const Icon(PhosphorIconsRegular.trash, color: C.urgent),
              title: const Text('Убрать аватарку', style: TextStyle(color: C.urgent)),
              onTap: () => Navigator.pop(c, 'remove'),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null) return;
    if (choice == 'remove') {
      setState(() {
        _newAvatar = null;
        _removeAvatar = true;
      });
      return;
    }
    final file = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 88,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _newAvatar = bytes;
      _newAvatarName = file.name;
      _removeAvatar = false;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final store = StoreScope.read(context);
    try {
      int id;
      if (!_editing) {
        id = (await store.createProject(name, hexOf(_color), parentId: _parentId)).id;
      } else {
        id = widget.project!.id;
        await store.updateProject(id, {'name': name, 'color': hexOf(_color), 'parent_id': _parentId});
      }
      if (_newAvatar != null) {
        await store.setAvatar(id, _newAvatar, _newAvatarName);
      } else if (_removeAvatar) {
        await store.setAvatar(id, null);
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
        content: Text('«${widget.project!.name}» и все его задачи будут удалены безвозвратно. '
            'Подпроекты останутся отдельными проектами.'),
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
    final store = StoreScope.of(context);
    final p = widget.project;
    final hasChildren = p != null && store.childrenOf(p.id).isNotEmpty;
    final parents = [for (final x in store.rootProjects) if (x.id != p?.id) x];
    final preview = Project(
      id: p?.id ?? -1,
      name: _name.text.isEmpty ? '?' : _name.text,
      color: hexOf(_color),
      avatar: _removeAvatar ? null : p?.avatar,
      parentId: _parentId,
    );

    Widget avatar;
    if (_newAvatar != null) {
      avatar = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.memory(Uint8List.fromList(_newAvatar!), width: 76, height: 76, fit: BoxFit.cover),
      );
    } else {
      avatar = ProjectAvatar(project: preview, size: 76);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(clipBehavior: Clip.none, children: [
                avatar,
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: C.elevated,
                      shape: BoxShape.circle,
                      border: Border.all(color: C.bg2, width: 3),
                    ),
                    child: const Icon(PhosphorIconsBold.camera, size: 14, color: C.text),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _name,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(hintText: 'Название проекта'),
          ),
          const SizedBox(height: 16),
          const Text('Цвет', style: TextStyle(color: C.text2, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in C.projectPalette)
              GestureDetector(
                onTap: () => setState(() => _color = c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.toARGB32() == _color.toARGB32() ? Colors.white : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 18),
          const Text('Внутри проекта', style: TextStyle(color: C.text2, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          if (hasChildren)
            const Text('У проекта есть подпроекты — сам он вложенным быть не может.',
                style: TextStyle(color: C.muted, fontSize: 13))
          else
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                _ParentChip(
                  label: 'Отдельно',
                  selected: _parentId == null,
                  onTap: () => setState(() => _parentId = null),
                ),
                for (final x in parents)
                  _ParentChip(
                    project: x,
                    label: x.name,
                    selected: _parentId == x.id,
                    onTap: () => setState(() => _parentId = x.id),
                  ),
              ]),
            ),
          const SizedBox(height: 22),
          Row(children: [
            if (_editing) ...[
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: C.bg3, foregroundColor: C.text, fixedSize: const Size(50, 50)),
                tooltip: p!.isArchived ? 'Из архива' : 'В архив',
                onPressed: _archive,
                icon: Icon(p.isArchived ? PhosphorIconsRegular.arrowUUpLeft : PhosphorIconsRegular.archive),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: C.bg3, foregroundColor: C.text, fixedSize: const Size(50, 50)),
                tooltip: 'Удалить',
                onPressed: _delete,
                icon: const Icon(PhosphorIconsRegular.trash, color: C.urgent),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: C.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : Text(_editing ? 'Сохранить' : 'Создать',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _ParentChip extends StatelessWidget {
  const _ParentChip({required this.label, required this.selected, required this.onTap, this.project});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Project? project;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? C.accent.withValues(alpha: 0.2) : C.bg3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? C.accent : Colors.transparent),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              if (project != null) ...[ProjectAvatar(project: project, size: 22), const SizedBox(width: 8)],
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
  }
}
