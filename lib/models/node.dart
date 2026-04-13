import 'package:uuid/uuid.dart';
import 'attachment.dart';
import 'hex_pos.dart';

enum NodeType { text, api }

enum NodeStatus { idle, running, done, error }

class Node {
  final String id;
  String name;
  final NodeType type;
  NodeStatus status;
  HexPos position;

  /// text node → own user-editable content
  /// api node  → last response text
  String text;

  /// Pushed text slots, keyed by source node id (text nodes only).
  /// Each connected source occupies one slot; re-running replaces the slot;
  /// disconnecting clears the slot.
  final Map<String, String> received;

  /// Attachments (images / files) on text nodes, sent as multimodal content.
  final List<Attachment> attachments;

  final DateTime createdAt;
  DateTime updatedAt;

  /// Direction of growth in the hex grid (index into hexDirs, 0=up).
  final int growthDir;

  Node({
    String? id,
    this.name = '',
    required this.type,
    this.status = NodeStatus.idle,
    required this.position,
    this.text = '',
    Map<String, String>? received,
    List<Attachment>? attachments,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.growthDir = 0,
  })  : id = id ?? const Uuid().v4(),
        received = received ?? {},
        attachments = attachments ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Node copyWith({
    String? name,
    NodeStatus? status,
    HexPos? position,
    String? text,
    Map<String, String>? received,
    List<Attachment>? attachments,
    DateTime? updatedAt,
  }) =>
      Node(
        id: id,
        name: name ?? this.name,
        type: type,
        status: status ?? this.status,
        position: position ?? this.position,
        text: text ?? this.text,
        received: received ?? Map<String, String>.from(this.received),
        attachments: attachments ?? List<Attachment>.from(this.attachments),
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        growthDir: growthDir,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'status': status.name,
        'position': position.toJson(),
        'text': text,
        'received': received,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'growthDir': growthDir,
      };

  factory Node.fromJson(Map<String, dynamic> j) => Node(
        id: j['id'] as String,
        name: j['name'] as String,
        type: NodeType.values.byName(j['type'] as String),
        status: NodeStatus.values.byName(j['status'] as String),
        position: HexPos.fromJson(j['position'] as Map<String, dynamic>),
        text: j['text'] as String,
        received: (j['received'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            {},
        attachments: (j['attachments'] as List?)
                ?.map((a) => Attachment.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: j['createdAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int)
            : null,
        updatedAt: j['updatedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] as int)
            : null,
        growthDir: j['growthDir'] as int? ?? 0,
      );
}
