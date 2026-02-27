import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' show Vector3;
import '../models/guide_model.dart';
import 'guide_detail_page.dart';
import '../models/guide_map_model.dart';
import '../models/user_model.dart';
import '../widgets/node_connector_painter.dart';
import 'admin_map_editor_page.dart';

class MapListPage extends StatefulWidget {
  final bool isAdmin;
  final UserModel user;

  const MapListPage({super.key, required this.user, this.isAdmin = false});

  @override
  State<MapListPage> createState() => _MapListPageState();
}

class _MapListPageState extends State<MapListPage> {
  // 캔버스 크기 및 컨트롤러 설정
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

  // 뷰 모드 상태 변수 (false: 캔버스 모드, true: 그래프 모드)
  bool _isGraphViewOpen = false;

  // 편집 가능 여부 (관리자 권한 및 웹 환경 동시 충족)
  bool get _canEdit => widget.isAdmin && kIsWeb;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // --- 비즈니스 로직 (Firestore 연동 및 무결성 검사) ---
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
      debugPrint("Undo 처리 중 오류: $e");
    }
  }

  // [통합] 데이터 및 이미지 완벽 삭제 로직 적용
  Future<void> _deleteNode(BuildContext context, GuideMap mapData) async {
    if (!_canEdit) return;

    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("지도 삭제"),
        content: Text("'${mapData.title}' 지도를 완전히 삭제하시겠습니까?\n등록된 태그 정보와 연결 관계도 모두 삭제됩니다."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("삭제", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 로딩 표시
    if (context.mounted) {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
    }

    try {
      // 1. 하위 노드의 연결 관계(parentIds) 끊기
      final children = await FirebaseFirestore.instance.collection('guide_maps').where('parentIds', arrayContains: mapData.id).get();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in children.docs) {
        List<String> pids = List<String>.from(doc.data()['parentIds'] ?? []);
        pids.remove(mapData.id);
        batch.update(doc.reference, {'parentIds': pids});
      }

      // 2. Firebase Storage 이미지 삭제
      if (mapData.imageUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(mapData.imageUrl).delete();
        } catch (e) {
          debugPrint("이미지 삭제 실패(이미 없을 수 있음): $e");
        }
      }

      // 3. Firestore 문서 삭제 및 커밋
      batch.delete(FirebaseFirestore.instance.collection('guide_maps').doc(mapData.id));
      await batch.commit();

      if (context.mounted) {
        Navigator.pop(context); // 로딩 종료
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("지도가 안전하게 삭제되었습니다.")));
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // 로딩 종료
      debugPrint("노드 삭제 실패: $e");
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("삭제 실패: $e")));
    }
  }

  Future<void> _disconnectAllParents(String childId) async {
    if (!_canEdit) return;
    try {
      await FirebaseFirestore.instance.collection('guide_maps').doc(childId).update({'parentIds': [], 'depth': 0});
    } catch (e) {
      debugPrint("연결 해제 실패: $e");
    }
  }

  Future<void> _savePosition(String id, Offset pos, {bool saveUndo = true}) async {
    try {
      await FirebaseFirestore.instance.collection('guide_maps').doc(id).update({'offsetX': pos.dx, 'offsetY': pos.dy});
    } catch (e) {
      debugPrint("위치 저장 실패: $e");
    }
  }

  Future<void> _connectNodes(String parentId, String childId, List<GuideMap> allMaps) async {
    if (!_canEdit || parentId == childId) return;
    if (_isCyclic(childId, parentId, allMaps)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("순환 참조가 감지되었습니다."), backgroundColor: Colors.orange));
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
      debugPrint("연결 처리 중 오류: $e");
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
          title: Text(_isGraphViewOpen ? "ScanSol Global Graph" : "ScanSol Mapping Canvas", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: _isGraphViewOpen ? "캔버스 모드" : "그래프 모드",
              icon: Icon(_isGraphViewOpen ? Icons.grid_view_rounded : Icons.hub_outlined),
              onPressed: () => setState(() => _isGraphViewOpen = !_isGraphViewOpen),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('guide_maps').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text("데이터 로드 중 오류가 발생했습니다."));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            List<GuideMap> allMaps = snapshot.data!.docs.map((doc) => GuideMap.fromFirestore(doc)).toList();

            // 1. 동적 물리 그래프 뷰 (옵시디언 모드)
            if (_isGraphViewOpen) {
              return ObsidianGraphWidget(
                maps: allMaps,
                onNodeTap: (id) => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminMapEditorPage(user: widget.user, mapId: id))),
              );
            }

            // 2. 관리자용 캔버스 뷰 (기존 시인성 높은 카드 UI 적용)
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
                  boundaryMargin: const EdgeInsets.all(2500),
                  minScale: 0.05, maxScale: 2.5,
                  scaleFactor: 1000.0,
                  child: Container(
                    key: _canvasKey,
                    width: canvasWidth, height: canvasHeight, color: const Color(0xFFF0F2F5),
                    child: Stack(
                      children: [
                        Positioned.fill(child: CustomPaint(painter: NodeConnectorPainter(isHorizontal: true, maps: allMaps))),
                        if (_dragLineStart != null && _dragLineEnd != null)
                          Positioned.fill(
                            child: CustomPaint(painter: TemporaryLinkPainter(start: _dragLineStart, end: _dragLineEnd)),
                          ),
                        ...allMaps.map((map) => _buildGraphNode(context, map, allMaps)),
                      ],
                    ),
                  ),
                ),
                Positioned(top: 20, right: 20, child: _buildMinimap(allMaps, MediaQuery.of(context).size)),
              ],
            );
          },
        ),
        floatingActionButton: _canEdit && !_isGraphViewOpen ? _buildFAB(context) : null,
      ),
    );
  }

  // 캔버스 내 노드 구성요소 (첫 번째 코드의 높은 시인성 적용)
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
              child: _buildNodeCard(context, mapData, isSource: isDragging, isTarget: isPotentialTarget),
            ),
          ),

          // 좌측 입력 포트
          Positioned(left: -8, top: 50, child: _buildConnectionPort(Icons.circle, Colors.grey)),

          // 우측 연결(출력) 포트 - 편집 권한자에게만 표시
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

  // 캔버스 모드 미니맵 (뷰포트 추적 포함)
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

  Widget _buildNodeCard(BuildContext context, GuideMap mapData, {bool isSource = false, bool isTarget = false}) {
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
              if (_canEdit) ...[
                IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.delete_forever, size: 20, color: Colors.redAccent), onPressed: () => _deleteNode(context, mapData)),
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
    return FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminMapEditorPage(user: widget.user, mapId: null))),
        backgroundColor: const Color(0xFF1A237E),
        child: const Icon(Icons.add, color: Colors.white)
    );
  }
}

