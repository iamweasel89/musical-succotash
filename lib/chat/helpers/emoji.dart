// Удаление emoji из текста. Используется чат-пузырём когда оператор
// включает флаг hideEmoji в настройках. Pure functions, без зависимостей.

bool isEmojiCodePoint(int r) =>
    (r >= 0x1F000 && r <= 0x1FFFF) || // All emoji in Plane 1
    (r >= 0x2600 && r <= 0x27BF) || // Misc symbols, dingbats
    (r >= 0xFE00 && r <= 0xFE0F) || // Variation selectors
    r == 0x200D || // ZWJ
    r == 0x20E3; // Combining enclosing keycap

String stripEmoji(String s) =>
    String.fromCharCodes(s.runes.where((r) => !isEmojiCodePoint(r)));
