import 'dart:convert';

import 'package:http/http.dart' as http;

// Веб-поиск с двумя провайдерами: Tavily (основной) и DuckDuckGo (резерв).
// Вызывающий получает результаты и поток лог-строк, объясняющих переходы.

enum WebSearchProvider { tavily, duckduckgo }

class WebSearchHit {
  final String title;
  final String url;
  final String snippet;

  const WebSearchHit({
    required this.title,
    required this.url,
    required this.snippet,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'snippet': snippet,
      };
}

class WebSearchResult {
  final WebSearchProvider provider;
  final List<WebSearchHit> hits;

  const WebSearchResult({required this.provider, required this.hits});
}

class WebSearchException implements Exception {
  final String message;
  WebSearchException(this.message);
  @override
  String toString() => message;
}

typedef SearchLogger = void Function(String line);

/// Tries Tavily first, falls back to DuckDuckGo. Each transition is logged.
/// Throws [WebSearchException] only if both fail.
Future<WebSearchResult> webSearch({
  required String query,
  required String tavilyKey,
  SearchLogger? log,
  int maxResults = 5,
}) async {
  // 1. Tavily — only if key present
  if (tavilyKey.isEmpty) {
    log?.call('Tavily: ключ не задан → переключаюсь на DuckDuckGo');
  } else {
    try {
      final hits = await _tavilySearch(query, tavilyKey, maxResults);
      if (hits.isEmpty) {
        log?.call('Tavily: 0 результатов → переключаюсь на DuckDuckGo');
      } else {
        log?.call('Tavily: найдено ${hits.length}');
        return WebSearchResult(provider: WebSearchProvider.tavily, hits: hits);
      }
    } on _QuotaException catch (e) {
      log?.call('Tavily: ${e.message} → переключаюсь на DuckDuckGo');
    } catch (e) {
      log?.call('Tavily: ошибка ($e) → переключаюсь на DuckDuckGo');
    }
  }

  // 2. DuckDuckGo
  try {
    final hits = await _duckDuckGoSearch(query, maxResults);
    if (hits.isEmpty) {
      log?.call('DuckDuckGo: 0 результатов');
      throw WebSearchException('Поиск не дал результатов ни в одном провайдере.');
    }
    log?.call('DuckDuckGo: найдено ${hits.length}');
    return WebSearchResult(provider: WebSearchProvider.duckduckgo, hits: hits);
  } on WebSearchException {
    rethrow;
  } catch (e) {
    log?.call('DuckDuckGo: ошибка ($e)');
    throw WebSearchException('Все провайдеры поиска недоступны: $e');
  }
}

class _QuotaException implements Exception {
  final String message;
  _QuotaException(this.message);
}

// ── Tavily ─────────────────────────────────────────────────────────────────

Future<List<WebSearchHit>> _tavilySearch(
    String query, String key, int max) async {
  final response = await http.post(
    Uri.parse('https://api.tavily.com/search'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'api_key': key,
      'query': query,
      'max_results': max,
      'search_depth': 'basic',
    }),
  );
  if (response.statusCode == 429) {
    throw _QuotaException('квота исчерпана (429)');
  }
  if (response.statusCode == 401 || response.statusCode == 403) {
    throw _QuotaException('ключ отклонён (${response.statusCode})');
  }
  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final results = (json['results'] as List? ?? []);
  return results
      .whereType<Map<String, dynamic>>()
      .map((r) => WebSearchHit(
            title: r['title'] as String? ?? '',
            url: r['url'] as String? ?? '',
            snippet: r['content'] as String? ?? '',
          ))
      .toList();
}

// ── DuckDuckGo (Instant Answer API + HTML lite parser) ─────────────────────

Future<List<WebSearchHit>> _duckDuckGoSearch(String query, int max) async {
  // Instant Answer API даёт абстракт и связанные темы. Достаточно для fallback.
  final uri = Uri.parse(
      'https://api.duckduckgo.com/?q=${Uri.encodeQueryComponent(query)}&format=json&no_html=1&skip_disambig=1');
  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}');
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final hits = <WebSearchHit>[];

  final abstract = json['AbstractText'] as String? ?? '';
  final abstractUrl = json['AbstractURL'] as String? ?? '';
  final heading = json['Heading'] as String? ?? '';
  if (abstract.isNotEmpty && abstractUrl.isNotEmpty) {
    hits.add(WebSearchHit(
        title: heading.isEmpty ? abstractUrl : heading,
        url: abstractUrl,
        snippet: abstract));
  }

  final related = json['RelatedTopics'] as List? ?? [];
  for (final t in related) {
    if (hits.length >= max) break;
    if (t is! Map<String, dynamic>) continue;
    final text = t['Text'] as String? ?? '';
    final url = (t['FirstURL'] as String? ?? '');
    if (text.isEmpty || url.isEmpty) continue;
    hits.add(WebSearchHit(title: text.split(' - ').first, url: url, snippet: text));
  }

  return hits.take(max).toList();
}
