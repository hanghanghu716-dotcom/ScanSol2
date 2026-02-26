import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guide_model.dart';
import '../models/user_model.dart';

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
    // 기존 데이터 로드
    if (widget.guide != null) {
      _idController.text = widget.guide!.id;
      _titleController.text = widget.guide!.title;
      _contentController.text = widget.guide!.content;

      // 사진 리스트 복원
      _displayImages = widget.guide!.imageUrls.isNotEmpty
          ? List.from(widget.guide!.imageUrls)
          : [];

      // 익명 제안 상태 복원
      _isAnonymous = widget.guide!.isAnonymous;

      _partsController.text = widget.guide!.partsInfo;
      _specController.text = widget.guide!.specInfo;
      _relationController.text = widget.guide!.relationInfo;
    }

    // 권한에 따른 자동 승인 옵션 설정
    if (widget.user?.role != 'ADMIN' && widget.user?.role != 'SUPER_ADMIN') {
      _isAdminDirectPublish = false;
    }
  }

  Future<void> _pickImages() async {
    final List<XFile> pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles.isEmpty) return;
    setState(() => _displayImages.addAll(pickedFiles));
  }

  void _removeImage(int index) => setState(() => _displayImages.removeAt(index));

  // 이미지 업로드 로직 개선
  Future<List<String>> _uploadImages() async {
    List<String> finalUrls = [];
    for (var item in _displayImages) {
      if (item is String) {
        // 이미 업로드된 URL인 경우 그대로 유지
        finalUrls.add(item);
        continue;
      }
      if (item is XFile) {
        try {
          String fileName = item.name;
          String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
          // 경로 설정: guides/{장비ID}/파일
          var ref = FirebaseStorage.instance.ref().child('guides/${_idController.text}/$timestamp\_$fileName');

          if (kIsWeb) {
            Uint8List fileBytes = await item.readAsBytes();
            await ref.putData(fileBytes, SettableMetadata(contentType: item.mimeType));
          } else {
            await ref.putFile(File(item.path));
          }
          String downloadUrl = await ref.getDownloadURL();
          finalUrls.add(downloadUrl);
        } catch (e) {
          debugPrint("이미지 업로드 에러: $e");
          // 업로드 실패 시 에러를 던져 전체 저장 프로세스를 중단시킵니다.
          throw '사진 업로드 중 오류가 발생했습니다. (원인: $e)';
        }
      }
    }
    return finalUrls;
  }

  Future<void> _submitData() async {
    final bool isAdmin = widget.user?.role == 'ADMIN' || widget.user?.role == 'SUPER_ADMIN';

    if (_idController.text.isEmpty || _titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("장비 ID와 제목은 필수입니다.")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final String currentFacilityId = widget.user?.facilityId ?? "";
      if (currentFacilityId.isEmpty) throw '소속 사업장 정보를 확인할 수 없습니다.';

      // 1. 요금제 한도 체크
      final facilityDoc = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(currentFacilityId)
          .get();

      if (!facilityDoc.exists) throw '사업장 정보를 찾을 수 없습니다.';
      int maxGuides = facilityDoc.data()?['maxGuides'] ?? 10;

      // 2. 현재 가이드 수 조회 (신규 등록 시에만 체크)
      if (widget.guide == null) {
        final guidesQuery = await FirebaseFirestore.instance
            .collection('guides')
            .where('facilityId', isEqualTo: currentFacilityId)
            .where('status', isEqualTo: 'approved')
            .get();

        if (guidesQuery.docs.length >= maxGuides) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("등록 한도 초과"),
                content: Text("현재 요금제 슬롯($maxGuides개)을 모두 사용하였습니다."),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인"))],
              ),
            );
          }
          setState(() => _isLoading = false);
          return;
        }
      }

      // 3. 이미지 업로드 (실패 시 catch 블록으로 이동)
      List<String> uploadedUrls = await _uploadImages();

      // 4. 데이터 빌드 및 저장
      String status = (isAdmin && _isAdminDirectPublish) ? 'approved' : 'pending';
      String docId = widget.firestoreDocId ?? '${_idController.text}_${DateTime.now().millisecondsSinceEpoch}';
      String nowStr = DateTime.now().toString().substring(0, 19);

      final Map<String, dynamic> guideData = {
        'id': _idController.text.trim(),
        'facilityId': currentFacilityId,
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'date': DateTime.now().toString().substring(0, 10),
        'imageUrls': uploadedUrls,
        'proposerName': widget.guide?.proposerName ?? widget.user?.name ?? '익명',
        'isAnonymous': _isAnonymous,
        'status': status,
        'partsInfo': _partsController.text.trim(),
        'specInfo': _specController.text.trim(),
        'relationInfo': _relationController.text.trim(),
        'createdAt': widget.guide?.createdAt ?? nowStr,
        'updatedAt': nowStr,
      };

      await FirebaseFirestore.instance.collection('guides').doc(docId).set(guideData);

      // 5. 정비 로그 기록
      await FirebaseFirestore.instance.collection('maintenance_logs').add({
        'type': widget.guide == null ? 'CHECK' : 'REPAIR',
        'title': widget.guide == null ? "[신규] ${_idController.text} 등록" : "[수정] ${_idController.text} 업데이트",
        'userName': widget.user?.name ?? '익명',
        'date': FieldValue.serverTimestamp(),
        'facilityId': currentFacilityId,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("가이드가 정상적으로 저장되었습니다."), backgroundColor: Colors.green));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("오류: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = widget.user?.role == 'ADMIN' || widget.user?.role == 'SUPER_ADMIN';
    final bool isReviewMode = (isAdmin && widget.guide?.status == 'pending');
    // 수정 또는 승인 검토 모드인지 확인
    final bool isEditOrReviewMode = widget.guide != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.guide == null ? "새 가이드 작성" : "가이드 수정"),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
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
                if (isReviewMode) ...[ _buildReviewAlert(), const SizedBox(height: 16) ],
                _buildSection(title: "기본 정보", children: [
                  _buildTextField("장비 ID (필수)", _idController, icon: Icons.qr_code, enabled: !isEditOrReviewMode),
                  const SizedBox(height: 16),
                  _buildTextField("제목 / 증상 (필수)", _titleController, icon: Icons.title),
                  const SizedBox(height: 16),
                  // 익명 체크박스: 수정/검토 모드에서는 조작 불가 처리
                  CheckboxListTile(
                    title: Text(isEditOrReviewMode ? "익명 여부 (수정 불가)" : "익명으로 제안"),
                    value: _isAnonymous,
                    onChanged: isEditOrReviewMode ? null : (v) => setState(() => _isAnonymous = v!),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: const Color(0xFF1A237E),
                  ),
                ]),
                const SizedBox(height: 16),
                _buildSection(title: "엔지니어링 데이터 (선택)", children: [
                  _buildTextField("필요 부품/자재", _partsController, icon: Icons.settings_input_component),
                  const SizedBox(height: 16),
                  _buildTextField("정상 운전 범위", _specController, icon: Icons.speed),
                  const SizedBox(height: 16),
                  _buildTextField("상관관계 로직", _relationController, icon: Icons.compare_arrows, maxLines: 3),
                ]),
                const SizedBox(height: 16),
                _buildSection(title: "현장 사진", children: [ _buildPhotoArea() ]),
                const SizedBox(height: 16),
                _buildSection(title: "조치 방법 (상세)", children: [
                  TextField(
                    controller: _contentController,
                    minLines: 10,
                    maxLines: null,
                    decoration: const InputDecoration(hintText: "1. 작업 준비...\n2. 분해 절차...", alignLabelWithHint: true, border: InputBorder.none),
                  ),
                ]),
                const SizedBox(height: 32),
                if (isAdmin)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        const SizedBox(height: 16), const Divider(), const SizedBox(height: 16), ...children,
      ]),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl, {IconData? icon, int maxLines = 1, bool enabled = true}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      enabled: enabled,
      decoration: InputDecoration(labelText: label, prefixIcon: icon != null ? Icon(icon) : null, border: const OutlineInputBorder()),
    );
  }

  Widget _buildPhotoArea() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 120,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _displayImages.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            if (index == 0) {
              return GestureDetector(
                onTap: _pickImages,
                child: Container(width: 100, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade400)), child: const Icon(Icons.add_a_photo, color: Colors.grey)),
              );
            }
            final imageIndex = index - 1;
            final item = _displayImages[imageIndex];
            return Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 100, height: 100, child: _buildImageWidget(item))),
              Positioned(top: 4, right: 4, child: GestureDetector(onTap: () => _removeImage(imageIndex), child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)))),
            ]);
          },
        ),
      ),
    ]);
  }

  Widget _buildImageWidget(dynamic item) {
    if (item is String) return Image.network(item, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image));
    if (item is XFile) return kIsWeb ? Image.network(item.path, fit: BoxFit.cover) : Image.file(File(item.path), fit: BoxFit.cover);
    return const Icon(Icons.error);
  }

  Widget _buildReviewAlert() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange)),
      child: const Row(children: [
        Icon(Icons.assignment_late, color: Colors.orange),
        SizedBox(width: 12),
        Expanded(child: Text("현재 이 가이드는 승인 대기 중입니다. 내용을 검토하고 '저장'을 누르면 승인 처리됩니다.", style: TextStyle(fontWeight: FontWeight.bold))),
      ]),
    );
  }
}