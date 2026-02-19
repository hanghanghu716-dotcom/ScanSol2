import 'package:cloud_firestore/cloud_firestore.dart';

class MapTag {
  final String guideId;
  final double dx;
  final double dy;
  final double width;
  final double height;
  final String label;

  MapTag({
    required this.guideId,
    required this.dx,
    required this.dy,
    this.width = 0.05,
    this.height = 0.05,
    required this.label,
  });

  Map<String, dynamic> toMap() => {
    'guideId': guideId, 'dx': dx, 'dy': dy, 'width': width, 'height': height, 'label': label,
  };

  factory MapTag.fromMap(Map<String, dynamic> map) => MapTag(
    guideId: map['guideId'] ?? '',
    dx: (map['dx'] ?? 0.0).toDouble(),
    dy: (map['dy'] ?? 0.0).toDouble(),
    width: (map['width'] ?? 0.05).toDouble(),
    height: (map['height'] ?? 0.05).toDouble(),
    label: map['label'] ?? '',
  );
}

class GuideMap {
  final String id;
  final String title;
  final String imageUrl;
  final List<MapTag> tags;
  final int depth;
  final List<String> parentIds; // [수정] 다중 부모 지원

  final double offsetX;
  final double offsetY;

  GuideMap({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.tags,
    this.depth = 0,
    this.parentIds = const [],
    this.offsetX = 0.0,
    this.offsetY = 0.0,
  });

  factory GuideMap.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GuideMap(
      id: doc.id,
      title: data['title'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      tags: (data['tags'] as List? ?? [])
          .map((t) => MapTag.fromMap(Map<String, dynamic>.from(t)))
          .toList(),
      depth: data['depth'] ?? 0,
      parentIds: List<String>.from(data['parentIds'] ?? []),
      offsetX: (data['offsetX'] ?? 0.0).toDouble(),
      offsetY: (data['offsetY'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'imageUrl': imageUrl,
      'tags': tags.map((t) => t.toMap()).toList(),
      'depth': depth,
      'parentIds': parentIds,
      'offsetX': offsetX,
      'offsetY': offsetY,
    };
  }

  GuideMap copyWith({
    double? offsetX,
    double? offsetY,
    List<String>? parentIds,
    int? depth,
  }) {
    return GuideMap(
      id: id,
      title: title,
      imageUrl: imageUrl,
      tags: tags,
      depth: depth ?? this.depth,
      parentIds: parentIds ?? this.parentIds,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
    );
  }
}