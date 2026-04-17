import 'package:flutter/material.dart';

import '../../models/settings.dart';

// ── Секция «Нода ЛЛМ (умолчания)» — провайдер, maxTokens, temperature ───────

class DefaultLlmSection extends StatelessWidget {
  final GlobalSettings settings;
  final VoidCallback onChanged;

  const DefaultLlmSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  static const _maxTokensPresets = [
    8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096,
  ];
  static const _tempPresets = [0.0, 0.3, 0.7, 1.0];

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          onSelectionChanged: (sel) {
            s.defaultProvider = sel.first;
            s.defaultModel = sel.first == 'anthropic'
                ? 'claude-sonnet-4-5'
                : sel.first == 'openai'
                    ? 'gpt-4o'
                    : 'deepseek-chat';
            onChanged();
          },
        ),
        const SizedBox(height: 8),
        Text('Max tokens',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: _maxTokensPresets
              .map((t) => ChoiceChip(
                    label: Text('$t', style: const TextStyle(fontSize: 11)),
                    selected: s.defaultMaxTokens == t,
                    onSelected: (_) {
                      s.defaultMaxTokens = t;
                      onChanged();
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
          children: _tempPresets
              .map((t) => ChoiceChip(
                    label: Text(t.toString()),
                    selected: s.defaultTemperature == t,
                    onSelected: (_) {
                      s.defaultTemperature = t;
                      onChanged();
                    },
                  ))
              .toList(),
        ),
      ],
    );
  }
}
