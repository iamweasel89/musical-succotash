import 'dart:io';

import 'package:flutter/material.dart';

import 'atom_view.dart';

enum _Sort { byTime, byDepth, byManualDepth }

class VaultListScreen extends StatefulWidget {
  final String title;
  final List<File> files;
  final Map<String, String> texts;
  final Map<String, int>? depth;
  final Map<String, int>? manualDepth;
  final Future<void> Function(File) onOpenFile;
  final bool showDepth;

  const VaultListScreen({
    super.key,
    required this.title,
    required this.files,
    required this.texts,
    required this.onOpenFile,
    this.depth,
    this.manualDepth,
    this.showDepth = false,
  });

  @override
  State<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends State<VaultListScreen> {
  final _searchCtl = TextEditingController();
  String _q = '';
  _Sort _sort = _Sort.byTime;

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  String _idOf(File f) => f.path.split('/').last.replaceAll('.md', '');

  List<File> get _visible {
    var list = widget.files;
    if (_q.isNotEmpty) {
      final q = _q.toLowerCase();
      list = list.where((f) {
        if (f.path.toLowerCase().contains(q)) return true;
        final t = widget.texts[f.path];
        return t != null && t.toLowerCase().contains(q);
      }).toList();
    }
    if (widget.showDepth && _sort != _Sort.byTime) {
      final map = _sort == _Sort.byDepth ? widget.depth : widget.manualDepth;
      if (map != null) {
        list = [...list];
        list.sort((a, b) {
          final da = map[_idOf(a)] ?? 0;
          final db = map[_idOf(b)] ?? 0;
          return db.compareTo(da);
        });
      }
    }
    return list;
  }

  String _firstLine(String? text) {
    if (text == null) return '';
    final parsed = parseFrontmatter(text);
    final line = parsed.body
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final stripped = line.replaceAll(RegExp(r'\*+'), '').trim();
    return stripped.length > 60
        ? '${stripped.substring(0, 60)}…'
        : stripped;
  }

  String _typeOf(String? text) {
    if (text == null) return '';
    return parseFrontmatter(text).meta['type'] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _searchCtl,
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Поиск по содержимому…',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtl.clear();
                          setState(() => _q = '');
                        },
                      ),
              ),
            ),
          ),
          if (widget.showDepth)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Text('Сортировка:', style: theme.textTheme.bodySmall),
                  const SizedBox(width: 8),
                  DropdownButton<_Sort>(
                    value: _sort,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(
                          value: _Sort.byTime, child: Text('по времени')),
                      DropdownMenuItem(
                          value: _Sort.byDepth,
                          child: Text('по глубине ⛓')),
                      DropdownMenuItem(
                          value: _Sort.byManualDepth,
                          child: Text('по чистой глубине ✓')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _sort = v);
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      widget.files.isEmpty
                          ? 'Пусто'
                          : 'Не найдено',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final f = visible[i];
                      final id = _idOf(f);
                      final text = widget.texts[f.path];
                      final preview = _firstLine(text);
                      final type = _typeOf(text);
                      return ListTile(
                        title: Text(
                          preview.isEmpty ? '(пусто)' : preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Row(
                          children: [
                            if (type.isNotEmpty) ...[
                              Text(type,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        theme.colorScheme.outline,
                                  )),
                              const SizedBox(width: 6),
                              Text('·',
                                  style: TextStyle(
                                      color:
                                          theme.colorScheme.outline)),
                              const SizedBox(width: 6),
                            ],
                            Text(id,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                  fontFamily: 'monospace',
                                )),
                          ],
                        ),
                        trailing: widget.showDepth
                            ? _depthChips(theme, id)
                            : null,
                        onTap: () => widget.onOpenFile(f),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _depthChips(ThemeData theme, String id) {
    final d = widget.depth?[id] ?? 0;
    final md = widget.manualDepth?[id] ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip(theme, '⛓ $d'),
        const SizedBox(width: 4),
        _chip(theme, '✓ $md',
            highlight: md == d && d > 0 ? Colors.green : null),
      ],
    );
  }

  Widget _chip(ThemeData theme, String text, {Color? highlight}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlight?.withOpacity(0.25) ??
            theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}
