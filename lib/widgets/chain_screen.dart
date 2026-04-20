import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'atom_view.dart';

// ── Full chain view ────────────────────────────────────────────────────────

class ChainScreen extends StatefulWidget {
  final List<File> moves; // root → tip
  final Map<String, String> atomTextById;
  final Map<String, String> moveTexts; // keyed by path
  final Map<String, int> depth;
  final Map<String, int> manualDepth;
  final Future<void> Function(File) onOpenMove;

  const ChainScreen({
    super.key,
    required this.moves,
    required this.atomTextById,
    required this.moveTexts,
    required this.depth,
    required this.manualDepth,
    required this.onOpenMove,
  });

  @override
  State<ChainScreen> createState() => _ChainScreenState();
}

class _ChainScreenState extends State<ChainScreen> {
  final _scrollCtl = ScrollController();

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  String _idOf(File f) => f.path.split('/').last.replaceAll('.md', '');

  void _jumpToLast() {
    _scrollCtl.animateTo(
      _scrollCtl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastId = _idOf(widget.moves.last);
    final d = widget.depth[lastId] ?? 0;
    final md = widget.manualDepth[lastId] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Цепочка · ${widget.moves.length} ходов'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text('⛓$d  ✓$md',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ),
          ),
          IconButton(
            tooltip: 'К последнему',
            icon: const Icon(Icons.arrow_downward),
            onPressed: _jumpToLast,
          ),
        ],
      ),
      body: ListView.builder(
        controller: _scrollCtl,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        itemCount: widget.moves.length,
        itemBuilder: (_, i) => _MoveCard(
          index: i,
          moveFile: widget.moves[i],
          isLast: i == widget.moves.length - 1,
          atomTextById: widget.atomTextById,
          moveText: widget.moveTexts[widget.moves[i].path] ?? '',
          depth: widget.depth,
          manualDepth: widget.manualDepth,
          onOpenMove: widget.onOpenMove,
        ),
      ),
    );
  }
}

class _MoveCard extends StatefulWidget {
  final int index;
  final File moveFile;
  final bool isLast;
  final Map<String, String> atomTextById;
  final String moveText;
  final Map<String, int> depth;
  final Map<String, int> manualDepth;
  final Future<void> Function(File) onOpenMove;

  const _MoveCard({
    required this.index,
    required this.moveFile,
    required this.isLast,
    required this.atomTextById,
    required this.moveText,
    required this.depth,
    required this.manualDepth,
    required this.onOpenMove,
  });

  @override
  State<_MoveCard> createState() => _MoveCardState();
}

class _MoveCardState extends State<_MoveCard> {
  bool _expanded = false;

  String get _id =>
      widget.moveFile.path.split('/').last.replaceAll('.md', '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = parseFrontmatter(widget.moveText).meta;
    final gate = meta['gate'] ?? 'auto';
    final d = widget.depth[_id] ?? 0;
    final md = widget.manualDepth[_id] ?? 0;
    final resultRefs = parseIdList(meta['result_refs']);
    final contextRefs = parseIdList(meta['context_refs']);

    String? promptBody;
    for (final ref in contextRefs) {
      final t = widget.atomTextById[ref];
      if (t == null) continue;
      final p = parseFrontmatter(t);
      if (p.meta['type'] == 'prompt') {
        promptBody = p.body;
        break;
      }
    }

    String? responseBody;
    if (resultRefs.isNotEmpty) {
      final t = widget.atomTextById[resultRefs.first];
      if (t != null) responseBody = parseFrontmatter(t).body;
    }

    final isManual = gate == 'manual';

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 4),
          elevation: 0,
          color: widget.isLast
              ? theme.colorScheme.primaryContainer.withOpacity(0.25)
              : theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: widget.isLast
                ? BorderSide(
                    color: theme.colorScheme.primary.withOpacity(0.5))
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onLongPress: () => widget.onOpenMove(widget.moveFile),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isManual
                            ? Colors.green.withOpacity(0.15)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isManual ? '✓ manual' : 'auto',
                        style: TextStyle(
                          fontSize: 11,
                          color: isManual
                              ? Colors.green
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('⛓$d  ✓$md',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                    const Spacer(),
                    Text('#${widget.index + 1}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                    if (widget.isLast) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.flag,
                          size: 14, color: theme.colorScheme.primary),
                    ],
                  ]),
                  if (promptBody != null && promptBody.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(promptBody,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                  ],
                  if (responseBody != null && responseBody.isNotEmpty) ...[
                    const Divider(height: 16),
                    if (_expanded)
                      MarkdownBody(
                        data: responseBody,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet.fromTheme(theme),
                      )
                    else
                      Text(responseBody,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.8)),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis),
                    TextButton(
                      onPressed: () =>
                          setState(() => _expanded = !_expanded),
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28)),
                      child: Text(_expanded ? 'Свернуть' : 'Развернуть',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (!widget.isLast)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Icon(Icons.arrow_downward,
                size: 16, color: theme.colorScheme.outlineVariant),
          ),
      ],
    );
  }
}

// ── Chain list ─────────────────────────────────────────────────────────────

class ChainListScreen extends StatelessWidget {
  final List<List<File>> chains;
  final Map<String, String> atomTextById;
  final Map<String, String> moveTexts;
  final Map<String, int> depth;
  final Map<String, int> manualDepth;
  final void Function(List<File>) onOpenChain;

  const ChainListScreen({
    super.key,
    required this.chains,
    required this.atomTextById,
    required this.moveTexts,
    required this.depth,
    required this.manualDepth,
    required this.onOpenChain,
  });

  String _idOf(File f) => f.path.split('/').last.replaceAll('.md', '');

  String _tipPreview(List<File> chain) {
    final tip = chain.last;
    final text = moveTexts[tip.path] ?? '';
    final resultRefs = parseIdList(parseFrontmatter(text).meta['result_refs']);
    if (resultRefs.isEmpty) return '';
    final t = atomTextById[resultRefs.first] ?? '';
    final body = parseFrontmatter(t).body;
    final line = body
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final s = line.replaceAll(RegExp(r'\*+'), '').trim();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Цепочки (${chains.length})')),
      body: chains.isEmpty
          ? Center(
              child: Text('Нет цепочек',
                  style: theme.textTheme.bodySmall))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: chains.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final chain = chains[i];
                final lastId = _idOf(chain.last);
                final d = depth[lastId] ?? 0;
                final md = manualDepth[lastId] ?? 0;
                final preview = _tipPreview(chain);
                return Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onOpenChain(chain),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text('${chain.length} ходов',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 10),
                                  Text('⛓$d  ✓$md',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color:
                                                  theme.colorScheme.outline)),
                                ]),
                                if (preview.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(preview,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: theme
                                                  .colorScheme.outline),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: theme.colorScheme.outline),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
