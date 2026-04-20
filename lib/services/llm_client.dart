import 'dart:convert';

import 'package:http/http.dart' as http;

class LlmResponse {
  final String content;
  final int tokensIn;
  final int tokensOut;
  final String model;
  const LlmResponse({
    required this.content,
    required this.tokensIn,
    required this.tokensOut,
    required this.model,
  });
}

class LlmClient {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _apiVersion = '2023-06-01';

  /// One API call = one move. Single atomic call.
  static Future<LlmResponse> call({
    required String apiKey,
    required String model,
    required int maxTokens,
    required String prompt,
  }) async {
    final resp = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': _apiVersion,
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      }),
    );

    if (resp.statusCode != 200) {
      throw Exception('API ${resp.statusCode}: ${resp.body}');
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = (body['content'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String? ?? '')
        .join('\n');
    final usage = body['usage'] as Map<String, dynamic>? ?? {};
    return LlmResponse(
      content: content,
      tokensIn: (usage['input_tokens'] as num?)?.toInt() ?? 0,
      tokensOut: (usage['output_tokens'] as num?)?.toInt() ?? 0,
      model: (body['model'] as String?) ?? model,
    );
  }
}
