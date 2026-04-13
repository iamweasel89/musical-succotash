import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'canvas_data.dart';
import 'edge.dart';
import 'node.dart';
import 'settings.dart';

// ── History entry ──────────────────────────────────────────────────────────

class HistoryEntry {
  final String description;
  final String nodesJson;
  final String edgesJson;
  final String chainJson;

  const HistoryEntry({
    required this.description,
    required this.nodesJson,
    required this.edgesJson,
    required this.chainJson,
  });

  Map<String, dynamic> toJson() => {
        'd': description,
        'n': nodesJson,
        'e': edgesJson,
        'c': chainJson,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        description: j['d'] as String? ?? '',
        nodesJson: j['n'] as String? ?? '[]',
        edgesJson: j['e'] as String? ?? '[]',
        chainJson: j['c'] as String? ?? '[]',
      );
}

// ── Model ──────────────────────────────────────────────────────────────────

class AppModel extends ChangeNotifier {
  final List<Node> nodes = [];
  final List<Edge> edges = [];
  final List<String> chainPath = [];
  final GlobalSettings settings = GlobalSettings();

  // ── Canvases ───────────────────────────────────────────────────────────────
  final List<CanvasData> canvases = [];
  String _activeCanvasId = '';

  CanvasData get activeCanvas {
    if (canvases.isEmpty) {
      final c = CanvasData(name: 'Canvas 1');
      canvases.add(c);
      _activeCanvasId = c.id;
    }
    return canvases.firstWhere(
      (c) => c.id == _activeCanvasId,
      orElse: () => canvases.first,
    );
  }

  String get activeCanvasId => _activeCanvasId;

  // ── History ────────────────────────────────────────────────────────────────
  final _undoStack = <HistoryEntry>[];
  final _redoStack = <HistoryEntry>[];
  static const _maxHistory = 30;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  List<HistoryEntry> get undoStack => List.unmodifiable(_undoStack);
  List<HistoryEntry> get redoStack => List.unmodifiable(_redoStack);

  Box<String> get _box => Hive.box<String>('state');

  // ── Persistence ────────────────────────────────────────────────────────────
  void load() {
    try {
      final nodesRaw = _box.get('nodes');
      if (nodesRaw != null) {
        nodes.addAll(
          (jsonDecode(nodesRaw) as List)
              .map((j) => Node.fromJson(j as Map<String, dynamic>)),
        );
      }
      final edgesRaw = _box.get('edges');
      if (edgesRaw != null) {
        edges.addAll(
          (jsonDecode(edgesRaw) as List)
              .map((j) => Edge.fromJson(j as Map<String, dynamic>)),
        );
      }
      final chainRaw = _box.get('chainPath');
      if (chainRaw != null) {
        chainPath.addAll((jsonDecode(chainRaw) as List).cast<String>());
      }
      final settingsRaw = _box.get('settings');
      if (settingsRaw != null) {
        _copySettings(GlobalSettings.fromJson(
            jsonDecode(settingsRaw) as Map<String, dynamic>));
      }

      // Load canvases
      final canvasesRaw = _box.get('canvases');
      if (canvasesRaw != null) {
        canvases.addAll(
          (jsonDecode(canvasesRaw) as List)
              .map((j) => CanvasData.fromJson(j as Map<String, dynamic>)),
        );
      }
      final activeIdRaw = _box.get('activeCanvasId');
      if (activeIdRaw != null && canvases.any((c) => c.id == activeIdRaw)) {
        _activeCanvasId = activeIdRaw;
      } else if (canvases.isNotEmpty) {
        _activeCanvasId = canvases.first.id;
      }

      // First run or migration: create default canvas from existing data
      if (canvases.isEmpty) {
        final canvas = CanvasData(
          name: 'Canvas 1',
          nodeIds: nodes.map((n) => n.id).toList(),
          chainPath: List<String>.from(chainPath),
        );
        canvases.add(canvas);
        _activeCanvasId = canvas.id;
      }

      _loadHistory();
    } catch (_) {}
  }

  void save() {
    // Sync current chainPath to active canvas before saving
    if (canvases.isNotEmpty) {
      activeCanvas.chainPath
        ..clear()
        ..addAll(chainPath);
    }
    _box.put('nodes', jsonEncode(nodes.map((n) => n.toJson()).toList()));
    _box.put('edges', jsonEncode(edges.map((e) => e.toJson()).toList()));
    _box.put('chainPath', jsonEncode(chainPath));
    _box.put(
        'canvases', jsonEncode(canvases.map((c) => c.toJson()).toList()));
    _box.put('activeCanvasId', _activeCanvasId);
    _box.put('settings', jsonEncode(settings.toJson()));
  }

