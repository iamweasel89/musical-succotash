import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'edge.dart';
import 'node.dart';
import 'settings.dart';

class AppModel extends ChangeNotifier {
  final List<Node> nodes = [];
  final List<Edge> edges = [];
  final List<String> chainPath = [];
  final GlobalSettings settings = GlobalSettings();

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
      }
    } catch (_) {}
  }

  void save() {
    _box.put('nodes', jsonEncode(nodes.map((n) => n.toJson()).toList()));
    _box.put('edges', jsonEncode(edges.map((e) => e.toJson()).toList()));
    _box.put('chainPath', jsonEncode(chainPath));
    _box.put('settings', jsonEncode(settings.toJson()));
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
}
