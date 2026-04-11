import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() {
  runApp(const HexCanvasApp());
}

class HexCanvasApp extends StatelessWidget {
  const HexCanvasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Hex Canvas',
      debugShowCheckedModeBanner: false,
      home: HexCanvasScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class HexCanvasScreen extends StatefulWidget {
  const HexCanvasScreen({super.key});

  @override
  State<HexCanvasScreen> createState() => _HexCanvasScreenState();
}

class _HexCanvasScreenState extends State<HexCanvasScreen> {
  // Viewport transform
  Offset _pan = Offset.zero;
  double _scale = 1.0;

  // Baseline captured at onScaleStart so we derive absolute values each update.
  // This avoids drift from floating-point accumulation.
  double _baseScale = 1.0;
  Offset _basePan = Offset.zero;
  Offset _focalStart = Offset.zero;

  // Frame-time notifier updated by the Flutter frame-timings callback.
  // Using ValueNotifier avoids calling setState on every frame.
  final _frameTimeNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _frameTimeNotifier.dispose();
    super.dispose();
  }

  // FrameTiming.totalSpan = rasterEnd − buildStart (full pipeline latency).
  void _onFrameTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    _frameTimeNotifier.value =
        timings.last.totalSpan.inMicroseconds / 1000.0;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _focalStart = details.focalPoint;
    _baseScale = _scale;
    _basePan = _pan;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Only react to two-finger gestures (pan + pinch-to-zoom).
    if (details.pointerCount < 2) return;

    setState(() {
      final newScale = (_baseScale * details.scale).clamp(0.05, 40.0);

      // Keep the world point under the initial focal point fixed in screen
      // space as both scale and focal position change:
      //   worldFocal = (focalStart − basePan) / baseScale  [constant]
      //   pan = focalPoint − worldFocal × newScale
      final worldFocal = (_focalStart - _basePan) / _baseScale;
      _scale = newScale;
      _pan = details.focalPoint - worldFocal * newScale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: Stack(
          children: [
            // RepaintBoundary lets the frame-time overlay rebuild independently
            // without invalidating the hex painter.
            RepaintBoundary(
              child: CustomPaint(
                painter: HexGridPainter(pan: _pan, scale: _scale),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              top: 48,
              right: 12,
              child: ValueListenableBuilder<double>(
                valueListenable: _frameTimeNotifier,
                builder: (_, ms, __) => _FrameTimeOverlay(ms: ms),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame-time overlay
// ─────────────────────────────────────────────────────────────────────────────

class _FrameTimeOverlay extends StatelessWidget {
  final double ms;
  const _FrameTimeOverlay({required this.ms});

  @override
  Widget build(BuildContext context) {
    // Green ≤ 16.7 ms (60 fps), Orange ≤ 33.3 ms (30 fps), Red > 33.3 ms.
    final Color color;
    if (ms <= 16.7) {
      color = Colors.greenAccent;
    } else if (ms <= 33.3) {
      color = Colors.orange;
    } else {
      color = Colors.redAccent;
    }
    final fps = ms > 0 ? (1000.0 / ms).round() : 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontFamily: 'monospace',
          decoration: TextDecoration.none,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${ms.toStringAsFixed(1)} ms'),
            Text('$fps fps'),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hex-grid painter
// ─────────────────────────────────────────────────────────────────────────────

/// Paints an infinite flat-top hexagonal grid with viewport culling.
///
/// ## Coordinate system (axial, flat-top)
///
///   center(q, r).x = R × 1.5 × q
///   center(q, r).y = R × √3 × (r + q × 0.5)
///
/// where R = [_hexR] is the hex circumradius (point-to-center distance).
///
/// ## Vertex layout (flat-top)
///
///   angle = 0°, 60°, 120°, 180°, 240°, 300°
///   vertex i = (cx + R·cos(60°·i),  cy + R·sin(60°·i))
class HexGridPainter extends CustomPainter {
  final Offset pan;
  final double scale;

  static const double _hexR = 40.0; // circumradius, world-space pixels
  static const double _sqrt3 = 1.7320508075688772935;

  // Pre-computed vertex offsets for one flat-top hex centred at origin.
  static final List<double> _vx =
      List.generate(6, (i) => _hexR * math.cos(math.pi / 3.0 * i));
  static final List<double> _vy =
      List.generate(6, (i) => _hexR * math.sin(math.pi / 3.0 * i));

  const HexGridPainter({required this.pan, required this.scale});

  @override
  bool shouldRepaint(HexGridPainter old) =>
      pan != old.pan || scale != old.scale;

  @override
  void paint(Canvas canvas, Size size) {
    // Apply viewport transform so we can work in world space below.
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale);

    // ── World-space viewport bounds ──────────────────────────────────────────
    // screen → world:  world = (screen - pan) / scale
    final wl = -pan.dx / scale;
    final wt = -pan.dy / scale;
    final wr = (size.width - pan.dx) / scale;
    final wb = (size.height - pan.dy) / scale;

    // ── Grid step sizes ──────────────────────────────────────────────────────
    //  Flat-top column step (horizontal distance between adjacent column centres):
    //    colStep = R × 3/2
    //  Row step (vertical distance between row centres in the same column):
    //    rowStep = R × √3
    const colStep = _hexR * 1.5;
    const rowStep = _hexR * _sqrt3;

    // ── AABB half-extents for a single hex ──────────────────────────────────
    //  Flat-top: width span = R left and right of centre → halfW = R
    //            height span = R·√3/2 above and below centre → halfH ≈ 0.866R
    const halfW = _hexR;
    const halfH = _hexR * _sqrt3 * 0.5;

    // ── Axial column range ───────────────────────────────────────────────────
    final qMin = ((wl - halfW) / colStep).floor() - 1;
    final qMax = ((wr + halfW) / colStep).ceil() + 1;

    // ── Draw ─────────────────────────────────────────────────────────────────
    final linePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      // Keep stroke at exactly 1 screen-pixel regardless of zoom level.
      ..strokeWidth = 1.0 / scale
      ..isAntiAlias = true;

    // Accumulate all visible hex outlines into one Path for a single draw call.
    final path = Path();

    for (int q = qMin; q <= qMax; q++) {
      final cx = _hexR * 1.5 * q;
      final qHalf = q * 0.5; // q/2 used in y-formula and row bounds

      // Per-column row range derived from world y bounds:
      //   r = cy/rowStep − q/2   ⟹   rMin/rMax from wt/wb
      final rMin = ((wt / rowStep) - qHalf).floor() - 1;
      final rMax = ((wb / rowStep) - qHalf).ceil() + 1;

      for (int r = rMin; r <= rMax; r++) {
        final cy = rowStep * (r + qHalf);

        // AABB cull: skip hexes entirely outside the viewport.
        if (cx + halfW < wl || cx - halfW > wr ||
            cy + halfH < wt || cy - halfH > wb) {
          continue;
        }

        // Trace hex outline (close() reconnects last vertex to first).
        path.moveTo(cx + _vx[0], cy + _vy[0]);
        for (int v = 1; v < 6; v++) {
          path.lineTo(cx + _vx[v], cy + _vy[v]);
        }
        path.close();
      }
    }

    canvas.drawPath(path, linePaint);

    // ── Origin marker ────────────────────────────────────────────────────────
    // Drawn in world space so it scales with zoom (radius = 5 world-px).
    // At scale 1× it is 5 screen-px; at 4× it becomes 20 screen-px.
    canvas.drawCircle(
      Offset.zero,
      5.0,
      Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill,
    );

    canvas.restore();
  }
}
