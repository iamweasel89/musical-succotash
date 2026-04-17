import 'package:flutter/material.dart';

import '../../models/settings.dart';

// ── Секция «Использование API» — токены + стоимость ─────────────────────────

const _pricePerMToken = {
  'anthropic': (3.0, 15.0), // input, output USD per 1M tokens
  'openai': (2.5, 10.0),
  'deepseek': (0.27, 1.10),
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

class UsageSection extends StatelessWidget {
  final GlobalSettings settings;
  final VoidCallback onReset;

  const UsageSection({
    super.key,
    required this.settings,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final data = [
      ('Anthropic', 'anthropic', s.tokensInAnthropicTotal, s.tokensOutAnthropicTotal),
      ('OpenAI', 'openai', s.tokensInOpenaiTotal, s.tokensOutOpenaiTotal),
      ('DeepSeek', 'deepseek', s.tokensInDeepseekTotal, s.tokensOutDeepseekTotal),
    ];
    double totalCost = 0;
    final rows = <Widget>[
      const Text('Использование API',
          style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
    ];
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
      onPressed: onReset,
      child: const Text('Сбросить статистику'),
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}
