import 'package:uuid/uuid.dart';
import 'hex_pos.dart';

class Edge {
  final String id;
  final String fromId;
  final String toId;

  /// Intermediate hex centres the route passes through.
  /// Does NOT include the from/to node positions.
  List<HexPos> waypoints;

  Edge({
    String? id,
    required this.fromId,
    required this.toId,
    List<HexPos>? waypoints,
  })  : id = id ?? const Uuid().v4(),
        waypoints = waypoints ?? [];

  Edge copyWith({List<HexPos>? waypoints}) => Edge(
        id: id,
        fromId: fromId,
        toId: toId,
        waypoints: waypoints ?? List.from(this.waypoints),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromId': fromId,
        'toId': toId,
        'waypoints': waypoints.map((p) => p.toJson()).toList(),
      };

  factory Edge.fromJson(Map<String, dynamic> j) => Edge(
        id: j['id'] as String,
        fromId: j['fromId'] as String,
        toId: j['toId'] as String,
        waypoints: (j['waypoints'] as List)
            .map((p) => HexPos.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
