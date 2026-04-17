import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/settings.dart';

// ── Unified LLM client (Р2) ──────────────────────────────────────────────────
// Один вход для вызова LLM (Anthropic / OpenAI / DeepSeek) в non-streaming
// режиме с опциональными tools. Используется `agent_runner` (tool_use loop)
// и `llm_transform` (one-shot). Streaming вызов в `api_runner` пока
// отдельный — у него своя SSE-логика и поддержка attachments.

class LlmTool {
  final String name;
  final String description;
  /// JSON-schema subset: { type: "object", properties: {...}, required: [...] }
  final Map<String, dynamic> schema;

  const LlmTool({
    required this.name,
    required this.description,
    required this.schema,
  });
}

class LlmToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> input;

  const LlmToolCall({
    required this.id,
    required this.name,
    required this.input,
  });
}

class LlmResult {
  /// Только текстовая часть ответа (без tool_use блоков).
  final String text;
  final List<LlmToolCall> toolCalls;
  /// Полное assistant-сообщение в формате провайдера — для отправки обратно
  /// в следующей итерации tool-use цикла.
  final Map<String, dynamic> assistantMessage;
  final int inputTokens;
  final int outputTokens;

  const LlmResult({
    required this.text,
    required this.toolCalls,
    required this.assistantMessage,
    required this.inputTokens,
    required this.outputTokens,
  });
}

