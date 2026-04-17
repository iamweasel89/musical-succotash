import 'package:flutter/material.dart';

import '../../models/app_model.dart';
import '../../models/settings.dart';
import '../../models/usage_event.dart';
import '../usage_screen.dart';

// ── Секция «Использование API» — компактно, с кнопкой «Подробнее» ───────────

class UsageSection extends StatelessWidget {
  final AppModel model;
  final GlobalSettings settings;
  final VoidCallback onReset;

  const UsageSection({
    super.key,
    required this.model,
    required this.settings,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final totals = [
      ('anthropic', s.tokensInAnthropicTotal, s.tokensOutAnthropicTotal),
      ('openai', s.tokensInOpenaiTotal, s.tokensOutOpenaiTotal),
      ('deepseek', s.tokensInDeepseekTotal, s.tokensOutDeepseekTotal),
    ];
    double totalCost = 0;
    for (final t in totals) {
      totalCost += calculateCost(t.$1, t.$2, t.$3);
    }
    final lastEventAt = model.recentUsage.isEmpty
        ? null
        : model.recentUsage.last.timestamp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Использование API',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                'Итого: ${_fmtCost(totalCost)}'
                '${lastEventAt != null ? "  ·  последний: ${_fmtShortTime(lastEventAt)}" : ""}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.bar_chart, size: 16),
              label: const Text('Подробнее'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => UsageScreen(model: model),
              )),
            ),
          ],
        ),
      ],
    );
  }
}

String _fmtCost(double usd) => '\$${usd.toStringAsFixed(4)}';

String _fmtShortTime(DateTime t) {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return '${two(t.hour)}:${two(t.minute)}';
  }
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
