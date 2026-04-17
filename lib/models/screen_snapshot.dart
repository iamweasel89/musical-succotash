// Универсальный интерфейс «снимок экрана как JSON».
// Реализуется State'ом виджета-экрана, регистрируется через
// AppModel.pushScreen(name, provider: this) / setBaseScreen.
// debug-сервер на запрос /screen зовёт capture() у верхнего в стеке.
//
// Зачем: внешнему клиенту (Claude / MCP) нужна структурированная картина
// того что сейчас видит оператор — без PNG, без OCR. Дёшево, точно,
// совместимо с будущей памятью-по-времени (снимки со штампом).
abstract class ScreenSnapshotProvider {
  /// Имя экрана (совпадает с тем что передали в pushScreen/setBaseScreen).
  String get screenName;

  /// Снимок содержимого на момент вызова.
  /// Формат свободный (Map<String, dynamic>), но соглашение:
  ///   'kind'          — тип экрана
  ///   'title'         — человекочитаемый заголовок
  ///   'items'         — основной список (если применимо)
  ///   'visibleRange'  — [firstIdx, lastIdx] в списке если скроллится
  Map<String, dynamic> capture();
}
