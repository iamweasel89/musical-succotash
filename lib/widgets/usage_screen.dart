import 'package:flutter/material.dart';

import '../models/app_model.dart';
import '../models/screen_snapshot.dart';
import '../models/usage_event.dart';

// ── Использование API (отдельный экран) ─────────────────────────────────────
// Тотaлы по провайдерам + журнал последних N запросов.

class UsageScreen extends StatefulWidget {
  final AppModel model;
  const UsageScreen({super.key, required this.model});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen>
    implements ScreenSnapshotProvider {
  @override
  void initState() {
    super.initState();
    widget.model.pushScreen('usage', provider: this);
  }

  @override
  void dispose() {
    widget.model.popScreen();
    super.dispose();
  }

  @override
  String get screenName => 'usage';

  @override
  Map<String, dynamic> capture() {
    final s = widget.model.settings;
    return {
      'kind': 'usage',
      'title': 'Использование API',
      'tokensIn': {
        'anthropic': s.tokensInAnthropicTotal,
        'openai': s.tokensInOpenaiTotal,
        'deepseek': s.tokensInDeepseekTotal,
      },
      'tokensOut': {
        'anthropic': s.tokensOutAnthropicTotal,
        'openai': s.tokensOutOpenaiTotal,
        'deepseek': s.tokensOutDeepseekTotal,
      },
      'recentCount': widget.model.recentUsage.length,
    };
  }

  Future<void> _resetTotals() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить счётчики?'),
        content: const Text('Обнулятся тотaлы по провайдерам. Журнал останется.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сбросить')),
        ],
      ),
    );
    if (ok == true) setState(() => widget.model.resetTokenUsage());
  }

  Future<void> _clearLog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить журнал?'),
        content: const Text('Будут удалены записи о последних LLM-запросах.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Очистить', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) setState(() => widget.model.clearRecentUsage());
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.model.settings;
    final events = widget.model.recentUsage.reversed.toList(); // новые сверху
    final totals = [
      ('Anthropic', 'anthropic', s.tokensInAnthropicTotal,
          s.tokensOutAnthropicTotal),
      ('OpenAI', 'openai', s.tokensInOpenaiTotal, s.tokensOutOpenaiTotal),
      ('DeepSeek', 'deepseek', s.tokensInDeepseekTotal,
          s.tokensOutDeepseekTotal),
    ];
    double totalCost = 0;
    for (final t in totals) {
      totalCost += calculateCost(t.$2, t.$3, t.$4);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Использование API'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Тотaлы
          const Text('Тотaлы', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final (name, key, inTok, outTok) in totals)
            _TotalRow(
              name: name,
              inTok: inTok,
              outTok: outTok,
              cost: calculateCost(key, inTok, outTok),
            ),
          const Divider(),
          Row(
            children: [
              const SizedBox(width: 90),
              const Expanded(
                  child: Text('Итого',
                      style: TextStyle(fontWeight: FontWeight.w600))),
              Text(_fmtCost(totalCost),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Сбросить тотaлы'),
            onPressed: _resetTotals,
          ),

          const Divider(height: 32),

          // Журнал
          Row(
            children: [
              const Expanded(
                child: Text('Последние запросы',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (events.isNotEmpty)
                TextButton(
                  onPressed: _clearLog,
                  child: const Text('Очистить'),
                ),
            ],
          ),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('(журнал пуст — пока не было LLM-вызовов)',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            )
          else
            ...events.map((e) => _EventTile(event: e)),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String name;
  final int inTok;
  final int outTok;
  final double cost;

  const _TotalRow({
    required this.name,
    required this.inTok,
    required this.outTok,
    required this.cost,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(name, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: Text(
              '${_fmtTokens(inTok)} in + ${_fmtTokens(outTok)} out',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          Text(_fmtCost(cost),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final UsageEvent event;

  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                _fmtShortTime(event.timestamp),
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                event.provider,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Text(
                '${_fmtTokens(event.inputTokens)}/${_fmtTokens(event.outputTokens)}  ·  ${event.context}',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            ),
            Text(
              _fmtCost(event.cost),
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtTokens(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '${(n / 1000).round()}k';
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
