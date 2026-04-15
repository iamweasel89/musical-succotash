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
  /// Если задан — показывается кнопка «Добавить в тезисы» вместо «Копировать всё».
  /// Вызывается со списком выбранных отрывков при подтверждении.
  final void Function(List<String> excerpts)? onConfirm;
  const ExcerptExtractor({super.key, required this.text, this.onConfirm});

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
  bool _inPivot = false;       // hysteresis state for pivot mode
  Set<String> _peakSelection = {}; // largest selection seen in this gesture
  int _currentLineIdx = -1;    // last known paragraph index (hysteresis for _lineIdxAt)
  double _bufferHeight = 215;  // resizable buffer panel height
  bool _isFlinging = false;    // true while inertia scroll animation runs

  // Buffer: list of committed text snippets + parallel word-id sets for pink highlight
  final List<String> _buffer = [];
  final List<Set<String>> _bufferWordIds = [];
  Set<String> _committedIds = {}; // union of all _bufferWordIds, rebuilt on change
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
    // First pass: visual span (first-word top → last-word bottom).
    for (final line in _lines) {
      if (line.words.isEmpty) continue;
      final firstBox = line.words.first.key.currentContext
          ?.findRenderObject() as RenderBox?;
      final lastBox = line.words.last.key.currentContext
          ?.findRenderObject() as RenderBox?;
      if (firstBox == null || !firstBox.hasSize) continue;
      if (lastBox == null || !lastBox.hasSize) continue;
      final top = firstBox.localToGlobal(Offset.zero).dy - 4;
      final bottom =
          lastBox.localToGlobal(Offset.zero).dy + lastBox.size.height + 4;
      if (globalY >= top && globalY <= bottom) {
        _currentLineIdx = line.idx;
        return line.idx;
      }
    }
    // Fallback: nearest paragraph center with hysteresis.
    // The current paragraph gets a 12px bonus — it must be clearly beaten
    // before we switch, preventing oscillation at paragraph boundaries.
    const kHysteresis = 12.0;
    int best = _currentLineIdx;
    double bestDist = double.infinity;

    // Seed bestDist with current paragraph distance (+ hysteresis bonus)
    if (_currentLineIdx >= 0 && _currentLineIdx < _lines.length) {
      final cur = _lines[_currentLineIdx];
      if (cur.words.isNotEmpty) {
        final box = cur.words.first.key.currentContext?.findRenderObject()
            as RenderBox?;
        if (box != null && box.hasSize) {
          final cy = box.localToGlobal(Offset.zero).dy + box.size.height / 2;
          bestDist = (globalY - cy).abs() + kHysteresis;
        }
      }
    }

    for (final line in _lines) {
      if (line.words.isEmpty) continue;
      final box = line.words.first.key.currentContext?.findRenderObject()
          as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final cy = box.localToGlobal(Offset.zero).dy + box.size.height / 2;
      final d = (globalY - cy).abs();
      if (d < bestDist) {
        bestDist = d;
        best = line.idx;
      }
    }
    _currentLineIdx = best;
    return best;
  }

  // When _wordAt returns null (finger between words), find the word whose
  // horizontal center is closest to the finger X. Prevents defaulting to
  // "select entire paragraph" when finger is in an inter-word gap.
  int _nearestWordIdxByX(List<_Word> words, double globalX) {
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < words.length; i++) {
      final box =
          words[i].key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final cx = box.localToGlobal(Offset.zero).dx + box.size.width / 2;
      final d = (globalX - cx).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  // ── Selection computation ─────────────────────────────────────────────

  Set<String> _compute(Offset global) {
    final anchor = _anchorWord;
    if (anchor == null) return {};

    final delta = global - _panStart;
    // Hysteresis: enter pivot when dy>=20, dx>=8, AND dy>=30% of dx (prevents
    // accidental pivot on primarily-horizontal swipes with slight vertical drift).
    // Exit pivot only at dy<15 to prevent oscillation around the entry threshold.
    final absDy = delta.dy.abs();
    final absDx = delta.dx.abs();
    if (absDy >= 20 && absDx >= _kThreshold && absDy >= absDx * 0.3) {
      _inPivot = true;
    } else if (absDy < 15) {
      _inPivot = false;
    }
    final inPivot = _inPivot;

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
      if (curLineIdx == anchorLineIdx) {
        // Still within anchor paragraph — select up to touch word (not whole paragraph).
        // Our _Line is a paragraph; forcing end-of-line here would snap to paragraph end.
        return _wordsOnAnchorLine(anchor, global, clamped: false);
      }
      // Crossed into a different paragraph: full paragraph-spanning mode.
      // Anchor paragraph: anchor word → end
      _addRange(_lines[anchorLineIdx].words, anchor.wordIdx,
          _lines[anchorLineIdx].words.length - 1, result);
      // Intermediate paragraphs: full
      for (int li = anchorLineIdx + 1; li < curLineIdx; li++) {
        for (final w in _lines[li].words) result.add(w.id);
      }
      // Current paragraph: start → touch word (or nearest by X if no hit)
      final curLine = _lines[curLineIdx];
      final touchWord = _wordAt(global);
      final endIdx = (touchWord?.lineIdx == curLineIdx)
          ? touchWord!.wordIdx
          : _nearestWordIdxByX(curLine.words, global.dx);
      _addRange(curLine.words, 0, endIdx, result);
    } else {
      // Left + up
      if (curLineIdx == anchorLineIdx) {
        return _wordsOnAnchorLine(anchor, global, clamped: false);
      }
      // Anchor paragraph: start → anchor word
      _addRange(_lines[anchorLineIdx].words, 0, anchor.wordIdx, result);
      // Intermediate paragraphs: full
      for (int li = curLineIdx + 1; li < anchorLineIdx; li++) {
        for (final w in _lines[li].words) result.add(w.id);
      }
      // Current (topmost) paragraph: touch word → end (or nearest by X if no hit)
      final curLine = _lines[curLineIdx];
      final touchWord = _wordAt(global);
      final startIdx = (touchWord?.lineIdx == curLineIdx)
          ? touchWord!.wordIdx
          : _nearestWordIdxByX(curLine.words, global.dx);
      _addRange(curLine.words, startIdx, curLine.words.length - 1, result);
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
        // Only use hit-tested word if it's on the same line AND to the right
        if (w?.lineIdx == anchor.lineIdx && w!.wordIdx >= anchor.wordIdx) {
          end = w.wordIdx;
        }
      }
      _addRange(line.words, anchor.wordIdx, end, result);
    } else {
      int start = 0;
      if (!clamped && global != null) {
        final w = _wordAt(global);
        // Only use hit-tested word if it's on the same line AND to the left
        if (w?.lineIdx == anchor.lineIdx && w!.wordIdx <= anchor.wordIdx) {
          start = w.wordIdx;
        }
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

  void _commit([Set<String>? sel]) {
    final effective = sel ?? _currentSelection;
    if (effective.isEmpty) return;
    final selected = _allWords.where((w) => effective.contains(w.id));
    final text = selected.map((w) => w.text).join(' ');
    if (text.trim().isEmpty) return;
    setState(() {
      _buffer.add(text.trim());
      _bufferWordIds.add(Set.from(effective));
      _rebuildCommittedIds();
      _currentSelection = {};
    });
  }

  void _rebuildCommittedIds() {
    _committedIds = _bufferWordIds.fold(<String>{}, (acc, s) => acc..addAll(s));
  }

  void _undo() {
    if (_buffer.isEmpty) return;
    setState(() {
      _buffer.removeLast();
      _bufferWordIds.removeLast();
      _rebuildCommittedIds();
    });
  }

  void _removeChip(int i) => setState(() {
    _buffer.removeAt(i);
    _bufferWordIds.removeAt(i);
    _rebuildCommittedIds();
  });

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

  void _selectAll() {
    final text = widget.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _buffer.add(text);
      _bufferWordIds.add(_allWords.map((w) => w.id).toSet());
      _rebuildCommittedIds();
    });
  }

  // ── Gesture handlers ──────────────────────────────────────────────────

  void _stopFling() {
    if (_isFlinging) {
      _scrollController.jumpTo(_scrollController.offset);
      _isFlinging = false;
    }
  }

  void _startFling(double velocityDy) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // velocityDy > 0: finger moved down → content scrolls up → offset decreases
    final distance = -velocityDy * 0.35;
    final target =
        (pos.pixels + distance).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((target - pos.pixels).abs() < 2) return;
    final ms = (velocityDy.abs() * 0.4).clamp(200.0, 700.0).round();
    _isFlinging = true;
    _scrollController
        .animateTo(target,
            duration: Duration(milliseconds: ms), curve: Curves.decelerate)
        .then((_) => _isFlinging = false);
  }

  void _onPanStart(DragStartDetails d) {
    _stopFling(); // cancel any running inertia scroll
    _phase = _Phase.determining;
    _panStart = d.globalPosition;
    _panCurrent = d.globalPosition;
    _anchorWord = _wordAt(d.globalPosition);
    _hDir = '';
    _currentSelection = {};
    _inPivot = false;
    _peakSelection = {};
    _currentLineIdx = _anchorWord?.lineIdx ?? -1;
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
      final next = _compute(_panCurrent); // updates _inPivot via hysteresis
      if (next.length > _peakSelection.length) _peakSelection = next;
      // Log uses _inPivot (already updated by _compute)
      final curVDir = delta.dy > 0 ? 'down' : 'up';
      final allowedVDir = _hDir == 'right' ? 'down' : 'up';
      final mode = !_inPivot
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

  void _onPanEnd(DragEndDetails d) {
    if (_phase == _Phase.selecting) {
      // If finger jitter on lift shrank selection to <50% of peak, use peak instead
      final sel = (_peakSelection.isNotEmpty &&
              _currentSelection.length * 2 < _peakSelection.length)
          ? _peakSelection
          : _currentSelection;
      final text = _selectionText(sel);
      _addLog('PAN_END committed="${text}" words=${sel.length}'
          ' (cur=${_currentSelection.length} peak=${_peakSelection.length})');
      _commit(sel);
    } else if (_phase == _Phase.scrolling) {
      _addLog('PAN_END phase=$_phase (no commit)');
      final vel = d.velocity.pixelsPerSecond.dy;
      if (vel.abs() > 80) _startFling(vel);
    } else {
      _addLog('PAN_END phase=$_phase (no commit)');
    }
    _phase = _Phase.idle;
    _lastMode = '';
    _anchorWord = null;
    _inPivot = false;
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
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: 'Весь текст',
            onPressed: _selectAll,
          ),
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
              onTapDown: (_) => _stopFling(),
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
          if (_buffer.isNotEmpty) _buildResizableBuffer(context),
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
    final committed = !sel && _committedIds.contains(word.id);
    return Container(
      key: word.key,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: sel
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(3),
            )
          : committed
              ? BoxDecoration(
                  color: const Color(0xFFFFB6C1).withOpacity(0.55),
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

  Widget _buildResizableBuffer(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Draggable divider with handle
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) {
            setState(() {
              _bufferHeight =
                  (_bufferHeight - d.delta.dy).clamp(80.0, 480.0);
            });
          },
          child: Container(
            height: 18,
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        // Buffer content
        SizedBox(
          height: _bufferHeight,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Выбранное',
                        style: Theme.of(context).textTheme.labelSmall),
                    const Spacer(),
                    if (widget.onConfirm != null)
                      TextButton(
                        onPressed: () {
                          widget.onConfirm!(List.of(_buffer));
                          Navigator.of(context).pop();
                        },
                        child: const Text('В тезисы'),
                      )
                    else
                      TextButton(
                        onPressed: _copyAll,
                        child: const Text('Копировать всё'),
                      ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(
                        _buffer.length,
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer
                                  .withOpacity(0.6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding:
                                const EdgeInsets.fromLTRB(10, 6, 4, 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    _buffer[i],
                                    style:
                                        const TextStyle(fontSize: 12),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _removeChip(i),
                                  child: const Padding(
                                    padding: EdgeInsets.fromLTRB(
                                        6, 0, 4, 0),
                                    child: Icon(Icons.close, size: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
