import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Parses an atom/move markdown file into (frontmatter map, body).
/// Returns empty map + full text if no frontmatter delimiters.
({Map<String, String> meta, String body}) parseFrontmatter(String text) {
  if (!text.startsWith('---')) return (meta: {}, body: text);
  final lines = text.split('\n');
  var end = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      end = i;
      break;
    }
  }
  if (end == -1) return (meta: {}, body: text);
  final meta = <String, String>{};
  for (var i = 1; i < end; i++) {
    final l = lines[i];
    final idx = l.indexOf(':');
    if (idx == -1) continue;
    final key = l.substring(0, idx).trim();
    final val = l.substring(idx + 1).trim();
    meta[key] = val;
  }
  final body = lines.skip(end + 1).join('\n').trim();
  return (meta: meta, body: body);
}

class AtomView extends StatefulWidget {
  final String filename;
  final String rawText;
  const AtomView({super.key, required this.filename, required this.rawText});

  @override
  State<AtomView> createState() => _AtomViewState();
}

class _AtomViewState extends State<AtomView> {
  bool _showMeta = false;

  @override
  Widget build(BuildContext context) {
    final parsed = parseFrontmatter(widget.rawText);
    final meta = parsed.meta;
    final body = parsed.body;
    final chips = <Widget>[];
    for (final key in ['type', 'created', 'model', 'tokens_in', 'tokens_out']) {
      final v = meta[key];
      if (v != null && v.isNotEmpty) {
        chips.add(_chip('$key: $v'));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            widget.filename,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: chips,
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showMeta = !_showMeta),
              icon: Icon(
                  _showMeta ? Icons.unfold_less : Icons.unfold_more,
                  size: 18),
              label: Text(_showMeta ? 'Скрыть исходник' : 'Показать исходник'),
            ),
          ),
        ),
        if (_showMeta)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                widget.rawText,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: MarkdownBody(
            data: body.isEmpty ? '*(пусто)*' : body,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
          ),
        ),
      ],
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}