String keyForProvider(String provider, GlobalSettings s) {
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

/// Non-streaming LLM call. Поддерживает tool_use (Anthropic) / function
/// calling (OpenAI/DeepSeek). Unified result — вызывающий код одинаков
/// для всех трёх провайдеров.
Future<LlmResult> callLlm({
  required String provider,
  required String model,
  required String key,
  required List<Map<String, dynamic>> messages,
  String systemPrompt = '',
  List<LlmTool> tools = const [],
  int maxTokens = 1024,
  double temperature = 0.3,
}) async {
  switch (provider) {
    case 'anthropic':
      return _callAnthropic(
        model: model,
        key: key,
        systemPrompt: systemPrompt,
        messages: messages,
        tools: tools,
        maxTokens: maxTokens,
        temperature: temperature,
      );
    case 'openai':
    case 'deepseek':
      return _callOpenAiCompat(
        provider: provider,
        model: model,
        key: key,
        systemPrompt: systemPrompt,
        messages: messages,
        tools: tools,
        maxTokens: maxTokens,
        temperature: temperature,
      );
    default:
      throw Exception('Unknown provider: $provider');
  }
}

/// Собирает сообщение с tool_result для следующей итерации tool-use loop.
/// Формат зависит от провайдера.
Map<String, dynamic> toolResultMessage({
  required String provider,
  required String toolUseId,
  required String content,
}) {
  if (provider == 'anthropic') {
    return {
      'role': 'user',
      'content': [
        {
          'type': 'tool_result',
          'tool_use_id': toolUseId,
          'content': content,
        },
      ],
    };
  }
  // OpenAI / DeepSeek
  return {
    'role': 'tool',
    'tool_call_id': toolUseId,
    'content': content,
  };
}

// ── Anthropic ──────────────────────────────────────────────────────────────

Future<LlmResult> _callAnthropic({
  required String model,
  required String key,
  required String systemPrompt,
  required List<Map<String, dynamic>> messages,
  required List<LlmTool> tools,
  required int maxTokens,
  required double temperature,
}) async {
  final body = <String, dynamic>{
    'model': model,
    'max_tokens': maxTokens,
    'temperature': temperature,
    if (systemPrompt.isNotEmpty) 'system': systemPrompt,
    'messages': messages,
    if (tools.isNotEmpty)
      'tools': tools
          .map((t) => {
                'name': t.name,
                'description': t.description,
                'input_schema': t.schema,
              })
          .toList(),
  };

  final r = await http.post(
    Uri.parse('https://api.anthropic.com/v1/messages'),
    headers: {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: jsonEncode(body),
  );
  if (r.statusCode != 200) {
    throw Exception('Anthropic HTTP ${r.statusCode}: ${r.body}');
  }
  final json = jsonDecode(r.body) as Map<String, dynamic>;
  final content = (json['content'] as List? ?? []);
  final usage = json['usage'] as Map<String, dynamic>? ?? {};

  final textParts = <String>[];
  final calls = <LlmToolCall>[];
  final allowedNames = tools.map((t) => t.name).toSet();
  for (final block in content.whereType<Map<String, dynamic>>()) {
    if (block['type'] == 'text') {
      textParts.add(block['text'] as String? ?? '');
    } else if (block['type'] == 'tool_use') {
      final name = block['name'] as String? ?? '';
      // Если tools пустой — не фильтруем по allowedNames (не должно случиться).
      if (allowedNames.isEmpty || allowedNames.contains(name)) {
        calls.add(LlmToolCall(
          id: block['id'] as String? ?? '',
          name: name,
          input: (block['input'] as Map<String, dynamic>?) ?? {},
        ));
      }
    }
  }

  return LlmResult(
    text: textParts.join(),
    toolCalls: calls,
    assistantMessage: {'role': 'assistant', 'content': content},
    inputTokens: usage['input_tokens'] as int? ?? 0,
    outputTokens: usage['output_tokens'] as int? ?? 0,
  );
}

// ── OpenAI / DeepSeek ──────────────────────────────────────────────────────

Future<LlmResult> _callOpenAiCompat({
  required String provider,
  required String model,
  required String key,
  required String systemPrompt,
  required List<Map<String, dynamic>> messages,
  required List<LlmTool> tools,
  required int maxTokens,
  required double temperature,
}) async {
  final url = provider == 'openai'
      ? 'https://api.openai.com/v1/chat/completions'
      : 'https://api.deepseek.com/v1/chat/completions';

  final apiMessages = <Map<String, dynamic>>[
    if (systemPrompt.isNotEmpty) {'role': 'system', 'content': systemPrompt},
    ...messages,
  ];

  final body = <String, dynamic>{
    'model': model,
    'max_tokens': maxTokens,
    'temperature': temperature,
    'messages': apiMessages,
    if (tools.isNotEmpty)
      'tools': tools
          .map((t) => {
                'type': 'function',
                'function': {
                  'name': t.name,
                  'description': t.description,
                  'parameters': t.schema,
                },
              })
          .toList(),
  };

  final r = await http.post(
    Uri.parse(url),
    headers: {
      'Authorization': 'Bearer $key',
      'content-type': 'application/json',
    },
    body: jsonEncode(body),
  );
  if (r.statusCode != 200) {
    throw Exception('${provider.toUpperCase()} HTTP ${r.statusCode}: ${r.body}');
  }
  final json = jsonDecode(r.body) as Map<String, dynamic>;
  final choices = json['choices'] as List? ?? [];
  if (choices.isEmpty) {
    throw Exception('Пустой ответ от $provider');
  }
  final msg = (choices.first as Map<String, dynamic>)['message']
      as Map<String, dynamic>;
  final usage = json['usage'] as Map<String, dynamic>? ?? {};

  final text = msg['content'] as String? ?? '';
  final toolCallsRaw = msg['tool_calls'] as List? ?? [];

  final calls = <LlmToolCall>[];
  final allowedNames = tools.map((t) => t.name).toSet();
  for (final tc in toolCallsRaw.whereType<Map<String, dynamic>>()) {
    final fn = tc['function'] as Map<String, dynamic>? ?? {};
    final name = fn['name'] as String? ?? '';
    if (allowedNames.isNotEmpty && !allowedNames.contains(name)) continue;
    Map<String, dynamic> args = {};
    final argsRaw = fn['arguments'];
    if (argsRaw is String && argsRaw.isNotEmpty) {
      try {
        args = jsonDecode(argsRaw) as Map<String, dynamic>;
      } catch (_) {}
    } else if (argsRaw is Map<String, dynamic>) {
      args = argsRaw;
    }
    calls.add(LlmToolCall(
      id: tc['id'] as String? ?? '',
      name: name,
      input: args,
    ));
  }

  return LlmResult(
    text: text,
    toolCalls: calls,
    assistantMessage: msg,
    inputTokens: usage['prompt_tokens'] as int? ?? 0,
    outputTokens: usage['completion_tokens'] as int? ?? 0,
  );
}
