import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

// ── Мастерская: Кейсы ───────────────────────────────────────────────────────
// Viewer базы кейсов из cases/*.md в репозитории. Список сортируется по дате
// (свежие сверху). Детальный экран — markdown + frontmatter вверху + wikilinks.

const _branch = 'claude/hex-canvas-mobile-08MeM';
const _githubApiList =
    'https://api.github.com/repos/iamweasel89/musical-succotash/contents/cases?ref=$_branch';
const _rawBase =
    'https://raw.githubusercontent.com/iamweasel89/musical-succotash/$_branch/cases';

// ── Модель кейса ────────────────────────────────────────────────────────────

class CaseEntry {
  final String filename; // e.g. "001-compress-stal-pt.md"
  final String id;
  final String title;
  final DateTime? date;
  final List<String> tags;
  final List<String> links;
  final String frontmatterRaw;
  final String body;

  const CaseEntry({
    required this.filename,
    required this.id,
    required this.title,
    required this.date,
    required this.tags,
    required this.links,
    required this.frontmatterRaw,
    required this.body,
  });

  factory CaseEntry.parse(String filename, String content) {
    // Разделяем frontmatter и тело
    String frontmatter = '';
    String body = content;
    final fmMatch = RegExp(r'^---\n([\s\S]*?)\n---\n', multiLine: false)
        .firstMatch(content);
    if (fmMatch != null) {
      frontmatter = fmMatch.group(1) ?? '';
      body = content.substring(fmMatch.end);
    }

    // Лёгкий парсер frontmatter: key: value, key: [a, b]
    final fields = <String, String>{};
    for (final line in frontmatter.split('\n')) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final key = line.substring(0, colon).trim();
      var value = line.substring(colon + 1).trim();
      // strip optional quotes
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      fields[key] = value;
    }

    List<String> parseList(String raw) {
      var s = raw.trim();
      if (s.startsWith('[') && s.endsWith(']')) {
        s = s.substring(1, s.length - 1);
      }
      return s
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return CaseEntry(
      filename: filename,
      id: fields['id'] ?? filename.split('-').first,
      title: fields['title'] ?? filename,
      date: DateTime.tryParse(fields['date'] ?? ''),
      tags: fields['tags'] != null ? parseList(fields['tags']!) : const [],
      links: fields['links'] != null ? parseList(fields['links']!) : const [],
      frontmatterRaw: frontmatter,
      body: body,
    );
  }
}

// ── Список кейсов ──────────────────────────────────────────────────────────

class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  List<CaseEntry>? _cases;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Список файлов через GitHub Contents API
      final listResp = await http
          .get(Uri.parse(_githubApiList))
          .timeout(const Duration(seconds: 15));
      if (listResp.statusCode != 200) {
        throw Exception('listing HTTP ${listResp.statusCode}');
      }
      final listJson = jsonDecode(listResp.body) as List;
      final filenames = listJson
          .whereType<Map<String, dynamic>>()
          .map((e) => e['name'] as String? ?? '')
          .where((n) => n.endsWith('.md') && n != 'README.md')
          .toList();

      // Содержимое каждого
      final cases = <CaseEntry>[];
      for (final name in filenames) {
        try {
          final r = await http
              .get(Uri.parse('$_rawBase/$name'))
              .timeout(const Duration(seconds: 10));
          if (r.statusCode == 200) {
            cases.add(CaseEntry.parse(name, r.body));
          }
        } catch (_) {}
      }

      // Сортировка: свежие сверху. При равной дате — по id убыванию.
      cases.sort((a, b) {
        final ad = a.date;
        final bd = b.date;
        if (ad != null && bd != null && ad != bd) return bd.compareTo(ad);
        return b.id.compareTo(a.id);
      });

      if (!mounted) return;
      setState(() {
        _cases = cases;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Кейсы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading && _cases == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _cases == null
              ? _ErrorView(error: _error!, onRetry: _load)
              : (_cases?.isEmpty ?? true)
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Кейсов пока нет.',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _cases!.length,
                      itemBuilder: (ctx, i) => _CaseTile(
                        entry: _cases![i],
                        allCases: _cases!,
                      ),
                    ),
    );
  }
}

class _CaseTile extends StatelessWidget {
  final CaseEntry entry;
  final List<CaseEntry> allCases;

  const _CaseTile({required this.entry, required this.allCases});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blueGrey[100],
          radius: 18,
          child: Text(entry.id,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        title: Text(entry.title, style: const TextStyle(fontSize: 14)),
        subtitle: Row(
          children: [
            if (entry.date != null)
              Text(_fmtDate(entry.date!),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.tags.map((t) => '#$t').join(' '),
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey[400]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CaseDetailScreen(entry: entry, allCases: allCases),
        )),
      ),
    );
  }
}

// ── Детальный экран ────────────────────────────────────────────────────────

class CaseDetailScreen extends StatelessWidget {
  final CaseEntry entry;
  final List<CaseEntry> allCases;

  const CaseDetailScreen({
    super.key,
    required this.entry,
    required this.allCases,
  });

  /// Преобразует `[[001]]` и `[[001-slug]]` в markdown-ссылки на соответствующие
  /// файлы (используем custom scheme `case://ID`).
  String _resolveWikilinks(String body) {
    return body.replaceAllMapped(RegExp(r'\[\[([^\]]+)\]\]'), (m) {
      final ref = m.group(1) ?? '';
      final id = ref.split('-').first;
      final target = allCases.where((c) => c.id == id).firstOrNull;
      final title = target?.title ?? ref;
      return '[[$id] $title](case://$id)';
    });
  }

  void _handleLinkTap(BuildContext context, String? href) {
    if (href == null) return;
    if (href.startsWith('case://')) {
      final id = href.substring('case://'.length);
      final target = allCases.where((c) => c.id == id).firstOrNull;
      if (target == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Кейс $id не найден')),
        );
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CaseDetailScreen(entry: target, allCases: allCases),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final linkedEntries = entry.links
        .map((id) => allCases.where((c) => c.id == id).firstOrNull)
        .whereType<CaseEntry>()
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text('#${entry.id}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(entry.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(
            children: [
              if (entry.date != null)
                Text(_fmtDate(entry.date!),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(width: 12),
              if (entry.tags.isNotEmpty)
                Expanded(
                  child: Text(
                    entry.tags.map((t) => '#$t').join(' '),
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey[400]),
                  ),
                ),
            ],
          ),
          if (linkedEntries.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: linkedEntries
                  .map((e) => ActionChip(
                        label: Text('#${e.id}',
                            style: const TextStyle(fontSize: 11)),
                        onPressed: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CaseDetailScreen(
                            entry: e,
                            allCases: allCases,
                          ),
                        )),
                      ))
                  .toList(),
            ),
          ],
          const Divider(height: 24),
          MarkdownBody(
            data: _resolveWikilinks(entry.body),
            selectable: true,
            onTapLink: (text, href, title) => _handleLinkTap(context, href),
          ),
        ],
      ),
    );
  }
}

// ── Utils ──────────────────────────────────────────────────────────────────

String _fmtDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text('Не удалось загрузить кейсы:\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}
