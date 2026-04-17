// ── Usage event (для журнала последних LLM-запросов) ───────────────────────

class UsageEvent {
  final String provider; // 'anthropic' | 'openai' | 'deepseek'
  final int inputTokens;
  final int outputTokens;
  final double cost; // USD
  final DateTime timestamp;
  final String context; // 'chat' | 'web-search' | 'web-search-tool' | 'transform' | ...

  const UsageEvent({
    required this.provider,
    required this.inputTokens,
    required this.outputTokens,
    required this.cost,
    required this.timestamp,
    required this.context,
  });

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'cost': cost,
        'timestamp': timestamp.toIso8601String(),
        'context': context,
      };

  factory UsageEvent.fromJson(Map<String, dynamic> j) => UsageEvent(
        provider: j['provider'] as String? ?? '',
        inputTokens: j['inputTokens'] as int? ?? 0,
        outputTokens: j['outputTokens'] as int? ?? 0,
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ??
            DateTime.now(),
        context: j['context'] as String? ?? '',
      );
}

/// Тарифы по провайдерам: (input_usd_per_M, output_usd_per_M)
const llmPricePerMToken = {
  'anthropic': (3.0, 15.0),
  'openai': (2.5, 10.0),
  'deepseek': (0.27, 1.10),
};

double calculateCost(String provider, int inTok, int outTok) {
  final pr = llmPricePerMToken[provider];
  if (pr == null) return 0;
  return inTok / 1e6 * pr.$1 + outTok / 1e6 * pr.$2;
}
