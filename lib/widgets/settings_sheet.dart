import 'package:flutter/material.dart';
import '../models/settings.dart';

class SettingsSheet extends StatefulWidget {
  final GlobalSettings settings;
  final VoidCallback onChanged;

  const SettingsSheet({
    super.key,
    required this.settings,
    required this.onChanged,
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
            // Show node labels
            _SwitchRow(
              label: 'Show node labels',
              value: s.showNodeLabels,
              onChanged: (v) {
                setState(() => s.showNodeLabels = v);
                _save();
              },
            ),
            // Streaming mode
            _SwitchRow(
              label: 'Streaming mode',
              value: s.streamingMode,
              onChanged: (v) {
                setState(() => s.streamingMode = v);
                _save();
              },
            ),
            const SizedBox(height: 12),
            // Default system prompt
            const Text('Default system prompt',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _sysPromptCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Leave empty for no system prompt',
              ),
              onChanged: (v) {
                s.defaultSystemPrompt = v;
                _save();
              },
            ),
            const SizedBox(height: 12),
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
