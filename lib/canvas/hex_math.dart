import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../models/hex_pos.dart';

// ── Constants ──────────────────────────────────────────────────────────────
const double hexR = 40.0;  // circumradius (world-space pixels)
const double nodeR = 10.0;  // node circle radius
const double ringR = 14.0;  // status ring centre
const double ringW = 7.5;   // status ring stroke width (inner≈10, outer≈17.75)
const double sqrt3 = 1.7320508075688772935;

// ── Pre-computed vertex offsets for flat-top hex ───────────────────────────
final List<Offset> hexVerts = List.generate(
  6,
  (i) => Offset(hexR * math.cos(math.pi / 3 * i),
      hexR * math.sin(math.pi / 3 * i)),
);

// ── Coordinate conversions ─────────────────────────────────────────────────

/// World-space centre of axial hex (q, r).
///   x = R·1.5·q
///   y = R·√3·(r + q/2)
Offset hexToWorld(HexPos pos) => Offset(
      hexR * 1.5 * pos.q,
      hexR * sqrt3 * (pos.r + pos.q * 0.5),
    );

/// Nearest hex to a world-space point (cube rounding).
HexPos worldToHex(Offset world) {
  final qf = world.dx / (hexR * 1.5);
  final rf = world.dy / (hexR * sqrt3) - qf * 0.5;

  // Convert to cube
  double x = qf, z = rf, y = -x - z;

  int rx = x.round(), ry = y.round(), rz = z.round();

  final xd = (rx - x).abs(), yd = (ry - y).abs(), zd = (rz - z).abs();
  if (xd > yd && xd > zd) {
    rx = -ry - rz;
  } else if (yd > zd) {
    ry = -rx - rz;
  } else {
    rz = -rx - ry;
  }
  return HexPos(rx, rz);
}

/// Screen/local position → world position given current pan/scale.
Offset screenToWorld(Offset screen, Offset pan, double scale) =>
    (screen - pan) / scale;

/// World position → screen/local position.
Offset worldToScreen(Offset world, Offset pan, double scale) =>
    world * scale + pan;
