import 'package:flutter/material.dart';
import '../models/guide_map_model.dart';

class NodeConnectorPainter extends CustomPainter {
  final bool isHorizontal;
  final List<GuideMap> maps;

  NodeConnectorPainter({required this.isHorizontal, required this.maps});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3949AB).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final Map<String, GuideMap> nodeLookup = {for (var map in maps) map.id: map};

    for (var map in maps) {
      // [수정] 다중 부모(parentIds)를 순회하며 선을 그립니다.
      for (String pid in map.parentIds) {
        if (nodeLookup.containsKey(pid)) {
          final parent = nodeLookup[pid]!;

          double startX = parent.offsetX + 300;
          double startY = parent.offsetY + 60;
          double endX = map.offsetX;
          double endY = map.offsetY + 60;

          final path = Path();
          path.moveTo(startX, startY);

          double controlPointDistance = (endX - startX).abs() / 2;
          path.cubicTo(
            startX + controlPointDistance, startY,
            endX - controlPointDistance, endY,
            endX, endY,
          );

          canvas.drawPath(path, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}