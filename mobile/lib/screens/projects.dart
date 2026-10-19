import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/project_picker.dart';
import '../widgets/task_sheet.dart';
import '../widgets/task_tile.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _q = TextEditingController();
  bool _showArchived = false;
  bool _reorder = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// Режим редактирования, как папки в Telegram: проекты покачиваются, их можно таскать.
  void _startEditing() {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    setState(() {
      _reorder = true;
      _q.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final roots = store.rootProjects;
    final query = _q.text.trim().toLowerCase();

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
                  if (_reorder)
                    TextButton(
                      onPressed: () => setState(() => _reorder = false),
                      child: const Text('Готово', style: TextStyle(fontWeight: FontWeight.w800)),
                    )
                  else ...[
                    IconButton(
                      tooltip: 'Редактировать',
                      onPressed: roots.isEmpty ? null : _startEditing,
                      icon: const Icon(PhosphorIconsRegular.arrowsDownUp, size: 23),
                    ),
                    IconButton(
                      tooltip: 'Новый проект',
                      onPressed: () => openProjectEditor(context),
                      icon: const Icon(PhosphorIconsRegular.plusCircle, size: 25),
                    ),
                  ],
                ]),
              ),
            ),
          ),
          if (!_reorder)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                child: TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Поиск проектов',
                    prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, size: 20, color: C.muted),
                    suffixIcon: _q.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => setState(_q.clear),
                            icon: const Icon(PhosphorIconsRegular.x, size: 18, color: C.muted),
                          ),
                    fillColor: C.bg2,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ),
          if (_reorder) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(22, 4, 22, 10),
                child: Text('Тащите за точки или удерживайте строку. Нажатие — меню проекта. '
                    'Порядок меняется внутри своего уровня, закреплённые всегда сверху.',
                    style: TextStyle(color: C.muted, fontSize: 13)),
              ),
            ),
            const SliverToBoxAdapter(child: _EditTree()),
          ] else if (query.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _searchResults(store, query),
              ),
            ),
          ] else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Group(children: [ProjectRow(project: null, count: store.inbox.length)]),
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
                  for (final (p, depth) in store.projectTree())
                    ProjectRow(project: p, count: store.openCount(p.id), depth: depth, onLongPress: _startEditing),
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
                      ProjectRow(project: p, count: store.openCount(p.id), archived: true),
                  ]),
                ),
            ],
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 130)),
        ],
      ),
    );
  }

  Widget _searchResults(AppStore store, String query) {
    final found = [for (final p in store.projects) if (p.name.toLowerCase().contains(query)) p];
    if (found.isEmpty) {
      return const EmptyState(icon: PhosphorIconsLight.magnifyingGlassMinus, title: 'Ничего не найдено');
    }
    return Group(children: [
      for (final p in found)
        ProjectRow(
          project: p,
          count: store.openCount(p.id),
          hint: p.parentId == null ? null : store.ancestorsOf(p).map((x) => x.name).join(' › '),
        ),
    ]);
  }
}

void openProject(BuildContext context, Project? p) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(projectId: p?.id)));
}

void openProjectEditor(BuildContext context, {Project? project, int? parentId}) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ProjectEditorScreen(project: project, parentId: parentId)),
  );
}

/// Действия по долгому нажатию на проект.
Future<void> showProjectActions(BuildContext context, Project p) {
  HapticFeedback.mediumImpact();
  final store = StoreScope.read(context);
  return showModalBottomSheet(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
          child: Row(children: [
            ProjectAvatar(project: p, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        Group(children: [
          if (!p.isArchived)
            _SheetAction(
              p.isPinned ? PhosphorIconsRegular.pushPinSlash : PhosphorIconsRegular.pushPin,
              p.isPinned ? 'Открепить' : 'Закрепить сверху',
              () {
                Navigator.pop(c);
                store.togglePin(p);
              },
            ),
          _SheetAction(PhosphorIconsRegular.pencilSimple, 'Изменить', () {
            Navigator.pop(c);
            openProjectEditor(context, project: p);
          }),
          if (!p.isArchived && store.depthOf(p) < AppStore.maxProjectLevels - 1)
            _SheetAction(PhosphorIconsRegular.folderSimplePlus, 'Добавить подпроект', () {
              Navigator.pop(c);
              openProjectEditor(context, parentId: p.id);
            }),
          _SheetAction(
            p.isArchived ? PhosphorIconsRegular.arrowUUpLeft : PhosphorIconsRegular.archive,
            p.isArchived ? 'Вернуть из архива' : 'В архив',
            () {
              Navigator.pop(c);
              store.updateProject(p.id, {'is_archived': !p.isArchived});
            },
          ),
        ]),
        const SizedBox(height: 16),
      ]),
    ),
  );
}

