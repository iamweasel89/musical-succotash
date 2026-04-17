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

// ── Результат поиска по дампам ─────────────────────────────────────────────

class DumpMatch {
  final String filename;
  final DateTime timestamp;
  final String snippet;
  final int score;
  const DumpMatch({
    required this.filename,
    required this.timestamp,
    required this.snippet,
    required this.score,
  });
}

/// Ищет подстроку (case-insensitive) по всем дампам в inbox.
/// Возвращает отсортированный по релевантности + свежести список.
Future<List<DumpMatch>> searchDumps(String query, {int limit = 5}) async {
  if (query.trim().isEmpty) return const [];
  final dir = await DumpService._inboxDir();
  if (!dir.existsSync()) return const [];

  final q = query.toLowerCase();
  final matches = <DumpMatch>[];

  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.md')) continue;

    String content;
    try {
      content = await entity.readAsString();
    } catch (_) {
      continue;
    }
    final lower = content.toLowerCase();
    final firstIdx = lower.indexOf(q);
    if (firstIdx < 0) continue;

    // Count occurrences
    int count = 0;
    int pos = 0;
    while (true) {
      final idx = lower.indexOf(q, pos);
      if (idx < 0) break;
      count++;
      pos = idx + q.length;
    }

    // Snippet ±100 chars around first match
    final start = (firstIdx - 100).clamp(0, content.length);
    final end = (firstIdx + q.length + 100).clamp(0, content.length);
    final snippet = content.substring(start, end).replaceAll('\n', ' ').trim();

    // Timestamp из имени YYYYMMDD-HHmmss-dump.md или из mtime
    final filename = entity.uri.pathSegments.last;
    DateTime ts;
    final m = RegExp(r'(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})')
        .firstMatch(filename);
    if (m != null) {
      ts = DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
      );
    } else {
      ts = entity.statSync().modified;
    }

    matches.add(DumpMatch(
      filename: filename,
      timestamp: ts,
      snippet: snippet,
      score: count,
    ));
  }

  // Сортировка: по score убыванию, затем по timestamp убыванию
  matches.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : b.timestamp.compareTo(a.timestamp);
  });
  return matches.take(limit).toList();
}

/// Читает содержимое одного дампа по имени файла. null если не найден.
Future<String?> readDump(String filename) async {
  final dir = await DumpService._inboxDir();
  if (!dir.existsSync()) return null;
  final file = File('${dir.path}/$filename');
  if (!file.existsSync()) return null;
  try {
    return await file.readAsString();
  } catch (_) {
    return null;
  }
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
      buf.writeln(label);
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
