import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guide_map_model.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/guide_model.dart';
import '../models/user_model.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'package:barcode/barcode.dart';

import 'guide_detail_page.dart';

class AdminMapEditorPage extends StatefulWidget {
  final String? mapId;
  final UserModel user;

  const AdminMapEditorPage({super.key, required this.user, this.mapId});

  @override
  State<AdminMapEditorPage> createState() => _AdminMapEditorPageState();
}

class _AdminMapEditorPageState extends State<AdminMapEditorPage> {
  final GlobalKey _imageKey = GlobalKey();
  final List<MapTag> _tempTags = [];
  final TextEditingController _titleController = TextEditingController(text: "새 현장 맵");

  bool _isUploading = false;
  String? _imageUrl;
  bool _showLabel = true;
  // 1. 웹버전은 가이드바 디폴트 노출, 앱(모바일)은 숨김 처리
  bool _isSidebarVisible = kIsWeb;

  Offset? _startPos;
  Offset? _currentPos;

  @override
  void initState() {
    super.initState();
    // 가로 모드 고정 (모바일 대응)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    });

    if (widget.mapId != null) {
      _loadExistingMapData();
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingMapData() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('guide_maps')
          .doc(widget.mapId)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _titleController.text = data['title'] ?? "";
          _imageUrl = data['imageUrl'];
          if (data['tags'] != null) {
            _tempTags.clear();
            for (var tagData in data['tags']) {
              _tempTags.add(MapTag.fromMap(tagData));
            }
          }
        });
      }
    } catch (e) {
      debugPrint("데이터 로드 실패: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // 화면 폭 및 플랫폼 환경 확인
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobileDevice = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final bool isSmallScreen = screenWidth < 850;

    // 최종 앱버전(모바일) 여부 판단
    final bool isMobileVersion = isMobileDevice || isSmallScreen;
    // 관리자이면서 모바일이 아닐 때만 편집 허용
    final bool canEdit = widget.user.role.toUpperCase() == "ADMIN" && !isMobileVersion;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        title: Text(isMobileVersion ? "현장 가이드 조회" : "현장 매핑 에디터",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          // 가이드바 토글 (웹/데스크탑에서만 노출)
          if (!isMobileVersion)
            IconButton(
              icon: Icon(_isSidebarVisible ? Icons.view_sidebar : Icons.view_sidebar_outlined),
              onPressed: () => setState(() => _isSidebarVisible = !_isSidebarVisible),
              tooltip: "가이드바 토글",
            ),

          // 라벨 토글 버튼
          IconButton(
            icon: Icon(_showLabel ? Icons.label : Icons.label_off_outlined),
            onPressed: () => setState(() => _showLabel = !_showLabel),
          ),

          // 3. 앱버전에서 프린트, 사진추가, 저장 버튼 완전 제거
          if (!isMobileVersion) ...[
            IconButton(
              icon: const Icon(Icons.print_outlined),
              onPressed: _imageUrl == null ? null : _printMap,
            ),
            if (canEdit) ...[
              IconButton(icon: const Icon(Icons.add_a_photo_outlined), onPressed: _pickAndUploadImage),
              Padding(
                padding: const EdgeInsets.only(right: 12, left: 8),
                child: ActionChip(
                  backgroundColor: Colors.greenAccent[700],
                  label: const Text("저장하기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: _imageUrl == null ? null : _saveMapData,
                  avatar: const Icon(Icons.save_outlined, size: 18, color: Colors.white),
                ),
              ),
            ],
          ],
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    // 3. 앱버전 매핑 추가 기능 완전 차단
                    onPanStart: canEdit ? (d) => setState(() => _startPos = d.localPosition) : null,
                    onPanUpdate: canEdit ? (d) => setState(() => _currentPos = d.localPosition) : null,
                    onPanEnd: canEdit ? (d) => _handleMappingEnd() : null,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_imageUrl != null)
                          Image.network(
                            _imageUrl!,
                            key: _imageKey,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) {
                                // 2. 이미지 로드 완료 후 즉시 프레임 갱신을 유도하여 매핑 데이터가 바로 보이게 함
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) setState(() {});
                                });
                                return child;
                              }
                              return const Center(child: CircularProgressIndicator(color: Colors.white));
                            },
                          )
                        else
                          _buildEmptyState(),

                        // 매핑 위젯 렌더링
                        ..._buildTagWidgets(constraints),

                        if (canEdit && _startPos != null && _currentPos != null)
                          _buildDragBox(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          // 사이드바 표시 제어: 웹이면서 활성화 상태일 때만 노출
          if (_isSidebarVisible && !isMobileVersion)
            Container(
              width: 300,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(left: BorderSide(color: Colors.black12)),
              ),
              child: _buildTagSideBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(child: Text("등록된 현장 지도가 없습니다.", style: TextStyle(color: Colors.white54)));
  }

  // 2. 초기 렌더링 시 보이지 않는 현상 개선을 위해 constraints 매개변수 활용 및 안전장치 강화
  List<Widget> _buildTagWidgets(BoxConstraints constraints) {
    final RenderBox? box = _imageKey.currentContext?.findRenderObject() as RenderBox?;

    // RenderBox를 아직 찾지 못했다면 이미지의 fit: contain 특성에 맞춰 LayoutBuilder의 최대 크기를 참조하여 가계산
    final Size displaySize = box?.size ?? Size(constraints.maxWidth, constraints.maxHeight);

    if (_imageUrl == null) return [];

    return _tempTags.map((tag) {
      return Positioned(
        left: (tag.dx * displaySize.width),
        top: (tag.dy * displaySize.height),
        child: _buildTagIcon(tag, displaySize),
      );
    }).toList();
  }

  Widget _buildTagIcon(MapTag tag, Size size) {
    double iconSize = (size.width * 0.05).clamp(20.0, 45.0);
    return Positioned(
      left: (tag.dx * size.width),
      top: (tag.dy * size.height),
      child: GestureDetector(
        onTap: () => _showGuideListDialog(tag), // 클릭 시 가이드 목록 팝업
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: tag.width * size.width,
              height: tag.height * size.height,
              decoration: BoxDecoration(
                color: Colors.yellow.withOpacity(0.2), // 가시성을 위해 불투명도 약간 상향
                border: Border.all(color: Colors.yellow, width: 2),
              ),
            ),
            Positioned(
              top: -(iconSize / 2),
              right: -(iconSize / 2),
              child: Container(
                width: iconSize,
                height: iconSize,
                decoration: const BoxDecoration(color: Color(0xFF1A237E), shape: BoxShape.circle),
                child: Icon(Icons.qr_code_2, color: Colors.white, size: iconSize * 0.6),
              ),
            ),
            if (_showLabel)
              Positioned(
                top: (tag.height * size.height) + 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  color: Colors.black87,
                  child: Text(tag.label, style: const TextStyle(color: Colors.white, fontSize: 10)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 2. 해당 설비 ID에 맞는 가이드 목록을 Firestore에서 불러와 표시하는 다이얼로그
// [수정] 가이드 목록 다이얼로그를 세련된 스타일로 변경
  void _showGuideListDialog(MapTag tag) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFFF5F5F5),
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: const BoxDecoration(
            color: Color(0xFF1A237E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              const Icon(Icons.list_alt, color: Colors.white),
              const SizedBox(width: 10),
              Text("${tag.label} 가이드",
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        content: SizedBox(
          width: 400, // 다이얼로그 너비 고정
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('guides')
                .where('id', isEqualTo: tag.guideId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SizedBox(
                  height: 100,
                  child: Center(child: Text("등록된 가이드가 없습니다.", style: TextStyle(color: Colors.grey))),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: snapshot.data!.docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = snapshot.data!.docs[index];
                  final guideData = Guide.fromFirestore(doc.data() as Map<String, dynamic>);

                  return InkWell(
                    // [수정] 상세 페이지 이동 시 화면 회전 처리 로직
                    onTap: () async {
                      Navigator.pop(context); // 다이얼로그 닫기

                      // 1. 상세 페이지로 가기 전 세로 모드로 강제 고정
                      await SystemChrome.setPreferredOrientations([
                        DeviceOrientation.portraitUp,
                        DeviceOrientation.portraitDown,
                      ]);

                      // 2. 상세 페이지 이동 (await를 사용하여 돌아올 때까지 대기)
                      if (!mounted) return;
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => GuideDetailPage(guide: guideData)),
                      );

                      // 3. 다시 맵 화면으로 돌아오면 가로 모드로 복구
                      await SystemChrome.setPreferredOrientations([
                        DeviceOrientation.landscapeLeft,
                        DeviceOrientation.landscapeRight,
                      ]);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.menu_book, color: Color(0xFF1A237E), size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(guideData.title,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(height: 4),
                                Text(guideData.date,
                                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("닫기", style: TextStyle(color: Color(0xFF1A237E))),
          ),
        ],
      ),
    );
  }

  void _handleMappingEnd() {
    if (_startPos == null || _currentPos == null) return;

    final RenderBox? box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final Size size = box.size;

    double left = (_startPos!.dx < _currentPos!.dx ? _startPos!.dx : _currentPos!.dx) / size.width;
    double top = (_startPos!.dy < _currentPos!.dy ? _startPos!.dy : _currentPos!.dy) / size.height;
    double width = (_currentPos!.dx - _startPos!.dx).abs() / size.width;
    double height = (_currentPos!.dy - _startPos!.dy).abs() / size.height;

    _showAddAreaDialog(left, top, width, height);
    setState(() { _startPos = null; _currentPos = null; });
  }

  void _showAddAreaDialog(double left, double top, double width, double height) {
    if (_imageUrl == null) return;
    String label = "";
    String guideId = "";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("장비 영역 가이드 연결"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(onChanged: (v) => label = v, decoration: const InputDecoration(labelText: "장비 명칭", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(onChanged: (v) => guideId = v, decoration: const InputDecoration(labelText: "장비 ID", border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          ElevatedButton(
            onPressed: () {
              if (label.isNotEmpty && guideId.isNotEmpty) {
                setState(() {
                  _tempTags.add(MapTag(guideId: guideId, dx: left, dy: top, width: width, height: height, label: label));
                });
                Navigator.pop(context);
              }
            },
            child: const Text("추가"),
          ),
        ],
      ),
    );
  }

  Widget _buildTagSideBar() {
    return Column(
      children: [
        Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: "현장 명칭", border: UnderlineInputBorder())
            )
        ),
        const Divider(),
        Expanded(
          child: _tempTags.isEmpty
              ? Center(child: Text("등록된 태그 없음", style: TextStyle(color: Colors.grey[400])))
              : ListView.builder(
            itemCount: _tempTags.length,
            itemBuilder: (context, index) => ListTile(
              leading: const Icon(Icons.qr_code, color: Color(0xFF1A237E)),
              title: Text(_tempTags[index].label),
              trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () => setState(() => _tempTags.removeAt(index))
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDragBox() {
    if (_startPos == null || _currentPos == null) return const SizedBox.shrink();
    return Positioned(
      left: _startPos!.dx < _currentPos!.dx ? _startPos!.dx : _currentPos!.dx,
      top: _startPos!.dy < _currentPos!.dy ? _startPos!.dy : _currentPos!.dy,
      child: Container(
        width: (_currentPos!.dx - _startPos!.dx).abs(),
        height: (_currentPos!.dy - _startPos!.dy).abs(),
        decoration: BoxDecoration(
            border: Border.all(color: Colors.blueAccent, width: 2),
            color: Colors.blueAccent.withOpacity(0.1)
        ),
      ),
    );
  }

  Future<void> _printMap() async {
    if (_imageUrl == null) return;
    try {
      final doc = pw.Document();
      final response = await http.get(Uri.parse(_imageUrl!));
      final image = pw.MemoryImage(response.bodyBytes);
      final format = PdfPageFormat.a3.landscape;
      final qrCode = Barcode.qrCode();

      doc.addPage(pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
              ..._tempTags.expand((tag) {
                final double left = tag.dx * format.width;
                final double top = tag.dy * format.height;
                final double width = tag.width * format.width;
                final double height = tag.height * format.height;

                return [
                  pw.Positioned(
                    left: left, top: top,
                    child: pw.Container(
                      width: width, height: height,
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.yellow, width: 2)),
                    ),
                  ),
                  pw.Positioned(
                    left: left + width - 25, top: top - 25,
                    child: pw.Container(
                      width: 50, height: 50, padding: const pw.EdgeInsets.all(5),
                      decoration: const pw.BoxDecoration(color: PdfColors.white, shape: pw.BoxShape.rectangle),
                      child: pw.BarcodeWidget(barcode: qrCode, data: tag.guideId, drawText: false),
                    ),
                  ),
                  if (_showLabel)
                    pw.Positioned(
                      left: left, top: top + height + 5,
                      child: pw.Container(
                          padding: const pw.EdgeInsets.all(2),
                          color: PdfColors.black,
                          child: pw.Text(tag.guideId, style: pw.TextStyle(color: PdfColors.white, fontSize: 10))
                      ),
                    ),
                ];
              }).toList(),
            ],
          );
        },
      ));
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
    } catch (e) {
      debugPrint("프린트 실패: $e");
    }
  }

  Future<void> _pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _isUploading = true);
      try {
        String fileName = 'map_${DateTime.now().millisecondsSinceEpoch}.jpg';
        Reference ref = FirebaseStorage.instance.ref().child('maps/$fileName');
        if (kIsWeb) { await ref.putData(await image.readAsBytes()); }
        else { await ref.putFile(File(image.path)); }
        String downloadUrl = await ref.getDownloadURL();
        setState(() { _imageUrl = downloadUrl; _isUploading = false; });
      } catch (e) { setState(() => _isUploading = false); }
    }
  }

  Future<void> _saveMapData() async {
    if (_imageUrl == null || _tempTags.isEmpty) return;
    try {
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator())
      );
      final Map<String, dynamic> mapData = {
        'title': _titleController.text,
        'imageUrl': _imageUrl,
        'tags': _tempTags.map((t) => t.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (widget.mapId != null) {
        await FirebaseFirestore.instance.collection('guide_maps').doc(widget.mapId).update(mapData);
      } else {
        mapData['createdAt'] = FieldValue.serverTimestamp();
        mapData['authorName'] = widget.user.name;
        mapData['authorId'] = widget.user.userId;
        await FirebaseFirestore.instance.collection('guide_maps').add(mapData);
      }
      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) { if (mounted) Navigator.pop(context); }
  }
}