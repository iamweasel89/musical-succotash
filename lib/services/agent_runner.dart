import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/settings.dart';
import 'web_search.dart';

// Агентский цикл с поддержкой одного инструмента — web_search.
// Поддерживает Anthropic (tool_use) и OpenAI/DeepSeek (function calling).
// Цикл: запрос → если tool_use — выполнить web_search → добавить результат → повторить.

const _toolName = 'web_search';
const _toolDescription =
    'Search the web for information. Returns a list of titles, URLs and snippets.';
const _maxIterations = 6;

class AgentResult {
  final String text;
  final int inputTokens;
  final int outputTokens;
  const AgentResult(this.text, this.inputTokens, this.outputTokens);
}

typedef AgentLogger = void Function(String line);

Future<AgentResult> runAgentTurn({
  required List<Map<String, dynamic>> messages,
  required String systemPrompt,
  required String provider,
  required String model,
  required GlobalSettings settings,
  AgentLogger? onLog,
}) async {
  final key = _llmKey(provider, settings);
  if (key.isEmpty) {
    throw Exception('Нет ключа API для провайдера «$provider».');
  }

  // Working copy of message history that the loop appends to.
  final history = List<Map<String, dynamic>>.from(messages);
  int totalIn = 0;
  int totalOut = 0;

  for (var iter = 0; iter < _maxIterations; iter++) {
    final response = await _callLlm(
      provider: provider,
      model: model,
      key: key,
      systemPrompt: systemPrompt,
      history: history,
    );
    totalIn += response.inputTokens;
    totalOut += response.outputTokens;

    if (response.toolCalls.isEmpty) {
      return AgentResult(response.text, totalIn, totalOut);
    }

    // Append assistant message (with tool_use blocks) to history before tool result.
    history.add(response.assistantMessage);

    for (final call in response.toolCalls) {
      final query = (call.input['query'] as String?)?.trim() ?? '';
      onLog?.call('🔍 web_search: «$query»');

      String resultText;
      if (query.isEmpty) {
        resultText = 'Empty query.';
        onLog?.call('  пустой запрос — пропуск');
      } else {
        try {
          final result = await webSearch(
            query: query,
            tavilyKey: settings.tavilyKey,
            log: (line) => onLog?.call('  $line'),
          );
          resultText = _formatResults(result);
        } on WebSearchException catch (e) {
          resultText = 'Search failed: ${e.message}';
        } catch (e) {
          resultText = 'Search error: $e';
        }
      }

      history.add(_toolResultMessage(provider, call.id, resultText));
    }
  }

  throw Exception('Агент превысил лимит итераций ($_maxIterations).');
}

String _formatResults(WebSearchResult r) {
  final buf = StringBuffer('Provider: ${r.provider.name}\n');
  for (var i = 0; i < r.hits.length; i++) {
    final h = r.hits[i];
    buf.writeln('---');
    buf.writeln('[${i + 1}] ${h.title}');
    buf.writeln(h.url);
    buf.writeln(h.snippet);
  }
  return buf.toString();
}

String _llmKey(String provider, GlobalSettings s) {
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

// ── LLM call (single round) ────────────────────────────────────────────────

class _ToolCall {
  final String id;
  final Map<String, dynamic> input;
  _ToolCall(this.id, this.input);
}

class _LlmResponse {
  final String text;
  final List<_ToolCall> toolCalls;
  final Map<String, dynamic> assistantMessage;
  final int inputTokens;
  final int outputTokens;
  _LlmResponse({
    required this.text,
    required this.toolCalls,
    required this.assistantMessage,
    required this.inputTokens,
    required this.outputTokens,
  });
}

Future<_LlmResponse> _callLlm({
  required String provider,
  required String model,
  required String key,
  required String systemPrompt,
  required List<Map<String, dynamic>> history,
}) async {
  switch (provider) {
    case 'anthropic':
      return _callAnthropic(model, key, systemPrompt, history);
    case 'openai':
    case 'deepseek':
      return _callOpenAiCompat(provider, model, key, systemPrompt, history);
    default:
      throw Exception('Unknown provider: $provider');
  }
}

// ── Anthropic ──────────────────────────────────────────────────────────────

Future<_LlmResponse> _callAnthropic(String model, String key,
    String systemPrompt, List<Map<String, dynamic>> history) async {
  final body = <String, dynamic>{
    'model': model,
    'max_tokens': 1024,
    if (systemPrompt.isNotEmpty) 'system': systemPrompt,
    'messages': history,
    'tools': [
      {
        'name': _toolName,
        'description': _toolDescription,
        'input_schema': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'Search query'},
          },
          'required': ['query'],
        },
      },
    ],
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
  final calls = <_ToolCall>[];
  for (final block in content.whereType<Map<String, dynamic>>()) {
    if (block['type'] == 'text') {
      textParts.add(block['text'] as String? ?? '');
    } else if (block['type'] == 'tool_use' && block['name'] == _toolName) {
      calls.add(_ToolCall(
        block['id'] as String? ?? '',
        (block['input'] as Map<String, dynamic>?) ?? {},
      ));
    }
  }

  return _LlmResponse(
    text: textParts.join(),
    toolCalls: calls,
    assistantMessage: {'role': 'assistant', 'content': content},
    inputTokens: usage['input_tokens'] as int? ?? 0,
    outputTokens: usage['output_tokens'] as int? ?? 0,
  );
}

// ── OpenAI / DeepSeek ──────────────────────────────────────────────────────

Future<_LlmResponse> _callOpenAiCompat(String provider, String model,
    String key, String systemPrompt, List<Map<String, dynamic>> history) async {
  final url = provider == 'openai'
      ? 'https://api.openai.com/v1/chat/completions'
      : 'https://api.deepseek.com/v1/chat/completions';

  final messages = <Map<String, dynamic>>[
    if (systemPrompt.isNotEmpty)
      {'role': 'system', 'content': systemPrompt},
    ...history,
  ];

  final body = <String, dynamic>{
    'model': model,
    'messages': messages,
    'tools': [
      {
        'type': 'function',
        'function': {
          'name': _toolName,
          'description': _toolDescription,
          'parameters': {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': 'Search query'},
            },
            'required': ['query'],
          },
        },
      },
    ],
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

  final calls = <_ToolCall>[];
  for (final tc in toolCallsRaw.whereType<Map<String, dynamic>>()) {
    final fn = tc['function'] as Map<String, dynamic>? ?? {};
    if (fn['name'] != _toolName) continue;
    Map<String, dynamic> args = {};
    final argsRaw = fn['arguments'];
    if (argsRaw is String && argsRaw.isNotEmpty) {
      try {
        args = jsonDecode(argsRaw) as Map<String, dynamic>;
      } catch (_) {}
    } else if (argsRaw is Map<String, dynamic>) {
      args = argsRaw;
    }
    calls.add(_ToolCall(tc['id'] as String? ?? '', args));
  }

  return _LlmResponse(
    text: text,
    toolCalls: calls,
    assistantMessage: msg,
    inputTokens: usage['prompt_tokens'] as int? ?? 0,
    outputTokens: usage['completion_tokens'] as int? ?? 0,
  );
}

// ── Tool result formatting ─────────────────────────────────────────────────

Map<String, dynamic> _toolResultMessage(
    String provider, String toolUseId, String content) {
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
