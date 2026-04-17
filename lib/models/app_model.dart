import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';

import 'canvas_data.dart';
import 'decision_entry.dart';
import 'edge.dart';
import 'node.dart';
import 'reminder.dart';
import 'screen_snapshot.dart';
import 'settings.dart';
import 'thesis_entry.dart';
import 'usage_event.dart';
import 'web_search_room.dart';

// ── History entry ──────────────────────────────────────────────────────────

class HistoryEntry {
  final String description;
  final String nodesJson;
  final String edgesJson;
  final String chainJson;
  /// Snapshot of canvas nodeIds: [{id, nodeIds:[...]}]
  final String canvasNodeIdsJson;

  const HistoryEntry({
    required this.description,
    required this.nodesJson,
    required this.edgesJson,
    required this.chainJson,
    this.canvasNodeIdsJson = '[]',
  });

  Map<String, dynamic> toJson() => {
        'd': description,
        'n': nodesJson,
        'e': edgesJson,
        'c': chainJson,
        'cv': canvasNodeIdsJson,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        description: j['d'] as String? ?? '',
        nodesJson: j['n'] as String? ?? '[]',
        edgesJson: j['e'] as String? ?? '[]',
        chainJson: j['c'] as String? ?? '[]',
        canvasNodeIdsJson: j['cv'] as String? ?? '[]',
      );
}

// ── Model ──────────────────────────────────────────────────────────────────

class AppModel extends ChangeNotifier {
  final List<Node> nodes = [];
  final List<Edge> edges = [];
  final List<String> chainPath = [];
  final GlobalSettings settings = GlobalSettings();

  // ── Тезисы ────────────────────────────────────────────────────────────────
  final List<ThesisEntry> theses = [];

  // ── Дерево решений ────────────────────────────────────────────────────────
  final List<DecisionEntry> decisions = [];
  void notifyDecisionsChanged() { save(); notifyListeners(); }
  void notifyThesesChanged() { save(); notifyListeners(); }

  // ── Веб-поиск (комната Мастерской) ────────────────────────────────────────
  final List<WebSearchMessage> webSearchMessages = [];
  final WebSearchConfig webSearchConfig = WebSearchConfig();
  void notifyWebSearchChanged() { save(); notifyListeners(); }
  void clearWebSearch() {
    webSearchMessages.clear();
    notifyWebSearchChanged();
  }

  // ── Напоминания (ВР4) ─────────────────────────────────────────────────────
  final List<Reminder> reminders = [];
  void notifyRemindersChanged() { save(); notifyListeners(); }

  // ── Журнал использования LLM ──────────────────────────────────────────────
  final List<UsageEvent> recentUsage = [];
  static const _maxRecentUsage = 100;

  // ── Присутствие: стек открытых экранов + провайдеры снимков ───────────────
  // Обновляется из initState/dispose экранов. Верх стека = «где оператор
  // прямо сейчас». Параллельный стек ScreenSnapshotProvider отдаёт JSON-снимок
  // содержимого экрана (без PNG). Универсальный интерфейс — каждый экран
  // описывает что на нём видно; debug-сервер /screen возвращает последний.
  // Эфемерное состояние, не persist.
  final List<String> _screenStack = ['chat'];
  final List<ScreenSnapshotProvider?> _providerStack = [null];
  String get currentScreen =>
      _screenStack.isEmpty ? 'chat' : _screenStack.last;
  List<String> get screenStack => List.unmodifiable(_screenStack);

  /// Снимок содержимого текущего экрана. null если экран провайдера не имеет
  /// или верх двух стеков разошёлся (drift-protection — защита от ситуации
  /// когда название экрана поменялось а провайдер остался от старого).
  Map<String, dynamic>? captureScreenSnapshot() {
    if (_providerStack.isEmpty) return null;
    final p = _providerStack.last;
    if (p == null) return null;
    if (p.screenName != currentScreen) return null;
    return p.capture();
  }

  /// Главный экран (tab внутри MainScreen) — обновляет только имя корня,
  /// провайдера не трогает (им владеют сами tab-экраны через registerBaseProvider).
  void setBaseScreen(String name) {
    if (_screenStack.isEmpty) {
      _screenStack.add(name);
      _providerStack.add(null);
    } else {
      _screenStack[0] = name;
    }
  }

