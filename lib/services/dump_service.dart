import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Saves a chat branch dump to local storage.
///
/// Two sections are written:
///   1. Full conversation (all roles in order)
///   2. Operator drafts only (user messages, raw, for later LLM processing)
///
/// Files land in: <documents>/inbox/YYYYMMDD-HHmmss-dump.md
class ThesisDump {
  final String sourceNodeId;
  final String excerpt;
  final String thesis;
  final String answer;
  const ThesisDump({required this.sourceNodeId, required this.excerpt, required this.thesis, required this.answer});
}

class DumpService {
  static Future<File> saveDump({
    required List<Map<String, dynamic>> messages,
    String? canvasName,
    List<ThesisDump>? theses,
  }) async {
    final now = DateTime.now();
    final timestamp = _formatTs(now);
    final dir = await _inboxDir();
    final file = File('${dir.path}/$timestamp-dump.md');

    final buf = StringBuffer();

    // ── Front-matter ────────────────────────────────────────────────────────
    buf.writeln('---');
    buf.writeln('type: chat-dump');
    buf.writeln('created: ${now.toIso8601String()}');
    if (canvasName != null) buf.writeln('canvas: $canvasName');
    buf.writeln('tags: [dump, inbox]');
    buf.writeln('---');
    buf.writeln();

    // ── Full conversation ────────────────────────────────────────────────────
    buf.writeln('## Диалог');
    buf.writeln();
    for (final msg in messages) {
      final role = msg['role'] as String;
      final content = (msg['content'] as String? ?? '').trim();
      if (content.isEmpty) continue;
      final label = role == 'user' ? '**Оператор**' : '**LLM**';
      buf.writeln('$label');
      buf.writeln();
      buf.writeln(content);
      buf.writeln();
      buf.writeln('---');
      buf.writeln();
    }

    // ── Operator drafts ─────────────────────────────────────────────────────
    final drafts = messages
        .where((m) => m['role'] == 'user')
        .map((m) => (m['content'] as String? ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (drafts.isNotEmpty) {
      buf.writeln('## Черновики оператора');
      buf.writeln();
      buf.writeln('<!-- для последующего анализа: что формализовать, что реализовано? -->');
      buf.writeln();
      for (int i = 0; i < drafts.length; i++) {
        buf.writeln('### Черновик ${i + 1}');
        buf.writeln();
        buf.writeln(drafts[i]);
        buf.writeln();
      }
    }

    // ── Theses ───────────────────────────────────────────────────────────────
    if (theses != null && theses.isNotEmpty) {
      buf.writeln('## Тезисы');
      buf.writeln();
      for (int i = 0; i < theses.length; i++) {
        final t = theses[i];
        buf.writeln('### Тезис ${i + 1}');
        buf.writeln();
        buf.writeln('**Источник:** `${t.sourceNodeId.substring(0, 6)}`');
        buf.writeln();
        buf.writeln(t.thesis);
        buf.writeln();
        if (t.answer.isNotEmpty) {
          buf.writeln('**Ответ:** ${t.answer}');
          buf.writeln();
        }
      }
    }

    await file.writeAsString(buf.toString(), flush: true);
    return file;
  }

  static Future<Directory> _inboxDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/inbox');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String _formatTs(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}'
      '-${dt.hour.toString().padLeft(2, '0')}'
      '${dt.minute.toString().padLeft(2, '0')}'
      '${dt.second.toString().padLeft(2, '0')}';
}
