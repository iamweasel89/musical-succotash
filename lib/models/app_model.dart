import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
        final s = GlobalSettings.fromJson(
            jsonDecode(settingsRaw) as Map<String, dynamic>);
        settings.anthropicKey = s.anthropicKey;
        settings.openAiKey = s.openAiKey;
        settings.deepSeekKey = s.deepSeekKey;
        settings.defaultSystemPrompt = s.defaultSystemPrompt;
        settings.streamingMode = s.streamingMode;
        settings.showNodeLabels = s.showNodeLabels;
        settings.defaultProvider = s.defaultProvider;
        settings.defaultModel = s.defaultModel;
        settings.defaultMaxTokens = s.defaultMaxTokens;
        settings.defaultTemperature = s.defaultTemperature;
        settings.compactChat = s.compactChat;
        settings.compactLines = s.compactLines;
        settings.renderMarkdown = s.renderMarkdown;
        settings.tokensInAnthropicTotal = s.tokensInAnthropicTotal;
        settings.tokensOutAnthropicTotal = s.tokensOutAnthropicTotal;
        settings.tokensInOpenaiTotal = s.tokensInOpenaiTotal;
        settings.tokensOutOpenaiTotal = s.tokensOutOpenaiTotal;
        settings.tokensInDeepseekTotal = s.tokensInDeepseekTotal;
        settings.tokensOutDeepseekTotal = s.tokensOutDeepseekTotal;
      }
      _loadHistory();
    } catch (_) {}
  }

  void save() {
    _box.put('nodes', jsonEncode(nodes.map((n) => n.toJson()).toList()));
    _box.put('edges', jsonEncode(edges.map((e) => e.toJson()).toList()));
    _box.put('chainPath', jsonEncode(chainPath));
    _box.put('settings', jsonEncode(settings.toJson()));
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
    save();
    notifyListeners();
  }

  void removeNodes(Set<String> ids) {
    nodes.removeWhere((n) => ids.contains(n.id));
    edges.removeWhere((e) => ids.contains(e.fromId) || ids.contains(e.toId));
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
