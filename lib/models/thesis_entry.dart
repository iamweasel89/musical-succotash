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

  Map<String, dynamic> toJson() => {
        'sourceNodeId': sourceNodeId,
        'excerpt': excerpt,
        'thesis': thesis,
        'answer': answer,
      };

  factory ThesisEntry.fromJson(Map<String, dynamic> j) => ThesisEntry(
        sourceNodeId: j['sourceNodeId'] as String,
        excerpt: j['excerpt'] as String,
        thesis: j['thesis'] as String?,
        answer: j['answer'] as String? ?? '',
      );
}
