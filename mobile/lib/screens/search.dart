import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/task_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final results = store.search(_q.text);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _q,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Поиск задач',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
        actions: [
          if (_q.text.isNotEmpty)
            IconButton(
              onPressed: () => setState(_q.clear),
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: _q.text.trim().isEmpty
          ? const EmptyState(icon: Icons.search_rounded, title: 'Найдите задачу', subtitle: 'По названию или описанию')
          : results.isEmpty
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'Ничего не найдено')
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 40),
                  itemCount: results.length,
                  itemBuilder: (_, i) => TaskTile(task: results[i], showDate: true),
                ),
      backgroundColor: C.bg,
    );
  }
}
