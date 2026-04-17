import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_model.dart';
import '../models/settings.dart';
import '../models/web_search_room.dart';
import '../services/agent_runner.dart';
import 'compress_sheet.dart';

// ── Мастерская: Веб-поиск (ПО) ────────────────────────────────────────────────

class WebSearchScreen extends StatefulWidget {
  final AppModel model;
  const WebSearchScreen({super.key, required this.model});

  @override
  State<WebSearchScreen> createState() => _WebSearchScreenState();
}

class _WebSearchScreenState extends State<WebSearchScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _busy = false;
  final List<String> _liveLogs = [];

  AppModel get _m => widget.model;
  List<WebSearchMessage> get _msgs => _m.webSearchMessages;
  WebSearchConfig get _cfg => _m.webSearchConfig;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final query = _input.text.trim();
    if (query.isEmpty || _busy) return;

    setState(() {
      _msgs.add(WebSearchMessage(role: 'user', text: query));
      _input.clear();
      _busy = true;
      _liveLogs.clear();
    });
    _m.notifyWebSearchChanged();
    _scrollToEnd();

    final apiMessages = _msgs
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .map((m) => <String, dynamic>{'role': m.role, 'content': m.text})
        .toList();

    try {
      final result = await runAgentTurn(
        messages: apiMessages,
        systemPrompt: _cfg.systemPrompt,
        provider: _cfg.provider,
        model: _cfg.model,
        settings: _m.settings,
        onLog: (line) {
          if (!mounted) return;
          setState(() => _liveLogs.add(line));
          _scrollToEnd();
        },
      );

      if (!mounted) return;
      setState(() {
        _msgs.add(WebSearchMessage(
          role: 'assistant',
          text: result.text.isEmpty ? '(пустой ответ)' : result.text,
          logs: List<String>.from(_liveLogs),
        ));
        _liveLogs.clear();
        _busy = false;
      });
      _m.addTokenUsage(_cfg.provider, result.inputTokens, result.outputTokens);
      _m.notifyWebSearchChanged();
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.add(WebSearchMessage(
          role: 'assistant',
          text: 'Ошибка: $e',
          logs: List<String>.from(_liveLogs),
        ));
        _liveLogs.clear();
        _busy = false;
      });
      _m.notifyWebSearchChanged();
      _scrollToEnd();
    }
  }

  Future<void> _confirmClear() async {
    if (_msgs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить историю поиска?'),
        content: const Text('Все сообщения будут удалены.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _m.clearWebSearch());
    }
  }

  void _deleteMessage(String id) {
    setState(() => _msgs.removeWhere((m) => m.id == id));
    _m.notifyWebSearchChanged();
  }

  void _openConfig() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConfigSheet(
        config: _cfg,
        onChanged: () {
          _m.notifyWebSearchChanged();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Веб-поиск'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Настройки комнаты',
            onPressed: _openConfig,
          ),
          if (_msgs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Очистить историю',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _msgs.isEmpty && !_busy
                  ? const _EmptyHint()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _msgs.length + (_busy ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i < _msgs.length) {
                          final m = _msgs[i];
                          return _MessageTile(
                            message: m,
                            onDelete: () => _deleteMessage(m.id),
                            settings: _m.settings,
                          );
                        }
                        return _BusyTile(logs: _liveLogs);
                      },
                    ),
            ),
            _InputBar(
              controller: _input,
              busy: _busy,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Задайте вопрос — агент использует web_search.\n'
          'Tavily основной, DuckDuckGo резерв.',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ── Message tile ───────────────────────────────────────────────────────────

class _MessageTile extends StatelessWidget {
  final WebSearchMessage message;
  final VoidCallback onDelete;
  final GlobalSettings settings;

  const _MessageTile({
    required this.message,
    required this.onDelete,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isUser ? Colors.blue[50] : Colors.grey[100];
    final border = isUser ? Colors.blue[100]! : Colors.grey[300]!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isUser && message.logs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: message.logs
                    .map((l) => Text(l,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        )))
                    .toList(),
              ),
            ),
          Align(
            alignment: align,
            child: GestureDetector(
              onLongPress: () => _showActions(context),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.85,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: bg,
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  message.text,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Скопировать'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.text));
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.compress),
              title: const Text('Сжать…'),
              onTap: () {
                Navigator.pop(ctx);
                openCompressSheet(
                  context,
                  text: message.text,
                  settings: settings,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Удалить', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Busy tile (live logs while waiting) ────────────────────────────────────

class _BusyTile extends StatelessWidget {
  final List<String> logs;
  const _BusyTile({required this.logs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...logs.map((l) => Text(l,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ))),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('думает…', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Input bar ──────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              enabled: !busy,
              decoration: const InputDecoration(
                hintText: 'Запрос…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: busy ? null : onSend,
          ),
        ],
      ),
    );
  }
}

// ── Config sheet (system prompt + LLM) ─────────────────────────────────────

class _ConfigSheet extends StatefulWidget {
  final WebSearchConfig config;
  final VoidCallback onChanged;
  const _ConfigSheet({required this.config, required this.onChanged});

  @override
  State<_ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends State<_ConfigSheet> {
  late final TextEditingController _promptCtrl;
  late final TextEditingController _modelCtrl;
  late String _provider;

  static const _providers = ['deepseek', 'openai', 'anthropic'];
  static const _defaultModels = {
    'deepseek': 'deepseek-chat',
    'openai': 'gpt-4o',
    'anthropic': 'claude-sonnet-4-5',
  };

  @override
  void initState() {
    super.initState();
    _promptCtrl = TextEditingController(text: widget.config.systemPrompt);
    _modelCtrl = TextEditingController(text: widget.config.model);
    _provider = widget.config.provider;
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _save() {
    widget.config.systemPrompt = _promptCtrl.text;
    widget.config.provider = _provider;
    widget.config.model = _modelCtrl.text.trim();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Настройки комнаты',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Системный промпт', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            TextField(
              controller: _promptCtrl,
              minLines: 4,
              maxLines: 12,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (_) => _save(),
            ),
            const SizedBox(height: 16),
            const Text('LLM провайдер', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: _provider,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: _providers
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _provider = v;
                  _modelCtrl.text = _defaultModels[v] ?? '';
                });
                _save();
              },
            ),
            const SizedBox(height: 12),
            const Text('Модель', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => _save(),
            ),
          ],
        ),
      ),
    );
  }
}
