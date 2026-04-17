import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../models/app_model.dart';
import '../models/screen_snapshot.dart';
import '../models/settings.dart';
import '../models/web_search_room.dart';
import '../services/agent_runner.dart';
import 'shared/compress_sheet.dart';
import 'web_search_detail_screen.dart';

// ── Мастерская: Веб-поиск (ПО) ────────────────────────────────────────────────

class WebSearchScreen extends StatefulWidget {
  final AppModel model;
  const WebSearchScreen({super.key, required this.model});

  @override
  State<WebSearchScreen> createState() => _WebSearchScreenState();
}

class _WebSearchScreenState extends State<WebSearchScreen>
    implements ScreenSnapshotProvider {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _busy = false;
  final List<String> _liveLogs = [];
  int _visibleFirst = 0;
  int _visibleLast = 0;
  DateTime? _busyStartAt;
  Timer? _elapsedTicker;

  AppModel get _m => widget.model;
  List<WebSearchMessage> get _msgs => _m.webSearchMessages;
  WebSearchConfig get _cfg => _m.webSearchConfig;

  @override
  void initState() {
    super.initState();
    _m.pushScreen('web-search', provider: this);
    _scroll.addListener(_updateVisibleRange);
  }

  @override
  void dispose() {
    _m.popScreen();
    _scroll.removeListener(_updateVisibleRange);
    _elapsedTicker?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _updateVisibleRange() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final count = _buildSessions().length;
    if (count == 0 || pos.maxScrollExtent <= 0) {
      _visibleFirst = 0;
      _visibleLast = count - 1;
      return;
    }
    final total = pos.maxScrollExtent + pos.viewportDimension;
    final avgH = total / count;
    if (avgH <= 0) return;
    _visibleFirst = (pos.pixels / avgH).floor().clamp(0, count - 1);
    _visibleLast =
        ((pos.pixels + pos.viewportDimension) / avgH).ceil().clamp(0, count - 1);
  }

  @override
  String get screenName => 'web-search';

  @override
  Map<String, dynamic> capture() {
    _updateVisibleRange();
    // Сессии новее→старее (как в UI).
    final sessions = _buildSessions().reversed.toList();
    final items = <Map<String, dynamic>>[];
    final from = _visibleFirst.clamp(0, sessions.length);
    final to = (_visibleLast + 1).clamp(0, sessions.length);
    for (var i = from; i < to; i++) {
      final s = sessions[i];
      final qText = s.query.text;
      final aText = s.answer?.text ?? '';
      final status = s.answer?.status;
      final completed = status != null &&
          status != 'running' &&
          status != 'interrupted';
      items.add({
        'index': i,
        'queryId': s.query.id,
        'queryPreview':
            qText.length > 160 ? '${qText.substring(0, 160)}…' : qText,
        'answered': completed,
        'answerStatus': status,
        'answerPreview':
            aText.length > 160 ? '${aText.substring(0, 160)}…' : aText,
        'createdAt': s.query.createdAt.toIso8601String(),
      });
    }
    return {
      'kind': 'web-search',
      'title': 'Веб-поиск',
      'provider': _cfg.provider,
      'model': _cfg.model,
      'sessionCount': sessions.length,
      'visibleRange': [_visibleFirst, _visibleLast],
      'busy': _busy,
      'liveLogs': _busy ? _liveLogs : const <String>[],
      'items': items,
    };
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

  void _startElapsedTicker() {
    _elapsedTicker?.cancel();
    _elapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {}); // просто ребилд для обновления отображаемых секунд
    });
  }

  void _stopElapsedTicker() {
    _elapsedTicker?.cancel();
    _elapsedTicker = null;
  }

  int? _busyElapsedSeconds() {
    if (_busyStartAt == null) return null;
    return DateTime.now().difference(_busyStartAt!).inSeconds;
  }

  Future<void> _send({String? retryQuery}) async {
    final query = retryQuery ?? _input.text.trim();
    if (query.isEmpty || _busy) return;

    // Сразу создаём assistant со status='running'. Объект живёт в AppModel —
    // если виджет будет unmounted, мы всё равно обновим эту же ссылку
    // (и сохраним через notifyWebSearchChanged).
    final assistant = WebSearchMessage(
      role: 'assistant',
      text: '',
      status: 'running',
    );
    setState(() {
      if (retryQuery == null) {
        _msgs.add(WebSearchMessage(role: 'user', text: query));
        _input.clear();
      }
      _msgs.add(assistant);
      _busy = true;
      _busyStartAt = DateTime.now();
      _liveLogs.clear();
    });
    _startElapsedTicker();
    _m.notifyWebSearchChanged();
    _scrollToEnd();

    // Контекст запроса — все user/assistant сообщения КРОМЕ только что
    // добавленного пустого assistant'а.
    final apiMessages = _msgs
        .where((m) =>
            (m.role == 'user' || m.role == 'assistant') && m.id != assistant.id)
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
          assistant.logs.add(line);
          if (mounted) {
            setState(() => _liveLogs.add(line));
            _scrollToEnd();
          }
          _m.notifyWebSearchChanged();
        },
      );

      assistant.text = result.text.isEmpty ? '(пустой ответ)' : result.text;
      assistant.status = result.status == 'limit' ? 'limit' : 'success';
      _stopElapsedTicker();
      if (mounted) {
        setState(() {
          _liveLogs.clear();
          _busy = false;
          _busyStartAt = null;
        });
      } else {
        _busy = false;
        _busyStartAt = null;
      }
      _m.addTokenUsage(_cfg.provider, result.inputTokens, result.outputTokens,
          context: 'web-search');
      _m.notifyWebSearchChanged();
      _scrollToEnd();
    } catch (e) {
      assistant.text = 'Ошибка: $e';
      assistant.status = 'error';
      _stopElapsedTicker();
      if (mounted) {
        setState(() {
          _liveLogs.clear();
          _busy = false;
          _busyStartAt = null;
        });
      } else {
        _busy = false;
        _busyStartAt = null;
      }
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

  // Новый поиск — модальная шторка с полем ввода. После отправки — карточка-
  // сеанс появляется в списке, агент работает в фоне.
  void _openNewSearchSheet() {
    if (_busy) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _InputBar(
          controller: _input,
          busy: _busy,
          onSend: () {
            Navigator.pop(ctx);
            _send();
          },
        ),
      ),
    );
  }

  // Группировка плоского списка сообщений в сеансы (user query + answer).
  List<_Session> _buildSessions() {
    final out = <_Session>[];
    for (var i = 0; i < _msgs.length; i++) {
      final m = _msgs[i];
      if (m.role != 'user') continue;
      WebSearchMessage? ans;
      if (i + 1 < _msgs.length && _msgs[i + 1].role == 'assistant') {
        ans = _msgs[i + 1];
      }
      out.add(_Session(m, ans));
    }
    return out;
  }

  // Повторить сеанс (interrupted / error): удалить старый assistant и
  // запустить _send с тем же текстом. User-сообщение переиспользуем.
  void _retrySession(_Session s) {
    if (_busy) return;
    if (s.answer != null) {
      setState(() {
        _msgs.removeWhere((m) => m.id == s.answer!.id);
      });
      _m.notifyWebSearchChanged();
    }
    _send(retryQuery: s.query.text);
  }

  // Удалить сеанс целиком (запрос + ответ если есть).
  void _deleteSession(_Session s) {
    setState(() {
      _msgs.removeWhere(
          (m) => m.id == s.query.id || (s.answer != null && m.id == s.answer!.id));
    });
    _m.notifyWebSearchChanged();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _buildSessions();
    // Новее — наверху.
    final reversed = sessions.reversed.toList();
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
              tooltip: 'Очистить всё',
              onPressed: _confirmClear,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _openNewSearchSheet,
        icon: const Icon(Icons.add),
        label: const Text('Новый поиск'),
      ),
      body: SafeArea(
        child: reversed.isEmpty && !_busy
            ? const _EmptyHint()
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: reversed.length,
                itemBuilder: (ctx, i) {
                  final s = reversed[i];
                  final isRunning = s.answer?.status == 'running';
                  final isRetryable = s.answer?.status == 'interrupted' ||
                      s.answer?.status == 'error';
                  return _SessionCard(
                    session: s,
                    running: isRunning,
                    liveLogs: isRunning
                        ? (s.answer?.logs.isNotEmpty == true
                            ? s.answer!.logs
                            : _liveLogs)
                        : const [],
                    elapsedSeconds: isRunning ? _busyElapsedSeconds() : null,
                    retryable: isRetryable,
                    onRetry: isRetryable ? () => _retrySession(s) : null,
                    onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => WebSearchDetailScreen(
                        query: s.query,
                        answer: s.answer,
                        liveLogs: isRunning
                            ? List<String>.from(
                                s.answer?.logs.isNotEmpty == true
                                    ? s.answer!.logs
                                    : _liveLogs)
                            : null,
                        running: isRunning,
                        elapsedSeconds:
                            isRunning ? _busyElapsedSeconds() : null,
                      ),
                    )),
                    onDelete: () => _deleteSession(s),
                    settings: _m.settings,
                  );
                },
              ),
      ),
    );
  }
}

