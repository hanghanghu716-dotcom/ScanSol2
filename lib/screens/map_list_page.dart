import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guide_map_model.dart';
import '../models/user_model.dart';
import '../widgets/node_connector_painter.dart';
import 'admin_map_editor_page.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3; // 이 줄을 추가합니다.

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

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // ... (기존 _isCyclic, _saveForUndo, _exorciseGhostConnections, _handleUndo, _deleteNode, _disconnectAllParents, _savePosition, _connectNodes 함수들은 그대로 유지)
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

  Future<void> _exorciseGhostConnections() async {
    // (기존 코드와 동일)
    print("👻 유령 연결 퇴치 시작...");
    final snapshot = await FirebaseFirestore.instance.collection('guide_maps').get();
    final batch = FirebaseFirestore.instance.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'parentIds': [], 'depth': 0});
    }
    await batch.commit();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✨ 모든 연결이 초기화되었습니다. 앱을 새로고침 하세요."), backgroundColor: Colors.redAccent)
      );
    }
  }

  Future<void> _handleUndo() async {
    // (기존 코드와 동일)
    if (_undoStack.isEmpty) return;
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
    // (기존 코드와 동일)
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
    // (기존 코드와 동일)
    try {
      await FirebaseFirestore.instance.collection('guide_maps').doc(childId).update({'parentIds': [], 'depth': 0});
    } catch (e) {
      debugPrint("해제 실패: $e");
    }
  }

  Future<void> _savePosition(String id, Offset pos, {bool saveUndo = true}) async {
    // (기존 코드와 동일)
    try {
      await FirebaseFirestore.instance.collection('guide_maps').doc(id).update({'offsetX': pos.dx, 'offsetY': pos.dy});
    } catch (e) {
      debugPrint("좌표 저장 실패: $e");
    }
  }

  Future<void> _connectNodes(String parentId, String childId, List<GuideMap> allMaps) async {
    // (기존 코드와 동일)
    if (parentId == childId) return;
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
        if (event is KeyDownEvent && HardwareKeyboard.instance.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyZ) {
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
                  // [요청 3 해결] 줌 감도 조절
                  // scaleFactor의 기본값은 200입니다. 숫자가 높을수록 줌 변화량이 작아져(둔해져) 부드럽게 느껴집니다.
                  // 800~1000 정도로 설정하면 휠 한 칸당 줌 변화폭이 줄어듭니다.
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
                // [요청 1 해결] 미니맵에 뷰포트 표시 (TransformationController 전달)
                Positioned(
                    top: 20, right: 20,
                    child: _buildMinimap(allMaps, MediaQuery.of(context).size)
                ),
              ],
            );
          },
        ),
        floatingActionButton: widget.isAdmin ? _buildFAB(context) : null,
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
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) {
                setState(() {
                  _draggingSourceId = mapData.id;
                  _dragStartMousePos = details.globalPosition;
                  _dragStartNodePos = Offset(mapData.offsetX, mapData.offsetY);
                });
              },
              onPanUpdate: (details) {
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
              },
              onPanEnd: (details) {
                if (_temporaryPositions.containsKey(mapData.id)) {
                  _saveForUndo('position', {'id': mapData.id, 'oldPos': _dragStartNodePos, 'newPos': _temporaryPositions[mapData.id]});
                  _savePosition(mapData.id, _temporaryPositions[mapData.id]!);
                }
                setState(() { _draggingSourceId = null; _potentialTargetId = null; });
              },
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminMapEditorPage(user: widget.user, mapId: mapData.id))),
              child: _buildNodeCard(mapData, isSource: isDragging, isTarget: isPotentialTarget),
            ),
          ),
          Positioned(left: -8, top: 50, child: _buildConnectionPort(Icons.circle, Colors.grey)),

          Positioned(
            right: -8, top: 50,
            // [요청 2 해결] MouseRegion으로 감싸서 커서를 손가락(click) 모양으로 변경
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

  // [수정] 미니맵에 '현재 보고 있는 영역(Viewport)'을 표시하는 기능 추가
  Widget _buildMinimap(List<GuideMap> maps, Size screenSize) {
    const double miniMapSize = 150.0;
    final double scale = miniMapSize / canvasWidth; // 미니맵 축소 비율 (0.03배)

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
          // 1. 노드 점들 표시
          ...maps.map((m) => Positioned(
              left: m.offsetX * scale,
              top: m.offsetY * scale,
              child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF1A237E), shape: BoxShape.circle))
          )),

          // 2. [핵심] 현재 뷰포트(내 화면) 표시
          // TransformationController의 값을 감시하여 실시간으로 빨간 박스를 그립니다.
          ValueListenableBuilder(
            valueListenable: _transformationController,
            builder: (context, Matrix4 matrix, child) {
              // InteractiveViewer의 매트릭스에서 현재 상태 추출
              final double currentScale = matrix.getMaxScaleOnAxis();
              final Vector3 translation = matrix.getTranslation();

              // 화면 좌표계 -> 캔버스 좌표계 역변환 공식
              // 뷰포트의 왼쪽 위 좌표 (Canvas 기준) = -translation / scale
              final double viewportX = -translation.x / currentScale;
              final double viewportY = -translation.y / currentScale;

              // 뷰포트의 크기 (Canvas 기준) = 화면 크기 / scale
              final double viewportW = screenSize.width / currentScale;
              final double viewportH = screenSize.height / currentScale;

              return Positioned(
                left: viewportX * scale, // 미니맵 비율 적용
                top: viewportY * scale,
                child: Container(
                  width: viewportW * scale,
                  height: viewportH * scale,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent, width: 2), // 빨간색 테두리
                    color: Colors.redAccent.withOpacity(0.1), // 내부 살짝 붉게
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // (이하 _buildNodeCard, _buildConnectionPort 등은 기존 동일)
  Widget _buildNodeCard(GuideMap mapData, {bool isSource = false, bool isTarget = false}) {
    // (기존 코드와 동일)
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
              if (widget.isAdmin) IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.delete_forever, size: 20, color: Colors.redAccent), onPressed: () => _deleteNode(mapData)),
              if (mapData.parentIds.isNotEmpty) IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.link_off, size: 18, color: Colors.blueGrey), onPressed: () => _disconnectAllParents(mapData.id)),
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
    // 유령 퇴치 버튼 포함한 기존 로직 유지
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'ghost_fix_btn',
          onPressed: () async {
            bool? confirm = await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("연결 초기화"),
                content: const Text("모든 노드의 연결 선을 끊고 초기화하시겠습니까?\n(데이터는 유지되지만 연결 관계는 삭제됩니다.)"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소")),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("확인", style: TextStyle(color: Colors.red))),
                ],
              ),
            );
            if (confirm == true) await _exorciseGhostConnections();
          },
          backgroundColor: Colors.red,
          tooltip: '모든 연결 관계 초기화',
          child: const Icon(Icons.cleaning_services),
        ),
        const SizedBox(height: 16),
        FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminMapEditorPage(user: widget.user, mapId: null))), backgroundColor: const Color(0xFF1A237E), child: const Icon(Icons.add, color: Colors.white)),
      ],
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