  /// Save pan/zoom without triggering a full rebuild.
  void saveCanvasPanZoom(double panX, double panY, double zoom) {
    activeCanvas
      ..panX = panX
      ..panY = panY
      ..zoom = zoom;
    _box.put(
        'canvases', jsonEncode(canvases.map((c) => c.toJson()).toList()));
  }

  // ── Canvas management ──────────────────────────────────────────────────────

  CanvasData createCanvas() {
    final num = canvases.length + 1;
    final canvas = CanvasData(name: 'Canvas $num');
    canvases.add(canvas);
    _switchToCanvas(canvas.id);
    save();
    notifyListeners();
    return canvas;
  }

  void switchCanvas(String id) {
    if (id == _activeCanvasId) return;
    _switchToCanvas(id);
    save();
    notifyListeners();
  }

  void _switchToCanvas(String id) {
    // Persist current chainPath into old canvas
    if (_activeCanvasId.isNotEmpty && canvases.any((c) => c.id == _activeCanvasId)) {
      activeCanvas.chainPath
        ..clear()
        ..addAll(chainPath);
    }
    _activeCanvasId = id;
    // Load new canvas's chainPath
    chainPath
      ..clear()
      ..addAll(activeCanvas.chainPath);
  }

  void renameCanvas(String id, String newName) {
    final idx = canvases.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    canvases[idx].name = newName;
    save();
    notifyListeners();
  }

  void deleteCanvas(String id) {
    if (canvases.length <= 1) return;
    final idx = canvases.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    final wasActive = _activeCanvasId == id;
    canvases.removeAt(idx);
    if (wasActive) {
      final newIdx = idx < canvases.length ? idx : idx - 1;
      _switchToCanvas(canvases[newIdx].id);
    }
    save();
    notifyListeners();
  }

  // ── History ────────────────────────────────────────────────────────────────

