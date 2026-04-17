import 'package:flutter_test/flutter_test.dart';

import 'package:hex_canvas_mobile/models/web_search_room.dart';

void main() {
  group('WebSearchMessage', () {
    test('round-trip через JSON', () {
      final m = WebSearchMessage(
        role: 'assistant',
        text: 'Ответ',
        logs: ['Tavily: ok', 'fallback skipped'],
        createdAt: DateTime(2026, 4, 17, 15, 0),
      );
      final j = m.toJson();
      final restored = WebSearchMessage.fromJson(j);

      expect(restored.id, m.id);
      expect(restored.role, 'assistant');
      expect(restored.text, 'Ответ');
      expect(restored.logs, ['Tavily: ok', 'fallback skipped']);
      expect(restored.createdAt, m.createdAt);
    });

    test('default role user если поле отсутствует', () {
      final restored = WebSearchMessage.fromJson({
        'text': 'hi',
        'createdAt': DateTime.now().toIso8601String(),
      });
      expect(restored.role, 'user');
    });

    test('пустые logs сериализуются в пустой список', () {
      final m = WebSearchMessage(role: 'user', text: 'q');
      final restored = WebSearchMessage.fromJson(m.toJson());
      expect(restored.logs, isEmpty);
    });
  });

  group('WebSearchConfig', () {
    test('дефолты', () {
      final c = WebSearchConfig();
      expect(c.provider, 'deepseek');
      expect(c.model, 'deepseek-chat');
      expect(c.systemPrompt, defaultWebSearchSystemPrompt);
    });

    test('round-trip через JSON', () {
      final c = WebSearchConfig(
        systemPrompt: 'custom prompt',
        provider: 'anthropic',
        model: 'claude-sonnet-4-5',
      );
      final restored = WebSearchConfig.fromJson(c.toJson());
      expect(restored.systemPrompt, 'custom prompt');
      expect(restored.provider, 'anthropic');
      expect(restored.model, 'claude-sonnet-4-5');
    });

    test('fromJson с пропущенными полями → дефолты', () {
      final restored = WebSearchConfig.fromJson({});
      expect(restored.provider, 'deepseek');
      expect(restored.systemPrompt, defaultWebSearchSystemPrompt);
    });
  });
}
