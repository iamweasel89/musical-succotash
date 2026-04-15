import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'canvas_data.dart';
import 'decision_entry.dart';
import 'edge.dart';
import 'node.dart';
import 'settings.dart';
import 'thesis_entry.dart';

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

  void _seedDecisions() {
    // Фиксированные ID чтобы дерево было воспроизводимым
    const p = 'seed_platform';
    const a = 'seed_arch';
    const t = 'seed_terms';
    const d = 'seed_design';
    const f = 'seed_future';

    final now = DateTime(2025, 4, 15);
    decisions.addAll([
      // ── Корневые ───────────────────────────────────────────────────────────
      DecisionEntry(id: p, title: 'Платформа и стек',
          type: DecisionType.technology, status: DecisionStatus.implemented,
          notes: 'Flutter (Android), Hive, GitHub Actions', createdAt: now),
      DecisionEntry(id: a, title: 'Архитектура приложения',
          type: DecisionType.architecture, status: DecisionStatus.implemented,
          notes: 'Два режима: Чат и Канва. Единое состояние в AppModel.', createdAt: now),
      DecisionEntry(id: t, title: 'Термины проекта',
          type: DecisionType.term, status: DecisionStatus.accepted,
          notes: 'Устоявшийся словарь — нода, тезис, дамп, инбокс, паспорт, мастерская.', createdAt: now),
      DecisionEntry(id: d, title: 'Дизайн-решения',
          type: DecisionType.design, status: DecisionStatus.implemented,
          notes: 'Ключевые UX-решения по интерфейсу.', createdAt: now),
      DecisionEntry(id: f, title: 'Идеи и горизонт',
          type: DecisionType.architecture, status: DecisionStatus.idea,
          notes: 'Направления которые обсуждаем но ещё не решили.', createdAt: now),

      // ── Платформа ──────────────────────────────────────────────────────────
      DecisionEntry(parentId: p, title: 'Flutter + Android',
          type: DecisionType.technology, status: DecisionStatus.implemented,
          notes: 'Единственная целевая платформа на данный момент.', createdAt: now),
      DecisionEntry(parentId: p, title: 'Hive как локальное хранилище',
          type: DecisionType.technology, status: DecisionStatus.implemented,
          notes: 'Вместо SQLite или файлов. Box<String> с JSON-сериализацией.', createdAt: now),
      DecisionEntry(parentId: p, title: 'GitHub Actions для сборки APK',
          type: DecisionType.technology, status: DecisionStatus.accepted,
          notes: 'CI/CD на GitHub. Замена не планируется — Android SDK уже настроен.', createdAt: now),
      DecisionEntry(parentId: p, title: 'flutter_markdown для пузырей',
          type: DecisionType.technology, status: DecisionStatus.implemented,
          notes: 'Markdown-рендеринг в сообщениях чата.', createdAt: now),

      // ── Архитектура ────────────────────────────────────────────────────────
      DecisionEntry(parentId: a, title: 'AppModel — единое состояние (ChangeNotifier)',
          type: DecisionType.architecture, status: DecisionStatus.implemented,
          notes: 'Один объект на всё приложение. Подписка через ListenableBuilder.', createdAt: now),
      DecisionEntry(parentId: a, title: 'Каждое сообщение чата = нода на канве',
          type: DecisionType.architecture, status: DecisionStatus.implemented,
          notes: 'Чат и канва — два представления одного графа нод.', createdAt: now),
      DecisionEntry(parentId: a, title: 'Тезисы персистентны в Hive',
          type: DecisionType.architecture, status: DecisionStatus.implemented,
          notes: 'Сначала были эфемерными. Переведены в Hive чтобы выживать перезапуск.', createdAt: now),
      DecisionEntry(parentId: a, title: 'Мастерская как отдельный навигационный экран',
          type: DecisionType.architecture, status: DecisionStatus.implemented,
          notes: 'Комнаты: Экстрактор, Тезисы, Дерево решений. Вход через настройки.', createdAt: now),
      DecisionEntry(parentId: a, title: 'Инбокс = documents/inbox/ (markdown-файлы)',
          type: DecisionType.architecture, status: DecisionStatus.implemented,
          notes: 'DumpService пишет *.md с YAML-фронтматтером. Для LLM-разбора позже.', createdAt: now),
      DecisionEntry(parentId: a, title: 'ExcerptExtractor с onConfirm для переиспользования',
          type: DecisionType.architecture, status: DecisionStatus.implemented,
          notes: 'Один виджет — два режима: standalone (копировать) и встроенный (в тезисы).', createdAt: now),

      // ── Термины ────────────────────────────────────────────────────────────
      DecisionEntry(parentId: t, title: 'Тезис',
          type: DecisionType.term, status: DecisionStatus.accepted,
          notes: 'Краткая формулировка мысли из фрагмента текста. Не цитата — интерпретация.', createdAt: now),
      DecisionEntry(parentId: t, title: 'Нода',
          type: DecisionType.term, status: DecisionStatus.accepted,
          notes: 'Единица информации на канве. Бывает текстовой и API-типа.', createdAt: now),
      DecisionEntry(parentId: t, title: 'Дамп',
          type: DecisionType.term, status: DecisionStatus.accepted,
          notes: 'Сохранённая ветка чата в markdown. Попадает в инбокс.', createdAt: now),
      DecisionEntry(parentId: t, title: 'Инбокс',
          type: DecisionType.term, status: DecisionStatus.accepted,
          notes: 'Папка documents/inbox/ — накопитель черновиков для последующего разбора.', createdAt: now),
      DecisionEntry(parentId: t, title: 'Паспорт',
          type: DecisionType.term, status: DecisionStatus.accepted,
          notes: 'Канонический статус документа. Не имя шага, а уровень зрелости.', createdAt: now),
      DecisionEntry(parentId: t, title: 'Три уровня документа',
          type: DecisionType.term, status: DecisionStatus.accepted,
          notes: 'Черновик (сырая запись) → Документ (синтез) → Паспорт (канонический).', createdAt: now),
      DecisionEntry(parentId: t, title: 'Мастерская',
          type: DecisionType.term, status: DecisionStatus.accepted,
          notes: 'Экран для инструментов и экспериментов. Не чат, не канва.', createdAt: now),

      // ── Дизайн ─────────────────────────────────────────────────────────────
      DecisionEntry(parentId: d, title: 'Два таба: Чат / Канва',
          type: DecisionType.design, status: DecisionStatus.implemented,
          notes: 'Нижняя навигация. Мастерская — через настройки, не таб.', createdAt: now),
      DecisionEntry(parentId: d, title: 'Время и ID на пузыре — опционально',
          type: DecisionType.design, status: DecisionStatus.implemented,
          notes: 'Флаги showBubbleTime / showBubbleId в GlobalSettings. По умолчанию выкл.', createdAt: now),
      DecisionEntry(parentId: d, title: 'Ветвящийся диалог — дерево, не список',
          type: DecisionType.design, status: DecisionStatus.implemented,
          notes: 'Каждый ответ можно ветвить. История = путь по дереву нод.', createdAt: now),
      DecisionEntry(parentId: d, title: 'Баннер тезисов в чате → переход в Мастерскую',
          type: DecisionType.design, status: DecisionStatus.implemented,
          notes: 'Кнопка ❝ на пузыре → ExcerptExtractor → «В тезисы» → воркшоп. Не оверлей.', createdAt: now),

      // ── Горизонт ───────────────────────────────────────────────────────────
      DecisionEntry(parentId: f, title: 'М2 — Мастерская как среда разработки',
          type: DecisionType.architecture, status: DecisionStatus.idea,
          notes: 'Claude Code внутри приложения. AI видит граф канваса. Оператор и AI на одном экране.', createdAt: now),
      DecisionEntry(parentId: f, title: 'Канва как порождающая структура',
          type: DecisionType.architecture, status: DecisionStatus.discussion,
          notes: 'Не отображение чата, а его источник. Чат — частный случай линейного пути по графу.', createdAt: now),
      DecisionEntry(parentId: f, title: 'Своя хостинг-инфраструктура',
          type: DecisionType.technology, status: DecisionStatus.rejected,
          notes: 'Отказались. GitHub Actions уже настроен, Android Studio локально нежелателен.', createdAt: now),
    ]);
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
      if (decisions.isEmpty) _seedDecisions();

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
    _box.put('theses', jsonEncode(theses.map((t) => t.toJson()).toList()));
    _box.put('decisions', jsonEncode(decisions.map((d) => d.toJson()).toList()));
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
