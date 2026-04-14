import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Data model ────────────────────────────────────────────────────────────

class _Word {
  final String text;
  final int lineIdx;
  final int wordIdx;
  final GlobalKey key = GlobalKey();

  _Word({required this.text, required this.lineIdx, required this.wordIdx});

  String get id => '$lineIdx:$wordIdx';
}

class _Line {
  final int idx;
  final List<_Word> words;
  _Line({required this.idx, required this.words});
}

enum _Phase { idle, determining, selecting, scrolling }

// ── Screen ────────────────────────────────────────────────────────────────

class ExcerptExtractor extends StatefulWidget {
  final String text;
  const ExcerptExtractor({super.key, required this.text});

  @override
  State<ExcerptExtractor> createState() => _ExcerptExtractorState();
}

class _ExcerptExtractorState extends State<ExcerptExtractor> {
  late List<_Line> _lines;
  late List<_Word> _allWords;

  _Phase _phase = _Phase.idle;
  Offset _panStart = Offset.zero;
  Offset _panCurrent = Offset.zero;
  String _hDir = ''; // 'left' | 'right'
  _Word? _anchorWord;
  Set<String> _currentSelection = {};

  // Buffer: list of committed text snippets
  final List<String> _buffer = [];
  // Diagnostic log (not shown in UI, only count + copy)
  final List<String> _log = [];

  final _scrollController = ScrollController();

  static const double _kThreshold = 8.0;