// 캔버스 모드용 베지어 곡선 연결선 페인터 (첫 번째 코드 적용)
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

// --- 그래프 뷰 위젯 (고급 물리 엔진 + 태그 위성 노드 기능 통합) ---
class ObsidianGraphWidget extends StatefulWidget {
  final List<GuideMap> maps;
  final Function(String) onNodeTap;
  const ObsidianGraphWidget({super.key, required this.maps, required this.onNodeTap});

  @override
  State<ObsidianGraphWidget> createState() => _ObsidianGraphWidgetState();
}

class _ObsidianGraphWidgetState extends State<ObsidianGraphWidget> with SingleTickerProviderStateMixin {
  late Ticker _ticker;

  // 맵 노드 물리 상태
  final Map<String, Offset> _positions = {};
  final Map<String, Offset> _velocities = {};

  // 태그(가이드) 노드 물리 상태
  final Map<String, MapTag> _tagData = {};
  final Map<String, String> _tagParentMap = {}; // tagNodeId -> parentMapId
  final Map<String, Offset> _tagPositions = {};
  final Map<String, Offset> _tagVelocities = {};

  final TransformationController _graphTransformCtrl = TransformationController();

  String? _hoveredNodeId;
  String? _hoveredTagId;
  Set<String> _highlightedNodes = {};
  Set<String> _highlightedTags = {};

