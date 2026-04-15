import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';

// ── Мастерская: Инбокс (О2) ──────────────────────────────────────────────────

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<File> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/inbox');
    if (!dir.existsSync()) {
      setState(() { _files = []; _loading = false; });
      return;
    }
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path)); // newest first
    setState(() { _files = files; _loading = false; });
  }

  Future<void> _delete(File file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить файл?'),
        content: Text(_label(file)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await file.delete();
    _load();
  }

  // YYYYMMDD-HHmmss-dump.md → "15 апр 2026, 14:30"
  String _label(File file) {
    final name = file.uri.pathSegments.last;
    try {
      final y = int.parse(name.substring(0, 4));
      final mo = int.parse(name.substring(4, 6));
      final d = int.parse(name.substring(6, 8));
      final h = int.parse(name.substring(9, 11));
      final mi = int.parse(name.substring(11, 13));
      final dt = DateTime(y, mo, d, h, mi);
      return '${_monthName(dt.month)} ${dt.day}, ${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return name;
    }
  }

  String _monthName(int m) => const [
        '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
        'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
      ][m];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Инбокс'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text('Инбокс пуст',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                        'Дампы из тезисов появятся здесь.',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                  itemBuilder: (_, i) {
                    final file = _files[i];
                    return ListTile(
                      leading: const Icon(Icons.description_outlined, color: Colors.teal),
                      title: Text(_label(file),
                          style: const TextStyle(fontSize: 14)),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[300]),
                        onPressed: () => _delete(file),
                        visualDensity: VisualDensity.compact,
                      ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _InboxViewer(file: file, label: _label(file)),
                      )),
                    );
                  },
                ),
    );
  }
}

// ── Viewer ────────────────────────────────────────────────────────────────────

class _InboxViewer extends StatefulWidget {
  final File file;
  final String label;
  const _InboxViewer({required this.file, required this.label});

  @override
  State<_InboxViewer> createState() => _InboxViewerState();
}

class _InboxViewerState extends State<_InboxViewer> {
  String? _content;

  @override
  void initState() {
    super.initState();
    widget.file.readAsString().then((s) => setState(() => _content = s));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.label, style: const TextStyle(fontSize: 14))),
      body: _content == null
          ? const Center(child: CircularProgressIndicator())
          : Markdown(
              data: _content!,
              selectable: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            ),
    );
  }
}
