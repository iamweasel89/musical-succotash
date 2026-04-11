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
import '../widgets/node_type_picker.dart';
import '../widgets/node_popup.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/text_node_sheet.dart';
import '../widgets/api_node_sheet.dart';
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
    setState(() => _nodes.add(Node(type: type, position: hex)));
    _saveState();
  }

  void _deleteNode(String id) {
    _snapshot();
    setState(() {
      _nodes.removeWhere((n) => n.id == id);
      _edges.removeWhere((e) => e.fromId == id || e.toId == id);
    });
    _saveState();
  }

  void _deleteEdge(String id) {
    _snapshot();
    setState(() => _edges.removeWhere((e) => e.id == id));
    _saveState();
  }

  void _deleteNodeEdges(String nodeId) {
    _snapshot();
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
    final existing = _edges
        .where((e) =>
            (e.fromId == fromId && e.toId == toId) ||
            (e.fromId == toId && e.toId == fromId))
        .toList();
    if (existing.length >= 2) return;
    if (existing.any((e) => e.fromId == fromId && e.toId == toId)) return;
    _snapshot();
    setState(
        () => _edges.add(Edge(fromId: fromId, toId: toId, waypoints: waypoints)));
    // Push source text into target text-node on connection
    final fromNode = _nodeById(fromId);
    final toNode = _nodeById(toId);
    if (fromNode != null &&
        fromNode.text.isNotEmpty &&
        toNode != null &&
        toNode.type == NodeType.text) {
      final combined = toNode.text.isEmpty
          ? fromNode.text
          : '${toNode.text}\n\n${fromNode.text}';
      _updateNode(toNode.copyWith(text: combined, status: NodeStatus.done));
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

  // Push api node result into all downstream text nodes (concatenate)
  void _propagateApiResult(Node apiNode) {
    if (apiNode.text.isEmpty) return;
    for (final e in _edges.where((e) => e.fromId == apiNode.id)) {
      final target = _nodeById(e.toId);
      if (target == null || target.type != NodeType.text) continue;
      final combined = target.text.isEmpty
          ? apiNode.text
          : '${target.text}\n\n${apiNode.text}';
      _updateNode(target.copyWith(text: combined, status: NodeStatus.done));
    }
  }

  // Build concatenated input text for a node (incoming texts joined with \n\n)
  String _buildInput(Node node) {
    final incoming = _edges
        .where((e) => e.toId == node.id)
        .map((e) => _nodeById(e.fromId))
        .whereType<Node>()
        .toList();
    if (incoming.isEmpty) return node.text;
    final parts = incoming.map((n) => n.text).where((t) => t.isNotEmpty);
    final joined = parts.join('\n\n');
    final own = node.text.trimLeft();
    if (own.isEmpty) return joined;
    return joined.isEmpty ? own : '$joined\n\n$own';
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
      _showNodePopup(node);
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

  void _showNodePopup(Node node) async {
    final worldCenter = hexToWorld(node.position);
    final screenCenter = worldToScreen(worldCenter, _pan, _scale);

    final box = context.findRenderObject()! as RenderBox;
    final global = box.localToGlobal(screenCenter);

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          global.dx, global.dy - 80, global.dx + 1, global.dy),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('Copy text')),
        const PopupMenuItem(value: 'settings', child: Text('Settings')),
        if (node.type == NodeType.text)
          const PopupMenuItem(value: 'clear', child: Text('Clear text')),
        const PopupMenuItem(value: 'del_edges', child: Text('Delete all edges')),
        const PopupMenuItem(value: 'delete', child: Text('Delete node')),
        if (node.type == NodeType.api)
          const PopupMenuItem(value: 'run', child: Text('Run')),
      ],
    );

    switch (result) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: node.text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied to clipboard'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case 'settings':
        _showNodeSettings(node);
      case 'clear':
        _snapshot();
        _updateNode(node.copyWith(text: '', status: NodeStatus.idle));
      case 'del_edges':
        _deleteNodeEdges(node.id);
      case 'delete':
        _deleteNode(node.id);
      case 'run':
        _runApiNode(node);
    }
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

  void _showNodeSettings(Node node) {
    if (node.type == NodeType.text) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => TextNodeSheet(
          node: node,
          incomingNodes: _edges
              .where((e) => e.toId == node.id)
              .map((e) => _nodeById(e.fromId))
              .whereType<Node>()
              .toList(),
          buildInput: _buildInput,
          onChanged: _updateNode,
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => ApiNodeSheet(
          node: node,
          settings: _settings,
          buildInput: _buildInput,
          onChanged: _updateNode,
          onRun: _runApiNode,
          lastRunStats: _lastRunStats[node.id],
        ),
      );
    }
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

    _updateNode(node.copyWith(status: NodeStatus.running, text: ''));

    final apiSettings = _settingsFor(node);

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
        final updated = _nodeById(node.id)?.copyWith(
              status: NodeStatus.done,
              text: result,
            );
        if (updated != null) {
          _updateNode(updated);
          _propagateApiResult(updated);
          // Store last run stats for the sheet to display
          _lastRunStats[node.id] = stats;
        }
      },
      onError: (err) {
        if (!mounted) return;
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

  const _TopBar({
    required this.deleteMode,
    required this.canUndo,
    required this.onUndo,
    required this.onToggleDelete,
    required this.onSettings,
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
