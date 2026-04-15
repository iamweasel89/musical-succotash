import 'package:flutter/material.dart';

import '../models/app_model.dart';
import '../models/decision_entry.dart';

// ── Мастерская: Дерево решений (Т1–Т5) ───────────────────────────────────────

class DecisionTreeScreen extends StatefulWidget {
  final AppModel model;
  const DecisionTreeScreen({super.key, required this.model});

  @override
  State<DecisionTreeScreen> createState() => _DecisionTreeScreenState();
}

class _DecisionTreeScreenState extends State<DecisionTreeScreen> {
  List<DecisionEntry> get _all => widget.model.decisions;

  // ── Flat tree: depth-first order with depth level ────────────────────────

  List<({DecisionEntry entry, int depth})> _buildFlat() {
    final result = <({DecisionEntry entry, int depth})>[];
    void visit(String? parentId, int depth) {
      for (final e in _all.where((e) => e.parentId == parentId)) {
        result.add((entry: e, depth: depth));
        visit(e.id, depth + 1);
      }
    }
    visit(null, 0);
    return result;
  }

  // ── Edit sheet ────────────────────────────────────────────────────────────

  Future<void> _openSheet({DecisionEntry? entry, String? parentId}) async {
    final result = await showModalBottomSheet<DecisionEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DecisionSheet(entry: entry, parentId: parentId),
    );
    if (result == null) return;
    setState(() {
      if (entry != null) {
        final i = _all.indexWhere((e) => e.id == entry.id);
        if (i >= 0) _all[i] = result;
      } else {
        _all.add(result);
      }
      widget.model.notifyDecisionsChanged();
    });
  }

  Future<void> _delete(DecisionEntry entry) async {
    // Удаляем запись и всех потомков рекурсивно
    final toRemove = <String>{};
    void collect(String id) {
      toRemove.add(id);
      for (final child in _all.where((e) => e.parentId == id)) {
        collect(child.id);
      }
    }
    collect(entry.id);
    setState(() {
      _all.removeWhere((e) => toRemove.contains(e.id));
      widget.model.notifyDecisionsChanged();
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final flat = _buildFlat();
    return Scaffold(
      appBar: AppBar(title: const Text('Дерево решений')),
      body: flat.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_tree_outlined, size: 48, color: Colors.teal),
                    SizedBox(height: 16),
                    Text('Нет решений',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    SizedBox(height: 8),
                    Text(
                      'Нажмите + чтобы добавить первое решение.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          : ListenableBuilder(
              listenable: widget.model,
              builder: (context, _) {
                final flat = _buildFlat();
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
                  itemCount: flat.length,
                  itemBuilder: (_, i) {
                    final (:entry, :depth) = flat[i];
                    return _DecisionTile(
                      entry: entry,
                      depth: depth,
                      onTap: () => _openSheet(entry: entry),
                      onAddChild: () => _openSheet(parentId: entry.id),
                      onDelete: () => _delete(entry),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSheet(),
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _DecisionTile extends StatelessWidget {
  final DecisionEntry entry;
  final int depth;
  final VoidCallback onTap;
  final VoidCallback onAddChild;
  final VoidCallback onDelete;

  const _DecisionTile({
    required this.entry,
    required this.depth,
    required this.onTap,
    required this.onAddChild,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(entry.status);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.0 + depth * 20.0, 6, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vertical tree line for children
            if (depth > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: Icon(Icons.subdirectory_arrow_right,
                    size: 14, color: Colors.grey[400]),
              ),
            // Status dot
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 8),
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  Row(
                    children: [
                      Text(entry.type.label,
                          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(entry.status.label,
                            style: TextStyle(
                                fontSize: 10,
                                color: statusColor,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  if (entry.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        entry.notes.length > 80
                            ? '${entry.notes.substring(0, 80)}…'
                            : entry.notes,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ),
                ],
              ),
            ),
            // Actions
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'Добавить дочернее',
              onPressed: onAddChild,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Удалить',
              onPressed: onDelete,
              color: Colors.red[300],
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(DecisionStatus s) => switch (s) {
        DecisionStatus.idea => Colors.grey,
        DecisionStatus.discussion => Colors.orange,
        DecisionStatus.accepted => Colors.blue,
        DecisionStatus.implemented => Colors.green,
        DecisionStatus.obsolete => Colors.brown,
        DecisionStatus.rejected => Colors.red,
      };
}

// ── Edit sheet ────────────────────────────────────────────────────────────────

class _DecisionSheet extends StatefulWidget {
  final DecisionEntry? entry;
  final String? parentId;
  const _DecisionSheet({this.entry, this.parentId});

  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _notesCtrl;
  late DecisionType _type;
  late DecisionStatus _status;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _type = e?.type ?? DecisionType.architecture;
    _status = e?.status ?? DecisionStatus.idea;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final e = widget.entry;
    final result = DecisionEntry(
      id: e?.id,
      parentId: e?.parentId ?? widget.parentId,
      title: title,
      type: _type,
      status: _status,
      notes: _notesCtrl.text.trim(),
      createdAt: e?.createdAt,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.entry == null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isNew ? 'Новое решение' : 'Редактировать',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Заголовок',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<DecisionType>(
                value: _type,
                decoration: const InputDecoration(
                    labelText: 'Тип', border: OutlineInputBorder(), isDense: true),
                items: DecisionType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.label, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) => setState(() => _type = v!),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<DecisionStatus>(
                value: _status,
                decoration: const InputDecoration(
                    labelText: 'Статус', border: OutlineInputBorder(), isDense: true),
                items: DecisionStatus.values
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.label, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) => setState(() => _status = v!),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Заметки',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              child: Text(isNew ? 'Добавить' : 'Сохранить'),
            ),
          ),
        ],
      ),
    );
  }
}
