import 'package:uuid/uuid.dart';

class CanvasData {
  final String id;
  String name;
  String? rootNodeId;
  final List<String> nodeIds;
  final List<String> chainPath;
  double panX;
  double panY;
  double zoom;
  final DateTime createdAt;

  CanvasData({
    String? id,
    this.name = '',
    this.rootNodeId,
    List<String>? nodeIds,
    List<String>? chainPath,
    this.panX = 0,
    this.panY = 0,
    this.zoom = 1.0,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        nodeIds = nodeIds ?? [],
        chainPath = chainPath ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (rootNodeId != null) 'rootNodeId': rootNodeId,
        'nodeIds': nodeIds,
        'chainPath': chainPath,
        'panX': panX,
        'panY': panY,
        'zoom': zoom,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory CanvasData.fromJson(Map<String, dynamic> j) => CanvasData(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        rootNodeId: j['rootNodeId'] as String?,
        nodeIds: (j['nodeIds'] as List?)?.cast<String>() ?? [],
        chainPath: (j['chainPath'] as List?)?.cast<String>() ?? [],
        panX: (j['panX'] as num?)?.toDouble() ?? 0,
        panY: (j['panY'] as num?)?.toDouble() ?? 0,
        zoom: (j['zoom'] as num?)?.toDouble() ?? 1.0,
        createdAt: j['createdAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int)
            : DateTime.now(),
      );
}
