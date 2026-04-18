import '../../models/app_model.dart';
import '../../models/hex_layout.dart';
import '../../models/hex_pos.dart';
import '../../models/node.dart';

// Хелперы размещения новых нод в гекс-гриде активной канвы. Чистые функции:
// берут данные через параметры, не владеют состоянием. Используются в чате
// при отправке сообщения, создании ответвления, при action'е chat.addNote.

// Множество занятых гекс-позиций в активной канве.
Set<HexPos> occupiedPositions(AppModel model) {
  final activeIds = model.activeCanvas.nodeIds.toSet();
  return model.nodes
      .where((n) => activeIds.contains(n.id))
      .map((n) => n.position)
      .toSet();
}

// Слот продолжения цепочки — новый узел идёт в том же направлении роста.
BranchSlot continuationSlot(Node lastNode) {
  final pos = chainNextPos(lastNode.position, lastNode.growthDir);
  return BranchSlot(pos, lastNode.growthDir);
}

// Слот для ответвления от узла с детьми — выбираем свободное направление.
BranchSlot branchSlot({
  required Node branchPoint,
  required AppModel model,
}) {
  final usedDirs = model.activeCanvasEdges
      .where((e) => e.fromId == branchPoint.id)
      .map((e) => model.nodeById(e.toId))
      .whereType<Node>()
      .map((n) => n.growthDir)
      .toSet();
  return nextBranchSlot(
    from: branchPoint.position,
    parentGrowthDir: branchPoint.growthDir,
    usedChildDirs: usedDirs,
    occupied: occupiedPositions(model),
  );
}

// Если выбранная позиция занята — идём дальше в том же направлении до
// первой свободной (или возвращаемся к шагу 2 если все 10 шагов заняты).
HexPos fallbackPos(HexPos from, int dir, Set<HexPos> occ) {
  for (int s = 2; s <= 10; s++) {
    final p = hexStep(from, dir, s);
    if (!occ.contains(p)) return p;
  }
  return hexStep(from, dir, 2);
}