  double _energy = 1.0;
  final double _minEnergy = 0.001;
  final double graphWorldSize = 2500.0;

  @override
  void initState() {
    super.initState();
    final random = math.Random();

    // 1. 초기 노드 및 태그 위치 분산
    for (var map in widget.maps) {
      _positions[map.id] = Offset(
          1250 + (random.nextDouble() - 0.5) * 500,
          1250 + (random.nextDouble() - 0.5) * 500
      );
      _velocities[map.id] = Offset.zero;

      // 해당 맵에 속한 가이드(태그)들을 위성 노드로 초기화
      for (int i = 0; i < map.tags.length; i++) {
        var tag = map.tags[i];
        String tagNodeId = "TAG_${map.id}_$i";
        _tagData[tagNodeId] = tag;
        _tagParentMap[tagNodeId] = map.id;
        // 부모 맵 노드 주변에 무작위 배치
        _tagPositions[tagNodeId] = _positions[map.id]! + Offset((random.nextDouble() - 0.5) * 150, (random.nextDouble() - 0.5) * 150);
        _tagVelocities[tagNodeId] = Offset.zero;
      }
    }

    _ticker = createTicker(_tick)..start();

    // 2. 초기 뷰포트 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final Size size = MediaQuery.of(context).size;
      const double initialScale = 0.5;
      final double tx = (size.width / 2) - (1250 * initialScale);
      final double ty = (size.height / 2) - (1250 * initialScale);
      _graphTransformCtrl.value = Matrix4.identity()..translate(tx, ty)..scale(initialScale);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _graphTransformCtrl.dispose();
    super.dispose();
  }

  // 매 프레임마다 호출되는 물리 시뮬레이션 로직
  void _tick(Duration elapsed) {
    if (_energy < _minEnergy) {
      _ticker.stop();
      return;
    }

    Map<String, Offset> forces = { for (var m in widget.maps) m.id : Offset.zero };
    Map<String, Offset> tagForces = { for (var tId in _tagPositions.keys) tId : Offset.zero };

    // [척력] 맵 노드 간 상호 밀어내기 (태그 공간을 위해 기존보다 척력을 강하게 설정)
    for (int i = 0; i < widget.maps.length; i++) {
      for (int j = i + 1; j < widget.maps.length; j++) {
        final id1 = widget.maps[i].id; final id2 = widget.maps[j].id;
        Offset delta = _positions[id1]! - _positions[id2]!;
        double distSq = delta.distanceSquared.clamp(900.0, 1000000.0);
        Offset f = (delta / math.sqrt(distSq)) * (350000.0 / distSq);
        forces[id1] = forces[id1]! + f;
        forces[id2] = forces[id2]! - f;
      }
    }

    // [인력] 부모-자식 맵 노드 간 당기기 및 중앙 수렴
    for (var map in widget.maps) {
      for (var pid in map.parentIds) {
        if (_positions.containsKey(pid)) {
          Offset delta = _positions[map.id]! - _positions[pid]!;
          double dist = delta.distance;
          Offset f = (delta / (dist == 0 ? 1 : dist)) * (dist - 200.0) * 0.08;
          forces[map.id] = forces[map.id]! - f;
          forces[pid] = forces[pid]! + f;
        }
      }
      forces[map.id] = forces[map.id]! + (const Offset(1250, 1250) - _positions[map.id]!) * 0.015;
    }

    // [위성 인력] 태그 노드가 부모 맵 노드 주위를 맴돌도록 설정
    for (var tagId in _tagPositions.keys) {
      String parentId = _tagParentMap[tagId]!;
      Offset delta = _tagPositions[tagId]! - _positions[parentId]!;
      double dist = delta.distance;
      // 부모 맵으로부터 이상적인 거리는 80.0
      Offset f = (delta / (dist == 0 ? 1 : dist)) * (dist - 80.0) * 0.15;
      tagForces[tagId] = tagForces[tagId]! - f;
      forces[parentId] = forces[parentId]! + f; // 작용-반작용
    }

    // [위성 척력] 태그 노드끼리 겹치지 않도록 밀어내기
    List<String> allTags = _tagPositions.keys.toList();
    for (int i = 0; i < allTags.length; i++) {
      for (int j = i + 1; j < allTags.length; j++) {
        Offset delta = _tagPositions[allTags[i]]! - _tagPositions[allTags[j]]!;
        double distSq = delta.distanceSquared.clamp(400.0, 100000.0);
        Offset f = (delta / math.sqrt(distSq)) * (15000.0 / distSq);
        tagForces[allTags[i]] = tagForces[allTags[i]]! + f;
        tagForces[allTags[j]] = tagForces[allTags[j]]! - f;
      }
    }

    setState(() {
      for (var map in widget.maps) {
        _velocities[map.id] = (_velocities[map.id]! + forces[map.id]!) * 0.83;
        _positions[map.id] = _positions[map.id]! + _velocities[map.id]! * _energy;
      }
      for (var tagId in _tagPositions.keys) {
        _tagVelocities[tagId] = (_tagVelocities[tagId]! + tagForces[tagId]!) * 0.83;
        _tagPositions[tagId] = _tagPositions[tagId]! + _tagVelocities[tagId]! * _energy;
      }
      _energy *= 0.993;
    });
  }

