import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guide_model.dart';
import '../models/user_model.dart';

// -----------------------------------------------------------
// [리디자인] 4-2. 에디터 페이지 (섹션 구분형 폼 위자드)
// -----------------------------------------------------------
class EditorPage extends StatefulWidget {
  final Guide? guide;
  final UserModel? user;
  final String? firestoreDocId;

  const EditorPage({super.key, this.guide, this.user, this.firestoreDocId});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _idController = TextEditingController();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _partsController = TextEditingController();
  final _specController = TextEditingController();
  final _relationController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  List<dynamic> _displayImages = [];
  bool _isAnonymous = false;
  bool _isAdminDirectPublish = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.guide != null) {
      _idController.text = widget.guide!.id;
      _titleController.text = widget.guide!.title;
      _contentController.text = widget.guide!.content;
      _displayImages = List.from(widget.guide!.imageUrls);
      _isAnonymous = widget.guide!.isAnonymous;
      _partsController.text = widget.guide!.partsInfo;
      _specController.text = widget.guide!.specInfo;
      _relationController.text = widget.guide!.relationInfo;
    }
    // 관리자가 아니면 직접 게시 옵션 끔
    if (widget.user?.role != 'ADMIN') {
      _isAdminDirectPublish = false;
    }
  }

  Future<void> _pickImages() async {
    final List<XFile> pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles.isEmpty) return;
    setState(() => _displayImages.addAll(pickedFiles));
  }

  void _removeImage(int index) {
    setState(() => _displayImages.removeAt(index));
  }

  Future<List<String>> _uploadImages() async {
    List<String> finalUrls = [];
    for (var item in _displayImages) {
      if (item is String) {
        finalUrls.add(item);
        continue;
      }
      if (item is XFile) {
        try {
          String fileName = item.name;
          String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
          var ref = FirebaseStorage.instance.ref().child('guides/${_idController.text}/${timestamp}_$fileName');

          if (kIsWeb) {
            Uint8List fileBytes = await item.readAsBytes();
            await ref.putData(fileBytes, SettableMetadata(contentType: item.mimeType));
          } else {
            await ref.putFile(File(item.path));
          }
          finalUrls.add(await ref.getDownloadURL());
        } catch (e) {
          print(e);
        }
      }
    }
    return finalUrls;
  }

  Future<void> _submitData() async {
    final bool isAdmin = widget.user?.role == 'ADMIN';
    if (_idController.text.isEmpty || _titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("장비 ID와 제목은 필수입니다.")));
      return;
    }

    setState(() => _isLoading = true);
    // showLoadingDialog(context, "데이터 저장 중..."); // 커스텀 로딩창 대신 로컬 상태 사용

    try {
      List<String> uploadedUrls = await _uploadImages();
      String status = (isAdmin && _isAdminDirectPublish) ? 'approved' : 'pending';
      String docId = widget.firestoreDocId ?? '${_idController.text}_${DateTime.now().millisecondsSinceEpoch}';

      String targetCompanyId = widget.guide?.companyId ?? widget.user?.facilityId ?? "KOGAS_WANJU";
      String nowStr = DateTime.now().toString().substring(0, 19);
      String createdAt = widget.guide?.createdAt ?? nowStr;

      final newGuide = Guide(
        id: _idController.text,
        companyId: targetCompanyId,
        title: _titleController.text,
        content: _contentController.text,
        date: DateTime.now().toString().substring(0, 10),
        imageUrls: uploadedUrls,
        originalTitle: widget.guide?.originalTitle ?? _titleController.text,
        originalContent: widget.guide?.originalContent ?? _contentController.text,
        proposerName: widget.guide?.proposerName ?? widget.user?.name ?? '익명',
        isAnonymous: _isAnonymous,
        status: status,
        partsInfo: _partsController.text,
        specInfo: _specController.text,
        relationInfo: _relationController.text,
        createdAt: createdAt,
        updatedAt: nowStr,
      );

      await FirebaseFirestore.instance.collection('guides').doc(docId).set(newGuide.toFirestore());

      // [신규 로직] 가이드 저장 성공 시 정비 로그를 자동으로 생성합니다.
      String logType = widget.guide == null ? 'CHECK' : 'REPAIR'; // 신규 작성은 점검, 수정은 수리로 분류
      String logTitle = widget.guide == null
          ? "${_idController.text} 신규 가이드 등록"
          : "${_idController.text} 가이드 내용 업데이트";

      await FirebaseFirestore.instance.collection('maintenance_logs').add({
        'type': logType,
        'title': logTitle,
        'userName': widget.user?.name ?? '익명 작업자',
        'date': FieldValue.serverTimestamp(), // 서버 시간 기준 저장
      });

      if (mounted) {
        // Navigator.pop(context); // 로딩창 닫기 (로컬 상태라 불필요)
        Navigator.pop(context); // 페이지 닫기
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'approved' ? "게시가 완료되었습니다." : "제안이 등록되었습니다. 관리자 승인을 기다리세요."),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      // if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("저장 오류: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = widget.user?.role == 'ADMIN';
    final bool isReviewMode = (isAdmin && widget.guide?.status == 'pending');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.guide == null ? "새 가이드 작성" : "가이드 수정"),
        actions: [
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
          else
            TextButton(
              onPressed: _submitData,
              child: const Text("저장", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                if (isReviewMode) ...[
                  _buildReviewAlert(),
                  const SizedBox(height: 16),
                ],

                // 1. 기본 정보 섹션
                _buildSection(
                  title: "기본 정보",
                  children: [
                    _buildTextField("장비 ID (필수)", _idController, icon: Icons.qr_code, enabled: !isReviewMode),
                    const SizedBox(height: 16),
                    _buildTextField("제목 / 증상 (필수)", _titleController, icon: Icons.title),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: const Text("익명으로 제안"),
                      value: _isAnonymous,
                      onChanged: (v) => setState(() => _isAnonymous = v!),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. 기술 정보 섹션
                _buildSection(
                  title: "엔지니어링 데이터 (선택)",
                  children: [
                    _buildTextField("필요 부품/자재", _partsController, icon: Icons.settings_input_component),
                    const SizedBox(height: 16),
                    _buildTextField("정상 운전 범위", _specController, icon: Icons.speed),
                    const SizedBox(height: 16),
                    _buildTextField("상관관계 로직", _relationController, icon: Icons.compare_arrows, maxLines: 3),
                  ],
                ),
                const SizedBox(height: 16),

                // 3. 사진 섹션
                _buildSection(
                  title: "현장 사진",
                  children: [
                    _buildPhotoArea(),
                  ],
                ),
                const SizedBox(height: 16),

                // 4. 내용 섹션
                _buildSection(
                  title: "조치 방법 (상세)",
                  children: [
                    TextField(
                      controller: _contentController,
                      minLines: 10,
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: "1. 작업 준비...\n2. 분해 절차...\n3. 교체 및 테스트...",
                        alignLabelWithHint: true,
                        border: InputBorder.none, // 컨테이너가 테두리 역할
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // 관리자 옵션
                if (isAdmin)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: CheckboxListTile(
                      title: const Text("관리자 권한으로 즉시 승인(게시)"),
                      value: _isAdminDirectPublish,
                      onChanged: (v) => setState(() => _isAdminDirectPublish = v!),
                    ),
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl, {IconData? icon, int maxLines = 1, bool enabled = true}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon) : null,
        // Theme에서 정의한 border 스타일 따름
      ),
    );
  }

  Widget _buildPhotoArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _displayImages.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return GestureDetector(
                  onTap: _pickImages,
                  child: Container(
                    width: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                    ),
                    child: const Icon(Icons.add_a_photo, color: Colors.grey),
                  ),
                );
              }
              final imageIndex = index - 1;
              final item = _displayImages[imageIndex];
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 100, height: 100,
                      child: _buildImageWidget(item),
                    ),
                  ),
                  Positioned(
                    top: 4, right: 4,
                    child: GestureDetector(
                      onTap: () => _removeImage(imageIndex),
                      child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildImageWidget(dynamic item) {
    if (item is String) return Image.network(item, fit: BoxFit.cover);
    if (item is XFile) {
      if (kIsWeb) return Image.network(item.path, fit: BoxFit.cover);
      return Image.file(File(item.path), fit: BoxFit.cover);
    }
    return const Icon(Icons.error);
  }

  Widget _buildReviewAlert() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: const [
          Icon(Icons.assignment_late, color: Colors.orange),
          SizedBox(width: 12),
          Expanded(child: Text("현재 이 가이드는 승인 대기 중입니다. 내용을 검토하고 '저장'을 누르면 승인 처리됩니다.")),
        ],
      ),
    );
  }
}
