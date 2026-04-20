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

/// Parses `[id1, id2, id3]` list syntax from frontmatter value.
List<String> parseIdList(String? value) {
  if (value == null) return const [];
  final s = value.trim();
  if (!s.startsWith('[') || !s.endsWith(']')) return const [];
  final inner = s.substring(1, s.length - 1).trim();
  if (inner.isEmpty) return const [];
  return inner
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

class AtomView extends StatefulWidget {
  final String filename;
  final String rawText;
  final int? depth;
  final int? manualDepth;
  final List<String> childMoveIds;
  final Future<void> Function(String id)? onOpenAtom;
  final Future<void> Function(String id)? onOpenMove;
  const AtomView({
    super.key,
    required this.filename,
    required this.rawText,
    this.depth,
    this.manualDepth,
    this.childMoveIds = const [],
    this.onOpenAtom,
    this.onOpenMove,
  });

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
    for (final key in ['type', 'created', 'timestamp', 'model', 'tokens_in', 'tokens_out', 'gate']) {
      final v = meta[key];
      if (v != null && v.isNotEmpty) {
        chips.add(_chip('$key: $v'));
      }
    }
    final sourceMoveId = meta['source_move_id'];
    final contextRefs = parseIdList(meta['context_refs']);
    final resultRefs = parseIdList(meta['result_refs']);
    final parentMoveIds = parseIdList(meta['parent_move_ids']);

    final linkSections = <Widget>[];

    if (sourceMoveId != null && sourceMoveId.isNotEmpty) {
      linkSections.add(_linkRow(
        context,
        label: 'Источник-ход',
        ids: [sourceMoveId],
        onTap: widget.onOpenMove,
      ));
    }
    if (parentMoveIds.isNotEmpty) {
      linkSections.add(_linkRow(
        context,
        label: 'Родительские ходы',
        ids: parentMoveIds,
        onTap: widget.onOpenMove,
      ));
    }
    if (widget.childMoveIds.isNotEmpty) {
      linkSections.add(_linkRow(
        context,
        label: 'Дочерние ходы',
        ids: widget.childMoveIds,
        onTap: widget.onOpenMove,
      ));
    }
    if (contextRefs.isNotEmpty) {
      linkSections.add(_linkRow(
        context,
        label: 'Контекст',
        ids: contextRefs,
        onTap: widget.onOpenAtom,
      ));
    }
    if (resultRefs.isNotEmpty) {
      linkSections.add(_linkRow(
        context,
        label: 'Результат',
        ids: resultRefs,
        onTap: widget.onOpenAtom,
      ));
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
        if (chips.isNotEmpty || widget.depth != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (widget.depth != null)
                  _chip('⛓ ${widget.depth}'),
                if (widget.manualDepth != null)
                  _chip('✓ ${widget.manualDepth}'),
                ...chips,
              ],
            ),
          ),
        if (linkSections.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...linkSections,
        ],
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

  Widget _linkRow(
    BuildContext context, {
    required String label,
    required List<String> ids,
    Future<void> Function(String id)? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final id in ids)
                  ActionChip(
                    label: Text(id, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    onPressed: onTap == null ? null : () => onTap(id),
                  ),
              ],
            ),
          ),
        ],
      ),
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
