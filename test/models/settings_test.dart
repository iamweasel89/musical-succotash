import 'package:flutter_test/flutter_test.dart';

import 'package:hex_canvas_mobile/models/settings.dart';

void main() {
  test('Settings round-trip через JSON (все новые поля)', () {
    final s = GlobalSettings(
      anthropicKey: 'ak',
      openAiKey: 'ok',
      deepSeekKey: 'dk',
      tavilyKey: 'tk',
      defaultProvider: 'openai',
      defaultModel: 'gpt-4o',
      defaultMaxTokens: 2048,
      defaultTemperature: 0.7,
      streamingMode: true,
      renderMarkdown: true,
      hideEmoji: true,
      compactChat: true,
      compactLines: 10,
      showBubbleTime: true,
      showBubbleId: true,
      hideThesisButton: true,
      hideCompressButton: true,
      debugServerEnabled: true,
      debugServerPort: 9999,
      debugServerToken: 'tok123',
      tokensInAnthropicTotal: 100,
      tokensOutAnthropicTotal: 200,
    );

    final restored = GlobalSettings.fromJson(s.toJson());

    expect(restored.anthropicKey, 'ak');
    expect(restored.tavilyKey, 'tk');
    expect(restored.defaultProvider, 'openai');
    expect(restored.defaultMaxTokens, 2048);
    expect(restored.hideThesisButton, true);
    expect(restored.hideCompressButton, true);
    expect(restored.debugServerEnabled, true);
    expect(restored.debugServerPort, 9999);
    expect(restored.debugServerToken, 'tok123');
    expect(restored.tokensInAnthropicTotal, 100);
    expect(restored.tokensOutAnthropicTotal, 200);
  });

  test('Settings fromJson({}) → дефолты', () {
    final s = GlobalSettings.fromJson({});
    expect(s.anthropicKey, '');
    expect(s.tavilyKey, '');
    expect(s.defaultProvider, 'deepseek');
    expect(s.debugServerPort, 8080);
    expect(s.hideThesisButton, false);
    expect(s.hideCompressButton, false);
    expect(s.debugServerToken, '');
  });

  test('Settings backwards-compat: старый JSON без новых полей', () {
    // Симулируем сохранение из более старой версии приложения
    final oldJson = <String, dynamic>{
      'anthropicKey': 'key',
      'defaultProvider': 'anthropic',
    };
    final s = GlobalSettings.fromJson(oldJson);
    expect(s.anthropicKey, 'key');
    expect(s.defaultProvider, 'anthropic');
    expect(s.tavilyKey, ''); // новое поле — дефолт
    expect(s.debugServerEnabled, false);
    expect(s.hideCompressButton, false);
  });
}
