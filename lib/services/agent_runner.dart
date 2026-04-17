import 'dart:async';

import '../models/settings.dart';
import 'llm_client.dart';
import 'llm_transform.dart';
import 'web_search.dart';

// Агентский цикл с поддержкой инструментов: web_search, web_extract,
// web_crawl, llm_transform. Поддерживает Anthropic (tool_use) и OpenAI/
// DeepSeek (function calling) через унифицированный `callLlm` из llm_client.
// Цикл: запрос → если tool_use — выполнить tool → добавить результат → повторить.

const _maxIterations = 10;
const _extractMaxChars = 3000;

// Tool registry: name → (description, input_schema, handler).
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
  'llm_transform': _ToolDef(
    'Transform text by an instruction using an LLM. Use to compress long '
        'text, translate, rewrite, outline, or otherwise restructure content '
        'before including it in your reasoning.',
    {
      'type': 'object',
      'properties': {
        'text': {'type': 'string', 'description': 'Text to transform'},
        'instruction': {
          'type': 'string',
          'description':
              'What to do with the text (e.g., "compress to 3 lines", '
                  '"translate to English", "outline as markdown")',
        },
      },
      'required': ['text', 'instruction'],
    },
    (args, s, log) async {
      final text = (args['text'] as String?) ?? '';
      final instruction = (args['instruction'] as String?) ?? '';
      if (text.trim().isEmpty || instruction.trim().isEmpty) {
        return 'Empty text or instruction.';
      }
      log?.call('✎ llm_transform: $instruction');
      try {
        return await llmTransform(
          text: text,
          instruction: instruction,
          settings: s,
        );
      } catch (e) {
        return 'Transform failed: $e';
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
          buf.writeln(_truncate(r.rawContent, _extractMaxChars));
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
          buf.writeln(_truncate(r.rawContent, _extractMaxChars));
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
};

String _truncate(String s, int limit) {
  if (s.length <= limit) return s;
  return '${s.substring(0, limit)}… [обрезано ${s.length - limit} симв.]';
}

String _formatElapsed(Duration d) {
  if (d.inSeconds < 1) return '${d.inMilliseconds}ms';
  final sec = (d.inMilliseconds / 1000).toStringAsFixed(1);
  return '${sec}s';
}

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
  final key = keyForProvider(provider, settings);
  if (key.isEmpty) {
    throw Exception('Нет ключа API для провайдера «$provider».');
  }

  final llmTools = _tools.entries
      .map((e) => LlmTool(
            name: e.key,
            description: e.value.description,
            schema: e.value.schema,
          ))
      .toList();

  // Working copy of message history that the loop appends to.
  final history = List<Map<String, dynamic>>.from(messages);
  int totalIn = 0;
  int totalOut = 0;
  final turnStopwatch = Stopwatch()..start();

  for (var iter = 0; iter < _maxIterations; iter++) {
    final llmSw = Stopwatch()..start();
    final response = await callLlm(
      provider: provider,
      model: model,
      key: key,
      systemPrompt: systemPrompt,
      messages: history,
      tools: llmTools,
      maxTokens: 1024,
    );
    llmSw.stop();
    totalIn += response.inputTokens;
    totalOut += response.outputTokens;

    if (response.toolCalls.isEmpty) {
      turnStopwatch.stop();
      onLog?.call(
          '⏱ итого: ${_formatElapsed(turnStopwatch.elapsed)}, '
          'итераций: ${iter + 1}, '
          'токенов: $totalIn in / $totalOut out');
      return AgentResult(response.text, totalIn, totalOut);
    }

    history.add(response.assistantMessage);

    for (final call in response.toolCalls) {
      final def = _tools[call.name];
      String resultText;
      final toolSw = Stopwatch()..start();
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
      toolSw.stop();
      onLog?.call('  ⏱ ${call.name}: ${_formatElapsed(toolSw.elapsed)}');
      history.add(toolResultMessage(
        provider: provider,
        toolUseId: call.id,
        content: resultText,
      ));
    }
  }

  // Fallback-синтез: лимит итераций исчерпан, делаем последний вызов без
  // tools и просим финальный ответ на основе собранного контекста.
  onLog?.call('⚠ лимит $_maxIterations итераций — форсирую синтез без tools');
  final finalResponse = await callLlm(
    provider: provider,
    model: model,
    key: key,
    systemPrompt:
        '$systemPrompt\n\nВажно: у тебя кончился бюджет на инструменты. '
        'Дай итоговый ответ только на основе уже собранного в истории '
        'контекста. Не пытайся вызывать tools.',
    messages: history,
    tools: const [],
    maxTokens: 1024,
  );
  totalIn += finalResponse.inputTokens;
  totalOut += finalResponse.outputTokens;
  turnStopwatch.stop();
  onLog?.call(
      '⏱ итого: ${_formatElapsed(turnStopwatch.elapsed)}, '
      'итераций: $_maxIterations + 1 синтез, '
      'токенов: $totalIn in / $totalOut out');
  return AgentResult(finalResponse.text, totalIn, totalOut);
}
