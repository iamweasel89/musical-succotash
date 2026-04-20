import 'dart:io';

import 'package:flutter/material.dart';

import 'atom_view.dart';

class Dashboard extends StatelessWidget {
  final List<File> atoms;
  final List<File> moves;
  final Map<String, String> atomText;
  final Map<String, String> moveText;
  final Map<String, int> depth;
  final Map<String, int> manualDepth;
  final Map<String, List<String>> children;
  final Future<void> Function(File) onOpenAtom;
  final Future<void> Function(File) onOpenMove;
  final VoidCallback onOpenAllAtoms;
  final VoidCallback onOpenAllMoves;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function() onRefresh;

  const Dashboard({
    super.key,
    required this.atoms,
    required this.moves,
    required this.atomText,
    required this.moveText,
    required this.depth,
    required this.manualDepth,
    required this.children,
    required this.onOpenAtom,
    required this.onOpenMove,
    required this.onOpenAllAtoms,
    required this.onOpenAllMoves,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onRefresh,
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
    return stripped.length > 80
        ? '${stripped.substring(0, 80)}…'
        : stripped;
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

  List<File> _lastAtoms(int n) {
    // atoms are already sorted newest-first by listAtoms
    return atoms.take(n).toList();
  }

  File? _deepestMove() {
    if (moves.isEmpty) return null;
    File? best;
    var bestDepth = -1;
    for (final f in moves) {
      final d = depth[_idOf(f)] ?? 0;
      if (d > bestDepth) {
        bestDepth = d;
        best = f;
      }
    }
    return best;
  }

  List<File> _chainFrom(File tip) {
    final chain = <File>[tip];
    var current = tip;
    while (true) {
      final id = _idOf(current);
      final text = moveText[current.path];
      if (text == null) break;
      final parents = parseIdList(
          parseFrontmatter(text).meta['parent_move_ids']);
      if (parents.isEmpty) break;
      final parentId = parents.first;
      final parentFile = moves.firstWhere(
        (m) => _idOf(m) == parentId,
        orElse: () => current,
      );
      if (_idOf(parentFile) == id) break;
      chain.insert(0, parentFile);
      current = parentFile;
      if (chain.length > 50) break;
    }
    return chain;
  }

  List<File> _filteredAtoms() {
    final q = searchQuery.toLowerCase();
    return atoms
        .where((f) => (atomText[f.path] ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _chainStats();
    final isSearching = searchQuery.isNotEmpty;
    final displayed = isSearching ? _filteredAtoms() : _lastAtoms(3);
    final sectionLabel =
        isSearching ? 'Найденное (${displayed.length})' : 'Недавнее';
    final deepest = _deepestMove();
    final chain = deepest == null ? <File>[] : _chainFrom(deepest);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _searchField(theme),
          const SizedBox(height: 16),
          _statsHeader(theme, stats),
          const SizedBox(height: 24),
          _sectionTitle(theme, sectionLabel),
          const SizedBox(height: 8),
          if (displayed.isNotEmpty)
            for (final f in displayed) _atomCard(theme, f)
          else if (isSearching)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Ничего не найдено',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          const SizedBox(height: 16),
          if (!isSearching && chain.length >= 2) ...[
            _sectionTitle(theme, 'Последняя цепочка',
                suffix:
                    '⛓ ${chain.length} · ✓ ${manualDepth[_idOf(deepest!)] ?? 0}'),
            const SizedBox(height: 8),
            _chainRow(theme, chain),
            const SizedBox(height: 24),
          ],
          _allButtons(theme),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _searchField(ThemeData theme) {
    return TextField(
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, size: 20),
        hintText: 'Поиск по содержимому…',
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

  Widget _statsHeader(ThemeData theme, _ChainStats stats) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _bigStatCard(
            theme,
            value: atoms.length.toString(),
            label: 'атомов',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _bigStatCard(
            theme,
            value: moves.length.toString(),
            label: 'ходов',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _smallStat(theme, '${stats.pure}', 'чистых'),
              const SizedBox(height: 4),
              _smallStat(theme, '${stats.mixed}', 'смешанных'),
              const SizedBox(height: 4),
              _smallStat(theme, '${stats.solo}', 'одиночных'),
            ],
          ),
        ),
      ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              )),
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              )),
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              )),
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
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              )),
        ],
      ],
    );
  }

  Widget _atomCard(ThemeData theme, File f) {
    final text = atomText[f.path];
    final type = _typeOf(text);
    final time = _timestampOf(text);
    final preview = _firstLine(text);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onOpenAtom(f),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
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
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      )),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      )),
                ),
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

  Widget _chainRow(ThemeData theme, List<File> chain) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chain.length,
        separatorBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.arrow_forward,
              size: 16, color: theme.colorScheme.outline),
        ),
        itemBuilder: (_, i) {
          final f = chain[i];
          final text = moveText[f.path];
          final preview = _firstLine(text);
          final id = _idOf(f);
          final d = depth[id] ?? 0;
          final md = manualDepth[id] ?? 0;
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onOpenMove(f),
            child: Container(
              width: 140,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: md == d && d > 0
                      ? Colors.green.withOpacity(0.5)
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(preview,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      Text('⛓$d',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          )),
                      const SizedBox(width: 6),
                      Text('✓$md',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: md == d && d > 0
                                ? Colors.green
                                : theme.colorScheme.outline,
                          )),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _allButtons(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onOpenAllAtoms,
            icon: const Icon(Icons.list_alt, size: 18),
            label: Text('Все атомы (${atoms.length})'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onOpenAllMoves,
            icon: const Icon(Icons.account_tree_outlined, size: 18),
            label: Text('Все ходы (${moves.length})'),
          ),
        ),
      ],
    );
  }
}

class _ChainStats {
  final int pure;
  final int mixed;
  final int solo;
  const _ChainStats(
      {required this.pure, required this.mixed, required this.solo});
}
