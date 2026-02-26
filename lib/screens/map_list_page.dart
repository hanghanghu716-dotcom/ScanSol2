import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 웹 확인을 위해 추가
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guide_map_model.dart';
import '../models/user_model.dart';
import '../widgets/node_connector_painter.dart';
import 'admin_map_editor_page.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class MapListPage extends StatefulWidget {
  final bool isAdmin;
  final UserModel user;

  const MapListPage({super.key, required this.user, this.isAdmin = false});

  @override
  State<MapListPage> createState() => _MapListPageState();
}

class _MapListPageState extends State<MapListPage> {
  final double canvasWidth = 5000;
  final double canvasHeight = 5000;

  final GlobalKey _canvasKey = GlobalKey();

  final Map<String, Offset> _temporaryPositions = {};
  final TransformationController _transformationController = TransformationController();
  final List<Map<String, dynamic>> _undoStack = [];

  String? _draggingSourceId;
  String? _potentialTargetId;
  Offset? _dragLineStart;
  Offset? _dragLineEnd;
  Offset? _dragStartMousePos;
  Offset? _dragStartNodePos;

  // 편집 가능 여부 확인 (관리자 AND 웹 환경)
  bool get _canEdit => widget.isAdmin && kIsWeb;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  bool _isCyclic(String currentId, String targetParentId, List<GuideMap> allMaps) {
    if (currentId == targetParentId) return true;
    final targetNode = allMaps.where((m) => m.id == targetParentId).firstOrNull;
    if (targetNode == null) return false;
    for (String pid in targetNode.parentIds) {
      if (_isCyclic(currentId, pid, allMaps)) return true;
    }
    return false;
  }

  void _saveForUndo(String actionType, Map<String, dynamic> data) {
    if (_undoStack.length > 20) _undoStack.removeAt(0);
    _undoStack.add({'type': actionType, 'data': data});
  }

  // [수정] _exorciseGhostConnections 함수(전체 삭제/초기화) 제거됨

  Future<void> _handleUndo() async {
    if (!_canEdit || _undoStack.isEmpty) return;
    final lastAction = _undoStack.removeLast();
    final data = lastAction['data'];
    try {
      if (lastAction['type'] == 'position') {
        await _savePosition(data['id'], data['oldPos'], saveUndo: false);
      } else if (lastAction['type'] == 'connect') {
        final doc = await FirebaseFirestore.instance.collection('guide_maps').doc(data['childId']).get();
        List<String> pids = List<String>.from(doc.data()?['parentIds'] ?? []);
        pids.remove(data['parentId']);
        await FirebaseFirestore.instance.collection('guide_maps').doc(data['childId']).update({'parentIds': pids});
      }
    } catch (e) {
      debugPrint("Undo 실패: $e");
    }
  }

