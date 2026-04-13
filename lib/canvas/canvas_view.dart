import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/app_model.dart';
import '../models/node.dart';
import 'hex_math.dart';
import 'hex_painter.dart';

/// Full-screen canvas view backed by AppModel.
/// Provides: hex grid, pan/zoom, FPS overlay, node/edge rendering,
/// chain-path amber highlight.
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
  }

  @override
  void dispose() {
    _pulse.dispose();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _frameMs.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CanvasView old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
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
        // Pinch: zoom + pan
        final worldFocal = (_focalStart - _basePan) / _baseScale;
        _scale = newScale;
        _pan = d.localFocalPoint - worldFocal * newScale;
      } else {
        // Single finger: pan only
        _pan = _basePan + (d.localFocalPoint - _focalStart);
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        _CanvasToolbar(
          onFitAll: _fitAll,
          onCenter: _centerOnOrigin,
        ),
        // Canvas area
        Expanded(
          child: LayoutBuilder(
            builder: (_, constraints) {
              _canvasSize = constraints.biggest;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                child: ListenableBuilder(
                  listenable: widget.model,
                  builder: (_, __) {
                    final chainSet = Set<String>.from(widget.model.chainPath);
                    return Stack(
                      children: [
                        // Painter
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
                        // FPS overlay
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

  const _CanvasToolbar({required this.onFitAll, required this.onCenter});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      child: Row(
        children: [
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
        ],
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
