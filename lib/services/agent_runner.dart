import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/settings.dart';
import 'web_search.dart';

// Агентский цикл с поддержкой инструментов: web_search, web_extract, web_crawl.
// Поддерживает Anthropic (tool_use) и OpenAI/DeepSeek (function calling).
// Цикл: запрос → если tool_use — выполнить tool → добавить результат → повторить.

const _maxIterations = 6;

// Tool registry: name → (description, input_schema, handler).
// Schema follows JSON Schema subset used both by Anthropic input_schema and
// OpenAI function.parameters.
class _ToolDef {
  final String description;
  final Map<String, dynamic> schema;
  final Future<String> Function(Map<String, dynamic> args, GlobalSettings s,
      AgentLogger? log) handler;
  const _ToolDef(this.description, this.schema, this.handler);
}

final Map<String, _ToolDef> _tools = {
  'web_search': _ToolDef(
    'Search the web for information. Returns a list of titles, URLs and snippets.',
    {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Search query'},
      },
      'required': ['query'],
    },
    (args, s, log) async {
      final query = (args['query'] as String?)?.trim() ?? '';
      if (query.isEmpty) return 'Empty query.';
      log?.call('🔍 web_search: «$query»');
      try {
        final result = await webSearch(
          query: query,
          tavilyKey: s.tavilyKey,
          log: (line) => log?.call('  $line'),
        );
        return _formatSearchResults(result);
      } on WebSearchException catch (e) {
        return 'Search failed: ${e.message}';
      } catch (e) {
        return 'Search error: $e';
      }
    },
  ),
  'web_extract': _ToolDef(
    'Extract main text content from one or more URLs (Tavily). Use when you '
        'need full article text, not just a snippet.',
    {
      'type': 'object',
      'properties': {
        'urls': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'List of URLs to extract text from',
        },
      },
      'required': ['urls'],
    },
    (args, s, log) async {
      final raw = args['urls'];
      final urls = raw is List ? raw.whereType<String>().toList() : <String>[];
      if (urls.isEmpty) return 'Empty urls.';
      log?.call('📄 web_extract: ${urls.length} url(s)');
      try {
        final results = await tavilyExtract(urls: urls, tavilyKey: s.tavilyKey);
        if (results.isEmpty) return 'No content extracted.';
        final buf = StringBuffer();
        for (final r in results) {
          buf.writeln('--- ${r.url} ---');
          buf.writeln(r.rawContent);
          buf.writeln();
        }
        log?.call('  получено ${results.length}');
        return buf.toString();
      } on WebSearchException catch (e) {
        return 'Extract failed: ${e.message}';
      } catch (e) {
        return 'Extract error: $e';
      }
    },
  ),
  'web_crawl': _ToolDef(
    'Crawl a website starting from a URL and return raw content of visited '
        'pages (Tavily). Use for scanning docs sites or small websites.',
    {
      'type': 'object',
      'properties': {
        'url': {'type': 'string', 'description': 'Start URL'},
        'max_depth': {
          'type': 'integer',
          'description': 'Crawl depth (default 1, max suggested 3)',
        },
        'limit': {
          'type': 'integer',
          'description': 'Max pages to fetch (default 20)',
        },
      },
      'required': ['url'],
    },
    (args, s, log) async {
      final url = (args['url'] as String?)?.trim() ?? '';
      if (url.isEmpty) return 'Empty url.';
      final depth = args['max_depth'] is int ? args['max_depth'] as int : 1;
      final limit = args['limit'] is int ? args['limit'] as int : 20;
      log?.call('🕸 web_crawl: $url (depth=$depth, limit=$limit)');
      try {
        final results = await tavilyCrawl(
            startUrl: url,
            tavilyKey: s.tavilyKey,
            maxDepth: depth,
            limit: limit);
        if (results.isEmpty) return 'No pages crawled.';
        final buf = StringBuffer();
        for (final r in results) {
          buf.writeln('--- ${r.url} ---');
          buf.writeln(r.rawContent);
          buf.writeln();
        }
        log?.call('  получено ${results.length} страниц');
        return buf.toString();
      } on WebSearchException catch (e) {
        return 'Crawl failed: ${e.message}';
      } catch (e) {
        return 'Crawl error: $e';
      }
    },
  ),
};

String _formatSearchResults(WebSearchResult r) {
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
      final def = _tools[call.name];
      String resultText;
      if (def == null) {
        resultText = 'Unknown tool: ${call.name}';
        onLog?.call('⚠ неизвестный tool: ${call.name}');
      } else {
        try {
          resultText = await def.handler(call.input, settings, onLog);
        } catch (e) {
          resultText = 'Tool ${call.name} error: $e';
        }
      }
      history.add(_toolResultMessage(provider, call.id, resultText));
    }
  }

  throw Exception('Агент превысил лимит итераций ($_maxIterations).');
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
  final String name;
  final Map<String, dynamic> input;
  _ToolCall(this.id, this.name, this.input);
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
    'tools': _tools.entries
        .map((e) => {
              'name': e.key,
              'description': e.value.description,
              'input_schema': e.value.schema,
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
  final calls = <_ToolCall>[];
  for (final block in content.whereType<Map<String, dynamic>>()) {
    if (block['type'] == 'text') {
      textParts.add(block['text'] as String? ?? '');
    } else if (block['type'] == 'tool_use') {
      final name = block['name'] as String? ?? '';
      if (_tools.containsKey(name)) {
        calls.add(_ToolCall(
          block['id'] as String? ?? '',
          name,
          (block['input'] as Map<String, dynamic>?) ?? {},
        ));
      }
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
    'tools': _tools.entries
        .map((e) => {
              'type': 'function',
              'function': {
                'name': e.key,
                'description': e.value.description,
                'parameters': e.value.schema,
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

  final calls = <_ToolCall>[];
  for (final tc in toolCallsRaw.whereType<Map<String, dynamic>>()) {
    final fn = tc['function'] as Map<String, dynamic>? ?? {};
    final name = fn['name'] as String? ?? '';
    if (!_tools.containsKey(name)) continue;
    Map<String, dynamic> args = {};
    final argsRaw = fn['arguments'];
    if (argsRaw is String && argsRaw.isNotEmpty) {
      try {
        args = jsonDecode(argsRaw) as Map<String, dynamic>;
      } catch (_) {}
    } else if (argsRaw is Map<String, dynamic>) {
      args = argsRaw;
    }
    calls.add(_ToolCall(tc['id'] as String? ?? '', name, args));
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
