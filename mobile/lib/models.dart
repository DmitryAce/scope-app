import 'dart:ui';

/// Цвет из `#RRGGBB` сервера; кривое значение — фирменный фиолетовый.
Color parseHex(String? hex, [Color fallback = const Color(0xFF7C3AED)]) {
  if (hex == null) return fallback;
  final v = hex.replaceFirst('#', '');
  if (v.length != 6) return fallback;
  final n = int.tryParse(v, radix: 16);
  return n == null ? fallback : Color(0xFF000000 | n);
}

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? parseYmd(String? s) {
  if (s == null || s.isEmpty) return null;
  final p = s.split('-');
  if (p.length != 3) return null;
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

class Project {
  final int id;
  final String name;
  final String description;
  final String color;
  final String icon;
  final bool isArchived;
  final int? parentId;
  final String? avatar; // путь /media/… на сервере
  final bool isPinned;
  final int position;

  const Project({
    required this.id,
    required this.name,
    this.description = '',
    this.color = '#7C3AED',
    this.icon = 'folder',
    this.isArchived = false,
    this.parentId,
    this.avatar,
    this.isPinned = false,
    this.position = 0,
  });

  Color get tint => parseHex(color);

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        color: (j['color'] ?? '#7C3AED') as String,
        icon: (j['icon'] ?? 'folder') as String,
        isArchived: (j['is_archived'] ?? false) as bool,
        parentId: j['parent_id'] as int?,
        avatar: j['avatar'] as String?,
        isPinned: (j['is_pinned'] ?? false) as bool,
        position: (j['position'] ?? 0) as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'color': color,
        'icon': icon,
        'is_archived': isArchived,
        'parent_id': parentId,
        'avatar': avatar,
        'is_pinned': isPinned,
        'position': position,
      };
}

class Tag {
  final int id;
  final String name;
  final String color;

  const Tag({required this.id, required this.name, this.color = '#7C3AED'});

  Color get tint => parseHex(color);

  factory Tag.fromJson(Map<String, dynamic> j) => Tag(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        color: (j['color'] ?? '#7C3AED') as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};
}

class ChecklistItem {
  final int id;
  final String text;
  final bool isCompleted;

  const ChecklistItem({required this.id, required this.text, this.isCompleted = false});

  factory ChecklistItem.fromJson(Map<String, dynamic> j) =>
      ChecklistItem(id: j['id'] as int, text: (j['text'] ?? '') as String, isCompleted: (j['is_completed'] ?? false) as bool);

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'is_completed': isCompleted};
}

class Task {
  final int id;
  final String title;
  final String description;
  final int priority;
  final bool isCompleted;
  final bool autoComplete;
  final bool autoDelete;
  final DateTime? dueDate;
  final String? dueTime; // HH:MM
  final int? durationMinutes;
  final String repeat;
  final DateTime? repeatUntil;
  final String? reminder; // YYYY-MM-DD HH:MM
  final int? projectId;
  final int order;
  final List<int> tagIds;
  final List<ChecklistItem> checklist;

  /// Задача из ERP: 'webstead' / 'omniwebers' или пусто. Закрытие в Scope — только локальное.
  final String externalSource;
  final String externalCode;
  final String externalUrl;
  final String externalStatus;

  bool get isExternal => externalSource.isNotEmpty;

  const Task({
    required this.id,
    required this.title,
    this.description = '',
    this.priority = 2,
    this.isCompleted = false,
    this.autoComplete = false,
    this.autoDelete = false,
    this.dueDate,
    this.dueTime,
    this.durationMinutes,
    this.repeat = '',
    this.repeatUntil,
    this.reminder,
    this.projectId,
    this.order = 0,
    this.tagIds = const [],
    this.checklist = const [],
    this.externalSource = '',
    this.externalCode = '',
    this.externalUrl = '',
    this.externalStatus = '',
  });

  bool get isOverdue {
    if (isCompleted || dueDate == null) return false;
    return dueDate!.isBefore(dayOnly(DateTime.now()));
  }

  /// Минуты от полуночи для времени задачи.
  int? get startMinute {
    final t = dueTime;
    if (t == null || t.length < 4) return null;
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  DateTime? get startsAt {
    final m = startMinute;
    if (dueDate == null || m == null) return null;
    return dueDate!.add(Duration(minutes: m));
  }

  DateTime? get reminderAt {
    final r = reminder;
    if (r == null || r.length < 16) return null;
    return DateTime.tryParse(r.replaceFirst(' ', 'T'));
  }

  Task copyWith({
    String? title,
    String? description,
    int? priority,
    bool? isCompleted,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? dueTime,
    bool clearDueTime = false,
    int? projectId,
    bool clearProject = false,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        priority: priority ?? this.priority,
        isCompleted: isCompleted ?? this.isCompleted,
        autoComplete: autoComplete,
        autoDelete: autoDelete,
        dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
        dueTime: clearDueTime ? null : (dueTime ?? this.dueTime),
        durationMinutes: durationMinutes,
        repeat: repeat,
        repeatUntil: repeatUntil,
        reminder: reminder,
        projectId: clearProject ? null : (projectId ?? this.projectId),
        order: order,
        tagIds: tagIds,
        checklist: checklist,
        externalSource: externalSource,
        externalCode: externalCode,
        externalUrl: externalUrl,
        externalStatus: externalStatus,
      );

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as int,
        title: (j['title'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        priority: (j['priority'] ?? 2) as int,
        isCompleted: (j['is_completed'] ?? false) as bool,
        autoComplete: (j['auto_complete'] ?? false) as bool,
        autoDelete: (j['auto_delete'] ?? false) as bool,
        dueDate: parseYmd(j['due_date'] as String?),
        dueTime: j['due_time'] as String?,
        durationMinutes: j['duration_minutes'] as int?,
        repeat: (j['repeat'] ?? '') as String,
        repeatUntil: parseYmd(j['repeat_until'] as String?),
        reminder: j['reminder'] as String?,
        projectId: j['project_id'] as int?,
        order: (j['order'] ?? 0) as int,
        tagIds: ((j['tag_ids'] ?? const []) as List).cast<int>(),
        checklist: ((j['checklist'] ?? const []) as List)
            .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        externalSource: (j['external_source'] ?? '') as String,
        externalCode: (j['external_code'] ?? '') as String,
        externalUrl: (j['external_url'] ?? '') as String,
        externalStatus: (j['external_status'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'priority': priority,
        'is_completed': isCompleted,
        'auto_complete': autoComplete,
        'auto_delete': autoDelete,
        'due_date': dueDate == null ? null : ymd(dueDate!),
        'due_time': dueTime,
        'duration_minutes': durationMinutes,
        'repeat': repeat,
        'repeat_until': repeatUntil == null ? null : ymd(repeatUntil!),
        'reminder': reminder,
        'project_id': projectId,
        'order': order,
        'tag_ids': tagIds,
        'checklist': checklist.map((c) => c.toJson()).toList(),
        'external_source': externalSource,
        'external_code': externalCode,
        'external_url': externalUrl,
        'external_status': externalStatus,
      };
}

const priorityLabels = {1: 'Низкий', 2: 'Средний', 3: 'Высокий', 4: 'Срочный'};

const repeatLabels = {
  '': 'Не повторять',
  'daily': 'Каждый день',
  'weekdays': 'По будням',
  'weekly': 'Каждую неделю',
  'biweekly': 'Раз в две недели',
  'monthly': 'Каждый месяц',
};


/// Подписи и цвета источников ERP.
const erpSources = {
  'webstead': ('Webstead', 0xFFB3365B),
  'omniwebers': ('OmniWebers', 0xFF06B6D4),
};
