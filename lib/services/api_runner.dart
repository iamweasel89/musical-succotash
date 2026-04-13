import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/node.dart';
import '../models/settings.dart';
import '../widgets/api_node_sheet.dart';

// ── Run result ─────────────────────────────────────────────────────────────
class RunStats {
  final int inputTokens;
  final int outputTokens;
  final Duration elapsed;

  const RunStats({
    required this.inputTokens,
    required this.outputTokens,
    required this.elapsed,
  });
}

// ── Public entry point ─────────────────────────────────────────────────────
/// Runs an API node and streams or awaits the result.
///
/// [messages]   ordered conversation history (role/content pairs).
///              If provided, takes precedence over [input].
/// [input]      single-turn fallback (used by canvas).
/// [onChunk]    called for each text delta (streaming mode).
/// [onComplete] called once with the full result text + stats.
/// [onError]    called on network/API error.
Future<void> runApiNode({
  required Node node,
  String input = '',
  List<Map<String, String>>? messages,
  required GlobalSettings settings,
  required ApiNodeSettings apiSettings,
  required void Function(String chunk) onChunk,
  required void Function(String result, RunStats stats) onComplete,
  required void Function(String error) onError,
}) async {
  final key = _keyFor(apiSettings.provider, settings);
  if (key.isEmpty) {
    onError('No API key set for ${apiSettings.provider}. '
        'Add it in Settings.');
    return;
  }

  final stopwatch = Stopwatch()..start();

  final msgs = messages ?? [{'role': 'user', 'content': input}];

  try {
    if (settings.streamingMode) {
      await _runStreaming(
        messages: msgs,
        settings: settings,
        apiSettings: apiSettings,
        key: key,
        onChunk: onChunk,
        onComplete: (text, inTok, outTok) {
          stopwatch.stop();
          onComplete(text, RunStats(
            inputTokens: inTok,
            outputTokens: outTok,
            elapsed: stopwatch.elapsed,
          ));
        },
        onError: onError,
      );
    } else {
      await _runFull(
        messages: msgs,
        settings: settings,
        apiSettings: apiSettings,
        key: key,
        onComplete: (text, inTok, outTok) {
          stopwatch.stop();
          onComplete(text, RunStats(
            inputTokens: inTok,
            outputTokens: outTok,
            elapsed: stopwatch.elapsed,
          ));
        },
        onError: onError,
      );
    }
  } catch (e) {
    stopwatch.stop();
    onError('Unexpected error: $e');
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

const _builtinPromptBody =
    'You are a helpful AI assistant embedded in a personal knowledge-management '
    'system. Conversations are stored as a graph of nodes on a hexagonal canvas. '
    'Each user message and each assistant reply is a node; conversations can '
    'branch at any point to explore alternatives. '
    'Keep your answers concise and to the point unless the user asks otherwise.';

String _effectiveSystemPrompt(GlobalSettings s) {
  final parts = <String>[];
  if (s.useBuiltinSystemPrompt) {
    final d = DateTime.now();
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    parts.add('Today is $date. $_builtinPromptBody');
  }
  if (s.defaultSystemPrompt.isNotEmpty) {
    parts.add(s.defaultSystemPrompt);
  }
  return parts.join('\n\n');
}

String _keyFor(String provider, GlobalSettings s) {
  switch (provider) {
    case 'anthropic': return s.anthropicKey;
    case 'openai':    return s.openAiKey;
    case 'deepseek':  return s.deepSeekKey;
    default:          return '';
  }
}

// ── Full (non-streaming) ────────────────────────────────────────────────────
Future<void> _runFull({
  required List<Map<String, String>> messages,
  required GlobalSettings settings,
  required ApiNodeSettings apiSettings,
  required String key,
  required void Function(String text, int inTok, int outTok) onComplete,
  required void Function(String error) onError,
}) async {
  final (uri, headers, body) = _buildRequest(
    messages: messages,
    settings: settings,
    apiSettings: apiSettings,
    key: key,
    stream: false,
  );

  final response = await http.post(uri, headers: headers,
      body: jsonEncode(body));

  if (response.statusCode != 200) {
    onError('HTTP ${response.statusCode}: ${response.body}');
    return;
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final (text, inTok, outTok) = _parseFullResponse(
      json, apiSettings.provider);
  onComplete(text, inTok, outTok);
}

// ── Streaming (SSE) ────────────────────────────────────────────────────────
Future<void> _runStreaming({
  required List<Map<String, String>> messages,
  required GlobalSettings settings,
  required ApiNodeSettings apiSettings,
  required String key,
  required void Function(String chunk) onChunk,
  required void Function(String text, int inTok, int outTok) onComplete,
  required void Function(String error) onError,
}) async {
  final (uri, headers, body) = _buildRequest(
    messages: messages,
    settings: settings,
    apiSettings: apiSettings,
    key: key,
    stream: true,
  );

  final client = http.Client();
  try {
    final request = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    final streamed = await client.send(request);
    if (streamed.statusCode != 200) {
      final err = await streamed.stream.bytesToString();
      onError('HTTP ${streamed.statusCode}: $err');
      return;
    }

    final buffer = StringBuffer();
    int inTok = 0, outTok = 0;

    await for (final line in streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') break;
      if (data.isEmpty) continue;

      try {
        final event = jsonDecode(data) as Map<String, dynamic>;
        final (chunk, iT, oT) =
            _parseStreamEvent(event, apiSettings.provider);
        if (chunk.isNotEmpty) {
          buffer.write(chunk);
          onChunk(chunk);
        }
        if (iT > 0) inTok = iT;
        if (oT > 0) outTok = oT;
      } catch (_) {
        // malformed event — skip
      }
    }

    onComplete(buffer.toString(), inTok, outTok);
  } finally {
    client.close();
  }
}

// ── Request builder ────────────────────────────────────────────────────────
(Uri, Map<String, String>, Map<String, dynamic>) _buildRequest({
  required List<Map<String, String>> messages,
  required GlobalSettings settings,
  required ApiNodeSettings apiSettings,
  required String key,
  required bool stream,
}) {
  final provider = apiSettings.provider;
  final systemPrompt = _effectiveSystemPrompt(settings);

  switch (provider) {
    case 'anthropic':
      return (
        Uri.parse('https://api.anthropic.com/v1/messages'),
        {
          'x-api-key': key,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        {
          'model': apiSettings.model,
          'max_tokens': apiSettings.maxTokens,
          if (systemPrompt.isNotEmpty) 'system': systemPrompt,
          'messages': messages,
          if (stream) 'stream': true,
        },
      );

    case 'openai':
    case 'deepseek':
      final baseUrl = provider == 'openai'
          ? 'https://api.openai.com/v1/chat/completions'
          : 'https://api.deepseek.com/v1/chat/completions';
      return (
        Uri.parse(baseUrl),
        {
          'Authorization': 'Bearer $key',
          'content-type': 'application/json',
        },
        {
          'model': apiSettings.model,
          'max_tokens': apiSettings.maxTokens,
          'temperature': apiSettings.temperature,
          'messages': [
            if (systemPrompt.isNotEmpty)
              {'role': 'system', 'content': systemPrompt},
            ...messages,
          ],
          if (stream) 'stream': true,
          if (stream) 'stream_options': {'include_usage': true},
        },
      );

    default:
      throw ArgumentError('Unknown provider: $provider');
  }
}

// ── Response parsers ───────────────────────────────────────────────────────
(String text, int inTok, int outTok) _parseFullResponse(
    Map<String, dynamic> json, String provider) {
  if (provider == 'anthropic') {
    final content = json['content'] as List;
    final text = content
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
    final usage = json['usage'] as Map<String, dynamic>? ?? {};
    return (
      text,
      usage['input_tokens'] as int? ?? 0,
      usage['output_tokens'] as int? ?? 0,
    );
  } else {
    // OpenAI / DeepSeek
    final choices = json['choices'] as List;
    final text =
        (choices.first as Map<String, dynamic>)['message']['content'] as String;
    final usage = json['usage'] as Map<String, dynamic>? ?? {};
    return (
      text,
      usage['prompt_tokens'] as int? ?? 0,
      usage['completion_tokens'] as int? ?? 0,
    );
  }
}

(String chunk, int inTok, int outTok) _parseStreamEvent(
    Map<String, dynamic> event, String provider) {
  if (provider == 'anthropic') {
    final type = event['type'] as String?;
    if (type == 'content_block_delta') {
      final delta = event['delta'] as Map<String, dynamic>?;
      if (delta?['type'] == 'text_delta') {
        return (delta!['text'] as String? ?? '', 0, 0);
      }
    }
    if (type == 'message_delta') {
      final usage = event['usage'] as Map<String, dynamic>? ?? {};
      return ('', 0, usage['output_tokens'] as int? ?? 0);
    }
    if (type == 'message_start') {
      final usage =
          (event['message'] as Map<String, dynamic>?)?['usage']
              as Map<String, dynamic>? ??
              {};
      return ('', usage['input_tokens'] as int? ?? 0, 0);
    }
    return ('', 0, 0);
  } else {
    // OpenAI / DeepSeek
    final choices = event['choices'] as List? ?? [];
    if (choices.isEmpty) {
      final usage = event['usage'] as Map<String, dynamic>? ?? {};
      return (
        '',
        usage['prompt_tokens'] as int? ?? 0,
        usage['completion_tokens'] as int? ?? 0,
      );
    }
    final delta =
        (choices.first as Map<String, dynamic>)['delta'] as Map<String, dynamic>?;
    final text = delta?['content'] as String? ?? '';
    return (text, 0, 0);
  }
}
