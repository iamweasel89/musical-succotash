import 'dart:math';

String _newId() {
  final r = Random();
  final bytes = List<int>.generate(6, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ── Reminder (ВР4.1) ─────────────────────────────────────────────────────────
// Локальное напоминание. Хранится в Hive, запускается через flutter_local_
// notifications. id типа int нужен для OS-уровня (Notification ID), дублируется
// в строку для Hive JSON.

class Reminder {
  final String id; // hex, для persistence
  final int nativeId; // int для Android notification API (0..2^31-1)
  final DateTime scheduledAt;
  final DateTime createdAt;
  String text;
  String? linkedNodeId; // опциональная привязка к ноде/тезису
  bool done;

  Reminder({
    String? id,
    int? nativeId,
    required this.scheduledAt,
    DateTime? createdAt,
    required this.text,
    this.linkedNodeId,
    this.done = false,
  })  : id = id ?? _newId(),
        nativeId = nativeId ?? DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'nativeId': nativeId,
        'scheduledAt': scheduledAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'text': text,
        'linkedNodeId': linkedNodeId,
        'done': done,
      };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: j['id'] as String?,
        nativeId: j['nativeId'] as int?,
        scheduledAt: DateTime.parse(j['scheduledAt'] as String),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        text: j['text'] as String? ?? '',
        linkedNodeId: j['linkedNodeId'] as String?,
        done: j['done'] as bool? ?? false,
      );
}
