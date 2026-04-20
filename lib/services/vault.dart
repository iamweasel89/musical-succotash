import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import 'llm_client.dart';

class Vault {
  Directory? _root;
  Directory? _moves;

  Directory get root => _root!;
  Directory get moves => _moves!;

  Future<void> init() async {
    final base = await getApplicationDocumentsDirectory();
    _root = Directory('${base.path}/vault');
    _moves = Directory('${_root!.path}/moves');
    if (!await _root!.exists()) await _root!.create(recursive: true);
    if (!await _moves!.exists()) await _moves!.create(recursive: true);
  }

  /// 6-hex id. Example: `a3f7c2`. Collision domain ~16M — enough for a
  /// personal vault in practice; collision handling can come later.
  static final _rnd = Random();
  static String _nowId() {
    return _rnd.nextInt(0x1000000).toRadixString(16).padLeft(6, '0');
  }

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// Writes an atom to the vault. Returns its id.
  Future<String> writeAtom({
    required String type,
    required String body,
    String? sourceMoveId,
  }) async {
    String id;
    File f;
    do {
      id = _nowId();
      f = File('${_root!.path}/$id.md');
    } while (await f.exists());
    final now = _nowIso();
    final fm = StringBuffer()
      ..writeln('---')
      ..writeln('id: $id')
      ..writeln('created: $now')
      ..writeln('updated: $now')
      ..writeln('type: $type');
    if (sourceMoveId != null) fm.writeln('source_move_id: $sourceMoveId');
    fm
      ..writeln('---')
      ..writeln()
      ..writeln(body);
    await f.writeAsString(fm.toString());
    return id;
  }

  /// Writes a move record. Returns its id.
  Future<String> writeMove({
    required String model,
    required List<String> contextRefs,
    required List<String> resultRefs,
    required int tokensIn,
    required int tokensOut,
    List<String> parentMoveIds = const [],
    String gate = 'auto',
    String? prompt,
  }) async {
    String id;
    File f;
    do {
      id = _nowId();
      f = File('${_moves!.path}/$id.md');
    } while (await f.exists());
    final ts = _nowIso();
    final fm = StringBuffer()
      ..writeln('---')
      ..writeln('id: $id')
      ..writeln('timestamp: $ts')
      ..writeln('model: $model')
      ..writeln('context_refs: [${contextRefs.join(', ')}]')
      ..writeln('result_refs: [${resultRefs.join(', ')}]')
      ..writeln('tokens_in: $tokensIn')
      ..writeln('tokens_out: $tokensOut')
      ..writeln('parent_move_ids: [${parentMoveIds.join(', ')}]')
      ..writeln('gate: $gate')
      ..writeln('---');
    if (prompt != null) {
      fm
        ..writeln()
        ..writeln(prompt);
    }
    await f.writeAsString(fm.toString());
    return id;
  }

  /// Reads `source_move_id` from atom frontmatter, if present.
  Future<String?> _sourceMoveId(String atomId) async {
    final f = File('${_root!.path}/$atomId.md');
    if (!await f.exists()) return null;
    final text = await f.readAsString();
    final m = RegExp(r'^source_move_id:\s*(\S+)', multiLine: true)
        .firstMatch(text);
    return m?.group(1);
  }

  /// Returns source_move_id set of the given atom ids (for parent_move_ids).
  Future<Set<String>> parentMovesFor(List<String> atomIds) async {
    final out = <String>{};
    for (final id in atomIds) {
      final pm = await _sourceMoveId(id);
      if (pm != null) out.add(pm);
    }
    return out;
  }

  /// Writes a move record with a pre-chosen id. Used by the UI path where
  /// the caller reserves the id before writing atoms so those atoms can
  /// carry source_move_id pointing back to this move.
  Future<void> writeMoveRecord({
    required String moveId,
    required String model,
    required List<String> contextRefs,
    required List<String> resultRefs,
    required int tokensIn,
    required int tokensOut,
    List<String> parentMoveIds = const [],
    String gate = 'manual',
    String? prompt,
  }) async {
    final ts = _nowIso();
    final fm = StringBuffer()
      ..writeln('---')
      ..writeln('id: $moveId')
      ..writeln('timestamp: $ts')
      ..writeln('model: $model')
      ..writeln('context_refs: [${contextRefs.join(', ')}]')
      ..writeln('result_refs: [${resultRefs.join(', ')}]')
      ..writeln('tokens_in: $tokensIn')
      ..writeln('tokens_out: $tokensOut')
      ..writeln('parent_move_ids: [${parentMoveIds.join(', ')}]')
      ..writeln('gate: $gate')
      ..writeln('---');
    if (prompt != null) fm..writeln()..writeln(prompt);
    final f = File('${_moves!.path}/$moveId.md');
    await f.writeAsString(fm.toString());
  }

  /// Picks a fresh unique id for a move without writing anything yet.
  Future<String> reserveMoveId() async {
    String id;
    File f;
    do {
      id = _nowId();
      f = File('${_moves!.path}/$id.md');
    } while (await f.exists());
    return id;
  }

  /// Single full move cycle for API path: writes prompt atom, calls LLM,
  /// writes response atom, writes move record with proper lineage.
  Future<MoveResult> runMove({
    required String apiKey,
    required String model,
    required int maxTokens,
    required String prompt,
    List<String> contextAtomIds = const [],
  }) async {
    final moveId = await reserveMoveId();
    final promptId =
        await writeAtom(type: 'prompt', body: prompt, sourceMoveId: moveId);
    final llm = await LlmClient.call(
      apiKey: apiKey,
      model: model,
      maxTokens: maxTokens,
      prompt: prompt,
    );
    final responseId = await writeAtom(
      type: 'response',
      body: llm.content,
      sourceMoveId: moveId,
    );
    final parents = await parentMovesFor(contextAtomIds);
    await writeMoveRecord(
      moveId: moveId,
      model: llm.model,
      contextRefs: [promptId, ...contextAtomIds],
      resultRefs: [responseId],
      tokensIn: llm.tokensIn,
      tokensOut: llm.tokensOut,
      parentMoveIds: parents.toList(),
      gate: 'auto',
      prompt: prompt,
    );
    return MoveResult(
      promptId: promptId,
      responseId: responseId,
      moveId: moveId,
      tokensIn: llm.tokensIn,
      tokensOut: llm.tokensOut,
    );
  }

  Future<List<File>> listAtoms() async {
    final files = await _root!
        .list()
        .where((e) => e is File && e.path.endsWith('.md'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<List<File>> listMoves() async {
    final files = await _moves!
        .list()
        .where((e) => e is File && e.path.endsWith('.md'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }
}

class MoveResult {
  final String promptId;
  final String responseId;
  final String moveId;
  final int tokensIn;
  final int tokensOut;
  const MoveResult({
    required this.promptId,
    required this.responseId,
    required this.moveId,
    required this.tokensIn,
    required this.tokensOut,
  });
}
