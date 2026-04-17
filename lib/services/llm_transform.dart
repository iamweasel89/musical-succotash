import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/settings.dart';

// ── LLM Transform (ПТ-ядро) ──────────────────────────────────────────────────
// Общий слой LLM-трансформаций текста: один вход → один выход по инструкции.
// Используется пресетами (compress/tldr/translate/…), long-press action'ами
// на нодах и как агентский tool `llm_transform`.
//
// Не streaming, не tool_use. Провайдер/модель — из settings.defaultProvider/
// defaultModel, при необходимости override параметрами.

Future<String> llmTransform({
  required String text,
  required String instruction,
  required GlobalSettings settings,
  String? providerOverride,
  String? modelOverride,
  int maxTokens = 1024,
  double temperature = 0.3,
}) async {
  if (text.trim().isEmpty) return '';
  final provider = providerOverride ?? settings.defaultProvider;
  final model = modelOverride ?? settings.defaultModel;
  final key = _keyFor(provider, settings);
  if (key.isEmpty) {
    throw Exception('Нет ключа API для провайдера «$provider».');
  }

  final systemPrompt =
      'Ты — инструмент преобразования текста. Следуй инструкции точно. '
      'Не добавляй вступлений, комментариев, объяснений или метаданных. '
      'Возвращай только результат преобразования.';

  final userContent = '$instruction\n\nТекст:\n$text';

  switch (provider) {
    case 'anthropic':
      return _callAnthropic(model, key, systemPrompt, userContent, maxTokens,
          temperature);
    case 'openai':
    case 'deepseek':
      return _callOpenAiCompat(provider, model, key, systemPrompt, userContent,
          maxTokens, temperature);
    default:
      throw Exception('Unknown provider: $provider');
  }
}

String _keyFor(String provider, GlobalSettings s) {
  switch (provider) {
    case 'anthropic':
      return s.anthropicKey;
    case 'openai':
      return s.openAiKey;
    case 'deepseek':
      return s.deepSeekKey;
    default:
      return '';
  }
}

Future<String> _callAnthropic(String model, String key, String systemPrompt,
    String userContent, int maxTokens, double temperature) async {
  final r = await http.post(
    Uri.parse('https://api.anthropic.com/v1/messages'),
    headers: {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: jsonEncode({
      'model': model,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': userContent},
      ],
    }),
  );
  if (r.statusCode != 200) {
    throw Exception('Anthropic HTTP ${r.statusCode}: ${r.body}');
  }
  final json = jsonDecode(r.body) as Map<String, dynamic>;
  final content = (json['content'] as List? ?? []);
  return content
      .whereType<Map<String, dynamic>>()
      .where((b) => b['type'] == 'text')
      .map((b) => b['text'] as String? ?? '')
      .join();
}

Future<String> _callOpenAiCompat(String provider, String model, String key,
    String systemPrompt, String userContent, int maxTokens, double temperature) async {
  final url = provider == 'openai'
      ? 'https://api.openai.com/v1/chat/completions'
      : 'https://api.deepseek.com/v1/chat/completions';
  final r = await http.post(
    Uri.parse(url),
    headers: {
      'Authorization': 'Bearer $key',
      'content-type': 'application/json',
    },
    body: jsonEncode({
      'model': model,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userContent},
      ],
    }),
  );
  if (r.statusCode != 200) {
    throw Exception('${provider.toUpperCase()} HTTP ${r.statusCode}: ${r.body}');
  }
  final json = jsonDecode(r.body) as Map<String, dynamic>;
  final choices = json['choices'] as List? ?? [];
  if (choices.isEmpty) return '';
  final msg = (choices.first as Map<String, dynamic>)['message']
      as Map<String, dynamic>;
  return msg['content'] as String? ?? '';
}

// ── Пресеты (ПТ2) ────────────────────────────────────────────────────────────

Future<String> compress({
  required String text,
  required int n,
  required GlobalSettings settings,
}) =>
    llmTransform(
      text: text,
      instruction:
          'Сожми этот текст до $n ${_plural(n, "строки", "строк", "строк")}. '
          'Сохрани главное, выброси подробности. Без вступлений.',
      settings: settings,
    );

Future<String> tldr({
  required String text,
  required GlobalSettings settings,
}) =>
    llmTransform(
      text: text,
      instruction:
          'Дай TL;DR одной короткой фразой — суть без подробностей.',
      settings: settings,
    );

Future<String> translate({
  required String text,
  required String lang,
  required GlobalSettings settings,
}) =>
    llmTransform(
      text: text,
      instruction: 'Переведи на $lang, сохрани стиль и смысл.',
      settings: settings,
    );

Future<String> rewriteFormal({
  required String text,
  required GlobalSettings settings,
}) =>
    llmTransform(
      text: text,
      instruction: 'Переформулируй формально и лаконично. Без жаргона.',
      settings: settings,
    );

Future<String> outline({
  required String text,
  required GlobalSettings settings,
}) =>
    llmTransform(
      text: text,
      instruction:
          'Структурируй как outline с заголовками и подпунктами (markdown).',
      settings: settings,
    );

String _plural(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return many;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}
