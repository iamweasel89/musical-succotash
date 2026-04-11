import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/edge.dart';
import '../models/node.dart';
import '../models/hex_pos.dart';
import 'hex_math.dart';

// ── Routing preview state passed to painter ────────────────────────────────
class RoutingState {
  final String fromNodeId;
  final List<HexPos> path; // hexes traced so far (excluding source hex)
  final Offset fingerWorld; // current finger in world coords

  const RoutingState({
    required this.fromNodeId,
    required this.path,
    required this.fingerWorld,
  });
}

// ── Colours ────────────────────────────────────────────────────────────────
Color nodeColor(NodeType t) =>
    t == NodeType.text ? const Color(0xFF2196F3) : const Color(0xFFF44336);

Color statusRingColor(NodeStatus s, double pulse) {
  switch (s) {
    case NodeStatus.idle:
      return const Color(0xFFCCCCCC);
    case NodeStatus.running:
      return Color.lerp(const Color(0xFFFF9800), Colors.white, pulse)!;
    case NodeStatus.done:
      return const Color(0xFF4CAF50);
    case NodeStatus.error:
      return const Color(0xFFF44336);
  }
}

// ── Painter ────────────────────────────────────────────────────────────────
class HexPainter extends CustomPainter {
  final Offset pan;
  final double scale;
  final List<Node> nodes;
  final List<Edge> edges;
  final double pulse; // 0‥1 for running-ring animation
  final RoutingState? routing;
  final String? movingNodeId;
  final HexPos? moveTarget;

  const HexPainter({
    required this.pan,
    required this.scale,
    required this.nodes,
    required this.edges,
    required this.pulse,
    this.routing,
    this.movingNodeId,
    this.moveTarget,
  });

  @override
  bool shouldRepaint(HexPainter o) =>
      pan != o.pan ||
      scale != o.scale ||
      nodes != o.nodes ||
      edges != o.edges ||
      pulse != o.pulse ||
      routing != o.routing ||
      movingNodeId != o.movingNodeId ||
      moveTarget != o.moveTarget;

