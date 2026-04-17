import '../models/settings.dart';
import 'llm_client.dart';

// ── LLM Transform (ПТ-ядро) ──────────────────────────────────────────────────
// Общий слой LLM-трансформаций текста: один вход → один выход по инструкции.
// Используется пресетами (compress/tldr/translate/…), long-press action'ами
// на нодах и как агентский tool `llm_transform`.
//
// Идёт через унифицированный `callLlm` (Р2) — один код на три провайдера.

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
  final key = keyForProvider(provider, settings);
  if (key.isEmpty) {
    throw Exception('Нет ключа API для провайдера «$provider».');
  }

  const systemPrompt =
      'Ты — инструмент преобразования текста. Следуй инструкции точно. '
      'Не добавляй вступлений, комментариев, объяснений или метаданных. '
      'Возвращай только результат преобразования.';

  final userContent = '$instruction\n\nТекст:\n$text';

  final result = await callLlm(
    provider: provider,
    model: model,
    key: key,
    systemPrompt: systemPrompt,
    messages: [
      {'role': 'user', 'content': userContent},
    ],
    tools: const [],
    maxTokens: maxTokens,
    temperature: temperature,
  );
  return result.text;
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
