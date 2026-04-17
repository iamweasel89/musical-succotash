import 'dart:math';

String _newId() {
  final r = Random();
  final bytes = List<int>.generate(6, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class WebSearchMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  final String text;
  final List<String> logs;
  final DateTime createdAt;
  /// Статус исполнения: null/'ok' — нормально, 'limit' — упёрся в лимит
  /// итераций и делал fallback-синтез, 'error' — исключение.
  final String? status;

  WebSearchMessage({
    String? id,
    required this.role,
    required this.text,
    List<String>? logs,
    DateTime? createdAt,
    this.status,
  })  : id = id ?? _newId(),
        logs = logs ?? const [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'text': text,
        'logs': logs,
        'createdAt': createdAt.toIso8601String(),
        if (status != null) 'status': status,
      };

  factory WebSearchMessage.fromJson(Map<String, dynamic> j) => WebSearchMessage(
        id: j['id'] as String?,
        role: j['role'] as String? ?? 'user',
        text: j['text'] as String? ?? '',
        logs: (j['logs'] as List?)?.cast<String>() ?? const [],
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        status: j['status'] as String?,
      );
}

const String defaultWebSearchSystemPrompt =
    'Ты — поисковый ассистент. У тебя есть инструмент web_search. '
    'При необходимости вызывай его (с конкретным запросом), затем синтезируй '
    'ответ на основе найденных источников. Отвечай по-русски, кратко, '
    'указывай ссылки на использованные источники.';

class WebSearchConfig {
  String systemPrompt;
  String provider; // 'anthropic' | 'openai' | 'deepseek'
  String model;

  WebSearchConfig({
    this.systemPrompt = defaultWebSearchSystemPrompt,
    this.provider = 'deepseek',
    this.model = 'deepseek-chat',
  });

  Map<String, dynamic> toJson() => {
        'systemPrompt': systemPrompt,
        'provider': provider,
        'model': model,
      };

  factory WebSearchConfig.fromJson(Map<String, dynamic> j) => WebSearchConfig(
        systemPrompt:
            j['systemPrompt'] as String? ?? defaultWebSearchSystemPrompt,
        provider: j['provider'] as String? ?? 'deepseek',
        model: j['model'] as String? ?? 'deepseek-chat',
      );
}