  void _updateHighlights(String? elementId, {bool isTag = false}) {
    if (elementId == null) {
      setState(() { _hoveredNodeId = null; _hoveredTagId = null; _highlightedNodes.clear(); _highlightedTags.clear(); });
      return;
    }

    Set<String> rNodes = {};
    Set<String> rTags = {};

    if (isTag) {
      String parentId = _tagParentMap[elementId]!;
      rTags.add(elementId);
      rNodes.add(parentId); // 태그에 호버 시 부모 맵 하이라이트
      _hoveredNodeId = null;
      _hoveredTagId = elementId;
    } else {
      rNodes.add(elementId);
      for (var m in widget.maps) {
        if (m.id == elementId) rNodes.addAll(m.parentIds);
        if (m.parentIds.contains(elementId)) rNodes.add(m.id);
      }
      // 맵에 호버 시 해당 맵에 속한 모든 태그 하이라이트
      _tagParentMap.forEach((tId, pId) {
        if (pId == elementId) rTags.add(tId);
      });
      _hoveredNodeId = elementId;
      _hoveredTagId = null;
    }
    setState(() { _highlightedNodes = rNodes; _highlightedTags = rTags; });
  }

  // 가이드(태그) 노드 클릭 시 동작하는 내비게이션 로직
  Future<void> _handleTagTap(MapTag tag) async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

