import 'package:flutter/material.dart';

import '../models/settings.dart';
import '../services/updater.dart';

// ── Usage helpers ─────────────────────────────────────────────────────────

const _pricePerMToken = {
  'anthropic': (3.0, 15.0),   // input, output USD per 1M tokens
  'openai':    (2.5, 10.0),
  'deepseek':  (0.27, 1.10),
};

double _usageCost(String p, int inTok, int outTok) {
  final pr = _pricePerMToken[p];
  if (pr == null) return 0;
  return inTok / 1e6 * pr.$1 + outTok / 1e6 * pr.$2;
}

String _fmtTokens(int n) {
  if (n < 1000) return '$n';
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _fmtCost(double usd) => '\$${usd.toStringAsFixed(4)}';

class SettingsSheet extends StatefulWidget {
  final GlobalSettings settings;
  final VoidCallback onChanged;
  final VoidCallback? onClearAll;
  final VoidCallback? onExport;
  final VoidCallback? onImport;

  const SettingsSheet({
    super.key,
    required this.settings,
    required this.onChanged,
    this.onClearAll,
    this.onExport,
    this.onImport,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _sysPromptCtrl;

  @override
  void initState() {
    super.initState();
    _sysPromptCtrl =
        TextEditingController(text: widget.settings.defaultSystemPrompt);
  }

  @override
  void dispose() {
    _sysPromptCtrl.dispose();
    super.dispose();
  }

  void _save() => widget.onChanged();

  List<Widget> _buildUsageRows(GlobalSettings s) {
    final data = [
      ('Anthropic', 'anthropic', s.tokensInAnthropicTotal, s.tokensOutAnthropicTotal),
      ('OpenAI',    'openai',    s.tokensInOpenaiTotal,    s.tokensOutOpenaiTotal),
      ('DeepSeek',  'deepseek',  s.tokensInDeepseekTotal,  s.tokensOutDeepseekTotal),
    ];
    double totalCost = 0;
    final rows = <Widget>[];
    for (final (name, key, inTok, outTok) in data) {
      final cost = _usageCost(key, inTok, outTok);
      totalCost += cost;
      rows.add(Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(name, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Text(
              '${_fmtTokens(inTok)} in + ${_fmtTokens(outTok)} out',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          Text(_fmtCost(cost),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ],
      ));
    }
    rows.add(const Divider(height: 12));
    rows.add(Row(
      children: [
        const SizedBox(width: 76),
        const Expanded(
          child: Text('Итого',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Text(_fmtCost(totalCost),
            style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600)),
      ],
    ));
    rows.add(const SizedBox(height: 8));
    rows.add(OutlinedButton(
      onPressed: () {
        setState(() {
          s.tokensInAnthropicTotal = 0;
          s.tokensOutAnthropicTotal = 0;
          s.tokensInOpenaiTotal = 0;
          s.tokensOutOpenaiTotal = 0;
          s.tokensInDeepseekTotal = 0;
          s.tokensOutDeepseekTotal = 0;
        });
        _save();
      },
      child: const Text('Сбросить статистику'),
    ));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _SwitchRow(
              label: 'Show node labels',
              value: s.showNodeLabels,
              onChanged: (v) {
                setState(() => s.showNodeLabels = v);
                _save();
              },
            ),
            _SwitchRow(
              label: 'Streaming mode',
              value: s.streamingMode,
              onChanged: (v) {
                setState(() => s.streamingMode = v);
                _save();
              },
            ),
            _SwitchRow(
              label: 'Markdown в ответах',
              value: s.renderMarkdown,
              onChanged: (v) {
                setState(() => s.renderMarkdown = v);
                _save();
              },
            ),
            _SwitchRow(
              label: 'Скрывать эмодзи',
              value: s.hideEmoji,
              onChanged: (v) {
                setState(() => s.hideEmoji = v);
                _save();
              },
            ),
            const SizedBox(height: 12),
            const Text('Системный промпт',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            _SwitchRow(
              label: 'Встроенный промпт',
              value: s.useBuiltinSystemPrompt,
              onChanged: (v) {
                setState(() => s.useBuiltinSystemPrompt = v);
                _save();
              },
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _sysPromptCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: s.useBuiltinSystemPrompt
                    ? 'Дополнение к встроенному промпту (необязательно)'
                    : 'Системный промпт (пусто — без промпта)',
              ),
              onChanged: (v) {
                s.defaultSystemPrompt = v;
                _save();
              },
            ),
            const SizedBox(height: 4),
            // API keys submenu
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('API Keys',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => _ApiKeysSheet(
                  settings: s,
                  onChanged: _save,
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Update section
            const _UpdateSection(),
            const Divider(height: 24),
            // Default API node settings
            const Text('Нода ЛЛМ (умолчания)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'anthropic', label: Text('anthropic')),
                ButtonSegment(value: 'openai', label: Text('openai')),
                ButtonSegment(value: 'deepseek', label: Text('deepseek')),
              ],
              selected: {s.defaultProvider},
              onSelectionChanged: (sel) => setState(() {
                s.defaultProvider = sel.first;
                s.defaultModel = sel.first == 'anthropic'
                    ? 'claude-sonnet-4-5'
                    : sel.first == 'openai'
                        ? 'gpt-4o'
                        : 'deepseek-chat';
                _save();
              }),
            ),
            const SizedBox(height: 8),
            Text('Max tokens',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096]
                  .map((t) => ChoiceChip(
                        label: Text('$t',
                            style: const TextStyle(fontSize: 11)),
                        selected: s.defaultMaxTokens == t,
                        onSelected: (_) {
                          setState(() => s.defaultMaxTokens = t);
                          _save();
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text('Temperature',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [0.0, 0.3, 0.7, 1.0]
                  .map((t) => ChoiceChip(
                        label: Text(t.toString()),
                        selected: s.defaultTemperature == t,
                        onSelected: (_) {
                          setState(() => s.defaultTemperature = t);
                          _save();
                        },
                      ))
                  .toList(),
            ),
            const Divider(height: 24),
            // Compact chat
            const Text('Компактный чат',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            _SwitchRow(
              label: 'Сворачивать по умолчанию',
              value: s.compactChat,
              onChanged: (v) {
                setState(() => s.compactChat = v);
                _save();
              },
            ),
            Row(
              children: [
                const Text('Строк видно:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 4,
                  children: [3, 5, 10]
                      .map((n) => ChoiceChip(
                            label: Text('$n'),
                            selected: s.compactLines == n,
                            onSelected: (_) {
                              setState(() => s.compactLines = n);
                              _save();
                            },
                          ))
                      .toList(),
                ),
              ],
            ),
            if (widget.onExport != null || widget.onImport != null) ...[
              const Divider(height: 24),
              const Text('Данные',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (widget.onExport != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.upload_outlined, size: 18),
                        label: const Text('Экспорт'),
                        onPressed: widget.onExport,
                      ),
                    ),
                  if (widget.onExport != null && widget.onImport != null)
                    const SizedBox(width: 8),
                  if (widget.onImport != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Импорт'),
                        onPressed: widget.onImport,
                      ),
                    ),
                ],
              ),
            ],
            const Divider(height: 24),
            const Text('Использование API',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._buildUsageRows(s),
            if (widget.onClearAll != null) ...[
              const Divider(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text('Очистить все данные',
                      style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red)),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Очистить всё?'),
                        content: const Text(
                            'Все ноды, рёбра и история чата будут удалены. Настройки и ключи сохранятся.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Отмена'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Удалить',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      widget.onClearAll!();
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Reusable switch row ────────────────────────────────────────────────────
class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

// ── API keys sub-sheet ─────────────────────────────────────────────────────
class _ApiKeysSheet extends StatefulWidget {
  final GlobalSettings settings;
  final VoidCallback onChanged;

  const _ApiKeysSheet({required this.settings, required this.onChanged});

  @override
  State<_ApiKeysSheet> createState() => _ApiKeysSheetState();
}

class _ApiKeysSheetState extends State<_ApiKeysSheet> {
  late final TextEditingController _anthropicCtrl;
  late final TextEditingController _openAiCtrl;
  late final TextEditingController _deepSeekCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _anthropicCtrl = TextEditingController(text: s.anthropicKey);
    _openAiCtrl = TextEditingController(text: s.openAiKey);
    _deepSeekCtrl = TextEditingController(text: s.deepSeekKey);
  }

  @override
  void dispose() {
    _anthropicCtrl.dispose();
    _openAiCtrl.dispose();
    _deepSeekCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final s = widget.settings;
    s.anthropicKey = _anthropicCtrl.text.trim();
    s.openAiKey = _openAiCtrl.text.trim();
    s.deepSeekKey = _deepSeekCtrl.text.trim();
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
            const Text('API Keys',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _KeyField(
                label: 'Anthropic', ctrl: _anthropicCtrl, onChanged: _save),
            _KeyField(label: 'OpenAI', ctrl: _openAiCtrl, onChanged: _save),
            _KeyField(
                label: 'DeepSeek', ctrl: _deepSeekCtrl, onChanged: _save),
          ],
        ),
      ),
    );
  }
}

// ── Obscured key field ─────────────────────────────────────────────────────
class _KeyField extends StatefulWidget {
  final String label;
  final TextEditingController ctrl;
  final VoidCallback onChanged;
  const _KeyField(
      {required this.label, required this.ctrl, required this.onChanged});

  @override
  State<_KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<_KeyField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: widget.ctrl,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onChanged: (_) => widget.onChanged(),
      ),
    );
  }
}

// ── Update section ─────────────────────────────────────────────────────────
// Reads from AppUpdater static state — survives bottom-sheet close/reopen.
class _UpdateSection extends StatefulWidget {
  const _UpdateSection();

  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  @override
  void initState() {
    super.initState();
    AppUpdater.addListener(_refresh);
    AppUpdater.resumePollingIfNeeded();
  }

  @override
  void dispose() {
    AppUpdater.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Update',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _buildBody(),
      ],
    );
  }

  Widget _buildBody() {
    switch (AppUpdater.state) {
      case UpdState.idle:
        return OutlinedButton(
          onPressed: AppUpdater.check,
          child: const Text('Check for update'),
        );

      case UpdState.checking:
        return const Row(children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Checking…', style: TextStyle(fontSize: 13)),
        ]);

      case UpdState.upToDate:
        return Row(children: [
          const Icon(Icons.check_circle_outline,
              color: Colors.green, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${AppUpdater.message} — up to date',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          TextButton(
            onPressed: AppUpdater.check,
            child: const Text('Re-check', style: TextStyle(fontSize: 12)),
          ),
        ]);

      case UpdState.available:
        return Row(children: [
          Expanded(
            child: Text('${AppUpdater.message} available',
                style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: AppUpdater.download,
            child: const Text('Download'),
          ),
        ]);

      case UpdState.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Downloading… ${(AppUpdater.progress * 100).round()}%',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: AppUpdater.progress),
          ],
        );

      case UpdState.ready:
        final readiness = AppUpdater.installReadiness;
        final installerLaunched = AppUpdater.message.startsWith('Установщик');
        final warn = installerLaunched
            ? null
            : readiness != null && !readiness.ok
                ? (!readiness.hasPermission
                    ? 'Нет разрешения "Установка из неизвестных источников". Нажмите Install — откроются настройки, выдайте разрешение, затем нажмите ещё раз.'
                    : 'Файл обновления не найден. Попробуйте скачать снова.')
                : null;
        if (installerLaunched) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.system_update_outlined,
                    color: Colors.blue, size: 18),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Установщик запущен',
                      style: TextStyle(fontSize: 13)),
                ),
                TextButton(
                  onPressed: AppUpdater.dismissInstaller,
                  child:
                      const Text('Готово', style: TextStyle(fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                'Следуйте инструкциям установщика. Если диалог не виден — сверните это окно.',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                readiness != null && !readiness.hasPermission
                    ? Icons.warning_amber_outlined
                    : Icons.download_done,
                color: readiness != null && !readiness.hasPermission
                    ? Colors.orange
                    : Colors.green,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Downloaded', style: TextStyle(fontSize: 13)),
              ),
              FilledButton(
                onPressed: AppUpdater.install,
                child: const Text('Install'),
              ),
            ]),
            if (warn != null) ...[
              const SizedBox(height: 4),
              Text(
                warn,
                style: TextStyle(fontSize: 11, color: Colors.orange[800]),
              ),
            ],
          ],
        );

      case UpdState.error:
        return Row(children: [
          Expanded(
            child: Text(
              AppUpdater.message,
              style: const TextStyle(fontSize: 12, color: Colors.red),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: AppUpdater.check,
            child: const Text('Retry', style: TextStyle(fontSize: 12)),
          ),
        ]);
    }
  }
}
