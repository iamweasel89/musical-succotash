import 'package:flutter/material.dart';

import '../models/app_model.dart';
import '../models/hex_pos.dart';
import '../models/node.dart';
import '../models/thesis_entry.dart';
import '../services/api_runner.dart';
import '../services/dump_service.dart';
import 'api_node_sheet.dart';
import 'shared/compress_sheet.dart';

// ── Мастерская: Режим тезисов (Я1–Я8) ────────────────────────────────────────

class ThesisWorkshopScreen extends StatefulWidget {
  final AppModel model;
  const ThesisWorkshopScreen({super.key, required this.model});

  @override
  State<ThesisWorkshopScreen> createState() => _ThesisWorkshopScreenState();
}

class _ThesisWorkshopScreenState extends State<ThesisWorkshopScreen> {
  List<ThesisEntry> get _theses => widget.model.theses;

  @override
  void initState() {
    super.initState();
    widget.model.pushScreen('thesis-workshop');
  }

  @override
  void dispose() {
    widget.model.popScreen();
    super.dispose();
  }

  Future<void> _save() async {
    if (_theses.isEmpty) return;
    await DumpService.saveDump(
      messages: const [],
      canvasName: widget.model.activeCanvas.name,
      theses: _theses
          .map((t) => ThesisDump(
                sourceNodeId: t.sourceNodeId,
                excerpt: t.excerpt,
                thesis: t.thesis,
                answer: t.answer,
              ))
          .toList(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Тезисы сохранены в inbox'),
      duration: Duration(seconds: 2),
    ));
    setState(() => widget.model.clearTheses());
  }

  Future<void> _confirmClear() async {
    if (_theses.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить тезисы?'),
        content: const Text('Все тезисы будут удалены без сохранения.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) setState(() => widget.model.clearTheses());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Режим тезисов'),
        actions: [
          if (_theses.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Очистить все',
              onPressed: _confirmClear,
            ),
            TextButton(
              onPressed: _save,
              child: const Text('В inbox'),
            ),
          ],
        ],
      ),
      body: _theses.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_note_outlined,
                        size: 48, color: Colors.deepPurple),
                    SizedBox(height: 16),
                    Text(
                      'Нет тезисов',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Нажмите ❝ на пузыре в чате чтобы добавить фрагмент.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          : ListenableBuilder(
              listenable: widget.model,
              builder: (context, _) => ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                itemCount: _theses.length,
                itemBuilder: (_, i) => ThesisCard(
                  entry: _theses[i],
                  model: widget.model,
                  onRemove: () => setState(() {
                    _theses.removeAt(i);
                    widget.model.notifyThesesChanged();
                  }),
                  onChanged: () => setState(() {}),
                ),
              ),
            ),
      floatingActionButton: _theses.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _save,
              backgroundColor: Colors.deepPurple,
              icon: const Icon(Icons.save_alt),
              label: const Text('В inbox'),
            )
          : null,
    );
  }
}

// ── ThesisCard ────────────────────────────────────────────────────────────────

