import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/edge.dart';
import '../models/node.dart';
import '../models/hex_pos.dart';
import '../models/settings.dart';
import '../services/api_runner.dart';
import '../services/logger.dart';
import '../widgets/node_type_picker.dart';
import '../widgets/node_popup.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/node_panel.dart';
import '../widgets/api_node_sheet.dart';
import '../widgets/log_sheet.dart';
import 'hex_math.dart';
import 'hex_painter.dart';

// ── Snapshot for undo ──────────────────────────────────────────────────────
class _Snap {
  final List<Node> nodes;
  final List<Edge> edges;
  _Snap(List<Node> nodes, List<Edge> edges)
      : nodes = nodes.map((n) => n.copyWith()).toList(),
        edges = edges.map((e) => e.copyWith()).toList();
}

// ── Screen ─────────────────────────────────────────────────────────────────
class HexCanvasScreen extends StatefulWidget {
  const HexCanvasScreen({super.key});

  @override
  State<HexCanvasScreen> createState() => _HexCanvasScreenState();
}

class _HexCanvasScreenState extends State<HexCanvasScreen>
    with TickerProviderStateMixin {
  // ── Canvas transform ─────────────────────────────────────────────────────
  Offset _pan = Offset.zero;
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _basePan = Offset.zero;
  Offset _focalStart = Offset.zero;

  // ── Data ──────────────────────────────────────────────────────────────────
  final List<Node> _nodes = [];
  final List<Edge> _edges = [];
  final GlobalSettings _settings = GlobalSettings();

  // ── Undo ──────────────────────────────────────────────────────────────────
  final List<_Snap> _undoStack = [];
  static const int _maxUndo = 50;

  // ── UI mode ───────────────────────────────────────────────────────────────
  bool _deleteMode = false;

  // ── API run stats (per node id) ───────────────────────────────────────────
  final Map<String, RunStats> _lastRunStats = {};

  // ── Gesture: tap tracking ─────────────────────────────────────────────────
  Offset _tapDownLocal = Offset.zero;

  // ── Gesture: edge routing ─────────────────────────────────────────────────
  String? _routingFromId;
  List<HexPos> _routingPath = []; // hexes traced (after source hex)
  Offset _routingFinger = Offset.zero; // in world coords

  // ── Gesture: move mode ────────────────────────────────────────────────────
  String? _movingNodeId;
  HexPos? _moveOrigin;
  HexPos? _moveTarget;

  // ── Animation: pulse for running nodes ───────────────────────────────────
  late final AnimationController _pulse;
  late final Animation<double> _pulseAnim;

  // ── Frame time ────────────────────────────────────────────────────────────
  final ValueNotifier<double> _frameMs = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _loadState();
  }

  @override
  void dispose() {
    _pulse.dispose();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _frameMs.dispose();
    super.dispose();
  }

  // ── Hive persistence ──────────────────────────────────────────────────────
  Box<String> get _box => Hive.box<String>('state');

  void _saveState() {
    _box.put('nodes', jsonEncode(_nodes.map((n) => n.toJson()).toList()));
    _box.put('edges', jsonEncode(_edges.map((e) => e.toJson()).toList()));
    _box.put('settings', jsonEncode(_settings.toJson()));
  }

  void _loadState() {
    try {
      final nodesRaw = _box.get('nodes');
      if (nodesRaw != null) {
        _nodes.addAll(
          (jsonDecode(nodesRaw) as List)
              .map((j) => Node.fromJson(j as Map<String, dynamic>)),
        );
      }
      final edgesRaw = _box.get('edges');
      if (edgesRaw != null) {
        _edges.addAll(
          (jsonDecode(edgesRaw) as List)
              .map((j) => Edge.fromJson(j as Map<String, dynamic>)),
        );
      }
      final settingsRaw = _box.get('settings');
      if (settingsRaw != null) {
        final s = GlobalSettings.fromJson(
            jsonDecode(settingsRaw) as Map<String, dynamic>);
        _settings.anthropicKey = s.anthropicKey;
        _settings.openAiKey = s.openAiKey;
        _settings.deepSeekKey = s.deepSeekKey;
        _settings.defaultSystemPrompt = s.defaultSystemPrompt;
        _settings.streamingMode = s.streamingMode;
      }
    } catch (_) {
      // Corrupt state — start fresh
    }
  }

  void _onTimings(List<FrameTiming> t) {
    if (t.isNotEmpty) _frameMs.value = t.last.totalSpan.inMicroseconds / 1000.0;
  }

  // ── Undo helpers ──────────────────────────────────────────────────────────
  void _snapshot() {
    _undoStack.add(_Snap(_nodes, _edges));
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final snap = _undoStack.removeLast();
    setState(() {
      _nodes
        ..clear()
        ..addAll(snap.nodes);
      _edges
        ..clear()
        ..addAll(snap.edges);
    });
  }

  // ── Node helpers ──────────────────────────────────────────────────────────
  Node? _nodeAt(HexPos hex) {
    for (final n in _nodes) {
      if (n.position == hex) return n;
    }
    return null;
  }

  Edge? _edgeAt(HexPos hex) {
    for (final e in _edges) {
      final from = _nodeById(e.fromId);
      final to = _nodeById(e.toId);
      if (from == null || to == null) continue;
      final all = [from.position, ...e.waypoints, to.position];
      if (all.contains(hex)) return e;
    }
    return null;
  }

  Node? _nodeById(String id) {
    for (final n in _nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  void _createNode(HexPos hex, NodeType type) {
    _snapshot();
    final node = Node(type: type, position: hex);
    setState(() => _nodes.add(node));
    AppLogger.log('NODE', 'Created ${type.name} node ${node.id.substring(0, 8)}');
    _saveState();
  }

  void _deleteNode(String id) {
    AppLogger.log('NODE', 'Deleted node ${id.substring(0, 8)}');
    _snapshot();
    // Clear this node's slot from any text nodes that received from it
    for (final n in _nodes) {
      if (n.type == NodeType.text && n.received.containsKey(id)) {
        final newReceived = Map<String, String>.from(n.received)..remove(id);
        final newStatus =
            newReceived.isEmpty && n.text.isEmpty ? NodeStatus.idle : n.status;
        _updateNode(n.copyWith(received: newReceived, status: newStatus));
      }
    }
    setState(() {
      _nodes.removeWhere((n) => n.id == id);
      _edges.removeWhere((e) => e.fromId == id || e.toId == id);
    });
    _saveState();
  }

  void _deleteEdge(String id) {
    _snapshot();
    final edge = _edges.where((e) => e.id == id).firstOrNull;
    if (edge != null) {
      final toNode = _nodeById(edge.toId);
      if (toNode != null &&
          toNode.type == NodeType.text &&
          toNode.received.containsKey(edge.fromId)) {
        final newReceived = Map<String, String>.from(toNode.received)
          ..remove(edge.fromId);
        final newStatus = newReceived.isEmpty && toNode.text.isEmpty
            ? NodeStatus.idle
            : toNode.status;
        _updateNode(toNode.copyWith(received: newReceived, status: newStatus));
      }
    }
    setState(() => _edges.removeWhere((e) => e.id == id));
    _saveState();
  }

  void _deleteNodeEdges(String nodeId) {
    _snapshot();
    // Clear slots in downstream text nodes (outgoing edges)
    for (final e in _edges.where((e) => e.fromId == nodeId)) {
      final toNode = _nodeById(e.toId);
      if (toNode != null &&
          toNode.type == NodeType.text &&
          toNode.received.containsKey(nodeId)) {
        final newReceived = Map<String, String>.from(toNode.received)
          ..remove(nodeId);
        final newStatus = newReceived.isEmpty && toNode.text.isEmpty
            ? NodeStatus.idle
            : toNode.status;
        _updateNode(toNode.copyWith(received: newReceived, status: newStatus));
      }
    }
    // Clear received slots of this node if it's a text node (incoming edges removed)
    final thisNode = _nodeById(nodeId);
    if (thisNode != null &&
        thisNode.type == NodeType.text &&
        thisNode.received.isNotEmpty) {
      final newStatus =
          thisNode.text.isEmpty ? NodeStatus.idle : thisNode.status;
      _updateNode(thisNode.copyWith(received: {}, status: newStatus));
    }
    setState(
        () => _edges.removeWhere((e) => e.fromId == nodeId || e.toId == nodeId));
    _saveState();
  }

  void _moveNode(String id, HexPos to) {
    final idx = _nodes.indexWhere((n) => n.id == id);
    if (idx < 0) return;
    _snapshot();
    setState(() {
      _nodes[idx] = _nodes[idx].copyWith(position: to);
      for (int i = 0; i < _edges.length; i++) {
        if (_edges[i].fromId == id || _edges[i].toId == id) {
          _edges[i] = _edges[i].copyWith(waypoints: []);
        }
      }
    });
    _saveState();
  }

  void _createEdge(String fromId, String toId, List<HexPos> waypoints) {
    final sameDir = _edges
        .where((e) => e.fromId == fromId && e.toId == toId)
        .firstOrNull;
    // If edge already exists in this direction — just reroute it
    if (sameDir != null) {
      _snapshot();
      setState(() {
        final idx = _edges.indexOf(sameDir);
        _edges[idx] = sameDir.copyWith(waypoints: waypoints);
      });
      AppLogger.log('EDGE', 'Rerouted ${fromId.substring(0, 8)} → ${toId.substring(0, 8)} (${waypoints.length} waypoints)');
      _saveState();
      return;
    }
    // Block a third edge between the same pair
    final pairCount = _edges
        .where((e) =>
            (e.fromId == fromId && e.toId == toId) ||
            (e.fromId == toId && e.toId == fromId))
        .length;
    if (pairCount >= 2) return;
    _snapshot();
    setState(
        () => _edges.add(Edge(fromId: fromId, toId: toId, waypoints: waypoints)));
    AppLogger.log('EDGE', 'Created ${fromId.substring(0, 8)} → ${toId.substring(0, 8)}');
    // Push source text into target text-node slot on connection
    final fromNode = _nodeById(fromId);
    final toNode = _nodeById(toId);
    if (fromNode != null &&
        toNode != null &&
        toNode.type == NodeType.text) {
      final srcText = _effectiveText(fromNode);
      if (srcText.isNotEmpty) {
        final newReceived = Map<String, String>.from(toNode.received)
          ..[fromId] = srcText;
        _updateNode(toNode.copyWith(
            received: newReceived, status: NodeStatus.done));
        AppLogger.log('SLOT', '${fromId.substring(0, 8)} → ${toId.substring(0, 8)}: pushed ${srcText.length} chars');
      }
    }
    _saveState();
  }

  void _updateNode(Node updated) {
    final idx = _nodes.indexWhere((n) => n.id == updated.id);
    if (idx < 0) return;
    setState(() => _nodes[idx] = updated);
    _saveState();
  }

  // Delegate to the per-node settings stored in api_node_sheet.dart
  ApiNodeSettings _settingsFor(Node node) =>
      nodeApiSettings.putIfAbsent(node.id, () => ApiNodeSettings());

  // Push api node result into all downstream text-node slots (replace slot)
  void _propagateApiResult(Node apiNode) {
    if (apiNode.text.isEmpty) return;
    for (final e in _edges.where((e) => e.fromId == apiNode.id)) {
      final target = _nodeById(e.toId);
      if (target == null || target.type != NodeType.text) continue;
      final newReceived = Map<String, String>.from(target.received)
        ..[apiNode.id] = apiNode.text;
      _updateNode(
          target.copyWith(received: newReceived, status: NodeStatus.done));
      AppLogger.log('SLOT', '${apiNode.id.substring(0, 8)} → ${target.id.substring(0, 8)}: pushed ${apiNode.text.length} chars');
    }
  }

  // Effective text of a node: received slots + own text (for text nodes),
  // or just .text (for api nodes).
  String _effectiveText(Node node) {
    if (node.type == NodeType.api) return node.text;
    final parts = <String>[
      ...node.received.values.where((t) => t.isNotEmpty),
      if (node.text.isNotEmpty) node.text,
    ];
    return parts.join('\n\n');
  }

  // Build input string for an API node: collect effective text from upstream nodes.
  // For text nodes used as token-count display in sheet, returns _effectiveText.
  String _buildInput(Node node) {
    if (node.type == NodeType.text) return _effectiveText(node);
    final parts = _edges
        .where((e) => e.toId == node.id)
        .map((e) => _nodeById(e.fromId))
        .whereType<Node>()
        .map(_effectiveText)
        .where((t) => t.isNotEmpty)
        .toList();
    if (node.text.isNotEmpty) parts.add(node.text);
    return parts.join('\n\n');
  }

  // ── Gesture: scale (pan/zoom + 1-finger routing) ──────────────────────────
  void _onScaleStart(ScaleStartDetails d) {
    // If second finger arrives during routing → cancel routing
    if (d.pointerCount >= 2 && _routingFromId != null) {
      setState(() {
        _routingFromId = null;
        _routingPath = [];
      });
    }
    _focalStart = d.localFocalPoint;
    _baseScale = _scale;
    _basePan = _pan;

    // Start routing only for single finger starting on a node
    if (d.pointerCount == 1 && _movingNodeId == null) {
      final world = screenToWorld(d.localFocalPoint, _pan, _scale);
      final hex = worldToHex(world);
      final node = _nodeAt(hex);
      if (node != null) {
        setState(() {
          _routingFromId = node.id;
          _routingPath = [];
          _routingFinger = world;
        });
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      // Cancel routing if second finger arrives mid-gesture
      if (_routingFromId != null) {
        setState(() {
          _routingFromId = null;
          _routingPath = [];
        });
      }
      // Pan + zoom
      setState(() {
        final newScale = (_baseScale * d.scale).clamp(0.05, 40.0);
        final worldFocal = (_focalStart - _basePan) / _baseScale;
        _scale = newScale;
        _pan = d.localFocalPoint - worldFocal * newScale;
      });
    } else if (_routingFromId != null && _movingNodeId == null) {
      // Edge routing: track hex path
      final world = screenToWorld(d.localFocalPoint, _pan, _scale);
      final hex = worldToHex(world);
      final sourceNode = _nodeById(_routingFromId!);
      setState(() {
        _routingFinger = world;
        if (sourceNode != null && hex != sourceNode.position) {
          if (_routingPath.isEmpty || _routingPath.last != hex) {
            _routingPath = [..._routingPath, hex];
          }
        }
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_routingFromId != null) {
      // Check if finger released on a target node
      final lastHex = _routingPath.isNotEmpty
          ? _routingPath.last
          : null;
      if (lastHex != null) {
        final target = _nodeAt(lastHex);
        if (target != null && target.id != _routingFromId) {
          // Waypoints = all path hexes except the final target hex
          final waypoints = _routingPath.sublist(
              0, _routingPath.length - 1);
          _createEdge(_routingFromId!, target.id, waypoints);
        }
      }
      setState(() {
        _routingFromId = null;
        _routingPath = [];
      });
    }
  }

  // ── Gesture: tap ──────────────────────────────────────────────────────────
  void _onTapDown(TapDownDetails d) => _tapDownLocal = d.localPosition;

  void _onTap() {
    final world = screenToWorld(_tapDownLocal, _pan, _scale);
    final hex = worldToHex(world);

    if (_deleteMode) {
      final node = _nodeAt(hex);
      if (node != null) {
        _deleteNode(node.id);
      } else {
        final edge = _edgeAt(hex);
        if (edge != null) _deleteEdge(edge.id);
      }
      return;
    }

    final node = _nodeAt(hex);
    if (node != null) {
      _showNodePanel(node);
      return;
    }
    final edge = _edgeAt(hex);
    if (edge != null) {
      _showEdgeMenu(edge);
      return;
    }
    // Empty hex hint
    _showHint(hex);
  }

  // ── Gesture: long press (create node or enter move mode) ──────────────────
  void _onLongPressStart(LongPressStartDetails d) {
    final world = screenToWorld(d.localPosition, _pan, _scale);
    final hex = worldToHex(world);
    final node = _nodeAt(hex);
    if (node != null && !_deleteMode) {
      setState(() {
        _movingNodeId = node.id;
        _moveOrigin = node.position;
        _moveTarget = node.position;
      });
    } else if (node == null && !_deleteMode) {
      _showNodeTypePicker(hex);
    }
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    if (_movingNodeId == null) return;
    final world = screenToWorld(d.localPosition, _pan, _scale);
    final hex = worldToHex(world);
    setState(() => _moveTarget = hex);
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    if (_movingNodeId != null && _moveTarget != null) {
      final occupied = _nodeAt(_moveTarget!);
      if (occupied == null || _moveTarget == _moveOrigin) {
        _moveNode(_movingNodeId!, _moveTarget!);
      }
    }
    setState(() {
      _movingNodeId = null;
      _moveOrigin = null;
      _moveTarget = null;
    });
  }

  // ── UI helpers ────────────────────────────────────────────────────────────
  void _showHint(HexPos hex) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Long-press to create a node here'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showNodeTypePicker(HexPos hex) async {
    final type = await showModalBottomSheet<NodeType>(
      context: context,
      builder: (_) => const NodeTypePicker(),
    );
    if (type != null) _createNode(hex, type);
  }

  void _showNodePanel(Node node) {
    final incomingNodes = _edges
        .where((e) => e.toId == node.id)
        .map((e) => _nodeById(e.fromId))
        .whereType<Node>()
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => NodePanel(
        node: node,
        effectiveText: _effectiveText(node),
        inputText: _buildInput(node),
        incomingNodes: incomingNodes,
        lastRunStats: _lastRunStats[node.id],
        onChanged: _updateNode,
        onRun: _runApiNode,
        onClear: () {
          _snapshot();
          final newStatus =
              node.received.isEmpty ? NodeStatus.idle : node.status;
          _updateNode(node.copyWith(text: '', status: newStatus));
        },
        onDeleteEdges: () => _deleteNodeEdges(node.id),
        onDelete: () => _deleteNode(node.id),
      ),
    );
  }

  void _showEdgeMenu(Edge edge) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete edge'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (result == 'delete') _deleteEdge(edge.id);
  }

  void _runApiNode(Node node) async {
    final input = _buildInput(node);
    if (input.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No input text to send')),
      );
      return;
    }

    final apiSettings = _settingsFor(node);
    AppLogger.log('API',
        'Run started: ${apiSettings.provider}/${apiSettings.model} '
        'max=${apiSettings.maxTokens} temp=${apiSettings.temperature} '
        'input=${input.length} chars\n'
        'INPUT: ${input.length > 300 ? input.substring(0, 300) + "…" : input}');

    _updateNode(node.copyWith(status: NodeStatus.running, text: ''));

    await runApiNode(
      node: node,
      input: input,
      settings: _settings,
      apiSettings: apiSettings,
      onChunk: (chunk) {
        if (!mounted) return;
        final current = _nodeById(node.id);
        if (current != null) {
          _updateNode(current.copyWith(text: current.text + chunk));
        }
      },
      onComplete: (result, stats) {
        if (!mounted) return;
        AppLogger.log('API',
            'Complete: in=${stats.inputTokens} out=${stats.outputTokens} tok '
            '${stats.elapsed.inMilliseconds}ms\n'
            'OUTPUT: ${result.length > 300 ? result.substring(0, 300) + "…" : result}');
        final updated = _nodeById(node.id)?.copyWith(
              status: NodeStatus.done,
              text: result,
            );
        if (updated != null) {
          _updateNode(updated);
          _propagateApiResult(updated);
          _lastRunStats[node.id] = stats;
        }
      },
      onError: (err) {
        if (!mounted) return;
        AppLogger.log('API', 'Error: $err');
        final current = _nodeById(node.id);
        if (current != null) {
          _updateNode(current.copyWith(status: NodeStatus.error, text: err));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $err'),
              behavior: SnackBarBehavior.floating),
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            _TopBar(
              deleteMode: _deleteMode,
              canUndo: _undoStack.isNotEmpty,
              onUndo: _undo,
              onToggleDelete: () =>
                  setState(() => _deleteMode = !_deleteMode),
              onSettings: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => SettingsSheet(
                  settings: _settings,
                  onChanged: () => setState(() {}),
                ),
              ),
              onLog: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const LogSheet(),
              ),
            ),
            // Canvas
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _onTapDown,
                onTap: _onTap,
                onLongPressStart: _onLongPressStart,
                onLongPressMoveUpdate: _onLongPressMoveUpdate,
                onLongPressEnd: _onLongPressEnd,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: Stack(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, __) => RepaintBoundary(
                        child: CustomPaint(
                          painter: HexPainter(
                            pan: _pan,
                            scale: _scale,
                            nodes: _nodes,
                            edges: _edges,
                            pulse: _pulseAnim.value,
                            routing: _routingFromId != null
                                ? RoutingState(
                                    fromNodeId: _routingFromId!,
                                    path: _routingPath,
                                    fingerWorld: _routingFinger,
                                  )
                                : null,
                            movingNodeId: _movingNodeId,
                            moveTarget: _moveTarget,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    // Frame time overlay
                    Positioned(
                      top: 8,
                      right: 12,
                      child: ValueListenableBuilder<double>(
                        valueListenable: _frameMs,
                        builder: (_, ms, __) => _FrameOverlay(ms: ms),
                      ),
                    ),
                    // Delete mode banner
                    if (_deleteMode)
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Delete mode — tap to delete',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top bar ────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final bool deleteMode;
  final bool canUndo;
  final VoidCallback onUndo;
  final VoidCallback onToggleDelete;
  final VoidCallback onSettings;
  final VoidCallback onLog;

  const _TopBar({
    required this.deleteMode,
    required this.canUndo,
    required this.onUndo,
    required this.onToggleDelete,
    required this.onSettings,
    required this.onLog,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: canUndo ? onUndo : null,
            tooltip: 'Undo',
          ),
          IconButton(
            icon: Icon(Icons.delete_sweep,
                color: deleteMode ? Colors.red : null),
            onPressed: onToggleDelete,
            tooltip: 'Delete mode',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: onSettings,
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            onPressed: onLog,
            tooltip: 'Log',
          ),
        ],
      ),
    );
  }
}

// ── Frame time overlay ─────────────────────────────────────────────────────
class _FrameOverlay extends StatelessWidget {
  final double ms;
  const _FrameOverlay({required this.ms});

  @override
  Widget build(BuildContext context) {
    final color = ms <= 16.7
        ? Colors.greenAccent
        : ms <= 33.3
            ? Colors.orange
            : Colors.redAccent;
    final fps = ms > 0 ? (1000 / ms).round() : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
            color: color, fontSize: 11, fontFamily: 'monospace',
            decoration: TextDecoration.none),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${ms.toStringAsFixed(1)} ms'),
            Text('$fps fps'),
          ],
        ),
      ),
    );
  }
}
