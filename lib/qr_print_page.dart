import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class QrPrintPage extends StatefulWidget {
  const QrPrintPage({super.key});

  @override
  State<QrPrintPage> createState() => _QrPrintPageState();
}

class _QrPrintPageState extends State<QrPrintPage> {
  final List<TextEditingController> _controllers = [TextEditingController()];
  final List<FocusNode> _focusNodes = [FocusNode()];

  @override
  void dispose() {
    for (var c in _controllers) c.dispose();
    for (var f in _focusNodes) f.dispose();
    super.dispose();
  }

  void _addNewField() {
    setState(() {
      _controllers.add(TextEditingController());
      _focusNodes.add(FocusNode());
    });
    // 프레임 렌더링 후 마지막 필드로 포커스 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focusNodes.isNotEmpty) {
        _focusNodes.last.requestFocus();
      }
    });
  }

  void _removeField(int index) {
    if (_controllers.length > 1) {
      setState(() {
        _controllers[index].dispose();
        _controllers.removeAt(index);
        _focusNodes[index].dispose();
        _focusNodes.removeAt(index);
      });
      // 삭제 후 포커스 이동 안전장치
      if (index > 0 && index - 1 < _focusNodes.length) {
        _focusNodes[index - 1].requestFocus();
      } else if (_focusNodes.isNotEmpty) {
        _focusNodes.first.requestFocus();
      }
    }
  }

  // [팝업] 범위 입력 다이얼로그
  void _showRangeDialog() {
    final prefixController = TextEditingController();
    final startController = TextEditingController();
    final endController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("범위로 일괄 추가"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: prefixController,
              decoration: const InputDecoration(
                labelText: "접두어 (예: PT)",
                hintText: "비워두면 숫자만 생성",
              ),
              autofocus: true, // 팝업 열리면 여기로 포커스
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: startController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "시작 번호 (예: 1)"),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text("~", style: TextStyle(fontSize: 20)),
                ),
                Expanded(
                  child: TextField(
                    controller: endController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "종료 번호 (예: 10)"),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              "* 시작 번호의 자릿수(001 등)에 맞춰 자동으로 생성됩니다.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("취소"),
          ),
          ElevatedButton(
            onPressed: () {
              if (startController.text.isNotEmpty && endController.text.isNotEmpty) {
                _generateRangeItems(
                  prefixController.text,
                  startController.text,
                  endController.text,
                );
                Navigator.pop(context);
              }
            },
            child: const Text("일괄 추가"),
          ),
        ],
      ),
    );
  }

  // [로직] 범위 생성
  void _generateRangeItems(String prefix, String startStr, String endStr) {
    int start = int.parse(startStr);
    int end = int.parse(endStr);

    if (start > end) return;

    int padLength = startStr.length;

    setState(() {
      if (_controllers.length == 1 && _controllers[0].text.isEmpty) {
        _controllers.clear();
        _focusNodes.clear();
      }

      for (int i = start; i <= end; i++) {
        String numberPart = i.toString().padLeft(padLength, '0');
        String fullText = "$prefix$numberPart";

        _controllers.add(TextEditingController(text: fullText));
        _focusNodes.add(FocusNode());
      }
      _addNewField(); // 편의상 빈 칸 하나 추가
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("QR 라벨 생성기"),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: "범위로 추가",
            onPressed: _showRangeDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. 상단 범위 입력 버튼
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: _showRangeDialog,
              icon: const Icon(Icons.library_add),
              label: const Text("범위 입력 모드 (PT 2201 ~ 2213)"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 45),
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
              ),
            ),
          ),

          // 2. 메인 리스트 (입력란)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: _controllers.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Focus(
                          onKeyEvent: (FocusNode node, KeyEvent event) {
                            if (event is KeyDownEvent) {
                              // [1] 탭(Tab) 키 로직: 마지막 칸에서 탭을 누르면 새 칸 추가
                              if (event.logicalKey == LogicalKeyboardKey.tab) {
                                // 마지막 항목일 때만 작동
                                if (index == _controllers.length - 1) {
                                  _addNewField(); // 새 칸 추가 (자동으로 포커스 이동됨)
                                  return KeyEventResult.handled; // 원래 탭 동작(버튼 이동 등) 막음
                                }
                              }

                              // [2] 삭제(Delete) 키 로직: 비어있으면 삭제
                              if (event.logicalKey == LogicalKeyboardKey.delete &&
                                  _controllers[index].text.isEmpty) {
                                _removeField(index);
                                return KeyEventResult.handled;
                              }
                            }
                            return KeyEventResult.ignored; // 다른 키는 통과
                          },
                          child: TextField(
                            controller: _controllers[index],
                            focusNode: _focusNodes[index],
                            decoration: InputDecoration(
                              labelText: "${index + 1}. 장비 ID",
                              border: const OutlineInputBorder(),
                              // [중요] X 버튼이 탭 포커스를 가져가지 않도록 설정
                              suffixIcon: IconButton(
                                focusNode: FocusNode(skipTraversal: true), // 탭 이동 시 무시됨
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () => _controllers[index].clear(),
                              ),
                            ),
                            // 엔터 키 동작
                            textInputAction: index == _controllers.length - 1
                                ? TextInputAction.done
                                : TextInputAction.next,
                            onSubmitted: (_) {
                              // 엔터 쳐도 추가되게 하려면 주석 해제
                              // _addNewField();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        // 삭제 버튼도 탭 이동에서 제외 (선택 사항)
                        focusNode: FocusNode(skipTraversal: true),
                        onPressed: () => _removeField(index),
                        icon: const Icon(Icons.remove_circle, color: Colors.red),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // 3. 하단 고정 버튼 영역 (PDF 생성 + 수동 추가 버튼)
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  blurRadius: 5,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              children: [
                // [신규 기능] 수동 추가 버튼 (키보드가 안 먹힐 때 대비)
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: OutlinedButton.icon(
                    onPressed: _addNewField,
                    icon: const Icon(Icons.add),
                    label: const Text("입력란 추가하기"),
                  ),
                ),
                const SizedBox(height: 10),
                // PDF 생성 버튼
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed: _generatePdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text("QR PDF 생성 (Level H)"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[900],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfButton() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton.icon(
          onPressed: _generatePdf,
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text("QR PDF 생성 (Level H)"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[900],
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _generatePdf() async {
    final pdf = pw.Document();
    final ByteData logoData = await rootBundle.load('assets/images/logo.png');
    final Uint8List logoBytes = logoData.buffer.asUint8List();
    final pw.MemoryImage logoImage = pw.MemoryImage(logoBytes);

    const double sizeInCm = 1.2;
    const double dotSize = sizeInCm * 28.3465;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            pw.Wrap(
              spacing: 15,
              runSpacing: 15,
              children: _controllers.where((c) => c.text.isNotEmpty).map((controller) {
                return pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Stack(
                      alignment: pw.Alignment.center,
                      children: [
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(
                            errorCorrectLevel: pw.BarcodeQRCorrectionLevel.high,
                          ),
                          data: controller.text,
                          width: dotSize,
                          height: dotSize,
                          drawText: false,
                        ),
                        pw.Container(
                          width: dotSize * 0.18,
                          height: dotSize * 0.18,
                          decoration: const pw.BoxDecoration(color: PdfColors.white),
                          padding: const pw.EdgeInsets.all(0.5),
                          child: pw.Image(logoImage),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      controller.text,
                      style: pw.TextStyle(fontSize: 3.5, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                );
              }).toList(),
            )
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }
}