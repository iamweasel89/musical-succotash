import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_model.dart';
import '../models/screen_snapshot.dart';
import '../models/settings.dart';
import '../services/updater.dart';
import 'masterskaya_screen.dart';
import 'settings/chat_display_section.dart';
import 'settings/data_section.dart';
import 'settings/default_llm_section.dart';
import 'settings/switch_row.dart';
import 'settings/usage_section.dart';

// ── Главный экран настроек — оркестратор секций ────────────────────────────

class SettingsSheet extends StatefulWidget {
  final AppModel model;
  final GlobalSettings settings;
  final VoidCallback onChanged;
  final VoidCallback? onClearAll;
  final VoidCallback? onExport;
  final VoidCallback? onImport;

  const SettingsSheet({
    super.key,
    required this.model,
    required this.settings,
    required this.onChanged,
    this.onClearAll,
    this.onExport,
    this.onImport,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet>
    implements ScreenSnapshotProvider {
  late final TextEditingController _sysPromptCtrl;

  @override
  void initState() {
    super.initState();
    _sysPromptCtrl =
        TextEditingController(text: widget.settings.defaultSystemPrompt);
    widget.model.pushScreen('settings', provider: this);
  }

  @override
  void dispose() {
    widget.model.popScreen();
    _sysPromptCtrl.dispose();
    super.dispose();
  }

  @override
  String get screenName => 'settings';

  @override
  Map<String, dynamic> capture() {
    final s = widget.settings;
    return {
      'kind': 'settings',
      'title': 'Настройки',
      'defaultProvider': s.defaultProvider,
      'defaultModel': s.defaultModel,
      'useBuiltinSystemPrompt': s.useBuiltinSystemPrompt,
      'defaultSystemPrompt': s.defaultSystemPrompt,
      'streamingMode': s.streamingMode,
      'renderMarkdown': s.renderMarkdown,
      'hideEmoji': s.hideEmoji,
      'showBubbleTime': s.showBubbleTime,
      'showBubbleId': s.showBubbleId,
      'hideThesisButton': s.hideThesisButton,
      'hideCompressButton': s.hideCompressButton,
      'compactChat': s.compactChat,
      'compactLines': s.compactLines,
      'debugServerEnabled': s.debugServerEnabled,
      'debugServerPort': s.debugServerPort,
      'hasAnthropicKey': s.anthropicKey.isNotEmpty,
      'hasOpenAiKey': s.openAiKey.isNotEmpty,
      'hasDeepSeekKey': s.deepSeekKey.isNotEmpty,
      'hasTavilyKey': s.tavilyKey.isNotEmpty,
    };
  }

  /// Вызывается секциями при любом изменении настройки. Персистим + rebuild.
  void _onChanged() {
    setState(() {});
    widget.onChanged();
  }

  void _resetTokenUsage() {
    setState(() {
      final s = widget.settings;
      s.tokensInAnthropicTotal = 0;
      s.tokensOutAnthropicTotal = 0;
      s.tokensInOpenaiTotal = 0;
      s.tokensOutOpenaiTotal = 0;
      s.tokensInDeepseekTotal = 0;
      s.tokensOutDeepseekTotal = 0;
    });
    widget.onChanged();
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

            // Базовые флаги
            SwitchRow(
              label: 'Show node labels',
              value: s.showNodeLabels,
              onChanged: (v) { s.showNodeLabels = v; _onChanged(); },
            ),
            SwitchRow(
              label: 'Streaming mode',
              value: s.streamingMode,
              onChanged: (v) { s.streamingMode = v; _onChanged(); },
            ),
            SwitchRow(
              label: 'Markdown в ответах',
              value: s.renderMarkdown,
              onChanged: (v) { s.renderMarkdown = v; _onChanged(); },
            ),
            SwitchRow(
              label: 'Скрывать эмодзи',
              value: s.hideEmoji,
              onChanged: (v) { s.hideEmoji = v; _onChanged(); },
            ),

            const SizedBox(height: 12),
            const Text('Системный промпт',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            SwitchRow(
              label: 'Встроенный промпт',
              value: s.useBuiltinSystemPrompt,
              onChanged: (v) { s.useBuiltinSystemPrompt = v; _onChanged(); },
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
                widget.onChanged();
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
                  onChanged: widget.onChanged,
                ),
              ),
            ),
            const Divider(height: 1),

            const SizedBox(height: 12),
            const _UpdateSection(),
            const Divider(height: 24),

            DefaultLlmSection(settings: s, onChanged: _onChanged),
            const Divider(height: 24),

            ChatDisplaySection(settings: s, onChanged: _onChanged),
            const Divider(height: 24),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.handyman_outlined),
              title: const Text('Мастерская'),
              subtitle: const Text('Инструменты в разработке'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MasterskayaScreen(model: widget.model),
              )),
            ),

