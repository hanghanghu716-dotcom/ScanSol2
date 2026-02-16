import 'package:cloud_firestore/cloud_firestore.dart';

class MapTag {
  final String guideId;
  final double dx;      // 시작점 X 비율 (0.0 ~ 1.0)
  final double dy;      // 시작점 Y 비율 (0.0 ~ 1.0)
  final double width;   // 사각형 너비 비율
  final double height;  // 사각형 높이 비율
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
    'guideId': guideId,
    'dx': dx,
    'dy': dy,
    'width': width,
    'height': height,
    'label': label,
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

// [핵심] 이 클래스가 정의되어 있어야 다른 파일에서 에러가 나지 않습니다.
class GuideMap {
  final String id;
  final String title;
  final String imageUrl;
  final List<MapTag> tags;

  GuideMap({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.tags,
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
    );
  }
}