    try {
      final query = await FirebaseFirestore.instance.collection('guides').where('id', isEqualTo: tag.guideId).get();
      if (mounted) Navigator.pop(context); // 로딩 닫기

      if (query.docs.isNotEmpty) {
        final guideData = Guide.fromFirestore(query.docs.first.data() as Map<String, dynamic>);
        if (mounted) {
          // 화면 방향 등은 GuideDetailPage 자체 로직을 따름
          Navigator.push(context, MaterialPageRoute(builder: (context) => GuideDetailPage(guide: guideData)));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("해당 가이드를 찾을 수 없습니다.")));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("가이드 로드 오류: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("오류 발생: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: const Color(0xFF0F1115),
          child: InteractiveViewer(
            transformationController: _graphTransformCtrl,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(3000),
            minScale: 0.02, maxScale: 3.5,
            scaleFactor: 1500.0,
            child: SizedBox(
              width: graphWorldSize, height: graphWorldSize,
              child: CustomPaint(
                painter: GraphLinkPainter(
                    maps: widget.maps,
                    positions: _positions,
                    tagPositions: _tagPositions,
                    tagParentMap: _tagParentMap,
                    highlightedNodes: _highlightedNodes,
                    highlightedTags: _highlightedTags,
                    hoveredNodeId: _hoveredNodeId,
                    hoveredTagId: _hoveredTagId
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 1. 맵 노드 렌더링
                    ...widget.maps.map((map) {
                      final pos = _positions[map.id]!;
                      bool isFocused = _highlightedNodes.isEmpty || _highlightedNodes.contains(map.id);
                      final double dotSize = map.parentIds.isEmpty ? 14.0 : 9.0;
                      final double dotRadius = dotSize / 2;

                      return Positioned(
                        left: pos.dx - 60,
                        top: pos.dy - dotRadius,
                        child: GestureDetector(
                          onTap: () => widget.onNodeTap(map.id),
                          child: MouseRegion(
                            onEnter: (_) => _updateHighlights(map.id),
                            onExit: (_) => _updateHighlights(null),
                            child: SizedBox(
                              width: 120,
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                        width: dotSize, height: dotSize,
                                        decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isFocused
                                                ? (map.parentIds.isEmpty ? Colors.amberAccent : Colors.cyanAccent)
                                                : Colors.grey.withOpacity(0.12),
                                            boxShadow: isFocused ? [BoxShadow(color: (map.parentIds.isEmpty ? Colors.amber : Colors.cyan).withOpacity(0.2), blurRadius: 8)] : []
                                        )
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                        map.title,
                                        style: TextStyle(
                                            color: isFocused ? Colors.white.withOpacity(0.85) : Colors.white12,
                                            fontSize: 9.0, fontWeight: FontWeight.bold
                                        ),
                                        textAlign: TextAlign.center, overflow: TextOverflow.ellipsis
                                    ),
                                  ]
                              ),
                            ),
                          ),
                        ),
                      );
                    }),

                    // 2. 가이드(태그) 위성 노드 렌더링
                    ..._tagPositions.keys.map((tagId) {
                      final pos = _tagPositions[tagId]!;
                      final tag = _tagData[tagId]!;
                      bool isFocused = _highlightedNodes.isEmpty || _highlightedTags.contains(tagId);

                      return Positioned(
                          left: pos.dx - 40, // 80 width / 2
                          top: pos.dy - 8,   // 16 height / 2
                          child: GestureDetector(
                              onTap: () => _handleTagTap(tag),
                              child: MouseRegion(
                                  onEnter: (_) => _updateHighlights(tagId, isTag: true),
                                  onExit: (_) => _updateHighlights(null),
                                  child: SizedBox(
                                      width: 80,
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 16, height: 16,
                                              decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: isFocused ? Colors.pinkAccent : Colors.grey.withOpacity(0.12),
                                                  boxShadow: isFocused ? [BoxShadow(color: Colors.pinkAccent.withOpacity(0.3), blurRadius: 6)] : []
                                              ),
                                              child: Icon(Icons.menu_book, size: 9, color: isFocused ? Colors.white : Colors.white24),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                                tag.label,
                                                style: TextStyle(
                                                  color: isFocused ? Colors.pinkAccent.shade100 : Colors.white12,
                                                  fontSize: 7.5,
                                                ),
                                                textAlign: TextAlign.center, overflow: TextOverflow.ellipsis
                                            ),
                                          ]
                                      )
                                  )
                              )
                          )
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(top: 25, right: 25, child: _buildGraphMinimap()),
      ],
    );
  }

  Widget _buildGraphMinimap() {
    const double miniMapSize = 170.0;
    final double scale = miniMapSize / graphWorldSize;
    return Container(
      width: miniMapSize, height: miniMapSize,
      decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12, width: 1.2)
      ),
      child: Stack(
          children: [
            ...widget.maps.map((m) {
              final pos = _positions[m.id]!;
              return Positioned(
                  left: pos.dx * scale, top: pos.dy * scale,
                  child: Container(width: 3, height: 3, decoration: BoxDecoration(color: m.parentIds.isEmpty ? Colors.amberAccent : Colors.cyanAccent, shape: BoxShape.circle))
              );
            }),
            // 미니맵에서도 태그 노드를 핑크색 아주 작은 점으로 표시
            ..._tagPositions.keys.map((tId) {
              final pos = _tagPositions[tId]!;
              return Positioned(
                  left: pos.dx * scale, top: pos.dy * scale,
                  child: Container(width: 1.5, height: 1.5, decoration: const BoxDecoration(color: Colors.pinkAccent, shape: BoxShape.circle))
              );
            }),
            ValueListenableBuilder(
              valueListenable: _graphTransformCtrl,
              builder: (context, Matrix4 matrix, child) {
                final double currentScale = matrix.getMaxScaleOnAxis();
                final Vector3 translation = matrix.getTranslation();
                final Size size = MediaQuery.of(context).size;
                return Positioned(
                    left: (-translation.x / currentScale) * scale,
                    top: (-translation.y / currentScale) * scale,
                    child: Container(
                        width: (size.width / currentScale) * scale,
                        height: (size.height / currentScale) * scale,
                        decoration: BoxDecoration(border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 1.5))
                    )
                );
              },
            ),
          ]
      ),
    );
  }
}

