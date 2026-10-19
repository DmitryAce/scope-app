import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../notifications.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../updater.dart';
import '../widgets/update_dialog.dart';
import 'tags.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, bottom: 130),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text('Ещё', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        ),
        _Card(children: [
          ListTile(
            leading: const ScopeLogo(size: 40),
            title: Text(store.username ?? '—', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              store.lastSync == null
                  ? 'Ещё не синхронизировано'
                  : 'Синхронизировано ${DateFormat('d MMM, HH:mm', 'ru').format(store.lastSync!)}',
              style: const TextStyle(color: C.text2),
            ),
            trailing: IconButton(
              onPressed: store.syncing ? null : store.refresh,
              icon: store.syncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(PhosphorIconsRegular.arrowsClockwise),
            ),
          ),
        ]),
        const SectionHeader('Оформление'),
        _Card(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
            child: Row(children: [
              for (final a in accents)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      store.setAccent(a.id);
                    },
                    child: Column(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: a.main,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: C.accentId == a.id ? C.text : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: C.accentId == a.id ? Icon(PhosphorIconsBold.check, size: 16, color: a.on) : null,
                      ),
                      const SizedBox(height: 6),
                      Text(a.name,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: C.accentId == a.id ? C.text : C.muted,
                          )),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
        const SectionHeader('Приложение'),
        _Card(children: [
          FutureBuilder<String>(
            future: Updater.currentLabel(),
            builder: (context, snap) => ListTile(
              leading: Icon(PhosphorIconsRegular.downloadSimple, color: C.accent2),
              title: const Text('Проверить обновления', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Версия ${snap.data ?? '…'}', style: const TextStyle(color: C.text2)),
              trailing: const Icon(PhosphorIconsBold.caretRight, size: 14, color: C.muted),
              onTap: () => showUpdateDialog(context),
            ),
          ),
        ]),
        const SectionHeader('Организация'),
        _Card(children: [
          ListTile(
            leading: Icon(PhosphorIconsRegular.hash, color: C.accent2),
            title: const Text('Теги', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${store.tags.length}', style: const TextStyle(color: C.text2)),
            trailing: const Icon(PhosphorIconsBold.caretRight, size: 14, color: C.muted),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TagsScreen())),
          ),
        ]),
        const SectionHeader('Сервер'),
        _Card(children: [
          ListTile(
            leading: Icon(store.onLocal ? PhosphorIconsRegular.house : PhosphorIconsRegular.globeSimple,
                color: store.onLocal ? C.low : C.medium),
            title: Text(store.onLocal ? 'Дома, напрямую' : 'Через интернет',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(store.activeBase ?? '—', style: const TextStyle(color: C.text2)),
            trailing: const Icon(PhosphorIconsBold.caretRight, color: C.muted),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ServerSettingsScreen())),
          ),
        ]),
        const SectionHeader('Напоминания'),
        _Card(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(children: [
              Icon(PhosphorIconsRegular.bellSimple, color: C.accent2),
              SizedBox(width: 12),
              Expanded(
                child: Text('Напоминать до задачи со временем',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in [0, 5, 10, 15, 30, 60])
                ChoiceChip(
                  label: Text(m == 0 ? 'Выкл' : (m == 60 ? '1 ч' : '$m мин')),
                  selected: store.leadMinutes == m,
                  selectedColor: C.accent,
                  showCheckmark: false,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    store.setLeadMinutes(m);
                  },
                ),
            ]),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.alarm, color: C.text2),
            title: const Text('Точное время уведомлений'),
            subtitle: const Text('Разрешить будильники, чтобы Android не откладывал напоминания',
                style: TextStyle(color: C.text2, fontSize: 12)),
            onTap: () async {
              await Reminders.instance.requestPermissions();
              await Reminders.instance.requestExact();
              store.setLeadMinutes(store.leadMinutes);
            },
          ),
        ]),
        const SectionHeader('Подсказки'),
        const _Card(children: [
          _Hint(PhosphorIconsRegular.handSwipeRight, 'Свайп вправо по задаче', 'Отметить выполненной'),
          _Hint(PhosphorIconsRegular.handSwipeLeft, 'Свайп влево', 'Перенести на завтра'),
          _Hint(PhosphorIconsRegular.handTap, 'Долгое нажатие на проект', 'Цвет, архив, удаление'),
          _Hint(PhosphorIconsRegular.arrowDown, 'Потянуть вниз', 'Синхронизировать и перевыбрать сервер'),
        ]),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: C.urgent,
              side: BorderSide(color: C.urgent.withValues(alpha: 0.4)),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Выйти из аккаунта?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Выйти')),
                  ],
                ),
              );
              if (ok == true) store.logout();
            },
            icon: const Icon(PhosphorIconsRegular.signOut),
            label: const Text('Выйти', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 16),

      ],
    );
  }
}

/// Выбор сервера: авто (сначала локалка), только дом, только интернет.
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  late final _store = StoreScope.read(context);
  late final _local = TextEditingController(text: _store.localUrl);
  late final _remote = TextEditingController(text: _store.remoteUrl);
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    final store = StoreScope.read(context);
    await store.setUrls(_local.text, _remote.text);
    await store.refresh();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Сервер')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (store.onLocal ? C.low : C.medium).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: (store.onLocal ? C.low : C.medium).withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(store.onLocal ? PhosphorIconsRegular.house : PhosphorIconsRegular.globeSimple,
                color: store.onLocal ? C.low : C.medium, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  store.activeBase == null
                      ? 'Сервер не выбран'
                      : store.onLocal
                          ? 'Сейчас: дома, по локальной сети'
                          : 'Сейчас: через интернет',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(store.activeBase ?? '', style: const TextStyle(color: C.text2, fontSize: 12)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        SegmentedButton<BackendMode>(
          segments: const [
            ButtonSegment(value: BackendMode.auto, label: Text('Авто'), icon: Icon(PhosphorIconsRegular.magicWand)),
            ButtonSegment(value: BackendMode.local, label: Text('Дом'), icon: Icon(PhosphorIconsRegular.house)),
            ButtonSegment(value: BackendMode.remote, label: Text('Интернет'), icon: Icon(PhosphorIconsRegular.globeSimple)),
          ],
          selected: {store.mode},
          onSelectionChanged: (s) => store.setMode(s.first),
        ),
        const SizedBox(height: 8),
        const Text(
          'Авто: при запуске и возвращении в приложение проверяем домашний сервер (1,5 с). '
          'Отвечает — работаем напрямую по Wi-Fi, нет — через интернет.',
          style: TextStyle(color: C.text2, fontSize: 13),
        ),
        const SizedBox(height: 22),
        const Text('Домашний адрес', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(controller: _local, keyboardType: TextInputType.url),
        const SizedBox(height: 14),
        const Text('Адрес в интернете', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(controller: _remote, keyboardType: TextInputType.url),
        const SizedBox(height: 20),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: _checking ? null : _check,
            icon: _checking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(PhosphorIconsRegular.wifiHigh),
            label: const Text('Сохранить и проверить'),
          ),
        ),
        TextButton(
          onPressed: () {
            _local.text = defaultLocalUrl;
            _remote.text = defaultRemoteUrl;
          },
          child: const Text('Вернуть адреса по умолчанию'),
        ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: C.bg2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: C.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(icon, color: C.accent2),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(color: C.text2)),
      );
}
