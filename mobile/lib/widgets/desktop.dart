import 'package:flutter/widgets.dart';

import '../models.dart';
import 'task_draft.dart';

/// Широкое окно (десктоп, планшет в альбомной): боковая панель вместо нижней навигации.
bool isWideLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

/// Что открыто в правой панели десктопа: существующая задача или черновик новой.
class PanelContent {
  PanelContent({this.task, this.draft}) : key = _seq++;

  final Task? task;
  final TaskDraft? draft;

  /// Новый ключ на каждое открытие — редактор пересоздаётся и сохраняет предыдущую задачу.
  final int key;

  static int _seq = 0;
}

class DesktopPanel {
  static final content = ValueNotifier<PanelContent?>(null);

  static void openTask(Task task) {
    if (content.value?.task?.id == task.id) return;
    content.value = PanelContent(task: task);
  }

  static void openDraft(TaskDraft draft) => content.value = PanelContent(draft: draft);

  static void close() => content.value = null;
}