  void snapshot(String description) {
    _undoStack.add(_capture(description));
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
    _saveHistory();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_capture(''));
    _applyEntry(_undoStack.removeLast());
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_capture(''));
    _applyEntry(_redoStack.removeLast());
  }

  HistoryEntry _capture(String desc) => HistoryEntry(
        description: desc,
        nodesJson: jsonEncode(nodes.map((n) => n.toJson()).toList()),
        edgesJson: jsonEncode(edges.map((e) => e.toJson()).toList()),
        chainJson: jsonEncode(chainPath),
      );

  void _applyEntry(HistoryEntry entry) {
    nodes
      ..clear()
      ..addAll((jsonDecode(entry.nodesJson) as List)
          .map((j) => Node.fromJson(j as Map<String, dynamic>)));
    edges
      ..clear()
      ..addAll((jsonDecode(entry.edgesJson) as List)
          .map((j) => Edge.fromJson(j as Map<String, dynamic>)));
    chainPath
      ..clear()
      ..addAll((jsonDecode(entry.chainJson) as List).cast<String>());
    save();
    _saveHistory();
    notifyListeners();
  }

  void _saveHistory() {
    _box.put(
      'history',
      jsonEncode({
        'u': _undoStack.map((e) => e.toJson()).toList(),
        'r': _redoStack.map((e) => e.toJson()).toList(),
      }),
    );
  }

  void _loadHistory() {
    final raw = _box.get('history');
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _undoStack.addAll((j['u'] as List? ?? [])
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>)));
      _redoStack.addAll((j['r'] as List? ?? [])
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>)));
    } catch (_) {}
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  void addNode(Node node) {
    nodes.add(node);
    activeCanvas.nodeIds.add(node.id);
    save();
    notifyListeners();
  }

  void updateNode(Node updated) {
    final idx = nodes.indexWhere((n) => n.id == updated.id);
    if (idx < 0) return;
    nodes[idx] = updated;
    save();
    notifyListeners();
  }

  void addEdge(Edge edge) {
    edges.add(edge);
    save();
    notifyListeners();
  }

  void clearAll() {
    nodes.clear();
    edges.clear();
    chainPath.clear();
    for (final c in canvases) {
      c.nodeIds.clear();
      c.chainPath.clear();
    }
    save();
    notifyListeners();
  }

  void removeNodes(Set<String> ids) {
    nodes.removeWhere((n) => ids.contains(n.id));
    edges.removeWhere((e) => ids.contains(e.fromId) || ids.contains(e.toId));
    for (final c in canvases) {
      c.nodeIds.removeWhere((id) => ids.contains(id));
    }
    save();
    notifyListeners();
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  Node? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  List<Node> upstreamNodes(String nodeId) => edges
      .where((e) => e.toId == nodeId)
      .map((e) => nodeById(e.fromId))
      .whereType<Node>()
      .toList();

  // ── Settings / export / import ─────────────────────────────────────────────

  void _copySettings(GlobalSettings s) {
    settings.anthropicKey = s.anthropicKey;
    settings.openAiKey = s.openAiKey;
    settings.deepSeekKey = s.deepSeekKey;
    settings.defaultSystemPrompt = s.defaultSystemPrompt;
    settings.useBuiltinSystemPrompt = s.useBuiltinSystemPrompt;
    settings.streamingMode = s.streamingMode;
    settings.showNodeLabels = s.showNodeLabels;
    settings.renderMarkdown = s.renderMarkdown;
    settings.hideEmoji = s.hideEmoji;
    settings.defaultProvider = s.defaultProvider;
    settings.defaultModel = s.defaultModel;
    settings.defaultMaxTokens = s.defaultMaxTokens;
    settings.defaultTemperature = s.defaultTemperature;
    settings.compactChat = s.compactChat;
    settings.compactLines = s.compactLines;
    settings.tokensInAnthropicTotal = s.tokensInAnthropicTotal;
    settings.tokensOutAnthropicTotal = s.tokensOutAnthropicTotal;
    settings.tokensInOpenaiTotal = s.tokensInOpenaiTotal;
    settings.tokensOutOpenaiTotal = s.tokensOutOpenaiTotal;
    settings.tokensInDeepseekTotal = s.tokensInDeepseekTotal;
    settings.tokensOutDeepseekTotal = s.tokensOutDeepseekTotal;
  }

  String exportJson() => jsonEncode({
        'version': 1,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        'chainPath': chainPath,
        'canvases': canvases.map((c) => c.toJson()).toList(),
        'activeCanvasId': _activeCanvasId,
        'settings': settings.toJson(),
      });

  void importJson(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    nodes
      ..clear()
      ..addAll((data['nodes'] as List)
          .map((j) => Node.fromJson(j as Map<String, dynamic>)));
    edges
      ..clear()
      ..addAll((data['edges'] as List)
          .map((j) => Edge.fromJson(j as Map<String, dynamic>)));
    chainPath
      ..clear()
      ..addAll((data['chainPath'] as List).cast<String>());
    canvases.clear();
    final canvasesData = data['canvases'] as List?;
    if (canvasesData != null && canvasesData.isNotEmpty) {
      canvases.addAll(canvasesData
          .map((j) => CanvasData.fromJson(j as Map<String, dynamic>)));
      _activeCanvasId =
          data['activeCanvasId'] as String? ?? canvases.first.id;
    } else {
      // Old export without canvases: create default
      final canvas = CanvasData(
        name: 'Canvas 1',
        nodeIds: nodes.map((n) => n.id).toList(),
        chainPath: List<String>.from(chainPath),
      );
      canvases.add(canvas);
      _activeCanvasId = canvas.id;
    }
    final s = data['settings'] as Map<String, dynamic>?;
    if (s != null) _copySettings(GlobalSettings.fromJson(s));
    save();
    notifyListeners();
  }

  List<String> chainForNode(String nodeId) {
    final path = <String>[nodeId];
    var cur = nodeId;
    for (var i = 0; i < 500; i++) {
      final parent =
          edges.where((e) => e.toId == cur).map((e) => e.fromId).firstOrNull;
      if (parent == null) break;
      path.insert(0, parent);
      cur = parent;
    }
    var tail = path.last;
    for (var i = 0; i < 500; i++) {
      final child =
          edges.where((e) => e.fromId == tail).map((e) => e.toId).firstOrNull;
      if (child == null) break;
      path.add(child);
      tail = child;
    }
    return path;
  }

  void notifySettingsChanged() {
    save();
    notifyListeners();
  }

  void addTokenUsage(String provider, int input, int output) {
    switch (provider) {
      case 'anthropic':
        settings.tokensInAnthropicTotal += input;
        settings.tokensOutAnthropicTotal += output;
      case 'openai':
        settings.tokensInOpenaiTotal += input;
        settings.tokensOutOpenaiTotal += output;
      case 'deepseek':
        settings.tokensInDeepseekTotal += input;
        settings.tokensOutDeepseekTotal += output;
    }
    save();
  }

  void resetTokenUsage() {
    settings.tokensInAnthropicTotal = 0;
    settings.tokensOutAnthropicTotal = 0;
    settings.tokensInOpenaiTotal = 0;
    settings.tokensOutOpenaiTotal = 0;
    settings.tokensInDeepseekTotal = 0;
    settings.tokensOutDeepseekTotal = 0;
    save();
    notifyListeners();
  }
}
