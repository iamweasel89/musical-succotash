import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:hex_canvas_mobile/models/app_model.dart';
import 'package:hex_canvas_mobile/models/edge.dart';
import 'package:hex_canvas_mobile/models/hex_pos.dart';
import 'package:hex_canvas_mobile/models/node.dart';
import 'package:hex_canvas_mobile/models/reminder.dart';

// ── Helpers ────────────────────────────────────────────────────────────────

Node _textNode({HexPos? pos}) => Node(
      type: NodeType.text,
      position: pos ?? HexPos(0, 0),
    );

Node _apiNode({HexPos? pos}) => Node(
      type: NodeType.api,
      position: pos ?? HexPos(1, 0),
    );

// ── Setup / teardown ───────────────────────────────────────────────────────

late Directory _tempDir;
late AppModel model;

Future<void> _setUp() async {
  _tempDir = await Directory.systemTemp.createTemp('hive_test_');
  Hive.init(_tempDir.path);
  await Hive.openBox<String>('state');
  model = AppModel();
  model.activeCanvas; // triggers lazy canvas creation
}

Future<void> _tearDown() async {
  await Hive.close();
  await _tempDir.delete(recursive: true);
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  setUp(_setUp);
  tearDown(_tearDown);

  // ── addNode ──────────────────────────────────────────────────────────────

  test('addNode adds to model.nodes and activeCanvas.nodeIds', () {
    final n = _textNode();
    model.addNode(n);
    expect(model.nodes, contains(n));
    expect(model.activeCanvas.nodeIds, contains(n.id));
  });

  test('addNode on canvas A does not affect canvas B nodeIds', () {
    final n1 = _textNode(pos: HexPos(0, 0));
    model.addNode(n1);

    model.createCanvas(); // switches to new canvas B
    final n2 = _textNode(pos: HexPos(1, 0));
    model.addNode(n2);

    // n2 should be only on canvas B (active), not on canvas A
    final canvasA = model.canvases.first;
    final canvasB = model.canvases.last;
    expect(canvasA.nodeIds, isNot(contains(n2.id)));
    expect(canvasB.nodeIds, contains(n2.id));
  });

  // ── activeCanvasNodes ────────────────────────────────────────────────────

  test('activeCanvasNodes returns only nodes on active canvas', () {
    final n1 = _textNode(pos: HexPos(0, 0));
    model.addNode(n1);

    model.createCanvas();
    final n2 = _textNode(pos: HexPos(5, 0));
    model.addNode(n2);

    // On canvas B: only n2
    expect(model.activeCanvasNodes.map((n) => n.id), equals([n2.id]));

    // Switch back to canvas A: only n1
    model.switchCanvas(model.canvases.first.id);
    expect(model.activeCanvasNodes.map((n) => n.id), equals([n1.id]));
  });

  // ── activeCanvasEdges ────────────────────────────────────────────────────

  test('activeCanvasEdges returns only edges between nodes on active canvas', () {
    final n1 = _textNode(pos: HexPos(0, 0));
    final n2 = _apiNode(pos: HexPos(1, 0));
    model.addNode(n1);
    model.addNode(n2);
    model.addEdge(Edge(fromId: n1.id, toId: n2.id));

    model.createCanvas();
    final n3 = _textNode(pos: HexPos(5, 0));
    final n4 = _apiNode(pos: HexPos(6, 0));
    model.addNode(n3);
    model.addNode(n4);
    model.addEdge(Edge(fromId: n3.id, toId: n4.id));

    // Canvas B edges: only n3→n4
    expect(model.activeCanvasEdges.length, equals(1));
    expect(model.activeCanvasEdges.first.fromId, equals(n3.id));

    // Canvas A edges: only n1→n2
    model.switchCanvas(model.canvases.first.id);
    expect(model.activeCanvasEdges.length, equals(1));
    expect(model.activeCanvasEdges.first.fromId, equals(n1.id));
  });

  // ── createCanvas ────────────────────────────────────────────────────────

  test('createCanvas produces canvas with empty nodeIds', () {
    model.addNode(_textNode());
    model.createCanvas();
    expect(model.activeCanvas.nodeIds, isEmpty);
  });

  test('createCanvas switches to the new canvas', () {
    final before = model.activeCanvasId;
    model.createCanvas();
    expect(model.activeCanvasId, isNot(equals(before)));
  });

  // ── switchCanvas ────────────────────────────────────────────────────────

  test('switchCanvas saves chainPath to old canvas and restores from new', () {
    final n1 = _textNode(pos: HexPos(0, 0));
    model.addNode(n1);
    model.chainPath.add(n1.id);

    final canvasAId = model.activeCanvasId;
    model.createCanvas(); // saves chainPath into canvas A, resets to []
    expect(model.chainPath, isEmpty);

    model.switchCanvas(canvasAId);
    expect(model.chainPath, contains(n1.id));
  });

  // ── undo / redo ──────────────────────────────────────────────────────────

  test('undo restores nodes and canvas nodeIds', () {
    model.snapshot('before add');
    final n = _textNode();
    model.addNode(n);
    expect(model.activeCanvas.nodeIds, contains(n.id));

    model.undo();
    expect(model.nodes, isEmpty);
    expect(model.activeCanvas.nodeIds, isEmpty);
  });

  test('redo restores nodes and canvas nodeIds after undo', () {
    model.snapshot('before add');
    final n = _textNode();
    model.addNode(n);
    model.undo();

    model.redo();
    expect(model.nodes.map((x) => x.id), contains(n.id));
    expect(model.activeCanvas.nodeIds, contains(n.id));
  });

  test('undo of two nodes leaves canvas nodeIds consistent with model.nodes', () {
    model.snapshot('before');
    model.addNode(_textNode(pos: HexPos(0, 0)));
    model.addNode(_apiNode(pos: HexPos(1, 0)));
    expect(model.activeCanvas.nodeIds.length, equals(2));

    model.undo();
    expect(model.nodes.length, equals(0));
    expect(model.activeCanvas.nodeIds.length, equals(0));
  });

  // ── removeNodes ──────────────────────────────────────────────────────────

  test('removeNodes cleans nodeIds from all canvases', () {
    final n1 = _textNode(pos: HexPos(0, 0));
    model.addNode(n1);
    model.createCanvas();
    // Manually add n1.id to canvas B to simulate cross-canvas scenario
    model.activeCanvas.nodeIds.add(n1.id);

    model.removeNodes({n1.id});

    expect(model.nodes, isEmpty);
    for (final c in model.canvases) {
      expect(c.nodeIds, isNot(contains(n1.id)));
    }
  });

  // ── activeCanvasNodes count == nodeIds count after mutations ─────────────

  test('activeCanvasNodes count matches nodeIds after add and remove', () {
    final n1 = _textNode(pos: HexPos(0, 0));
    final n2 = _apiNode(pos: HexPos(1, 0));
    model.addNode(n1);
    model.addNode(n2);
    expect(model.activeCanvasNodes.length, equals(2));

    model.removeNodes({n1.id});
    expect(model.activeCanvasNodes.length, equals(1));
    expect(model.activeCanvas.nodeIds.length, equals(1));
  });

  // ── Reminders (ВР4) ──────────────────────────────────────────────────────

  test('Reminders: add, preserve, remove (через список)', () {
    // Просто CRUD по списку напоминаний на уровне модели — без вызова
    // ReminderService (требует plugin). Тестируется что данные живут
    // и корректно сериализуются.
    expect(model.reminders, isEmpty);

    model.reminders.add(
      Reminder(scheduledAt: DateTime(2026, 5, 1), text: 'первое'),
    );
    model.reminders.add(
      Reminder(scheduledAt: DateTime(2026, 5, 2), text: 'второе'),
    );
    expect(model.reminders.length, 2);

    model.reminders.removeWhere((r) => r.text == 'первое');
    expect(model.reminders.length, 1);
    expect(model.reminders.first.text, 'второе');
  });

  test('Reminders: save+load round-trip через Hive', () async {
    model.reminders.add(
      Reminder(scheduledAt: DateTime(2026, 6, 1, 10, 0), text: 'сохраняемое'),
    );
    await model.save();

    // Создаём новую модель — она должна подхватить сохранённые из Hive
    final reloaded = AppModel();
    await reloaded.load();
    expect(reloaded.reminders.length, 1);
    expect(reloaded.reminders.first.text, 'сохраняемое');
  });
}
