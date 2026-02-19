import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guide_map_model.dart';
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
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
  bool _isSidebarVisible = kIsWeb;

  // [인쇄 모드 변수]
  bool _isPrintMode = false;
  ui.Image? _loadedImageInfo;
  PdfPageFormat _selectedFormat = PdfPageFormat.a3.landscape;
  Rect _printRect = const Rect.fromLTWH(0, 0, 1, 1);
  double _zoomLevel = 1.0;

  Offset? _startPos;
  Offset? _currentPos;
  int _savedDepth = 0;

  @override
  void initState() {
    super.initState();
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
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('guide_maps').doc(widget.mapId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _titleController.text = data['title'] ?? "";
          _imageUrl = data['imageUrl'];
          _savedDepth = data['depth'] ?? 0;
          if (data['tags'] != null) {
            _tempTags.clear();
            for (var tagData in data['tags']) {
              _tempTags.add(MapTag.fromMap(tagData));
            }
          }
        });
        if (_imageUrl != null) _fetchImageInfo(_imageUrl!);
      }
    } catch (e) {
      debugPrint("데이터 로드 실패: $e");
    }
  }

  Future<void> _fetchImageInfo(String url) async {
    try {
      final ImageStream stream = NetworkImage(url).resolve(ImageConfiguration.empty);
      final Completer<ui.Image> completer = Completer();
      late ImageStreamListener listener;
      listener = ImageStreamListener((ImageInfo frame, bool synchronousCall) {
        stream.removeListener(listener);
        completer.complete(frame.image);
      });
      stream.addListener(listener);
      final info = await completer.future;
      setState(() {
        _loadedImageInfo = info;
      });
      _resetPrintRect();
    } catch (e) {
      debugPrint("이미지 정보 로드 실패: $e");
    }
  }

  void _resetPrintRect() {
    if (_loadedImageInfo == null) return;

    double imgAspect = _loadedImageInfo!.width / _loadedImageInfo!.height;
    double paperAspect = _selectedFormat.width / _selectedFormat.height;

    double newW, newH;
    // 이미지가 용지보다 가로로 긴 경우 (이미지 비율 > 용지 비율)
    if (imgAspect > paperAspect) {
      newH = 1.0;
      newW = paperAspect / imgAspect; // 너비는 1.0보다 작아짐
    } else {
      newW = 1.0;
      newH = imgAspect / paperAspect; // 높이는 1.0보다 작아짐
    }

    setState(() {
      _zoomLevel = 1.0;
      _printRect = Rect.fromCenter(
          center: const Offset(0.5, 0.5),
          width: newW,
          height: newH
      );
    });
  }

  void _updatePrintRectZoom(double zoom) {
    if (_loadedImageInfo == null) return;
    setState(() {
      _zoomLevel = zoom;
      double scale = 1 / zoom;

      double imgAspect = _loadedImageInfo!.width / _loadedImageInfo!.height;
      double paperAspect = _selectedFormat.width / _selectedFormat.height;

      double baseW, baseH;
      if (imgAspect > paperAspect) {
        baseH = 1.0;
        baseW = paperAspect / imgAspect;
      } else {
        baseW = 1.0;
        baseH = imgAspect / paperAspect;
      }

      double finalW = baseW * scale;
      double finalH = baseH * scale;

      // [핵심] clamp 제거: 박스가 1.0보다 커질 수 있도록 허용 (화면 꽉 채우기 지원)
      _printRect = Rect.fromCenter(
          center: _printRect.center,
          width: finalW,
          height: finalH
      );

      _clampPrintRectPosition(); // 위치 보정
    });
  }

  void _clampPrintRectPosition() {
    double newCx = _printRect.center.dx;
    double newCy = _printRect.center.dy;
    double w = _printRect.width;
    double h = _printRect.height;

    // 너비가 이미지(1.0)보다 작으면 범위 내 이동, 크면 중앙 고정
    if (w < 1.0) {
      newCx = newCx.clamp(w / 2, 1.0 - w / 2);
    } else {
      newCx = 0.5; // 이미지가 박스보다 작으므로 중앙 정렬
    }

    // 높이가 이미지(1.0)보다 작으면 범위 내 이동, 크면 중앙 고정
    if (h < 1.0) {
      newCy = newCy.clamp(h / 2, 1.0 - h / 2);
    } else {
      newCy = 0.5;
    }

    _printRect = Rect.fromCenter(
      center: Offset(newCx, newCy),
      width: w,
      height: h,
    );
  }

  Future<void> _pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() => _isUploading = true);
      try {
        String fileName = 'map_${DateTime.now().millisecondsSinceEpoch}.jpg';
        Reference ref = FirebaseStorage.instance.ref().child('maps/$fileName');
        final bytes = await image.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        String downloadUrl = await ref.getDownloadURL();
        setState(() {
          _imageUrl = downloadUrl;
          _isUploading = false;
        });
        _fetchImageInfo(downloadUrl);
      } catch (e) {
        debugPrint("업로드 오류: $e");
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobileDevice = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final bool isMobileVersion = isMobileDevice || (screenWidth < 850);
    final bool canEdit = widget.user.role.toUpperCase() == "ADMIN" && !isMobileVersion;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          backgroundColor: _isPrintMode ? Colors.black87 : const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          elevation: 4,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 28),
            onPressed: () {
              if (_isPrintMode) {
                setState(() => _isPrintMode = false); // 인쇄 모드 종료 시 다시 '꽉 채우기'로 복귀
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: _isPrintMode
              ? _buildPrintModeToolbar()
              : Row(
            children: [
              const Text("에디터", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(width: 30),
              if (!isMobileVersion) ...[
                _buildToolbarDivider(),
                _buildLargeToolbarButton(
                  icon: _isSidebarVisible ? Icons.view_sidebar : Icons.view_sidebar_outlined,
                  label: "목록", isActive: _isSidebarVisible, onTap: () => setState(() => _isSidebarVisible = !_isSidebarVisible),
                ),
                _buildLargeToolbarButton(
                  icon: _showLabel ? Icons.label : Icons.label_off_outlined,
                  label: "라벨", isActive: _showLabel, onTap: () => setState(() => _showLabel = !_showLabel),
                ),
                _buildToolbarDivider(),
                if (canEdit)
                  _buildLargeToolbarButton(
                    icon: _imageUrl == null ? Icons.add_photo_alternate : Icons.image_search,
                    label: _imageUrl == null ? "사진등록" : "사진변경",
                    isActive: true, onTap: _pickAndUploadImage,
                  ),
              ]
            ],
          ),
          actions: [
            if (!_isPrintMode)
              _buildLargeToolbarButton(
                icon: Icons.print,
                label: "인쇄 설정",
                isActive: _imageUrl != null,
                onTap: _imageUrl == null ? null : () {
                  // 인쇄 모드 진입 시 이미지 정보가 없으면 로드
                  if (_loadedImageInfo == null && _imageUrl != null) {
                    _fetchImageInfo(_imageUrl!);
                  }
                  setState(() {
                    _isPrintMode = true;
                    _resetPrintRect();
                  });
                },
              ),
            if (!_isPrintMode && !isMobileVersion && canEdit)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: ElevatedButton.icon(
                  onPressed: _imageUrl == null ? null : _saveMapData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676), foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  icon: const Icon(Icons.save, size: 24), label: const Text("저장"),
                ),
              ),
          ],
        ),
      ),
      body: Row(
        children: [
          Expanded(
            child: Container(
              color: const Color(0xFF21262D),
              child: Center(
                // [핵심 변경 사항] 인쇄 모드일 때만 '원본 비율(AspectRatio)'을 적용합니다.
                // 이렇게 하면 인쇄 모드에서는 이미지가 찌그러지지 않고 원본 비율대로 표시됩니다.
                child: _isPrintMode && _loadedImageInfo != null
                    ? AspectRatio(
                  aspectRatio: _loadedImageInfo!.width / _loadedImageInfo!.height,
                  child: _buildEditorContent(), // 공통 컨텐츠 위젯 호출
                )
                    : _buildEditorContent(), // 일반 모드에서는 그냥 꽉 채움
              ),
            ),
          ),
          if (_isSidebarVisible && !isMobileVersion && !_isPrintMode)
            Container(
              width: 320, decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: Colors.black12))),
              child: _buildTagSideBar(),
            ),
        ],
      ),
    );
  }

  // [신규] 에디터 메인 컨텐츠 (LayoutBuilder 분리)
  // AspectRatio 안에서도 정상 작동하도록 분리하였습니다.
  Widget _buildEditorContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanStart: (!_isPrintMode && widget.user.role.toUpperCase() == "ADMIN") ? (d) => setState(() => _startPos = d.localPosition) : null,
          onPanUpdate: (!_isPrintMode && widget.user.role.toUpperCase() == "ADMIN") ? (d) => setState(() => _currentPos = d.localPosition) : null,
          onPanEnd: (!_isPrintMode && widget.user.role.toUpperCase() == "ADMIN") ? (d) => _handleMappingEnd() : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. 이미지 레이어
              if (_imageUrl != null)
                Positioned.fill(
                  child: Image.network(
                    _imageUrl!, key: _imageKey,
                    // [중요] 인쇄 모드에선 contain(비율유지), 일반 모드에선 fill(꽉채움)
                    fit: _isPrintMode ? BoxFit.contain : BoxFit.fill,
                    loadingBuilder: (context, child, p) => p == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                )
              else
                _buildEmptyState(),

              // 2. 태그 레이어 (인쇄 모드에서도 보이도록 수정됨)
              ..._buildTagWidgets(constraints),

              // 3. 인쇄 영역 오버레이 (인쇄 모드일 때만)
              if (_isPrintMode && _imageUrl != null)
                _buildPrintOverlay(constraints),

              // 4. 드래그 박스
              if (!_isPrintMode && _startPos != null && _currentPos != null) _buildDragBox(),

              if (_isUploading) const Center(child: CircularProgressIndicator(color: Colors.white)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrintModeToolbar() {
    return Row(
      children: [
        const Icon(Icons.print_outlined, color: Colors.greenAccent),
        const SizedBox(width: 10),
        const Text("인쇄 영역 설정", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
        const SizedBox(width: 30),
        DropdownButton<PdfPageFormat>(
          value: _selectedFormat,
          dropdownColor: Colors.grey[800],
          style: const TextStyle(color: Colors.white),
          underline: Container(),
          items: [
            DropdownMenuItem(value: PdfPageFormat.a3.landscape, child: const Text("A3 가로 (420x297)")),
            DropdownMenuItem(value: PdfPageFormat.a3.portrait, child: const Text("A3 세로 (297x420)")),
            DropdownMenuItem(value: PdfPageFormat.a4.landscape, child: const Text("A4 가로 (297x210)")),
            DropdownMenuItem(value: PdfPageFormat.a4.portrait, child: const Text("A4 세로 (210x297)")),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedFormat = val);
              _resetPrintRect();
            }
          },
        ),
        const SizedBox(width: 20),
        const Icon(Icons.zoom_out, size: 20, color: Colors.white54),
        SizedBox(
          width: 150,
          child: Slider(
            // [수정] 줌 범위 0.5 ~ 5.0 (0.5 = 2배 줌아웃 = 박스 커짐)
            value: _zoomLevel, min: 0.5, max: 5.0,
            activeColor: Colors.greenAccent, inactiveColor: Colors.white24,
            onChanged: _updatePrintRectZoom,
          ),
        ),
        const Icon(Icons.zoom_in, size: 20, color: Colors.white54),
        const SizedBox(width: 20),
        ElevatedButton.icon(
          onPressed: _printClippedMap,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
          icon: const Icon(Icons.print), label: const Text("현재 영역 인쇄"),
        )
      ],
    );
  }

  // [중요 수정] Overlay를 Align 대신 Positioned로 구현하여 좌표 오차 해결
  Widget _buildPrintOverlay(BoxConstraints constraints) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        setState(() {
          double dx = details.delta.dx / constraints.maxWidth;
          double dy = details.delta.dy / constraints.maxHeight;

          double newCx = _printRect.center.dx + dx;
          double newCy = _printRect.center.dy + dy;
          double w = _printRect.width;
          double h = _printRect.height;

          // 이동 제한 로직
          if (w < 1.0) {
            newCx = newCx.clamp(w / 2, 1.0 - w / 2);
          } else {
            newCx = 0.5; // 박스가 화면보다 크면 중앙 고정 (이동 불가)
          }

          if (h < 1.0) {
            newCy = newCy.clamp(h / 2, 1.0 - h / 2);
          } else {
            newCy = 0.5;
          }

          _printRect = Rect.fromCenter(center: Offset(newCx, newCy), width: w, height: h);
        });
      },
      child: Stack(
        children: [
          // 배경 마스크
          ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.6), BlendMode.srcOut),
            child: Stack(
              children: [
                Container(decoration: const BoxDecoration(color: Colors.transparent)),
                // [수정] Positioned 사용
                Positioned(
                  left: _printRect.left * constraints.maxWidth,
                  top: _printRect.top * constraints.maxHeight,
                  width: _printRect.width * constraints.maxWidth,
                  height: _printRect.height * constraints.maxHeight,
                  child: Container(decoration: const BoxDecoration(color: Colors.black, borderRadius: BorderRadius.zero)),
                ),
              ],
            ),
          ),

          // 선택 영역 테두리 (초록색)
          Positioned(
            left: _printRect.left * constraints.maxWidth,
            top: _printRect.top * constraints.maxHeight,
            width: _printRect.width * constraints.maxWidth,
            height: _printRect.height * constraints.maxHeight,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 3),
                color: Colors.greenAccent.withOpacity(0.1),
              ),
              child: Center(
                child: Icon(Icons.drag_indicator, color: Colors.greenAccent.withOpacity(0.5), size: 48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printClippedMap() async {
    if (_imageUrl == null) return;
    try {
      final doc = pw.Document();
      final response = await http.get(Uri.parse(_imageUrl!));
      final image = pw.MemoryImage(response.bodyBytes);

      const double marginSize = 28.35;
      final format = _selectedFormat;

      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(marginSize),
          build: (pw.Context context) {
            final double availW = format.width - (marginSize * 2);
            final double availH = format.height - (marginSize * 2);

            return pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.ClipRect(
                    child: pw.Transform(
                      transform: Matrix4.identity()
                        ..translate(-_printRect.left * availW * (1/_printRect.width), -_printRect.top * availH * (1/_printRect.height))
                        ..scale(1 / _printRect.width, 1 / _printRect.height),
                      child: pw.Image(image, fit: pw.BoxFit.fill, width: availW, height: availH),
                    ),
                  ),
                ),
                ..._tempTags.where((tag) {
                  double cx = tag.dx + tag.width / 2;
                  double cy = tag.dy + tag.height / 2;
                  return _printRect.contains(Offset(cx, cy));
                }).expand((tag) {
                  final double relativeX = (tag.dx - _printRect.left) / _printRect.width;
                  final double relativeY = (tag.dy - _printRect.top) / _printRect.height;
                  final double relativeW = tag.width / _printRect.width;
                  final double relativeH = tag.height / _printRect.height;

                  final double left = relativeX * availW;
                  final double top = relativeY * availH;
                  final double width = relativeW * availW;
                  final double height = relativeH * availH;

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
                        child: pw.BarcodeWidget(barcode: Barcode.qrCode(), data: tag.guideId, drawText: false),
                      ),
                    ),
                  ];
                }).toList(),
              ],
            );
          },
        ),
      );
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
    } catch (e) {
      debugPrint("프린트 실패: $e");
    }
  }

  Widget _buildLargeToolbarButton({required IconData icon, required String label, required bool isActive, required VoidCallback? onTap}) {
    final Color color = isActive ? Colors.white : Colors.white54;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap, borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [Icon(icon, size: 24, color: color), const SizedBox(width: 8), Text(label, style: TextStyle(fontSize: 15, color: color, fontWeight: isActive ? FontWeight.bold : FontWeight.normal))]),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarDivider() => Container(width: 1, height: 32, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8));

  Widget _buildEmptyState() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate_outlined, size: 80, color: Colors.white24), const SizedBox(height: 20), const Text("상단의 [사진등록] 버튼을 눌러\n도면 이미지를 불러오세요.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 16))]);

  Widget _buildTagSideBar() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.grey[50], border: const Border(bottom: BorderSide(color: Colors.black12))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("기본 정보 설정", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: "현장 명칭 (Map Title)", border: OutlineInputBorder(), filled: true, fillColor: Colors.white, prefixIcon: Icon(Icons.title))),
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.withOpacity(0.2))), child: const Row(children: [Icon(Icons.info_outline, size: 16, color: Colors.blue), SizedBox(width: 8), Expanded(child: Text("상위 맵 연결 및 계층 구조는 '맵 리스트' 화면에서 선을 연결하여 설정하세요.", style: TextStyle(fontSize: 12, color: Colors.blueGrey)))]))
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [const Icon(Icons.qr_code_scanner, size: 20, color: Color(0xFF1A237E)), const SizedBox(width: 8), Text("등록된 구역 (${_tempTags.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]), if (_tempTags.isNotEmpty) TextButton.icon(onPressed: () => setState(() => _tempTags.clear()), icon: const Icon(Icons.delete_sweep, size: 16), label: const Text("전체 삭제"), style: TextButton.styleFrom(foregroundColor: Colors.red))])),
        const Divider(height: 1),
        Expanded(
          child: _tempTags.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.crop_free, size: 48, color: Colors.grey[300]), const SizedBox(height: 16), Text("이미지 위를 드래그하여\n장비 구역을 추가하세요.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[400]))]))
              : ListView.separated(padding: const EdgeInsets.all(10), itemCount: _tempTags.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, index) => Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))]), child: ListTile(dense: true, leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.yellow.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: Colors.yellow[700]!)), child: Text("${index + 1}", style: TextStyle(color: Colors.yellow[900], fontWeight: FontWeight.bold))), title: Text(_tempTags[index].label, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text("ID: ${_tempTags[index].guideId}", style: const TextStyle(fontSize: 11)), trailing: IconButton(icon: const Icon(Icons.close, color: Colors.grey, size: 18), onPressed: () => setState(() => _tempTags.removeAt(index)))))),
        ),
      ],
    );
  }

  Future<void> _saveMapData() async {
    if (_imageUrl == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("현장 지도 사진을 먼저 등록해주세요."))); return; }
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      final Map<String, dynamic> mapData = {
        'title': _titleController.text, 'imageUrl': _imageUrl, 'tags': _tempTags.map((t) => t.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(), 'depth': widget.mapId != null ? _savedDepth : 0,
      };
      if (widget.mapId != null) { await FirebaseFirestore.instance.collection('guide_maps').doc(widget.mapId).update(mapData); }
      else { mapData['createdAt'] = FieldValue.serverTimestamp(); mapData['authorName'] = widget.user.name; mapData['authorId'] = widget.user.userId; mapData['parentIds'] = []; await FirebaseFirestore.instance.collection('guide_maps').add(mapData); }
      if (mounted) { Navigator.pop(context); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("성공적으로 저장되었습니다."))); }
    } catch (e) { if (mounted) Navigator.pop(context); debugPrint("저장 에러: $e"); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("저장 실패: $e"))); }
  }

  List<Widget> _buildTagWidgets(BoxConstraints constraints) {
    if (_imageUrl == null) return [];
    return _tempTags.map((tag) => Positioned(left: (tag.dx * constraints.maxWidth), top: (tag.dy * constraints.maxHeight), child: _buildTagIcon(tag, Size(constraints.maxWidth, constraints.maxHeight)))).toList();
  }

  Widget _buildTagIcon(MapTag tag, Size size) {
    double iconSize = (size.width * 0.05).clamp(20.0, 45.0);
    return GestureDetector(
      onTap: () => _showGuideListDialog(tag),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(width: tag.width * size.width, height: tag.height * size.height, decoration: BoxDecoration(color: Colors.yellow.withOpacity(0.2), border: Border.all(color: Colors.yellow, width: 2))),
        Positioned(top: -(iconSize / 2), right: -(iconSize / 2), child: Container(width: iconSize, height: iconSize, decoration: const BoxDecoration(color: Color(0xFF1A237E), shape: BoxShape.circle), child: Icon(Icons.qr_code_2, color: Colors.white, size: iconSize * 0.6))),
        if (_showLabel) Positioned(top: (tag.height * size.height) + 2, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), color: Colors.black87, child: Text(tag.label, style: const TextStyle(color: Colors.white, fontSize: 10)))),
      ]),
    );
  }

  void _showGuideListDialog(MapTag tag) {
    showDialog(context: context, builder: (context) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), backgroundColor: const Color(0xFFF5F5F5), titlePadding: EdgeInsets.zero, title: Container(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20), decoration: const BoxDecoration(color: Color(0xFF1A237E), borderRadius: BorderRadius.vertical(top: Radius.circular(16))), child: Row(children: [const Icon(Icons.list_alt, color: Colors.white), const SizedBox(width: 10), Text("${tag.label} 가이드", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))])), content: SizedBox(width: 400, child: StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('guides').where('id', isEqualTo: tag.guideId).snapshots(), builder: (context, snapshot) { if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())); if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox(height: 100, child: Center(child: Text("등록된 가이드가 없습니다.", style: TextStyle(color: Colors.grey)))); return ListView.separated(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 10), itemCount: snapshot.data!.docs.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (context, index) { final doc = snapshot.data!.docs[index]; final guideData = Guide.fromFirestore(doc.data() as Map<String, dynamic>); return InkWell(onTap: () async { Navigator.pop(context); await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]); if (!mounted) return; await Navigator.push(context, MaterialPageRoute(builder: (context) => GuideDetailPage(guide: guideData))); await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]); }, child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))]), child: Row(children: [const Icon(Icons.menu_book, color: Color(0xFF1A237E), size: 28), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(guideData.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), const SizedBox(height: 4), Text(guideData.date, style: TextStyle(color: Colors.grey[600], fontSize: 12))])), const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey)]))); }); })), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("닫기", style: TextStyle(color: Color(0xFF1A237E))))]));
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
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text("장비 영역 가이드 연결"), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(onChanged: (v) => label = v, decoration: const InputDecoration(labelText: "장비 명칭", border: OutlineInputBorder())), const SizedBox(height: 16), TextField(onChanged: (v) => guideId = v, decoration: const InputDecoration(labelText: "장비 ID", border: OutlineInputBorder()))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")), ElevatedButton(onPressed: () { if (label.isNotEmpty && guideId.isNotEmpty) { setState(() { _tempTags.add(MapTag(guideId: guideId, dx: left, dy: top, width: width, height: height, label: label)); }); Navigator.pop(context); } }, child: const Text("추가"))]));
  }

  Widget _buildDragBox() {
    if (_startPos == null || _currentPos == null) return const SizedBox.shrink();
    return Positioned(left: _startPos!.dx < _currentPos!.dx ? _startPos!.dx : _currentPos!.dx, top: _startPos!.dy < _currentPos!.dy ? _startPos!.dy : _currentPos!.dy, child: Container(width: (_currentPos!.dx - _startPos!.dx).abs(), height: (_currentPos!.dy - _startPos!.dy).abs(), decoration: BoxDecoration(border: Border.all(color: Colors.blueAccent, width: 2), color: Colors.blueAccent.withOpacity(0.1))));
  }

  void _printMap() => _printClippedMap();
}