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

List<String> parseTags(String? value) => parseIdList(value);

class AtomView extends StatefulWidget {
  final String filename;
  final String rawText;
  final int? depth;
  final int? manualDepth;
  final List<String> childMoveIds;
  final Future<void> Function(String id)? onOpenAtom;
  final Future<void> Function(String id)? onOpenMove;
  final Future<void> Function(List<String>)? onTagsChanged;
  const AtomView({
    super.key,
    required this.filename,
    required this.rawText,
    this.depth,
    this.manualDepth,
    this.childMoveIds = const [],
    this.onOpenAtom,
    this.onOpenMove,
    this.onTagsChanged,
  });

  @override
  State<AtomView> createState() => _AtomViewState();
}

class _AtomViewState extends State<AtomView> {
  bool _showMeta = false;
  late List<String> _tags;
  bool _addingTag = false;
  final _tagCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final parsed = parseFrontmatter(widget.rawText);
    _tags = parseTags(parsed.meta['tags']);
  }

  @override
  void dispose() {
    _tagCtl.dispose();
    super.dispose();
  }

  Future<void> _removeTag(String tag) async {
    final updated = _tags.where((t) => t != tag).toList();
    setState(() => _tags = updated);
    await widget.onTagsChanged?.call(updated);
  }

  Future<void> _submitTag(String raw) async {
    final t = raw.trim().toLowerCase().replaceAll(' ', '-');
    if (t.isEmpty || _tags.contains(t)) {
      setState(() { _addingTag = false; _tagCtl.clear(); });
      return;
    }
    final updated = [..._tags, t];
    setState(() { _tags = updated; _addingTag = false; _tagCtl.clear(); });
    await widget.onTagsChanged?.call(updated);
  }

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
        _tagsSection(context),
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

  Widget _tagsSection(BuildContext context) {
    final theme = Theme.of(context);
    final editable = widget.onTagsChanged != null;
    if (_tags.isEmpty && !editable) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in _tags)
            Chip(
              label: Text('#$tag',
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSecondaryContainer)),
              backgroundColor: theme.colorScheme.secondaryContainer,
              deleteIcon: editable
                  ? Icon(Icons.close, size: 14,
                      color: theme.colorScheme.onSecondaryContainer)
                  : null,
              onDeleted: editable ? () => _removeTag(tag) : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          if (editable)
            if (_addingTag)
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _tagCtl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'тег',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: _submitTag,
                ),
              )
            else
              ActionChip(
                avatar: const Icon(Icons.add, size: 14),
                label: const Text('тег', style: TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () => setState(() => _addingTag = true),
              ),
        ],
      ),
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