  // ── paint ─────────────────────────────────────────────────────────────────
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale);

    // World-space viewport bounds
    final wl = -pan.dx / scale;
    final wt = -pan.dy / scale;
    final wr = (size.width - pan.dx) / scale;
    final wb = (size.height - pan.dy) / scale;

    // Build node map once
    final nodeMap = <String, Node>{for (final n in nodes) n.id: n};

    // ① Hex grid
    _drawGrid(canvas, wl, wt, wr, wb);

    // ② Intersection highlights (permanent pink hexes)
    final intersections = _intersections(edges, nodeMap);
    _drawHexFills(canvas, intersections, const Color(0xAAFFB6C1));

    // ③ Routing path highlight
    if (routing != null) {
      _drawHexFills(canvas, routing!.path.toSet(), const Color(0x44000000));
    }

    // ④ Edges (behind nodes)
    for (final e in edges) {
      _drawEdge(canvas, e, nodeMap);
    }

    // ⑤ Routing preview edge
    if (routing != null) {
      _drawRoutingPreview(canvas, routing!, nodeMap);
    }

    // ⑥ Nodes
    for (final node in nodes) {
      final isMoving = node.id == movingNodeId;
      final pos =
          (isMoving && moveTarget != null) ? moveTarget! : node.position;
      _drawNode(canvas, node, pos, isMoving);
    }

    // ⑦ Origin dot
    canvas.drawCircle(
      Offset.zero,
      5.0,
      Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill,
    );

    canvas.restore();
  }

  // ── Hex grid ──────────────────────────────────────────────────────────────
  void _drawGrid(Canvas canvas, double wl, double wt, double wr, double wb) {
    const colStep = hexR * 1.5;
    const rowStep = hexR * sqrt3;
    const halfW = hexR, halfH = hexR * sqrt3 * 0.5;

    final qMin = ((wl - halfW) / colStep).floor() - 1;
    final qMax = ((wr + halfW) / colStep).ceil() + 1;

    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / scale
      ..isAntiAlias = true;

    final path = Path();
    for (int q = qMin; q <= qMax; q++) {
      final cx = hexR * 1.5 * q;
      final qh = q * 0.5;
      final rMin = ((wt / rowStep) - qh).floor() - 1;
      final rMax = ((wb / rowStep) - qh).ceil() + 1;
      for (int r = rMin; r <= rMax; r++) {
        final cy = rowStep * (r + qh);
        if (cx + halfW < wl || cx - halfW > wr ||
            cy + halfH < wt || cy - halfH > wb) continue;
        path.moveTo(cx + hexVerts[0].dx, cy + hexVerts[0].dy);
        for (int v = 1; v < 6; v++) {
          path.lineTo(cx + hexVerts[v].dx, cy + hexVerts[v].dy);
        }
        path.close();
      }
    }
    canvas.drawPath(path, paint);
  }

  // ── Hex fills (intersections / routing) ──────────────────────────────────
  void _drawHexFills(Canvas canvas, Set<HexPos> hexes, Color color) {
    if (hexes.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    for (final pos in hexes) {
      final c = hexToWorld(pos);
      path.moveTo(c.dx + hexVerts[0].dx, c.dy + hexVerts[0].dy);
      for (int v = 1; v < 6; v++) {
        path.lineTo(c.dx + hexVerts[v].dx, c.dy + hexVerts[v].dy);
      }
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  // ── Intersection detection ────────────────────────────────────────────────
  Set<HexPos> _intersections(List<Edge> edges, Map<String, Node> nodeMap) {
    if (edges.length < 2) return {};
    final nodeHexes = nodeMap.values.map((n) => n.position).toSet();
    final hexEdgeCount = <HexPos, int>{};

    for (final e in edges) {
      final from = nodeMap[e.fromId]?.position;
      final to = nodeMap[e.toId]?.position;
      if (from == null || to == null) continue;
      final allPos = [from, ...e.waypoints, to];
      for (final pos in allPos) {
        hexEdgeCount[pos] = (hexEdgeCount[pos] ?? 0) + 1;
      }
    }
    return hexEdgeCount.entries
        .where((e) => e.value >= 2 && !nodeHexes.contains(e.key))
        .map((e) => e.key)
        .toSet();
  }

  // ── Edge rendering ────────────────────────────────────────────────────────
  void _drawEdge(Canvas canvas, Edge edge, Map<String, Node> nodeMap,
      {double opacity = 1.0}) {
    final from = nodeMap[edge.fromId];
    final to = nodeMap[edge.toId];
    if (from == null || to == null) return;

    final points = [
      hexToWorld(from.position),
      ...edge.waypoints.map(hexToWorld),
      hexToWorld(to.position),
    ];

    final color = nodeColor(from.type).withOpacity(opacity);
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0 / scale
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, linePaint);

    // Arrowhead at target (offset to ring edge so it doesn't overlap node)
    final last = points[points.length - 2];
    final tip = points.last;
    final dir = tip - last;
    final len = dir.distance;
    if (len > 0) {
      final unit = dir / len;
      _drawArrow(canvas, tip - unit * ringR, unit, color);
    }
  }

  void _drawArrow(Canvas canvas, Offset tip, Offset unit, Color color) {
    const s = 10.0; // arrowhead size in world px
    final angle = math.atan2(unit.dy, unit.dx);
    final p1 = tip +
        Offset(-s * math.cos(angle - math.pi / 6),
            -s * math.sin(angle - math.pi / 6));
    final p2 = tip +
        Offset(-s * math.cos(angle + math.pi / 6),
            -s * math.sin(angle + math.pi / 6));
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  void _drawRoutingPreview(
      Canvas canvas, RoutingState routing, Map<String, Node> nodeMap) {
    final fromNode = nodeMap[routing.fromNodeId];
    if (fromNode == null) return;

    final start = hexToWorld(fromNode.position);
    final waypoints = routing.path.map(hexToWorld).toList();
    final end = routing.fingerWorld;

    final color = nodeColor(fromNode.type).withOpacity(0.5);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0 / scale
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(start.dx, start.dy);
    for (final wp in waypoints) {
      path.lineTo(wp.dx, wp.dy);
    }
    path.lineTo(end.dx, end.dy);
    canvas.drawPath(path, paint);
  }

  // ── Node rendering ────────────────────────────────────────────────────────
  void _drawNode(Canvas canvas, Node node, HexPos pos, bool lifted) {
    final c = hexToWorld(pos);

    if (lifted) {
      // Shadow
      final shadowPath = Path()
        ..addOval(Rect.fromCircle(center: c + Offset(4 / scale, 4 / scale),
            radius: nodeR + 2));
      canvas.drawShadow(shadowPath, Colors.black54, 8.0, false);
    }

    // Status ring
    canvas.drawCircle(
      c,
      ringR,
      Paint()
        ..color = statusRingColor(node.status, pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringW
        ..isAntiAlias = true,
    );

    // Filled circle
    canvas.drawCircle(
      c,
      nodeR,
      Paint()
        ..color = nodeColor(node.type)
        ..style = PaintingStyle.fill,
    );

    // Subtle white inner border
    canvas.drawCircle(
      c,
      nodeR,
      Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Name label
    if (node.name.isNotEmpty) {
      _drawLabel(canvas, c, node.name);
    }
  }

  void _drawLabel(Canvas canvas, Offset center, String text) {
    final fs = 11.0 / scale;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fs,
          color: Colors.black87,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.none,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        center + Offset(-tp.width / 2, (nodeR + 6) / scale));
  }
}