  @override
  void initState() {
    super.initState();
    _parseText();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _parseText() {
    _lines = [];
    _allWords = [];
    final rawLines = widget.text.split('\n');
    for (int li = 0; li < rawLines.length; li++) {
      final rawWords = rawLines[li]
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      final words = <_Word>[];
      for (int wi = 0; wi < rawWords.length; wi++) {
        final w = _Word(text: rawWords[wi], lineIdx: li, wordIdx: wi);
        words.add(w);
        _allWords.add(w);
      }
      _lines.add(_Line(idx: li, words: words));
    }
  }

  // ── Hit-testing ───────────────────────────────────────────────────────

  _Word? _wordAt(Offset global) {
    for (final word in _allWords) {
      final box = word.key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final tl = box.localToGlobal(Offset.zero);
      final rect = Rect.fromLTWH(tl.dx, tl.dy - 4, box.size.width, box.size.height + 8);
      if (rect.contains(global)) return word;
    }
    return null;
  }

  int _lineIdxAt(double globalY) {
    int best = -1;
    double bestDist = double.infinity;
    for (final line in _lines) {
      if (line.words.isEmpty) continue;
      final box = line.words.first.key.currentContext?.findRenderObject()
          as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final tl = box.localToGlobal(Offset.zero);
      final cy = tl.dy + box.size.height / 2;
      final d = (globalY - cy).abs();
      if (d < bestDist) {
        bestDist = d;
        best = line.idx;
      }
    }
    return best;
  }

  // ── Selection computation ─────────────────────────────────────────────

  Set<String> _compute(Offset global) {
    final anchor = _anchorWord;
    if (anchor == null) return {};

    final delta = global - _panStart;
    final inPivot = delta.dy.abs() > 20 && delta.dx.abs() > _kThreshold;

    if (!inPivot) {
      return _wordsOnAnchorLine(anchor, global, clamped: false);
    }

    final curVDir = delta.dy > 0 ? 'down' : 'up';
    final allowedVDir = _hDir == 'right' ? 'down' : 'up';

    if (curVDir != allowedVDir) {
      // Wrong vertical direction — clamp to anchor line
      return _wordsOnAnchorLine(anchor, null, clamped: true);
    }

    // Full pivot selection
    final curLineIdx = _lineIdxAt(global.dy);
    if (curLineIdx == -1) return _wordsOnAnchorLine(anchor, null, clamped: true);

    final result = <String>{};
    final anchorLineIdx = anchor.lineIdx;

    if (_hDir == 'right') {
      // Anchor line: anchor word → end
      _addRange(_lines[anchorLineIdx].words, anchor.wordIdx,
          _lines[anchorLineIdx].words.length - 1, result);
      // Intermediate lines: full
      for (int li = anchorLineIdx + 1; li < curLineIdx; li++) {
        for (final w in _lines[li].words) result.add(w.id);
      }
      // Current line: start → touch word
      if (curLineIdx > anchorLineIdx) {
        final curLine = _lines[curLineIdx];
        final touchWord = _wordAt(global);
        final endIdx = (touchWord?.lineIdx == curLineIdx)
            ? touchWord!.wordIdx
            : curLine.words.length - 1;
        _addRange(curLine.words, 0, endIdx, result);
      }
    } else {
      // Left + up
      // Anchor line: start → anchor word
      _addRange(_lines[anchorLineIdx].words, 0, anchor.wordIdx, result);
      // Intermediate lines: full
      for (int li = curLineIdx + 1; li < anchorLineIdx; li++) {
        for (final w in _lines[li].words) result.add(w.id);
      }
      // Current (topmost) line: touch word → end
      if (curLineIdx < anchorLineIdx) {
        final curLine = _lines[curLineIdx];
        final touchWord = _wordAt(global);
        final startIdx = (touchWord?.lineIdx == curLineIdx)
            ? touchWord!.wordIdx
            : 0;
        _addRange(curLine.words, startIdx, curLine.words.length - 1, result);
      }
    }

    return result;
  }

  Set<String> _wordsOnAnchorLine(_Word anchor, Offset? global,
      {required bool clamped}) {
    final line = _lines[anchor.lineIdx];
    final result = <String>{};
    if (_hDir == 'right') {
      int end = line.words.length - 1;
      if (!clamped && global != null) {
        final w = _wordAt(global);
        if (w?.lineIdx == anchor.lineIdx) end = w!.wordIdx;
      }
      _addRange(line.words, anchor.wordIdx, end, result);
    } else {
      int start = 0;
      if (!clamped && global != null) {
        final w = _wordAt(global);
        if (w?.lineIdx == anchor.lineIdx) start = w!.wordIdx;
      }
      _addRange(line.words, start, anchor.wordIdx, result);
    }
    return result;
  }

  void _addRange(List<_Word> words, int from, int to, Set<String> out) {
    final lo = from.clamp(0, words.length - 1);
    final hi = to.clamp(0, words.length - 1);
    for (int i = lo; i <= hi; i++) out.add(words[i].id);
  }

  // ── Buffer management ─────────────────────────────────────────────────

  void _commit() {
    if (_currentSelection.isEmpty) return;
    final selected = _allWords.where((w) => _currentSelection.contains(w.id));
    final text = selected.map((w) => w.text).join(' ');
    if (text.trim().isEmpty) return;
    setState(() {
      _buffer.add(text.trim());
      _currentSelection = {};
    });
  }

  void _undo() {
    if (_buffer.isEmpty) return;
    setState(() => _buffer.removeLast());
  }

  void _removeChip(int i) => setState(() => _buffer.removeAt(i));

  Future<void> _copyAll() async {
    final text = _buffer.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Скопировано')));
  }

  void _addLog(String entry) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    _log.add('[$ts] $entry');
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _log.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Лог скопирован')));
  }

