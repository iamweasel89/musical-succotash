import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'canvas/canvas_view.dart';
import 'chat_screen.dart';
import 'models/app_model.dart';
import 'search_screen.dart';
import 'widgets/settings_sheet.dart';

class MainScreen extends StatefulWidget {
  final AppModel model;
  const MainScreen({super.key, required this.model});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tab = 0;

  // ── Settings ──────────────────────────────────────────────────────────────

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SettingsSheet(
        model: widget.model,
        settings: widget.model.settings,
        onChanged: widget.model.notifySettingsChanged,
        onClearAll: widget.model.clearAll,
        onExport: _exportData,
        onImport: _importData,
      ),
    );
  }

  // ── Export / Import ───────────────────────────────────────────────────────

  Future<void> _exportData() async {
    try {
      final json = widget.model.exportJson();
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/hex_canvas_$ts.json');
      await file.writeAsString(json);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Hex Canvas Export',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  Future<void> _importData() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      final jsonStr = utf8.decode(bytes);

      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Импортировать данные?'),
          content: const Text(
              'Текущий граф и настройки будут заменены. '
              'Действие можно отменить через ↩.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Импортировать',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      widget.model.snapshot('Импорт данных');
      widget.model.importJson(jsonStr);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка импорта: $e')),
        );
      }
    }
  }

  // ── Search ────────────────────────────────────────────────────────────────

  Future<void> _openSearch() async {
    final nodeId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
          builder: (_) => SearchScreen(model: widget.model)),
    );
    if (nodeId == null || !mounted) return;

    final chain = widget.model.chainForNode(nodeId);
    widget.model.chainPath
      ..clear()
      ..addAll(chain);
    widget.model.save();
    setState(() => _tab = 0);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hex Canvas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Поиск',
            onPressed: _openSearch,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          ChatScreen(model: widget.model),
          CanvasView(model: widget.model, isActive: _tab == 1),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.forum), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Canvas'),
        ],
      ),
    );
  }
}
