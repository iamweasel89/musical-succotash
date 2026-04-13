import 'hex_pos.dart';

// Flat-top axial hex: 6 directions
// Order: up(0), upper-right(1), lower-right(2), down(3), lower-left(4), upper-left(5)
const _dq = [0, 1, 1, 0, -1, -1];
const _dr = [-1, -1, 0, 1, 1, 0];

/// Step [steps] times in direction [dir] from [pos].
HexPos hexStep(HexPos pos, int dir, [int steps = 1]) {
  final d = dir % 6;
  return HexPos(pos.q + _dq[d] * steps, pos.r + _dr[d] * steps);
}

/// Forward directions from [dir] in priority order:
/// straight, right(+60°), left(−60°), far-right(+120°), far-left(−120°).
List<int> forwardDirs(int dir) => [
      dir % 6,
      (dir + 1) % 6,
      (dir + 5) % 6,
      (dir + 2) % 6,
      (dir + 4) % 6,
    ];

/// Next position for a straight chain continuation (1 step in [growthDir]).
HexPos chainNextPos(HexPos from, int growthDir) => hexStep(from, growthDir);

class BranchSlot {
  final HexPos pos;
  final int dir;
  const BranchSlot(this.pos, this.dir);
}

/// Find start position and direction for a new branch from [from].
///
/// Branches start 2 steps away to guarantee non-adjacency with siblings.
BranchSlot nextBranchSlot({
  required HexPos from,
  required int parentGrowthDir,
  required Set<int> usedChildDirs,
  required Set<HexPos> occupied,
}) {
  final candidates = forwardDirs(parentGrowthDir);

  for (int dist = 2; dist <= 10; dist++) {
    for (final dir in candidates) {
      if (usedChildDirs.contains(dir)) continue;
      final pos = hexStep(from, dir, dist);
      if (!occupied.contains(pos)) {
        return BranchSlot(pos, dir);
      }
    }
  }

  return BranchSlot(hexStep(from, parentGrowthDir, 2), parentGrowthDir);
}
