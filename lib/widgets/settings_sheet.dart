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
  late final TextEditingController _anthropicCtrl;
  late final TextEditingController _openAiCtrl;
  late final TextEditingController _deepSeekCtrl;
  late final TextEditingController _sysPromptCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _anthropicCtrl = TextEditingController(text: s.anthropicKey);
    _openAiCtrl = TextEditingController(text: s.openAiKey);
    _deepSeekCtrl = TextEditingController(text: s.deepSeekKey);
    _sysPromptCtrl = TextEditingController(text: s.defaultSystemPrompt);
  }

  @override
  void dispose() {
    _anthropicCtrl.dispose();
    _openAiCtrl.dispose();
    _deepSeekCtrl.dispose();
    _sysPromptCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final s = widget.settings;
    s.anthropicKey = _anthropicCtrl.text.trim();
    s.openAiKey = _openAiCtrl.text.trim();
    s.deepSeekKey = _deepSeekCtrl.text.trim();
    s.defaultSystemPrompt = _sysPromptCtrl.text;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('API Keys',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _KeyField(label: 'Anthropic', ctrl: _anthropicCtrl, onChanged: _save),
            _KeyField(label: 'OpenAI', ctrl: _openAiCtrl, onChanged: _save),
            _KeyField(label: 'DeepSeek', ctrl: _deepSeekCtrl, onChanged: _save),
            const SizedBox(height: 16),
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
              onChanged: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Streaming mode',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Switch(
                  value: widget.settings.streamingMode,
                  onChanged: (v) {
                    setState(() => widget.settings.streamingMode = v);
                    _save();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
