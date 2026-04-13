import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/app_model.dart';
import '../models/canvas_data.dart';
import '../models/node.dart';
import 'hex_math.dart';
import 'hex_painter.dart';

/// Full-screen canvas view backed by AppModel.
/// Provides: hex grid, pan/zoom, FPS overlay, node/edge rendering,
/// chain-path amber highlight, multi-canvas support.
class CanvasView extends StatefulWidget {
  final AppModel model;
  final bool isActive;
  const CanvasView({super.key, required this.model, this.isActive = false});

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView>
    with SingleTickerProviderStateMixin {
  // ── Transform ────────────────────────────────────────────────────────────
  Offset _pan = Offset.zero;
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _basePan = Offset.zero;
  Offset _focalStart = Offset.zero;
  Size _canvasSize = Size.zero;

  // ── Canvas tracking ───────────────────────────────────────────────────────
  String? _lastCanvasId;

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
    widget.model.addListener(_onModelChanged);
    _loadPanZoom();
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModelChanged);
    _pulse.dispose();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _frameMs.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CanvasView old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Only fit if the canvas hasn't been panned/zoomed manually
        final c = widget.model.activeCanvas;
        if (c.panX == 0 && c.panY == 0 && c.zoom == 1.0) {
          _fitAll();
        }
      });
    }
  }

  void _onModelChanged() {
    final newId = widget.model.activeCanvasId;
    if (_lastCanvasId != null && _lastCanvasId != newId) {
      _loadPanZoom();
    }
  }

  void _loadPanZoom() {
    final canvas = widget.model.activeCanvas;
    _lastCanvasId = canvas.id;
    if (canvas.panX == 0 && canvas.panY == 0 && canvas.zoom == 1.0) {
      // New canvas or never panned — fit all after layout
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
    } else {
      setState(() {
        _pan = Offset(canvas.panX, canvas.panY);
        _scale = canvas.zoom;
      });
    }
  }

  void _onTimings(List<FrameTiming> t) {
    if (t.isNotEmpty) _frameMs.value = t.last.totalSpan.inMicroseconds / 1000.0;
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _centerOnOrigin() {
    setState(() {
      _pan = Offset(_canvasSize.width / 2, _canvasSize.height / 2);
    });
    _savePanZoom();
  }

  void _fitAll() {
    final nodes = widget.model.nodes;
    if (nodes.isEmpty) {
      _centerOnOrigin();
      return;
    }
    final centers = nodes.map((n) => hexToWorld(n.position)).toList();
    double left = centers.first.dx, right = centers.first.dx;
    double top = centers.first.dy, bottom = centers.first.dy;
    for (final c in centers) {
      if (c.dx < left) left = c.dx;
      if (c.dx > right) right = c.dx;
      if (c.dy < top) top = c.dy;
      if (c.dy > bottom) bottom = c.dy;
    }
    const pad = ringR + ringW / 2 + 40.0;
    left -= pad;
    right += pad;
    top -= pad;
    bottom += pad;
    final sw = _canvasSize.width;
    final sh = _canvasSize.height;
    if (sw <= 0 || sh <= 0) return;
    final newScale = (sw / (right - left)).clamp(0.05, 40.0) <
            (sh / (bottom - top)).clamp(0.05, 40.0)
        ? (sw / (right - left)).clamp(0.05, 40.0)
        : (sh / (bottom - top)).clamp(0.05, 40.0);
    final worldCx = (left + right) / 2;
    final worldCy = (top + bottom) / 2;
    setState(() {
      _scale = newScale;
      _pan = Offset(sw / 2 - worldCx * newScale, sh / 2 - worldCy * newScale);
    });
    _savePanZoom();
  }

  void _savePanZoom() {
    widget.model.saveCanvasPanZoom(_pan.dx, _pan.dy, _scale);
  }

  // ── Gestures ──────────────────────────────────────────────────────────────
  void _onScaleStart(ScaleStartDetails d) {
    _focalStart = d.localFocalPoint;
    _baseScale = _scale;
    _basePan = _pan;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      final newScale = (_baseScale * d.scale).clamp(0.05, 40.0);
      if (d.pointerCount >= 2) {
        final worldFocal = (_focalStart - _basePan) / _baseScale;
        _scale = newScale;
        _pan = d.localFocalPoint - worldFocal * newScale;
      } else {
        _pan = _basePan + (d.localFocalPoint - _focalStart);
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _savePanZoom();
  }

  // ── Canvas switcher ────────────────────────────────────────────────────────
  void _showCanvasSwitcher() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CanvasSwitcherSheet(model: widget.model),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CanvasToolbar(
          onFitAll: _fitAll,
          onCenter: _centerOnOrigin,
          onCanvasTap: _showCanvasSwitcher,
          onNewCanvas: () => widget.model.createCanvas(),
          model: widget.model,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (_, constraints) {
              _canvasSize = constraints.biggest;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                child: ListenableBuilder(
                  listenable: widget.model,
                  builder: (_, __) {
                    final chainSet = Set<String>.from(widget.model.chainPath);
                    return Stack(
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnim,
                          builder: (_, __) => RepaintBoundary(
                            child: CustomPaint(
                              painter: HexPainter(
                                pan: _pan,
                                scale: _scale,
                                nodes: widget.model.nodes,
                                edges: widget.model.edges,
                                pulse: _pulseAnim.value,
                                selectedIds: Set.unmodifiable(chainSet),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 12,
                          child: ValueListenableBuilder<double>(
                            valueListenable: _frameMs,
                            builder: (_, ms, __) => _FrameOverlay(ms: ms),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────

class _CanvasToolbar extends StatelessWidget {
  final VoidCallback onFitAll;
  final VoidCallback onCenter;
  final VoidCallback onCanvasTap;
  final VoidCallback onNewCanvas;
  final AppModel model;

  const _CanvasToolbar({
    required this.onFitAll,
    required this.onCenter,
    required this.onCanvasTap,
    required this.onNewCanvas,
    required this.model,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (_, __) => Material(
        elevation: 1,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.undo, size: 20),
              tooltip: model.canUndo
                  ? 'Отменить: ${model.undoStack.last.description}'
                  : 'Нечего отменять',
              onPressed: model.canUndo ? model.undo : null,
              color: model.canUndo ? null : Colors.grey[400],
            ),
            IconButton(
              icon: const Icon(Icons.redo, size: 20),
              tooltip: model.canRedo ? 'Повторить' : 'Нечего повторять',
              onPressed: model.canRedo ? model.redo : null,
              color: model.canRedo ? null : Colors.grey[400],
            ),
            const VerticalDivider(width: 8),
            IconButton(
              icon: const Icon(Icons.zoom_out_map),
              tooltip: 'Fit all',
              onPressed: onFitAll,
            ),
            IconButton(
              icon: const Icon(Icons.center_focus_strong),
              tooltip: 'Centre on origin',
              onPressed: onCenter,
            ),
            const VerticalDivider(width: 8),
            // Canvas name — tap to switch
            Expanded(
              child: InkWell(
                onTap: onCanvasTap,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.layers_outlined, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          model.activeCanvas.name.isEmpty
                              ? 'Canvas ${model.canvases.indexOf(model.activeCanvas) + 1}'
                              : model.activeCanvas.name,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (model.canvases.length > 1) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${model.canvases.indexOf(model.activeCanvas) + 1}/${model.canvases.length}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                      const Icon(Icons.expand_more, size: 16),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              tooltip: 'Новая канва',
              onPressed: onNewCanvas,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Canvas switcher sheet ─────────────────────────────────────────────────

class _CanvasSwitcherSheet extends StatefulWidget {
  final AppModel model;
  const _CanvasSwitcherSheet({required this.model});

  @override
  State<_CanvasSwitcherSheet> createState() => _CanvasSwitcherSheetState();
}

class _CanvasSwitcherSheetState extends State<_CanvasSwitcherSheet> {
  Future<void> _rename(CanvasData canvas) async {
    final ctrl = TextEditingController(text: canvas.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Сохранить')),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty) {
      widget.model.renameCanvas(canvas.id, result);
      if (mounted) setState(() {});
    }
  }

  Future<void> _delete(CanvasData canvas) async {
    if (widget.model.canvases.length <= 1) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить канву?'),
        content: Text(
            'Канва "${canvas.name}" будет удалена. Ноды останутся в графе.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      widget.model.deleteCanvas(canvas.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final canvases = widget.model.canvases;
    final activeId = widget.model.activeCanvasId;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              const Text('Канвы',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Новая'),
                onPressed: () {
                  widget.model.createCanvas();
                  Navigator.pop(context);
                },
              ),
            ]),
          ),
          ListView.builder(
            shrinkWrap: true,
            itemCount: canvases.length,
            itemBuilder: (_, i) {
              final canvas = canvases[i];
              final isActive = canvas.id == activeId;
              return ListTile(
                leading: Icon(
                  Icons.layers_outlined,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[500],
                ),
                title: Text(
                  canvas.name.isEmpty ? 'Canvas ${i + 1}' : canvas.name,
                  style: TextStyle(
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                subtitle: Text(
                  '${canvas.nodeIds.length} нод',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                trailing: isActive
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () {
                  widget.model.switchCanvas(canvas.id);
                  Navigator.pop(context);
                },
                onLongPress: () => _showOptions(canvas),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showOptions(CanvasData canvas) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Переименовать'),
              onTap: () {
                Navigator.pop(context);
                _rename(canvas);
              },
            ),
            if (widget.model.canvases.length > 1)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Удалить',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _delete(canvas);
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ── FPS overlay ───────────────────────────────────────────────────────────

class _FrameOverlay extends StatelessWidget {
  final double ms;
  const _FrameOverlay({required this.ms});

  @override
  Widget build(BuildContext context) {
    final fps = ms > 0 ? (1000 / ms).round() : 0;
    final color = fps >= 55
        ? Colors.green
        : fps >= 30
            ? Colors.orange
            : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$fps fps',
        style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace'),
      ),
    );
  }
}
