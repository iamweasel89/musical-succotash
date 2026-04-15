import 'dart:math';

enum DecisionType {
  term,
  technology,
  architecture,
  design,
  process;

  String get label => const {
        DecisionType.term: 'Термин',
        DecisionType.technology: 'Технология',
        DecisionType.architecture: 'Архитектура',
        DecisionType.design: 'Дизайн',
        DecisionType.process: 'Процесс',
      }[this]!;
}

enum DecisionStatus {
  idea,
  discussion,
  accepted,
  implemented,
  obsolete,
  rejected;

  String get label => const {
        DecisionStatus.idea: 'Идея',
        DecisionStatus.discussion: 'Обсуждается',
        DecisionStatus.accepted: 'Принято',
        DecisionStatus.implemented: 'Реализовано',
        DecisionStatus.obsolete: 'Устарело',
        DecisionStatus.rejected: 'Отклонено',
      }[this]!;
}

class DecisionEntry {
  final String id;
  final String? parentId;
  String title;
  DecisionType type;
  DecisionStatus status;
  String notes;
  final DateTime createdAt;

  DecisionEntry({
    String? id,
    this.parentId,
    required this.title,
    this.type = DecisionType.architecture,
    this.status = DecisionStatus.idea,
    this.notes = '',
    DateTime? createdAt,
  })  : id = id ?? _genId(),
        createdAt = createdAt ?? DateTime.now();

  static String _genId() {
    const chars = '0123456789abcdef';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'parentId': parentId,
        'title': title,
        'type': type.name,
        'status': status.name,
        'notes': notes,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory DecisionEntry.fromJson(Map<String, dynamic> j) => DecisionEntry(
        id: j['id'] as String,
        parentId: j['parentId'] as String?,
        title: j['title'] as String,
        type: DecisionType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => DecisionType.architecture,
        ),
        status: DecisionStatus.values.firstWhere(
          (e) => e.name == j['status'],
          orElse: () => DecisionStatus.idea,
        ),
        notes: j['notes'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (j['createdAt'] as num?)?.toInt() ?? 0,
        ),
      );
}