  /// Регистрация провайдера корневого экрана (tab). Вызывается из initState
  /// экрана-таба. Провайдер снимается при dispose через clearBaseProvider.
  void registerBaseProvider(ScreenSnapshotProvider p) {
    if (_providerStack.isEmpty) {
      _providerStack.add(p);
    } else {
      _providerStack[0] = p;
    }
  }

  void clearBaseProvider(ScreenSnapshotProvider p) {
    if (_providerStack.isNotEmpty && _providerStack[0] == p) {
      _providerStack[0] = null;
    }
  }

  /// Вложенный pushed-экран. Вызывается в initState.
  void pushScreen(String name, {ScreenSnapshotProvider? provider}) {
    _screenStack.add(name);
    _providerStack.add(provider);
  }

  /// Парный вызов к pushScreen в dispose.
  void popScreen() {
    if (_screenStack.length > 1) {
      _screenStack.removeLast();
      _providerStack.removeLast();
    }
  }

  Future<void> _seedDecisions() async {
    try {
      final raw = await rootBundle.loadString('assets/seed/decisions.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final createdAt = DateTime.parse(data['createdAt'] as String);
      final entries = (data['entries'] as List).cast<Map<String, dynamic>>();
      for (final e in entries) {
        decisions.add(DecisionEntry(
          id: e['id'] as String?,
          parentId: e['parentId'] as String?,
          title: e['title'] as String,
          type: DecisionType.values.firstWhere(
            (v) => v.name == e['type'],
            orElse: () => DecisionType.architecture,
          ),
          status: DecisionStatus.values.firstWhere(
            (v) => v.name == e['status'],
            orElse: () => DecisionStatus.idea,
          ),
          notes: (e['notes'] as String?) ?? '',
          createdAt: createdAt,
        ));
      }
    } catch (err) {
      // Asset не доступен — оставляем дерево пустым. Не ломаем запуск.
      // ignore: avoid_print
      print('seed decisions failed: $err');
    }
  }

  // Добавляет новые seed-записи к уже существующему дереву (по фиксированному ID).
  void _migrateDecisions() {
    final ids = decisions.map((e) => e.id).toSet();
    final now = DateTime(2025, 4, 15);
    const a = 'seed_arch';
    if (!ids.contains('seed_inbox_o2')) {
      decisions.add(DecisionEntry(
        id: 'seed_inbox_o2',
        parentId: a,
        title: 'Просмотр инбокса внутри приложения (О2)',
        type: DecisionType.design,
        status: DecisionStatus.implemented,
        notes: 'Комната в Мастерской. Список *.md файлов, сортировка новые сначала. Тап — markdown-просмотр. Удаление с подтверждением.',
        createdAt: now,
      ));
    }
  }

  void clearTheses() {
    theses.clear();
    notifyThesesChanged();
  }

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

  /// Nodes that belong to the active canvas.
  List<Node> get activeCanvasNodes {
    final ids = activeCanvas.nodeIds.toSet();
    return nodes.where((n) => ids.contains(n.id)).toList();
  }

  /// Edges where both endpoints belong to the active canvas.
  List<Edge> get activeCanvasEdges {
    final ids = activeCanvas.nodeIds.toSet();
    return edges
        .where((e) => ids.contains(e.fromId) && ids.contains(e.toId))
        .toList();
  }

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
  Future<void> load() async {
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
        settings.copyFrom(GlobalSettings.fromJson(
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

      // Load theses
      final thesesRaw = _box.get('theses');
      if (thesesRaw != null) {
        theses.addAll(
          (jsonDecode(thesesRaw) as List)
              .map((j) => ThesisEntry.fromJson(j as Map<String, dynamic>)),
        );
      }

      // Load decisions
      final decisionsRaw = _box.get('decisions');
      if (decisionsRaw != null) {
        decisions.addAll(
          (jsonDecode(decisionsRaw) as List)
              .map((j) => DecisionEntry.fromJson(j as Map<String, dynamic>)),
        );
      }
      if (decisions.isEmpty) await _seedDecisions();
      _migrateDecisions();

      // Load web search room
      final wsMsgsRaw = _box.get('webSearchMessages');
      if (wsMsgsRaw != null) {
        webSearchMessages.addAll(
          (jsonDecode(wsMsgsRaw) as List)
              .map((j) => WebSearchMessage.fromJson(j as Map<String, dynamic>)),
        );
      }
      final wsCfgRaw = _box.get('webSearchConfig');
      if (wsCfgRaw != null) {
        final loaded = WebSearchConfig.fromJson(
            jsonDecode(wsCfgRaw) as Map<String, dynamic>);
        webSearchConfig.systemPrompt = loaded.systemPrompt;
        webSearchConfig.provider = loaded.provider;
        webSearchConfig.model = loaded.model;
      }

      // Load reminders
      final remindersRaw = _box.get('reminders');
      if (remindersRaw != null) {
        reminders.addAll(
          (jsonDecode(remindersRaw) as List)
              .map((j) => Reminder.fromJson(j as Map<String, dynamic>)),
        );
      }

      // Load recent usage
      final usageRaw = _box.get('recentUsage');
      if (usageRaw != null) {
        recentUsage.addAll(
          (jsonDecode(usageRaw) as List)
              .map((j) => UsageEvent.fromJson(j as Map<String, dynamic>)),
        );
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

  Future<void> save() async {
    // Sync current chainPath to active canvas before saving
    if (canvases.isNotEmpty) {
      activeCanvas.chainPath
        ..clear()
        ..addAll(chainPath);
    }
    // Box may be closed during test teardown — swallow errors so they don't
    // escape to the zone and fail unrelated tests.
    try {
      await _box.put('nodes', jsonEncode(nodes.map((n) => n.toJson()).toList()));
      await _box.put('edges', jsonEncode(edges.map((e) => e.toJson()).toList()));
      await _box.put('chainPath', jsonEncode(chainPath));
      await _box.put(
          'canvases', jsonEncode(canvases.map((c) => c.toJson()).toList()));
      await _box.put('activeCanvasId', _activeCanvasId);
      await _box.put('settings', jsonEncode(settings.toJson()));
      await _box.put('theses', jsonEncode(theses.map((t) => t.toJson()).toList()));
      await _box.put('decisions', jsonEncode(decisions.map((d) => d.toJson()).toList()));
      await _box.put('webSearchMessages',
          jsonEncode(webSearchMessages.map((m) => m.toJson()).toList()));
      await _box.put('webSearchConfig', jsonEncode(webSearchConfig.toJson()));
      await _box.put('reminders',
          jsonEncode(reminders.map((r) => r.toJson()).toList()));
      await _box.put('recentUsage',
          jsonEncode(recentUsage.map((u) => u.toJson()).toList()));
    } catch (_) {}
  }

  /// Save pan/zoom without triggering a full rebuild.
  Future<void> saveCanvasPanZoom(double panX, double panY, double zoom) async {
    activeCanvas
      ..panX = panX
      ..panY = panY
      ..zoom = zoom;
    try {
      await _box.put(
          'canvases', jsonEncode(canvases.map((c) => c.toJson()).toList()));
    } catch (_) {}
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
        canvasNodeIdsJson: jsonEncode(
          canvases.map((c) => {'id': c.id, 'nodeIds': c.nodeIds}).toList(),
        ),
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
    // Restore canvas nodeIds from snapshot (keeps pan/zoom/name intact)
    final cvList = jsonDecode(entry.canvasNodeIdsJson) as List;
    for (final item in cvList) {
      final id = item['id'] as String;
      final idx = canvases.indexWhere((c) => c.id == id);
      if (idx >= 0) {
        canvases[idx].nodeIds
          ..clear()
          ..addAll((item['nodeIds'] as List).cast<String>());
      }
    }
    save();
    _saveHistory();
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    try {
      await _box.put(
        'history',
        jsonEncode({
          'u': _undoStack.map((e) => e.toJson()).toList(),
          'r': _redoStack.map((e) => e.toJson()).toList(),
        }),
      );
    } catch (_) {}
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
    canvases.clear();
    final defaultCanvas = CanvasData(name: 'Canvas 1');
    canvases.add(defaultCanvas);
    _activeCanvasId = defaultCanvas.id;
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

  // _copySettings удалён — используется settings.copyFrom(...) напрямую.

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
    if (s != null) settings.copyFrom(GlobalSettings.fromJson(s));
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

  void addTokenUsage(String provider, int input, int output,
      {String context = 'chat'}) {
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
    // Журнал последних N событий
    recentUsage.add(UsageEvent(
      provider: provider,
      inputTokens: input,
      outputTokens: output,
      cost: calculateCost(provider, input, output),
      timestamp: DateTime.now(),
      context: context,
    ));
    if (recentUsage.length > _maxRecentUsage) {
      recentUsage.removeRange(0, recentUsage.length - _maxRecentUsage);
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

  void clearRecentUsage() {
    recentUsage.clear();
    save();
    notifyListeners();
  }
}