class _SheetAction extends StatelessWidget {
  const _SheetAction(this.icon, this.label, this.onTap, {this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Icon(icon, size: 21, color: color ?? C.text2),
            const SizedBox(width: 18),
            Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color ?? C.text)),
          ]),
        ),
      );
}

class ProjectRow extends StatelessWidget {
  const ProjectRow({
    super.key,
    required this.project,
    required this.count,
    this.depth = 0,
    this.archived = false,
    this.hint,
    this.onLongPress,
  });

  final Project? project;
  final int count;
  final int depth;
  final bool archived;
  final String? hint;

  /// По умолчанию долгое нажатие открывает меню проекта.
  final VoidCallback? onLongPress;

  bool get nested => depth > 0;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final store = StoreScope.of(context);
    final subs = p == null ? 0 : store.childrenOf(p.id).length;
    final subtitle = hint ?? (p == null ? 'Задачи без даты' : (subs > 0 ? '$subs ${_subs(subs)}' : null));
    return InkWell(
      onTap: () => openProject(context, p),
      onLongPress: p == null ? null : (onLongPress ?? () => showProjectActions(context, p)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.0 + depth * 22, nested ? 8 : 10, 12, nested ? 8 : 10),
        child: Row(children: [
          Opacity(opacity: archived ? 0.5 : 1, child: ProjectAvatar(project: p, size: nested ? 30 : 38)),

          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(p?.name ?? 'Входящие',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: nested ? 14.5 : 15.5,
                        fontWeight: FontWeight.w700,
                        color: archived ? C.text2 : C.text,
                      )),
                ),
                if (p?.isPinned == true) ...[
                  const SizedBox(width: 6),
                  Icon(PhosphorIconsFill.pushPin, size: 13, color: C.accent2),
                ],
              ]),
              if (subtitle != null)
                Text(subtitle, style: const TextStyle(fontSize: 12.5, color: C.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (count > 0)
            Text('$count', style: const TextStyle(color: C.text2, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(width: 6),
          const Icon(PhosphorIconsBold.caretRight, size: 14, color: C.muted),
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

/// Перетаскиваемый список проектов одного уровня (корни или подпроекты одного родителя).
class _ReorderList extends StatelessWidget {
  const _ReorderList({required this.projects});

  final List<Project> projects;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: C.bg2, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: projects.length,
        proxyDecorator: (child, _, __) => Material(
          color: C.elevated,
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          child: child,
        ),
        onReorder: (from, to) {
          HapticFeedback.selectionClick();
          final list = [...projects];
          if (to > from) to--;
          final moved = list.removeAt(from);
          // Закреплённые не уезжают вниз под незакреплённые.
          list.insert(to, moved);
          store.reorderProjects([for (final p in list) p.id]);
        },
        itemBuilder: (context, i) {
          final p = projects[i];
          return Container(
            key: ValueKey(p.id),
            decoration: BoxDecoration(
              border: i == 0 ? null : const Border(top: BorderSide(color: C.border, width: 0.6)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              ProjectAvatar(project: p, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: p.isPinned ? 'Открепить' : 'Закрепить',
                onPressed: () => store.togglePin(p),
                icon: Icon(p.isPinned ? PhosphorIconsFill.pushPin : PhosphorIconsRegular.pushPin,
                    size: 19, color: p.isPinned ? C.accent2 : C.muted),
              ),
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(PhosphorIconsBold.dotsSixVertical, size: 20, color: C.text2),
                ),
              ),
            ]),
          );
        },
      ),
    );
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
  bool _reorderSubs = false;

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
          if (p != null) ...[
            IconButton(
              tooltip: p.isPinned ? 'Открепить' : 'Закрепить',
              onPressed: () => store.togglePin(p),
              icon: Icon(p.isPinned ? PhosphorIconsFill.pushPin : PhosphorIconsRegular.pushPin,
                  color: p.isPinned ? C.accent2 : null),
            ),
            IconButton(
              onPressed: () => openProjectEditor(context, project: p),
              icon: const Icon(PhosphorIconsRegular.pencilSimple),
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showTaskSheet(context, projectId: p?.id),
        shape: const CircleBorder(),
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
                  onTap: p == null ? null : () => openProjectEditor(context, project: p),
                  child: ProjectAvatar(project: p, size: 56),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (parent != null)
                      // Полный путь: каждый уровень кликабелен.
                      Wrap(children: [
                        for (final (i, a) in store.ancestorsOf(p!).indexed) ...[
                          if (i > 0)
                            const Text(' › ',
                                style: TextStyle(color: C.muted, fontWeight: FontWeight.w700, fontSize: 13)),
                          GestureDetector(
                            onTap: () => Navigator.pushReplacement(
                                context, MaterialPageRoute(builder: (_) => ProjectScreen(projectId: a.id))),
                            child: Text(a.name,
                                style: const TextStyle(color: C.text2, fontWeight: FontWeight.w700, fontSize: 13)),
                          ),
                        ],
                      ]),
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
            if (p != null && (children.isNotEmpty || store.depthOf(p) < AppStore.maxProjectLevels - 1)) ...[
              SectionHeader(
                'Подпроекты',
                count: children.isEmpty ? null : children.length,
                trailing: children.length < 2
                    ? null
                    : TextButton(
                        onPressed: () => setState(() => _reorderSubs = !_reorderSubs),
                        child: Text(_reorderSubs ? 'Готово' : 'Порядок',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
              ),
              if (_reorderSubs)
                _ReorderList(projects: children)
              else
                Group(children: [
                  for (final c in children) ProjectRow(project: c, count: store.openCount(c.id)),
                  if (store.depthOf(p) < AppStore.maxProjectLevels - 1)
                    InkWell(
                    onTap: () => openProjectEditor(context, parentId: p.id),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Row(children: [
                        Icon(PhosphorIconsRegular.plus, size: 20, color: C.accent2),
                        SizedBox(width: 20),
                        Text('Добавить подпроект',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.accent2)),
                      ]),
                    ),
                  ),
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

/// Проект на весь экран: аватарка, название, описание, цвет, родитель, закрепление.
class ProjectEditorScreen extends StatefulWidget {
  const ProjectEditorScreen({super.key, this.project, this.parentId});

  final Project? project;
  final int? parentId;

  @override
  State<ProjectEditorScreen> createState() => _ProjectEditorScreenState();
}

class _ProjectEditorScreenState extends State<ProjectEditorScreen> {
  late final _name = TextEditingController(text: widget.project?.name ?? '');
  late final _desc = TextEditingController(text: widget.project?.description ?? '');
  late Color _color = widget.project?.tint ??
      (widget.parentId != null ? C.projectPalette[2] : C.projectPalette.first);
  late int? _parentId = widget.project?.parentId ?? widget.parentId;
  late bool _pinned = widget.project?.isPinned ?? false;
  List<int>? _newAvatar;
  String _newAvatarName = 'a.jpg';
  bool _removeAvatar = false;
  bool _busy = false;

  bool get _editing => widget.project != null;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final has = (widget.project?.avatar != null && !_removeAvatar) || _newAvatar != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(PhosphorIconsRegular.image),
            title: Text(Platform.isAndroid || Platform.isIOS ? 'Выбрать из галереи' : 'Выбрать файл'),
            onTap: () => Navigator.pop(c, 'gallery'),
          ),
          if (Platform.isAndroid || Platform.isIOS)
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
    // Аватарка в списке — максимум 56px; 256px с запасом под плотные экраны и весит ~15 КБ.
    final file = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 80,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _newAvatar = bytes;
      _newAvatarName = file.name;
      _removeAvatar = false;
    });
  }

  Future<void> _pickParent() async {
    final v = await showProjectPicker(
      context,
      title: 'Внутри проекта',
      selectedId: _parentId,
      allow: (x) => StoreScope.read(context).canNestUnder(x, widget.project),
      noneLabel: 'Отдельный проект',
    );
    if (v != null) setState(() => _parentId = v == 0 ? null : v);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _busy = true);
    final store = StoreScope.read(context);
    try {
      int id;
      final body = {
        'name': name,
        'description': _desc.text.trim(),
        'color': hexOf(_color),
        'parent_id': _parentId,
      };
      if (!_editing) {
        id = (await store.createProject(name, hexOf(_color), parentId: _parentId)).id;
        if (_desc.text.trim().isNotEmpty || _pinned) {
          await store.updateProject(id, {'description': _desc.text.trim(), 'is_pinned': _pinned});
        }
      } else {
        id = widget.project!.id;
        await store.updateProject(id, {...body, 'is_pinned': _pinned});
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

    final parent = store.projectById(_parentId);
    final preview = Project(
      id: p?.id ?? -1,
      name: _name.text.isEmpty ? '?' : _name.text,
      color: hexOf(_color),
      avatar: _removeAvatar ? null : p?.avatar,
      parentId: _parentId,
    );

    final avatar = _newAvatar != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Image.memory(Uint8List.fromList(_newAvatar!), width: 88, height: 88, fit: BoxFit.cover),
          )
        : ProjectAvatar(project: preview, size: 88);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(PhosphorIconsRegular.x),
        ),
        title: Text(_editing ? 'Проект' : (widget.parentId != null ? 'Новый подпроект' : 'Новый проект'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: C.accent, visualDensity: VisualDensity.compact),
              onPressed: _busy ? null : _save,
              child: Text(_editing ? 'Сохранить' : 'Создать', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: _pickAvatar,
            child: Stack(clipBehavior: Clip.none, children: [
              avatar,
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: C.elevated,
                    shape: BoxShape.circle,
                    border: Border.all(color: C.bg, width: 3),
                  ),
                  child: const Icon(PhosphorIconsBold.camera, size: 15, color: C.text),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: TextField(
            controller: _name,
            autofocus: !_editing,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(
              hintText: 'Название',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: TextField(
            controller: _desc,
            minLines: 1,
            maxLines: 4,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: C.text2),
            decoration: const InputDecoration(
              hintText: 'Описание (необязательно)',
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [
              for (final c in C.projectPalette)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
            ],
          ),
        ),
        const SizedBox(height: 18),
        Group(children: [
          InkWell(
            onTap: _pickParent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(children: [
                const Icon(PhosphorIconsRegular.treeStructure, size: 21, color: C.text2),
                const SizedBox(width: 18),
                const Text('Внутри проекта', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (parent != null) ...[ProjectAvatar(project: parent, size: 22), const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    parent?.name ?? 'Отдельно',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: parent == null ? C.muted : C.text2,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(PhosphorIconsBold.caretRight, size: 13, color: C.muted),
              ]),
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.only(left: 16, right: 10),
            secondary: const Icon(PhosphorIconsRegular.pushPin, size: 21, color: C.text2),
            title: const Text('Закрепить сверху', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            value: _pinned,
            activeTrackColor: C.accent,
            onChanged: (v) => setState(() => _pinned = v),
          ),
        ]),
        if (_editing) ...[
          const SizedBox(height: 14),
          Group(children: [
            _SheetAction(
              p!.isArchived ? PhosphorIconsRegular.arrowUUpLeft : PhosphorIconsRegular.archive,
              p.isArchived ? 'Вернуть из архива' : 'В архив',
              () async {
                final nav = Navigator.of(context);
                await store.updateProject(p.id, {'is_archived': !p.isArchived});
                nav.pop();
              },
            ),
            _SheetAction(PhosphorIconsRegular.trash, 'Удалить проект', _delete, color: C.urgent),
          ]),
        ],
      ]),
    );
  }
}

/// Режим редактирования списка проектов: всё дерево покачивается, строки можно
/// таскать за точки или удержанием, нажатие открывает меню проекта.
/// Порядок меняется внутри своего уровня — среди «братьев» по родителю.
class _EditTree extends StatefulWidget {
  const _EditTree();

  @override
  State<_EditTree> createState() => _EditTreeState();
}

class _EditTreeState extends State<_EditTree> with SingleTickerProviderStateMixin {
  late final _wiggle = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }

  void _onReorder(List<(Project, int)> tree, int from, int to) {
    if (to > from) to--;
    if (from == to) return;
    final list = [...tree];
    final moved = list.removeAt(from);
    list.insert(to, moved);
    // Новый порядок «братьев» перемещённого проекта — как они встали в списке.
    final siblings = [for (final (p, _) in list) if (p.parentId == moved.$1.parentId) p.id];
    HapticFeedback.selectionClick();
    StoreScope.read(context).reorderProjects(siblings);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final tree = store.projectTree();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: C.bg2, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: tree.length,
        onReorderStart: (_) => HapticFeedback.mediumImpact(),
        proxyDecorator: (child, _, __) => Material(
          color: C.elevated,
          elevation: 10,
          borderRadius: BorderRadius.circular(14),
          child: child,
        ),
        onReorder: (from, to) => _onReorder(tree, from, to),
        itemBuilder: (context, i) {
          final (p, depth) = tree[i];
          final row = InkWell(
            onTap: () => showProjectActions(context, p),
            child: Container(
              decoration: BoxDecoration(
                border: i == 0 ? null : const Border(top: BorderSide(color: C.border, width: 0.6)),
              ),
              padding: EdgeInsets.fromLTRB(12.0 + depth * 22, 8, 4, 8),
              child: Row(children: [
                ProjectAvatar(project: p, size: depth == 0 ? 34 : 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: depth == 0 ? 15 : 14, fontWeight: FontWeight.w700)),
                ),
                if (p.isPinned) Icon(PhosphorIconsFill.pushPin, size: 15, color: C.accent2),
                ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(PhosphorIconsBold.dotsSixVertical, size: 20, color: C.text2),
                  ),
                ),
              ]),
            ),
          );
          return ReorderableDelayedDragStartListener(
            key: ValueKey(p.id),
            index: i,
            child: AnimatedBuilder(
              animation: _wiggle,
              // Соседние строки качаются в противофазе — как иконки в режиме правки.
              builder: (_, child) => Transform.rotate(
                angle: (i.isEven ? 1 : -1) * (_wiggle.value - 0.5) * 0.014,
                child: child,
              ),
              child: row,
            ),
          );
        },
      ),
    );
  }
}
