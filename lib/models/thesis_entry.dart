// Тезис — единица работы в режиме тезисов (Мастерская).
class ThesisEntry {
  final String sourceNodeId;
  final String excerpt;
  String thesis;
  String answer;

  ThesisEntry({
    required this.sourceNodeId,
    required this.excerpt,
    String? thesis,
    this.answer = '',
  }) : thesis = thesis ??
            (excerpt.length > 120 ? '${excerpt.substring(0, 120)}…' : excerpt);
}
