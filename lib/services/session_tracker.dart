// ── Session tracker ──────────────────────────────────────────────────────────
// Точка отсчёта текущей сессии приложения. Используется `_effectiveSystemPrompt`
// чтобы LLM видел «когда ты открыл приложение» и «сколько идёт сессия».

class SessionTracker {
  static DateTime _startedAt = DateTime.now();
  static DateTime? _lastActivityAt;

  /// Вызывается один раз из main() после init Hive.
  static void init() {
    _startedAt = DateTime.now();
    _lastActivityAt = null;
  }

  static DateTime get startedAt => _startedAt;
  static Duration get elapsed => DateTime.now().difference(_startedAt);

  /// Помечает момент действия оператора (отправка сообщения, открытие экрана и
  /// т.п.) — чтобы отличать «оператор активен» от «сидит молча».
  static void markActivity() {
    _lastActivityAt = DateTime.now();
  }

  static DateTime? get lastActivityAt => _lastActivityAt;
  static Duration? get sinceLastActivity => _lastActivityAt == null
      ? null
      : DateTime.now().difference(_lastActivityAt!);
}