class ThesisCard extends StatefulWidget {
  final ThesisEntry entry;
  final AppModel model;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const ThesisCard({
    super.key,
    required this.entry,
    required this.model,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<ThesisCard> createState() => _ThesisCardState();
}

class _ThesisCardState extends State<ThesisCard> {
  late final TextEditingController _thesisCtrl;
  late final TextEditingController _answerCtrl;
  CancelToken? _formulateToken;
  bool _formulating = false;
  String? _formulateError;
  CancelToken? _answerToken;
  bool _answering = false;
  String? _answerError;

  @override
  void initState() {
    super.initState();
    _thesisCtrl = TextEditingController(text: widget.entry.thesis);
    _answerCtrl = TextEditingController(text: widget.entry.answer);
    _thesisCtrl.addListener(() {
      widget.entry.thesis = _thesisCtrl.text;
      widget.onChanged();
    });
    _answerCtrl.addListener(() {
      widget.entry.answer = _answerCtrl.text;
      widget.onChanged();
    });
  }

  @override
  void dispose() {
    _formulateToken?.cancel();
    _answerToken?.cancel();
    _thesisCtrl.dispose();
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _formulateThesis() async {
    if (_formulating) return;
    final excerpt = widget.entry.excerpt.trim();
    if (excerpt.isEmpty) return;

    final settings = widget.model.settings;
    final apiSettings = ApiNodeSettings(
      provider: settings.defaultProvider,
      model: settings.defaultModel,
      maxTokens: settings.defaultMaxTokens,
      temperature: settings.defaultTemperature,
    );
    final stubNode = Node(type: NodeType.api, position: const HexPos(0, 0));
    final prompt =
        'Сформулируй краткий тезис (одна-две фразы) на основе фрагмента ниже. '
        'Верни только сам тезис — без вступлений, комментариев и маркеров списка.\n\n'
        'Фрагмент:\n$excerpt';

    setState(() {
      _formulating = true;
      _formulateError = null;
    });

    final buffer = StringBuffer();
    final token = CancelToken();
    _formulateToken = token;

    await runApiNode(
      node: stubNode,
      messages: [
        <String, dynamic>{'role': 'user', 'content': prompt},
      ],
      settings: settings,
      apiSettings: apiSettings,
      cancelToken: token,
      onChunk: (chunk) {
        if (!mounted) return;
        buffer.write(chunk);
        _thesisCtrl.text = buffer.toString().trim();
      },
      onComplete: (result, _) {
        if (!mounted) return;
        final text = result.trim();
        if (text.isNotEmpty) {
          _thesisCtrl.text = text;
          widget.entry.thesis = text;
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _formulateError = error);
      },
    );

    if (!mounted) return;
    setState(() {
      _formulating = false;
      _formulateToken = null;
    });
  }

  Future<void> _answerThesis() async {
    if (_answering) return;
    final thesis = widget.entry.thesis.trim();
    if (thesis.isEmpty) return;

    final settings = widget.model.settings;
    final apiSettings = ApiNodeSettings(
      provider: settings.defaultProvider,
      model: settings.defaultModel,
      maxTokens: settings.defaultMaxTokens,
      temperature: settings.defaultTemperature,
    );
    final stubNode = Node(type: NodeType.api, position: const HexPos(0, 0));
    final prompt =
        'Ответь кратко и по существу на следующий тезис. '
        'Только ответ — без вступлений и повторения тезиса.\n\n'
        'Тезис:\n$thesis';

    setState(() {
      _answering = true;
      _answerError = null;
    });

    final buffer = StringBuffer();
    final token = CancelToken();
    _answerToken = token;

    await runApiNode(
      node: stubNode,
      messages: [
        <String, dynamic>{'role': 'user', 'content': prompt},
      ],
      settings: settings,
      apiSettings: apiSettings,
      cancelToken: token,
      onChunk: (chunk) {
        if (!mounted) return;
        buffer.write(chunk);
        _answerCtrl.text = buffer.toString().trim();
      },
      onComplete: (result, _) {
        if (!mounted) return;
        final text = result.trim();
        if (text.isNotEmpty) {
          _answerCtrl.text = text;
          widget.entry.answer = text;
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _answerError = error);
      },
    );

    if (!mounted) return;
    setState(() {
      _answering = false;
      _answerToken = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.entry.excerpt.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepPurple[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.entry.excerpt.length > 160
                      ? '${widget.entry.excerpt.substring(0, 160)}…'
                      : widget.entry.excerpt,
                  style: TextStyle(
                      fontSize: 12, color: Colors.deepPurple[700]),
                ),
              ),
            Row(children: [
              const Text('Тезис',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_formulating)
                GestureDetector(
                  onTap: () => _formulateToken?.cancel(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: _formulateThesis,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.auto_awesome,
                        size: 16, color: Colors.deepPurple[400]),
                  ),
                ),
              if (!widget.model.settings.hideCompressButton)
                GestureDetector(
                  onTap: () {
                    if (_thesisCtrl.text.trim().isEmpty) return;
                    openCompressSheet(
                      context,
                      text: _thesisCtrl.text,
                      settings: widget.model.settings,
                      onApply: (r) {
                        setState(() {
                          _thesisCtrl.text = r;
                          widget.entry.thesis = r;
                        });
                        widget.onChanged();
                      },
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.compress,
                        size: 14, color: Colors.deepPurple[300]),
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                  onTap: widget.onRemove,
                  child:
                      const Icon(Icons.close, size: 14, color: Colors.grey)),
            ]),
            if (_formulateError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_formulateError!,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.red)),
              ),
            const SizedBox(height: 4),
            TextField(
              controller: _thesisCtrl,
              maxLines: null,
              style: const TextStyle(fontSize: 13),
              decoration:
                  const InputDecoration(isDense: true, border: InputBorder.none),
            ),
            const Divider(height: 12),
            Row(children: [
              const Text('Ответ',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_answering)
                GestureDetector(
                  onTap: () => _answerToken?.cancel(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: _answerThesis,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.bolt, size: 16, color: Colors.grey[500]),
                  ),
                ),
              if (!widget.model.settings.hideCompressButton)
                GestureDetector(
                  onTap: () {
                    if (_answerCtrl.text.trim().isEmpty) return;
                    openCompressSheet(
                      context,
                      text: _answerCtrl.text,
                      settings: widget.model.settings,
                      onApply: (r) {
                        setState(() {
                          _answerCtrl.text = r;
                          widget.entry.answer = r;
                        });
                        widget.onChanged();
                      },
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.compress, size: 14, color: Colors.grey[400]),
                  ),
                ),
            ]),
            if (_answerError != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_answerError!, style: const TextStyle(fontSize: 11, color: Colors.red)),
              ),
            const SizedBox(height: 4),
            TextField(
              controller: _answerCtrl,
              maxLines: null,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Ваш ответ…',
                border: InputBorder.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
