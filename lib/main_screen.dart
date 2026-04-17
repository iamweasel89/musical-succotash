import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'canvas/canvas_view.dart';
import 'chat_screen.dart';
import 'models/app_model.dart';
import 'search_screen.dart';
import 'services/debug_server.dart';
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

  // ── Share snapshot with Claude (ВИ1 фаза 1) ───────────────────────────────

  Future<void> _shareWithClaude() async {
    try {
      // State snapshot (same shape as debug /state)
      final m = widget.model;
      final state = <String, dynamic>{
        'timestamp': DateTime.now().toIso8601String(),
        'activeCanvas': {
          'id': m.activeCanvasId,
          'name': m.activeCanvas.name,
          'nodeCount': m.activeCanvasNodes.length,
          'edgeCount': m.activeCanvasEdges.length,
        },
        'counts': {
          'canvases': m.canvases.length,
          'nodes': m.nodes.length,
          'edges': m.edges.length,
          'theses': m.theses.length,
          'decisions': m.decisions.length,
          'webSearchMessages': m.webSearchMessages.length,
        },
        'chainPathLength': m.chainPath.length,
        'currentTab': _tab == 0 ? 'chat' : 'canvas',
      };
      final text = 'hex-canvas snapshot for Claude\n\n' +
          const JsonEncoder.withIndent('  ').convert(state);

      // Screenshot of root widget
      Uint8List? pngBytes;
      try {
        final ctx = DebugServer.screenshotKey.currentContext;
        final boundary = ctx?.findRenderObject();
        if (boundary is RenderRepaintBoundary) {
          final ui.Image img = await boundary.toImage(pixelRatio: 2.0);
          final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
          pngBytes = byteData?.buffer.asUint8List();
        }
      } catch (_) {}

      if (pngBytes != null) {
        final dir = await getTemporaryDirectory();
        final file = File(
            '${dir.path}/hex-snapshot-${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(pngBytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/png')],
          text: text,
          subject: 'hex-canvas snapshot',
        );
      } else {
        await Share.share(text, subject: 'hex-canvas snapshot');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hex Canvas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Показать Claude',
            onPressed: _shareWithClaude,
          ),
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
