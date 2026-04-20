import 'dart:io';

import 'package:flutter/material.dart';

import 'atom_view.dart';

class Dashboard extends StatelessWidget {
  final List<File> atoms;
  final List<File> moves;
  final Map<String, String> atomText;
  final Map<String, int> depth;
  final Map<String, int> manualDepth;
  final int chainCount;
  final Future<void> Function(File) onOpenAtom;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  const Dashboard({
    super.key,
    required this.atoms,
    required this.moves,
    required this.atomText,
    required this.depth,
    required this.manualDepth,
    required this.chainCount,
    required this.onOpenAtom,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  String _idOf(File f) => f.path.split('/').last.replaceAll('.md', '');

  String _firstLine(String? text) {
    if (text == null) return '';
    final parsed = parseFrontmatter(text);
    final body = parsed.body;
    final line = body
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final stripped = line.replaceAll(RegExp(r'\*+'), '').trim();
    return stripped.length > 80 ? '${stripped.substring(0, 80)}…' : stripped;
  }

  String _typeOf(String? text) {
    if (text == null) return '';
    return parseFrontmatter(text).meta['type'] ?? '';
  }

  String _timestampOf(String? text) {
    if (text == null) return '';
    final m = parseFrontmatter(text).meta;
    final ts = m['created'] ?? m['timestamp'];
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  _ChainStats _chainStats() {
    var pure = 0;
    var mixed = 0;
    var solo = 0;
    for (final f in moves) {
      final id = _idOf(f);
      final d = depth[id] ?? 0;
      final md = manualDepth[id] ?? 0;
      if (d == 0) {
        solo++;
      } else if (md == d + 1 || md == d) {
        pure++;
      } else {
        mixed++;
      }
    }
    return _ChainStats(pure: pure, mixed: mixed, solo: solo);
  }

  List<File> _filteredAtoms() {
    final q = searchQuery.toLowerCase();
    if (q.startsWith('#')) {
      final tag = q.substring(1).trim();
      if (tag.isEmpty) return atoms;
      return atoms.where((f) {
        final tags = parseIdList(
            parseFrontmatter(atomText[f.path] ?? '').meta['tags']);
        return tags.any((t) => t.toLowerCase().contains(tag));
      }).toList();
    }
    return atoms
        .where((f) => (atomText[f.path] ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _chainStats();
    final isSearching = searchQuery.isNotEmpty;

    if (isSearching) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _searchField(theme),
            const SizedBox(height: 16),
            _sectionTitle(theme, 'Найденное (${_filteredAtoms().length})'),
            const SizedBox(height: 8),
            Expanded(child: _searchResults(theme)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _searchField(theme),
          const SizedBox(height: 16),
          _statsRow(theme, stats),
        ],
      ),
    );
  }

  Widget _statsRow(ThemeData theme, _ChainStats stats) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _bigStatCard(theme, value: '${atoms.length}', label: 'атомов')),
          const SizedBox(width: 8),
          Expanded(child: _bigStatCard(theme, value: '${moves.length}', label: 'ходов')),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _smallStat(theme, '$chainCount', 'цепочек'),
                const SizedBox(height: 4),
                _smallStat(theme, '${stats.pure}', 'чистых'),
                const SizedBox(height: 4),
                _smallStat(theme, '${stats.mixed}', 'смешан.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchResults(ThemeData theme) {
    final results = _filteredAtoms();
    if (results.isEmpty) {
      return Center(
        child: Text('Ничего не найдено',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) => _atomCard(theme, results[i]),
    );
  }

  Widget _searchField(ThemeData theme) {
    return TextField(
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, size: 20),
        hintText: 'Поиск… или #тег',
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Widget _bigStatCard(ThemeData theme,
      {required String value, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _smallStat(ThemeData theme, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text, {String? suffix}) {
    return Row(
      children: [
        Text(text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            )),
        if (suffix != null) ...[
          const Spacer(),
          Text(suffix,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ],
    );
  }

  Widget _atomCard(ThemeData theme, File f) {
    final text = atomText[f.path];
    final type = _typeOf(text);
    final time = _timestampOf(text);
    final preview = _firstLine(text);
    final tags = parseIdList(parseFrontmatter(text ?? '').meta['tags']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onOpenAtom(f),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (type.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _typeColor(theme, type),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(type,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          )),
                    ),
                  const Spacer(),
                  Text(time,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(preview,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('(пусто)',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    for (final tag in tags)
                      GestureDetector(
                        onTap: () => onSearchChanged('#$tag'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('#$tag',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                              )),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _typeColor(ThemeData theme, String type) {
    switch (type) {
      case 'prompt':
        return theme.colorScheme.tertiaryContainer;
      case 'response':
        return theme.colorScheme.primaryContainer;
      case 'move':
        return theme.colorScheme.secondaryContainer;
      default:
        return theme.colorScheme.surfaceContainerHighest;
    }
  }
}

class _ChainStats {
  final int pure;
  final int mixed;
  final int solo;
  const _ChainStats({required this.pure, required this.mixed, required this.solo});
}
