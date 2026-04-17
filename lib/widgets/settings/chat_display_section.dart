import 'package:flutter/material.dart';

import '../../models/settings.dart';
import 'switch_row.dart';

// ── Секция «Компактный чат + Компоненты UI» ─────────────────────────────────

class ChatDisplaySection extends StatelessWidget {
  final GlobalSettings settings;
  final VoidCallback onChanged;

  const ChatDisplaySection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Компактный чат',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        SwitchRow(
          label: 'Сворачивать по умолчанию',
          value: s.compactChat,
          onChanged: (v) {
            s.compactChat = v;
            onChanged();
          },
        ),
        SwitchRow(
          label: 'Время на пузыре',
          value: s.showBubbleTime,
          onChanged: (v) {
            s.showBubbleTime = v;
            onChanged();
          },
        ),
        SwitchRow(
          label: 'ID на пузыре',
          value: s.showBubbleId,
          onChanged: (v) {
            s.showBubbleId = v;
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        const Text('Компоненты UI',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey)),
        SwitchRow(
          label: 'Скрыть кнопку тезиса на пузыре',
          value: s.hideThesisButton,
          onChanged: (v) {
            s.hideThesisButton = v;
            onChanged();
          },
        ),
        SwitchRow(
          label: 'Скрыть кнопку compress (сжатие)',
          value: s.hideCompressButton,
          onChanged: (v) {
            s.hideCompressButton = v;
            onChanged();
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
                          s.compactLines = n;
                          onChanged();
                        },
                      ))
                  .toList(),
            ),
          ],
        ),
      ],
    );
  }
}