// ── Session: пара «запрос + ответ» ─────────────────────────────────────────

class _Session {
  final WebSearchMessage query;
  final WebSearchMessage? answer;
  const _Session(this.query, this.answer);
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

// ── Session card: один сеанс-подраздел в ленте ────────────────────────────

class _SessionCard extends StatelessWidget {
  final _Session session;
  final bool running;
  final List<String> liveLogs;
  final int? elapsedSeconds;
  final bool retryable;
  final VoidCallback? onRetry;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final GlobalSettings settings;

  const _SessionCard({
    required this.session,
    required this.running,
    required this.liveLogs,
    required this.elapsedSeconds,
    required this.retryable,
    required this.onRetry,
    required this.onOpen,
    required this.onDelete,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final q = session.query;
    final a = session.answer;
    final ts = q.createdAt;

    IconData? statusIcon;
    Color? statusColor;
    String? statusTooltip;
    if (running) {
      statusTooltip = 'Идёт поиск';
    } else if (a == null) {
      statusIcon = Icons.hourglass_empty;
      statusColor = Colors.grey;
      statusTooltip = 'Нет ответа';
    } else {
      switch (a.status) {
        case 'limit':
          statusIcon = Icons.warning_amber_outlined;
          statusColor = Colors.orange[700];
          statusTooltip = 'Упёрся в лимит итераций';
          break;
        case 'error':
          statusIcon = Icons.error_outline;
          statusColor = Colors.red[400];
          statusTooltip = 'Ошибка';
          break;
        case 'interrupted':
          statusIcon = Icons.power_settings_new;
          statusColor = Colors.orange[900];
          statusTooltip = 'Сеанс был прерван';
          break;
        default:
          statusIcon = Icons.check_circle_outline;
          statusColor = Colors.green[600];
          statusTooltip = 'Готово';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onOpen,
        onLongPress: () => _showActions(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (running)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (statusIcon != null)
                    Tooltip(
                      message: statusTooltip ?? '',
                      child: Icon(statusIcon, size: 16, color: statusColor),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _fmtTime(ts),
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  if (running && elapsedSeconds != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${elapsedSeconds}s',
                      style: TextStyle(
                        fontSize: 11,
                        color: elapsedSeconds! > 60
                            ? Colors.orange[700]
                            : Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (retryable && onRetry != null)
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Повторить сеанс',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 28, minHeight: 28),
                      onPressed: onRetry,
                    ),
                  Text(
                    '#${q.id.substring(0, 6)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500],
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                q.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
              if (running && liveLogs.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final l in liveLogs.take(3))
                  Text(l,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      )),
              ] else if (a != null) ...[
                const SizedBox(height: 4),
                Text(
                  a.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtTime(DateTime t) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${two(t.hour)}:${two(t.minute)}';
    }
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
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
              title: const Text('Скопировать запрос'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: session.query.text));
                Navigator.pop(ctx);
              },
            ),
            if (session.answer != null)
              ListTile(
                leading: const Icon(Icons.copy_all),
                title: const Text('Скопировать ответ'),
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: session.answer!.text));
                  Navigator.pop(ctx);
                },
              ),
            if (!settings.hideCompressButton && session.answer != null)
              ListTile(
                leading: const Icon(Icons.compress),
                title: const Text('Сжать ответ…'),
                onTap: () {
                  Navigator.pop(ctx);
                  openCompressSheet(
                    context,
                    text: session.answer!.text,
                    settings: settings,
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Удалить сеанс',
                  style: TextStyle(color: Colors.red)),
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
