import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'notifications.dart';

/// Всё состояние приложения: сессия, выбор сервера, кэш задач и проектов.
///
/// Изменения применяются сразу на экране и потом уходят на сервер; при ошибке
/// откатываются. Последний снимок данных лежит в SharedPreferences — приложение
/// открывается мгновенно и без сети.
class AppStore extends ChangeNotifier {
  late SharedPreferences _prefs;
  late ScopeApi api;

  String? username;
  bool ready = false;
  bool syncing = false;
  String? error;
  DateTime? lastSync;
  int leadMinutes = 15;

  List<Project> projects = [];
  List<Project> archivedProjects = [];
  List<Tag> tags = [];
  final Map<int, Task> _tasks = {};

  bool get loggedIn => api.token != null;
  BackendMode get mode => api.mode;
  bool get onLocal => api.onLocal;
  String? get activeBase => api.activeBase;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    api = ScopeApi(
      localUrl: _prefs.getString('local_url') ?? defaultLocalUrl,
      remoteUrl: _prefs.getString('remote_url') ?? defaultRemoteUrl,
      mode: BackendMode.values[_prefs.getInt('mode') ?? 0],
      token: _prefs.getString('token'),
    );
    username = _prefs.getString('username');
    leadMinutes = _prefs.getInt('lead_minutes') ?? 15;
    _loadCache();
    ready = true;
    notifyListeners();
    if (loggedIn) refresh();
  }

  // ---------- сессия и настройки ----------

  Future<void> login(String user, String password) async {
    api.token = null;
    await api.resolve(force: true);
    final token = await api.login(user.trim(), password);
    api.token = token;
    username = user.trim();
    await _prefs.setString('token', token);
    await _prefs.setString('username', username!);
    notifyListeners();
    await refresh();
    await Reminders.instance.requestPermissions();
  }

  Future<void> logout() async {
    try {
      await api.post('auth/logout/');
    } catch (_) {}
    api.token = null;
    username = null;
    projects = [];
    archivedProjects = [];
    tags = [];
    _tasks.clear();
    await _prefs.remove('token');
    await _prefs.remove('username');
    await _prefs.remove('cache');
    await Reminders.instance.cancelAll();
    notifyListeners();
  }

  Future<void> setMode(BackendMode m) async {
    api.mode = m;
    await _prefs.setInt('mode', m.index);
    await api.resolve(force: true);
    notifyListeners();
    refresh();
  }

  Future<void> setUrls(String local, String remote) async {
    api.localUrl = local.trim();
    api.remoteUrl = remote.trim();
    await _prefs.setString('local_url', api.localUrl);
    await _prefs.setString('remote_url', api.remoteUrl);
    await api.resolve(force: true);
    notifyListeners();
  }

  String get localUrl => api.localUrl;
  String get remoteUrl => api.remoteUrl;

  Future<void> setLeadMinutes(int m) async {
    leadMinutes = m;
    await _prefs.setInt('lead_minutes', m);
    notifyListeners();
    _reschedule();
  }

  // ---------- синхронизация ----------

  /// Перевыбрать сервер (вернулись домой / ушли) и подтянуть свежие данные.
  Future<void> refresh({bool reprobe = true}) async {
    if (!loggedIn || syncing) return;
    syncing = true;
    error = null;
    notifyListeners();
    try {
      if (reprobe) await api.resolve(force: true);
      await _housekeepingOnceADay();
      final today = dayOnly(DateTime.now());
      final results = await Future.wait([
        api.get('projects/'),
        api.get('projects/', {'archived': 'true'}),
        api.get('tags/'),
        api.getAll('tasks/', {'completed': 'false'}),
        api.getAll('tasks/', {
          'completed': 'true',
          'due_after': ymd(today.subtract(const Duration(days: 21))),
          'due_before': ymd(today.add(const Duration(days: 90))),
        }),
      ]);
      projects = (results[0] as List).map((j) => Project.fromJson(j)).toList();
      archivedProjects = (results[1] as List).map((j) => Project.fromJson(j)).toList();
      tags = (results[2] as List).map((j) => Tag.fromJson(j)).toList();
      _tasks
        ..clear()
        ..addEntries([...results[3] as List, ...results[4] as List]
            .map((j) => Task.fromJson(j as Map<String, dynamic>))
            .map((t) => MapEntry(t.id, t)));
      lastSync = DateTime.now();
      _saveCache();
      _reschedule();
    } on ApiException catch (e) {
      if (e.isAuth) {
        await logout();
        error = 'Сессия истекла — войдите снова';
      } else {
        error = e.message;
      }
    } catch (e) {
      error = 'Не удалось обновить: $e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _housekeepingOnceADay() async {
    final today = ymd(DateTime.now());
    if (_prefs.getString('housekeeping') == today) return;
    try {
      await api.post('housekeeping/');
      await _prefs.setString('housekeeping', today);
    } catch (_) {
      // Старый сервер без эндпоинта — не повод ломать синхронизацию.
    }
  }

  /// Догрузить выполненные задачи за прошлый период (листание календаря назад).
  final Set<String> _loadedRanges = {};

  Future<void> ensureRange(DateTime from, DateTime to) async {
    final key = '${ymd(from)}_${ymd(to)}';
    if (!loggedIn || _loadedRanges.contains(key)) return;
    _loadedRanges.add(key);
    try {
      final rows = await api.getAll('tasks/', {'due_after': ymd(from), 'due_before': ymd(to)});
      for (final j in rows) {
        final t = Task.fromJson(j);
        _tasks[t.id] = t;
      }
      notifyListeners();
    } catch (_) {
      _loadedRanges.remove(key);
    }
  }

  void _saveCache() {
    _prefs.setString(
      'cache',
      jsonEncode({
        'projects': projects.map((p) => p.toJson()).toList(),
        'archived': archivedProjects.map((p) => p.toJson()).toList(),
        'tags': tags.map((t) => t.toJson()).toList(),
        'tasks': _tasks.values.map((t) => t.toJson()).toList(),
        'at': lastSync?.toIso8601String(),
      }),
    );
  }

  void _loadCache() {
    final raw = _prefs.getString('cache');
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      projects = (j['projects'] as List).map((e) => Project.fromJson(e)).toList();
      archivedProjects = ((j['archived'] ?? []) as List).map((e) => Project.fromJson(e)).toList();
      tags = (j['tags'] as List).map((e) => Tag.fromJson(e)).toList();
      for (final e in j['tasks'] as List) {
        final t = Task.fromJson(e);
        _tasks[t.id] = t;
      }
      lastSync = j['at'] == null ? null : DateTime.tryParse(j['at']);
    } catch (_) {}
  }

  void _reschedule() {
    Reminders.instance.schedule(_tasks.values, leadMinutes, projectById);
  }

  void _changed() {
    _saveCache();
    _reschedule();
    notifyListeners();
  }

  // ---------- выборки ----------

  Project? projectById(int? id) {
    if (id == null) return null;
    for (final p in projects) {
      if (p.id == id) return p;
    }
    for (final p in archivedProjects) {
      if (p.id == id) return p;
    }
    return null;
  }

  Tag? tagById(int id) {
    for (final t in tags) {
      if (t.id == id) return t;
    }
    return null;
  }

  Task? taskById(int id) => _tasks[id];

  static int _byTime(Task a, Task b) {
    final am = a.startMinute, bm = b.startMinute;
    if (am != null && bm != null && am != bm) return am.compareTo(bm);
    if (am != null && bm == null) return -1;
    if (am == null && bm != null) return 1;
    if (a.priority != b.priority) return b.priority.compareTo(a.priority);
    return a.order.compareTo(b.order);
  }

  List<Task> tasksOn(DateTime day) {
    final d = dayOnly(day);
    final list = _tasks.values.where((t) => t.dueDate == d).toList()..sort(_byTime);
    return list;
  }

  List<Task> get overdue {
    final list = _tasks.values.where((t) => t.isOverdue).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    return list;
  }

  List<Task> get inbox {
    final list = _tasks.values.where((t) => t.dueDate == null && !t.isCompleted).toList()
      ..sort(_byTime);
    return list;
  }

  List<Task> projectTasks(int projectId, {bool completed = false}) {
    final list = _tasks.values
        .where((t) => t.projectId == projectId && t.isCompleted == completed)
        .toList()
      ..sort((a, b) {
        final ad = a.dueDate, bd = b.dueDate;
        if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
        if (ad == null && bd != null) return 1;
        if (ad != null && bd == null) return -1;
        return _byTime(a, b);
      });
    return list;
  }

  /// Проекты верхнего уровня; подпроекты живут внутри родителя.
  List<Project> get rootProjects => [for (final p in projects) if (p.parentId == null || projectById(p.parentId) == null) p];

  List<Project> childrenOf(int id) => [for (final p in projects) if (p.parentId == id) p];

  Set<int> _family(int id) => {id, for (final c in childrenOf(id)) c.id};

  /// Аватарка проекта, а если своей нет — родителя.
  String? avatarUrl(Project p) =>
      api.mediaUrl(p.avatar) ?? api.mediaUrl(projectById(p.parentId)?.avatar);

  int openCount(int projectId, {bool withChildren = true}) {
    final ids = withChildren ? _family(projectId) : {projectId};
    return _tasks.values.where((t) => ids.contains(t.projectId) && !t.isCompleted).length;
  }

  int doneCount(int projectId, {bool withChildren = true}) {
    final ids = withChildren ? _family(projectId) : {projectId};
    return _tasks.values.where((t) => ids.contains(t.projectId) && t.isCompleted).length;
  }

  /// Сколько задач на день и сколько из них сделано — для точек в календаре.
  (int, int) dayLoad(DateTime day) {
    final d = dayOnly(day);
    var total = 0, done = 0;
    for (final t in _tasks.values) {
      if (t.dueDate == d) {
        total++;
        if (t.isCompleted) done++;
      }
    }
    return (total, done);
  }

  List<Task> search(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return [];
    final list = _tasks.values
        .where((t) => t.title.toLowerCase().contains(s) || t.description.toLowerCase().contains(s))
        .toList()
      ..sort((a, b) {
        if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
        return (a.dueDate ?? DateTime(2100)).compareTo(b.dueDate ?? DateTime(2100));
      });
    return list.take(60).toList();
  }

  // ---------- изменения ----------

  Future<void> toggle(Task t) async {
    _tasks[t.id] = t.copyWith(isCompleted: !t.isCompleted);
    _changed();
    try {
      await api.post('tasks/${t.id}/toggle/');
    } on ApiException catch (e) {
      _tasks[t.id] = t;
      _fail(e);
    }
  }

  Future<void> moveTo(Task t, DateTime? day) async {
    _tasks[t.id] = day == null ? t.copyWith(clearDueDate: true) : t.copyWith(dueDate: dayOnly(day));
    _changed();
    try {
      final j = await api.patch('tasks/${t.id}/', {'due_date': day == null ? '' : ymd(day)});
      _tasks[t.id] = Task.fromJson(j);
      _changed();
    } on ApiException catch (e) {
      _tasks[t.id] = t;
      _fail(e);
    }
  }

  Future<Task> createTask(Map<String, dynamic> body) async {
    final j = await api.post('tasks/', body);
    final t = Task.fromJson(j);
    _tasks[t.id] = t;
    _changed();
    // Повторы сервер раскладывает сам — забираем их следом.
    if ((body['repeat'] ?? '') != '') refresh(reprobe: false);
    return t;
  }

  Future<Task> updateTask(int id, Map<String, dynamic> body) async {
    final j = await api.patch('tasks/$id/', body);
    final t = Task.fromJson(j);
    _tasks[id] = t;
    _changed();
    if (body.containsKey('repeat')) refresh(reprobe: false);
    return t;
  }

  // ---------- чек-лист ----------

  Future<void> _checklistCall(Future<dynamic> Function() call) async {
    try {
      final t = Task.fromJson(await call());
      _tasks[t.id] = t;
      _changed();
    } on ApiException catch (e) {
      _fail(e);
    }
  }

  Future<void> addChecklistItem(int taskId, String text) =>
      _checklistCall(() => api.post('tasks/$taskId/checklist/', {'text': text}));

  Future<void> toggleChecklistItem(Task t, ChecklistItem item) {
    // Сразу на экране, сервер догонит.
    _tasks[t.id] = Task.fromJson({
      ...t.toJson(),
      'checklist': [
        for (final c in t.checklist)
          c.id == item.id ? {...c.toJson(), 'is_completed': !c.isCompleted} : c.toJson(),
      ],
    });
    notifyListeners();
    return _checklistCall(() => api.patch('checklist/${item.id}/', {'is_completed': !item.isCompleted}));
  }

  Future<void> deleteChecklistItem(Task t, ChecklistItem item) {
    _tasks[t.id] = Task.fromJson({
      ...t.toJson(),
      'checklist': [for (final c in t.checklist) if (c.id != item.id) c.toJson()],
    });
    notifyListeners();
    return _checklistCall(() => api.delete('checklist/${item.id}/'));
  }

  Future<void> deleteTask(Task t) async {
    _tasks.remove(t.id);
    _changed();
    try {
      await api.delete('tasks/${t.id}/');
    } on ApiException catch (e) {
      _tasks[t.id] = t;
      _fail(e);
    }
  }

  /// Вернуть удалённую задачу (кнопка «Отменить» в снекбаре).
  Future<void> restoreTask(Task t) async {
    final body = <String, dynamic>{
      'title': t.title,
      'description': t.description,
      'priority': t.priority,
      'project_id': t.projectId,
      'due_date': t.dueDate == null ? null : ymd(t.dueDate!),
      'due_time': t.dueTime,
      'duration_minutes': t.durationMinutes,
      'auto_complete': t.autoComplete,
      'reminder': t.reminder,
      'tag_ids': t.tagIds,
    };
    final created = await createTask(body);
    for (final c in t.checklist) {
      await addChecklistItem(created.id, c.text);
    }
    if (t.isCompleted) await toggle(created);
  }

  Future<Project> createProject(String name, String color, {int? parentId}) async {
    final j = await api.post('projects/', {'name': name, 'color': color, 'parent_id': parentId});
    final p = Project.fromJson(j);
    projects = [p, ...projects];
    _changed();
    return p;
  }

  Future<void> updateProject(int id, Map<String, dynamic> body) async {
    final j = await api.patch('projects/$id/', body);
    final p = Project.fromJson(j);
    projects = [for (final x in projects) if (x.id != id) x];
    archivedProjects = [for (final x in archivedProjects) if (x.id != id) x];
    if (p.isArchived) {
      archivedProjects = [p, ...archivedProjects];
    } else {
      projects = [p, ...projects];
    }
    _changed();
  }

  Future<void> setAvatar(int id, List<int>? bytes, [String filename = 'a.jpg']) async {
    final j = bytes == null ? await api.delete('projects/$id/avatar/') : await api.uploadAvatar(id, bytes, filename);
    final p = Project.fromJson(j);
    projects = [for (final x in projects) x.id == id ? p : x];
    archivedProjects = [for (final x in archivedProjects) x.id == id ? p : x];
    _changed();
  }

  Future<void> deleteProject(int id) async {
    await api.delete('projects/$id/');
    projects = [for (final x in projects) if (x.id != id) x];
    archivedProjects = [for (final x in archivedProjects) if (x.id != id) x];
    _tasks.removeWhere((_, t) => t.projectId == id);
    _changed();
  }

  Future<Tag> createTag(String name, String color) async {
    final j = await api.post('tags/', {'name': name, 'color': color});
    final t = Tag.fromJson(j);
    tags = [...tags, t]..sort((a, b) => a.name.compareTo(b.name));
    _changed();
    return t;
  }

  void _fail(ApiException e) {
    error = e.message;
    _changed();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