class GraphLinkPainter extends CustomPainter {
  final List<GuideMap> maps;
  final Map<String, Offset> positions;
  final Map<String, Offset> tagPositions;
  final Map<String, String> tagParentMap;

  final Set<String> highlightedNodes;
  final Set<String> highlightedTags;
  final String? hoveredNodeId;
  final String? hoveredTagId;

  GraphLinkPainter({
    required this.maps, required this.positions,
    required this.tagPositions, required this.tagParentMap,
    required this.highlightedNodes, required this.highlightedTags,
    this.hoveredNodeId, this.hoveredTagId
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 맵-맵 연결선 Paint
    final paint = Paint()..color = Colors.white.withOpacity(0.07)..strokeWidth = 0.9;
    final hPaint = Paint()..color = Colors.cyanAccent.withOpacity(0.75)..strokeWidth = 2.2;

    // 맵-태그 연결선 Paint
    final tagPaint = Paint()..color = Colors.white.withOpacity(0.03)..strokeWidth = 0.5;
    final tagHPaint = Paint()..color = Colors.pinkAccent.withOpacity(0.5)..strokeWidth = 1.2;

    // 1. 맵 간의 계층 엣지 그리기
    for (var map in maps) {
      if (!positions.containsKey(map.id)) continue;
      for (var pid in map.parentIds) {
        if (!positions.containsKey(pid)) continue;
        bool isH = highlightedNodes.contains(map.id) && highlightedNodes.contains(pid) && (map.id == hoveredNodeId || pid == hoveredNodeId || hoveredTagId != null);
        canvas.drawLine(positions[pid]!, positions[map.id]!, isH ? hPaint : paint);
      }
    }

    // 2. 맵-태그 간의 위성 엣지 그리기
    for (var tagId in tagPositions.keys) {
      String parentId = tagParentMap[tagId]!;
      if (positions.containsKey(parentId)) {
        bool isH = (highlightedTags.contains(tagId) && highlightedNodes.contains(parentId)) &&
            (tagId == hoveredTagId || parentId == hoveredNodeId);
        canvas.drawLine(positions[parentId]!, tagPositions[tagId]!, isH ? tagHPaint : tagPaint);
      }
    }
  }

  @override
  bool shouldRepaint(GraphLinkPainter oldDelegate) => true;
}