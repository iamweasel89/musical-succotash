import 'package:uuid/uuid.dart';
import 'hex_pos.dart';

enum NodeType { text, api }

enum NodeStatus { idle, running, done, error }

class Node {
  final String id;
  String name;
  final NodeType type;
  NodeStatus status;
  HexPos position;

  /// text node  → own text content
  /// api node   → last received response (last_result)
  String text;

  Node({
    String? id,
    this.name = '',
    required this.type,
    this.status = NodeStatus.idle,
    required this.position,
    this.text = '',
  }) : id = id ?? const Uuid().v4();

  Node copyWith({
    String? name,
    NodeStatus? status,
    HexPos? position,
    String? text,
  }) =>
      Node(
        id: id,
        name: name ?? this.name,
        type: type,
        status: status ?? this.status,
        position: position ?? this.position,
        text: text ?? this.text,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'status': status.name,
        'position': position.toJson(),
        'text': text,
      };

  factory Node.fromJson(Map<String, dynamic> j) => Node(
        id: j['id'] as String,
        name: j['name'] as String,
        type: NodeType.values.byName(j['type'] as String),
        status: NodeStatus.values.byName(j['status'] as String),
        position: HexPos.fromJson(j['position'] as Map<String, dynamic>),
        text: j['text'] as String,
      );
}