  Future<void> _deleteNode(GuideMap map) async {
    if (!_canEdit) return;
    _saveForUndo('delete', {'id': map.id, 'data': map.toFirestore()});
    try {
      final children = await FirebaseFirestore.instance.collection('guide_maps')
          .where('parentIds', arrayContains: map.id).get();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in children.docs) {
        List<String> pids = List<String>.from(doc.data()['parentIds'] ?? []);
        pids.remove(map.id);
        batch.update(doc.reference, {'parentIds': pids});
      }
      batch.delete(FirebaseFirestore.instance.collection('guide_maps').doc(map.id));
      await batch.commit();
    } catch (e) {
      debugPrint("삭제 실패: $e");
    }
  }

  Future<void> _disconnectAllParents(String childId) async {
    if (!_canEdit) return;
    try {
      await FirebaseFirestore.instance.collection('guide_maps').doc(childId).update({'parentIds': [], 'depth': 0});
    } catch (e) {
      debugPrint("해제 실패: $e");
    }
  }

  Future<void> _savePosition(String id, Offset pos, {bool saveUndo = true}) async {
    try {
      await FirebaseFirestore.instance.collection('guide_maps').doc(id).update({'offsetX': pos.dx, 'offsetY': pos.dy});
    } catch (e) {
      debugPrint("좌표 저장 실패: $e");
    }
  }

  Future<void> _connectNodes(String parentId, String childId, List<GuideMap> allMaps) async {
    if (!_canEdit || parentId == childId) return;
    if (_isCyclic(childId, parentId, allMaps)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("순환 연결은 불가능합니다."), backgroundColor: Colors.orange));
      return;
    }
    try {
      final childDoc = await FirebaseFirestore.instance.collection('guide_maps').doc(childId).get();
      List<String> pids = List<String>.from(childDoc.data()?['parentIds'] ?? []);
      if (!pids.contains(parentId)) {
        pids.add(parentId);
        _saveForUndo('connect', {'childId': childId, 'parentId': parentId});
        await FirebaseFirestore.instance.collection('guide_maps').doc(childId).update({'parentIds': pids, 'depth': FieldValue.increment(1)});
      }
    } catch (e) {
      print("Error: $e");
    }
  }

  void _updatePotentialTarget(double x, double y, List<GuideMap> allMaps, String sourceId) {
    String? foundId;
    double minDistance = double.infinity;

    for (var node in allMaps) {
      if (node.id == sourceId) continue;
      double centerX = node.offsetX + 150;
      double centerY = node.offsetY + 75;

      bool isInsideX = x >= node.offsetX - 50 && x <= node.offsetX + 350;
      bool isInsideY = y >= node.offsetY - 50 && y <= node.offsetY + 200;

      if (isInsideX && isInsideY) {
        double distance = (Offset(x, y) - Offset(centerX, centerY)).distance;
        if (distance < minDistance) {
          minDistance = distance;
          foundId = node.id;
        }
      }
    }
    if (_potentialTargetId != foundId) {
      setState(() => _potentialTargetId = foundId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (_canEdit && event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyZ) {
          _handleUndo();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        appBar: AppBar(
          title: const Text("ScanSol Mapping Graph", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('guide_maps').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text("데이터 로드 오류"));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            List<GuideMap> allMaps = snapshot.data!.docs.map((doc) => GuideMap.fromFirestore(doc)).toList();

            for (int i = 0; i < allMaps.length; i++) {
              if (_temporaryPositions.containsKey(allMaps[i].id)) {
                allMaps[i] = allMaps[i].copyWith(
                  offsetX: _temporaryPositions[allMaps[i].id]!.dx,
                  offsetY: _temporaryPositions[allMaps[i].id]!.dy,
                );
              }
            }

            return Stack(
              children: [
                InteractiveViewer(
                  transformationController: _transformationController,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(2000),
                  minScale: 0.1, maxScale: 2.5,
                  scaleFactor: 1000.0,
                  child: Container(
                    key: _canvasKey,
                    width: canvasWidth, height: canvasHeight, color: const Color(0xFFF0F2F5),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: NodeConnectorPainter(isHorizontal: true, maps: allMaps)),
                        ),
                        if (_dragLineStart != null && _dragLineEnd != null)
                          Positioned.fill(
                            child: CustomPaint(painter: TemporaryLinkPainter(start: _dragLineStart, end: _dragLineEnd)),
                          ),
                        ...allMaps.map((map) => _buildGraphNode(context, map, allMaps)),
                      ],
                    ),
                  ),
                ),
                Positioned(
                    top: 20, right: 20,
                    child: _buildMinimap(allMaps, MediaQuery.of(context).size)
                ),
              ],
            );
          },
        ),
        // [수정] 편집 가능할 때만 FAB 표시 (전체 초기화 버튼 삭제됨)
        floatingActionButton: _canEdit ? _buildFAB(context) : null,
      ),
    );
  }

  Widget _buildGraphNode(BuildContext context, GuideMap mapData, List<GuideMap> allMaps) {
    bool isDragging = _draggingSourceId == mapData.id && _dragLineStart == null;
    bool isPotentialTarget = _potentialTargetId == mapData.id;

    return Positioned(
      key: ValueKey(mapData.id),
      left: mapData.offsetX, top: mapData.offsetY,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          MouseRegion(
            cursor: _canEdit ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _canEdit ? (details) {
                setState(() {
                  _draggingSourceId = mapData.id;
                  _dragStartMousePos = details.globalPosition;
                  _dragStartNodePos = Offset(mapData.offsetX, mapData.offsetY);
                });
              } : null,
              onPanUpdate: _canEdit ? (details) {
                if (_dragStartMousePos == null || _dragStartNodePos == null) return;
                setState(() {
                  double currentScale = _transformationController.value.getMaxScaleOnAxis();
                  final double deltaX = details.globalPosition.dx - _dragStartMousePos!.dx;
                  final double deltaY = details.globalPosition.dy - _dragStartMousePos!.dy;
                  _temporaryPositions[mapData.id] = Offset(
                    _dragStartNodePos!.dx + (deltaX / currentScale),
                    _dragStartNodePos!.dy + (deltaY / currentScale),
                  );
                });
              } : null,
              onPanEnd: _canEdit ? (details) {
                if (_temporaryPositions.containsKey(mapData.id)) {
                  _saveForUndo('position', {'id': mapData.id, 'oldPos': _dragStartNodePos, 'newPos': _temporaryPositions[mapData.id]});
                  _savePosition(mapData.id, _temporaryPositions[mapData.id]!);
                }
                setState(() { _draggingSourceId = null; _potentialTargetId = null; });
              } : null,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminMapEditorPage(user: widget.user, mapId: mapData.id))),
              child: _buildNodeCard(mapData, isSource: isDragging, isTarget: isPotentialTarget),
            ),
          ),

          // 왼쪽 포트는 항상 표시 (시각적 일관성)
          Positioned(left: -8, top: 50, child: _buildConnectionPort(Icons.circle, Colors.grey)),

          // [수정] 편집 가능(웹+관리자)할 때만 오른쪽 연결 포트 표시
          if (_canEdit)
            Positioned(
              right: -8, top: 50,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) {
                    setState(() {
                      _draggingSourceId = mapData.id;
                      _dragLineStart = Offset(mapData.offsetX + 300, mapData.offsetY + 60);
                      _dragLineEnd = _dragLineStart;
                    });
                  },
                  onPanUpdate: (details) {
                    final RenderBox? renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
                    if (renderBox != null) {
                      Offset localOffset = renderBox.globalToLocal(details.globalPosition);
                      setState(() {
                        _dragLineEnd = localOffset;
                        _updatePotentialTarget(_dragLineEnd!.dx, _dragLineEnd!.dy, allMaps, mapData.id);
                      });
                    }
                  },
                  onPanEnd: (details) async {
                    if (_potentialTargetId != null && _draggingSourceId != null) {
                      await _connectNodes(_draggingSourceId!, _potentialTargetId!, allMaps);
                    }
                    setState(() { _draggingSourceId = null; _potentialTargetId = null; _dragLineStart = null; _dragLineEnd = null; });
                  },
                  child: _buildConnectionPort(Icons.arrow_right_alt, _dragLineStart != null && _draggingSourceId == mapData.id ? Colors.orange : const Color(0xFF1A237E)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMinimap(List<GuideMap> maps, Size screenSize) {
    const double miniMapSize = 150.0;
    final double scale = miniMapSize / canvasWidth;

    return Container(
      width: miniMapSize, height: miniMapSize,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
      ),
      child: Stack(
        children: [
          ...maps.map((m) => Positioned(
              left: m.offsetX * scale,
              top: m.offsetY * scale,
              child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF1A237E), shape: BoxShape.circle))
          )),
          ValueListenableBuilder(
            valueListenable: _transformationController,
            builder: (context, Matrix4 matrix, child) {
              final double currentScale = matrix.getMaxScaleOnAxis();
              final Vector3 translation = matrix.getTranslation();
              final double viewportX = -translation.x / currentScale;
              final double viewportY = -translation.y / currentScale;
              final double viewportW = screenSize.width / currentScale;
              final double viewportH = screenSize.height / currentScale;

              return Positioned(
                left: viewportX * scale,
                top: viewportY * scale,
                child: Container(
                  width: viewportW * scale,
                  height: viewportH * scale,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent, width: 2),
                    color: Colors.redAccent.withOpacity(0.1),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNodeCard(GuideMap mapData, {bool isSource = false, bool isTarget = false}) {
    Color borderColor = const Color(0xFF1A237E).withOpacity(0.2);
    if (isSource) borderColor = Colors.orange;
    if (isTarget) borderColor = Colors.greenAccent[700]!;

    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isSource || isTarget ? 3 : 1),
        boxShadow: [BoxShadow(color: isTarget ? Colors.green.withOpacity(0.2) : Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_outlined, color: isSource ? Colors.orange : const Color(0xFF1A237E), size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(mapData.title, style: TextStyle(fontWeight: FontWeight.bold, color: isSource ? Colors.orange : const Color(0xFF1A237E)), overflow: TextOverflow.ellipsis)),
              // [수정] 편집 가능할 때만 삭제 및 링크 해제 버튼 표시
              if (_canEdit) ...[
                IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.delete_forever, size: 20, color: Colors.redAccent), onPressed: () => _deleteNode(mapData)),
                if (mapData.parentIds.isNotEmpty) IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.link_off, size: 18, color: Colors.blueGrey), onPressed: () => _disconnectAllParents(mapData.id)),
              ]
            ],
          ),
          const Divider(height: 20),
          _buildInfoRow(Icons.layers, "Depth: ${mapData.depth}"),
          const SizedBox(height: 4),
          _buildInfoRow(Icons.tag, "태그: ${mapData.tags.length}개"),
        ],
      ),
    );
  }

  Widget _buildConnectionPort(IconData icon, Color color) {
    return Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: color, width: 2)), child: Center(child: Icon(icon, size: 12, color: color)));
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(children: [Icon(icon, size: 14, color: Colors.grey[600]), const SizedBox(width: 6), Text(text, style: TextStyle(color: Colors.grey[700], fontSize: 12))]);
  }

  Widget _buildFAB(BuildContext context) {
    // [수정] 전체 초기화 버튼 로직 삭제 및 추가 버튼만 유지
    return FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminMapEditorPage(user: widget.user, mapId: null))),
        backgroundColor: const Color(0xFF1A237E),
        child: const Icon(Icons.add, color: Colors.white)
    );
  }
}

class TemporaryLinkPainter extends CustomPainter {
  final Offset? start; final Offset? end;
  TemporaryLinkPainter({this.start, this.end});
  @override
  void paint(Canvas canvas, Size size) {
    if (start == null || end == null) return;
    final paint = Paint()..color = const Color(0xFF1A237E).withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 3.0..strokeCap = StrokeCap.round;
    final path = Path(); path.moveTo(start!.dx, start!.dy);
    double controlPointDistance = (end!.dx - start!.dx).abs() / 2;
    path.cubicTo(start!.dx + controlPointDistance, start!.dy, end!.dx - controlPointDistance, end!.dy, end!.dx, end!.dy);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}