            if (widget.onExport != null ||
                widget.onImport != null ||
                widget.onClearAll != null) ...[
              const Divider(height: 24),
              DataSection(
                onExport: widget.onExport,
                onImport: widget.onImport,
                onClearAll: widget.onClearAll,
              ),
            ],

            const Divider(height: 24),
            UsageSection(
                model: widget.model, settings: s, onReset: _resetTokenUsage),
          ],
        ),
      ),
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
  late final TextEditingController _tavilyCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _anthropicCtrl = TextEditingController(text: s.anthropicKey);
    _openAiCtrl = TextEditingController(text: s.openAiKey);
    _deepSeekCtrl = TextEditingController(text: s.deepSeekKey);
    _tavilyCtrl = TextEditingController(text: s.tavilyKey);
  }

  @override
  void dispose() {
    _anthropicCtrl.dispose();
    _openAiCtrl.dispose();
    _deepSeekCtrl.dispose();
    _tavilyCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final s = widget.settings;
    s.anthropicKey = _anthropicCtrl.text.trim();
    s.openAiKey = _openAiCtrl.text.trim();
    s.deepSeekKey = _deepSeekCtrl.text.trim();
    s.tavilyKey = _tavilyCtrl.text.trim();
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
            _KeyField(label: 'Anthropic', ctrl: _anthropicCtrl, onChanged: _save),
            _KeyField(label: 'OpenAI', ctrl: _openAiCtrl, onChanged: _save),
            _KeyField(label: 'DeepSeek', ctrl: _deepSeekCtrl, onChanged: _save),
            _KeyField(
                label: 'Tavily (web search)',
                ctrl: _tavilyCtrl,
                onChanged: _save),
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
  String _buildLabel = '';

  @override
  void initState() {
    super.initState();
    AppUpdater.addListener(_refresh);
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _buildLabel = 'Build ${info.buildNumber}');
    });
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
        Row(children: [
          const Text('Update',
              style: TextStyle(fontWeight: FontWeight.w600)),
          if (_buildLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(_buildLabel,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() => AppUpdater.showLog = !AppUpdater.showLog);
            },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: Text(AppUpdater.showLog ? 'Скрыть лог' : 'Лог',
                style: const TextStyle(fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 8),
        _buildBody(),
        if (AppUpdater.showLog) _buildLog(),
      ],
    );
  }

  Widget _buildLog() {
    final lines = AppUpdater.log;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(6),
      ),
      constraints: const BoxConstraints(maxHeight: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('Updater log',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.white54,
                    fontFamily: 'monospace')),
            const Spacer(),
            GestureDetector(
              onTap: () {
                final text = AppUpdater.log.reversed.join('\n');
                Clipboard.setData(ClipboardData(text: text));
              },
              child: const Text('copy',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white38,
                      fontFamily: 'monospace')),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: AppUpdater.clearLog,
              child: const Text('clear',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white38,
                      fontFamily: 'monospace')),
            ),
          ]),
          const SizedBox(height: 4),
          Expanded(
            child: lines.isEmpty
                ? const Text('(пусто)',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white38,
                        fontFamily: 'monospace'))
                : ListView.builder(
                    itemCount: lines.length,
                    reverse: true,
                    itemBuilder: (_, i) => Text(
                      lines[lines.length - 1 - i],
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.greenAccent,
                          fontFamily: 'monospace'),
                    ),
                  ),
          ),
        ],
      ),
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