  // ── Gesture handlers ──────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    _phase = _Phase.determining;
    _panStart = d.globalPosition;
    _panCurrent = d.globalPosition;
    _anchorWord = _wordAt(d.globalPosition);
    _hDir = '';
    _currentSelection = {};
    setState(() {
      _addLog('PAN_START x=${d.globalPosition.dx.toStringAsFixed(1)}'
          ' y=${d.globalPosition.dy.toStringAsFixed(1)}'
          ' anchor="${_anchorWord?.text ?? "none"}"'
          ' line=${_anchorWord?.lineIdx ?? -1}'
          ' wordIdx=${_anchorWord?.wordIdx ?? -1}');
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    _panCurrent = d.globalPosition;
    final delta = _panCurrent - _panStart;

    if (_phase == _Phase.determining) {
      if (delta.dx.abs() > _kThreshold) {
        _phase = _Phase.selecting;
        _hDir = delta.dx > 0 ? 'right' : 'left';
        _anchorWord ??= _wordAt(_panStart);
        _addLog('DIRECTION h=$_hDir'
            ' dx=${delta.dx.toStringAsFixed(1)}'
            ' dy=${delta.dy.toStringAsFixed(1)}');
      } else if (delta.dy.abs() > _kThreshold) {
        _phase = _Phase.scrolling;
        _addLog('DIRECTION scroll'
            ' dx=${delta.dx.toStringAsFixed(1)}'
            ' dy=${delta.dy.toStringAsFixed(1)}');
      }
    }

    if (_phase == _Phase.selecting) {
      final prev = _currentSelection;
      final next = _compute(_panCurrent);
      // Log pivot detection and mode changes
      final inPivot = delta.dy.abs() > 20 && delta.dx.abs() > _kThreshold;
      final curVDir = delta.dy > 0 ? 'down' : 'up';
      final allowedVDir = _hDir == 'right' ? 'down' : 'up';
      final mode = !inPivot
          ? 'horizontal'
          : (curVDir != allowedVDir ? 'clamped' : 'pivot-$curVDir');
      if (prev.length != next.length || mode != _lastMode) {
        _addLog('SELECT mode=$mode'
            ' words=${next.length}'
            ' text="${_selectionText(next)}"'
            ' dx=${delta.dx.toStringAsFixed(1)}'
            ' dy=${delta.dy.toStringAsFixed(1)}');
        _lastMode = mode;
      }
      setState(() => _currentSelection = next);
    } else if (_phase == _Phase.scrolling) {
      final pos = _scrollController.position;
      final next = (_scrollController.offset - d.delta.dy)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      _scrollController.jumpTo(next);
    }
  }

  String _lastMode = '';

  String _selectionText(Set<String> sel) {
    final words = _allWords.where((w) => sel.contains(w.id)).map((w) => w.text);
    final joined = words.join(' ');
    return joined.length > 40 ? '${joined.substring(0, 40)}…' : joined;
  }

  void _onPanEnd(DragEndDetails _) {
    if (_phase == _Phase.selecting) {
      final text = _selectionText(_currentSelection);
      _addLog('PAN_END committed="${text}" words=${_currentSelection.length}');
      _commit();
    } else {
      _addLog('PAN_END phase=$_phase (no commit)');
    }
    _phase = _Phase.idle;
    _lastMode = '';
    _anchorWord = null;
    if (_currentSelection.isNotEmpty) {
      setState(() => _currentSelection = {});
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Извлечение'),
        actions: [
          if (_buffer.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Назад',
              onPressed: _undo,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _lines.map(_buildLine).toList(),
                ),
              ),
            ),
          ),
          if (_buffer.isNotEmpty) _buildBuffer(context),
          _buildLogBar(context),
        ],
      ),
    );
  }

  Widget _buildLine(_Line line) {
    if (line.words.isEmpty) return const SizedBox(height: 10);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        spacing: 0,
        children: line.words.map(_buildWord).toList(),
      ),
    );
  }

  Widget _buildWord(_Word word) {
    final sel = _currentSelection.contains(word.id);
    return Container(
      key: word.key,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: sel
          ? BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(3),
            )
          : null,
      child: Text('${word.text} ',
          style: Theme.of(context).textTheme.bodyMedium),
    );
  }

  Widget _buildLogBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Text('Лог: ${_log.length}',
              style: Theme.of(context).textTheme.labelSmall),
          const Spacer(),
          TextButton(
            onPressed: _log.isEmpty ? null : _copyLog,
            child: const Text('Копировать лог'),
          ),
        ],
      ),
    );
  }

  Widget _buildBuffer(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Выбранное',
                  style: Theme.of(context).textTheme.labelSmall),
              const Spacer(),
              TextButton(
                onPressed: _copyAll,
                child: const Text('Копировать всё'),
              ),
            ],
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: List.generate(
                  _buffer.length,
                  (i) => InputChip(
                    label: Text(
                      _buffer[i].length > 40
                          ? '${_buffer[i].substring(0, 40)}…'
                          : _buffer[i],
                      style: const TextStyle(fontSize: 12),
                    ),
                    onDeleted: () => _removeChip(i),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
