import 'package:flutter_test/flutter_test.dart';

import 'package:hex_canvas_mobile/models/usage_event.dart';

void main() {
  test('UsageEvent round-trip через JSON', () {
    final e = UsageEvent(
      provider: 'deepseek',
      inputTokens: 1500,
      outputTokens: 400,
      cost: 0.00085,
      timestamp: DateTime(2026, 4, 17, 17, 30),
      context: 'web-search',
    );
    final restored = UsageEvent.fromJson(e.toJson());
    expect(restored.provider, 'deepseek');
    expect(restored.inputTokens, 1500);
    expect(restored.outputTokens, 400);
    expect(restored.cost, 0.00085);
    expect(restored.timestamp, e.timestamp);
    expect(restored.context, 'web-search');
  });

  test('calculateCost для разных провайдеров', () {
    // anthropic: 3.0/15.0 per M
    // 1M in + 1M out = 3 + 15 = 18
    expect(calculateCost('anthropic', 1000000, 1000000), closeTo(18.0, 0.001));
    // openai: 2.5/10.0
    expect(calculateCost('openai', 1000000, 1000000), closeTo(12.5, 0.001));
    // deepseek: 0.27/1.10
    expect(calculateCost('deepseek', 1000000, 1000000), closeTo(1.37, 0.001));
    // unknown provider
    expect(calculateCost('unknown', 100, 100), 0.0);
    // 0 tokens → 0 cost
    expect(calculateCost('anthropic', 0, 0), 0.0);
  });
}
