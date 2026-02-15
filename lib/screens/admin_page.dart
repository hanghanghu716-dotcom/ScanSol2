import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guide_model.dart';
import '../models/user_model.dart';
import 'editor_page.dart';
import 'admin_user_page.dart';
// QR 인쇄 페이지는 별도로 존재하므로 경로를 맞춰주세요.
import '../qr_print_page.dart';

// -----------------------------------------------------------
// [리디자인] 5-1. 관리자 메인 페이지 (데이터 시각화 및 카드 리스트)
// -----------------------------------------------------------
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  // 관리자용 더미 유저 데이터 (작성 시 사용)
  final UserModel adminUser = UserModel(
    docId: 'admin',
    facilityId: 'KOGAS',
    userId: 'admin',
    password: '',
    role: 'ADMIN',
    name: '관리자',
    department: '본사',
    status: 'approved',
  );

  // 가이드 삭제 (Soft Delete) - 휴지통 이동
  void _moveToTrash(String docId, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.delete_sweep, color: Colors.red),
            SizedBox(width: 10),
            Text("휴지통 이동"),
          ],
        ),
        content: Text("'$title' 매뉴얼을 게시 중단하고 휴지통으로 이동하시겠습니까?\n(데이터는 완전히 삭제되지 않습니다.)"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          ElevatedButton(
            onPressed: () async {
              String nowStr = DateTime.now().toString().substring(0, 19);
              await FirebaseFirestore.instance.collection('guides').doc(docId).update({
                'status': 'rejected',
                'updatedAt': nowStr,
              });
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("휴지통으로 이동되었습니다.")));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("이동"),
          ),
        ],
      ),
    );
  }

  // 가이드 완전 삭제 (Hard Delete) - 휴지통에서 영구 삭제
  void _deletePermanently(String docId, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("영구 삭제"),
        content: Text("'$title'을(를) 영구히 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('guides').doc(docId).delete();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("영구 삭제되었습니다.")));
              }
            },
            child: const Text("삭제", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 가이드 복구 (Rejected -> Approved)
  void _restoreGuide(String docId, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("매뉴얼 복구"),
        content: Text("'$title'을(를) 다시 게시하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          ElevatedButton(
            onPressed: () async {
              String nowStr = DateTime.now().toString().substring(0, 19);
              await FirebaseFirestore.instance.collection('guides').doc(docId).update({
                'status': 'approved',
                'updatedAt': nowStr,
              });
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("정상적으로 복구(게시)되었습니다.")));
              }
            },
            child: const Text("복구"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text("관리자 대시보드"),
          centerTitle: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.manage_accounts),
              tooltip: "직원 관리",
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminUserPage())),
            ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            indicatorColor: Theme.of(context).colorScheme.secondary,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: "승인 대기", icon: Icon(Icons.assignment_late_outlined)),
              Tab(text: "게시됨", icon: Icon(Icons.assignment_turned_in_outlined)),
              Tab(text: "휴지통", icon: Icon(Icons.delete_outline)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildGuideList(status: 'pending'),
            _buildGuideList(status: 'approved'),
            _buildGuideList(status: 'rejected'),
          ],
        ),
// [수정] 관리자 페이지 하단 플로팅 버튼 (QR 인쇄 버튼 가시성 강화)
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end, // 오른쪽 정렬
          children: [
            // 1. QR 라벨 인쇄 버튼 (원형 -> 텍스트가 있는 알약형으로 변경)
            FloatingActionButton.extended(
              heroTag: 'fab_qr',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const QrPrintPage())),
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1A237E), // 네이비색 텍스트
              elevation: 4,
              icon: const Icon(Icons.qr_code_2), // QR 코드 아이콘으로 변경하여 의미 명확화
              label: const Text("QR 라벨 인쇄", style: TextStyle(fontWeight: FontWeight.bold)),
            ),

            const SizedBox(height: 16),

            // 2. 새 매뉴얼 작성 버튼
            FloatingActionButton.extended(
              heroTag: 'fab_new',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditorPage(user: adminUser))),
              backgroundColor: const Color(0xFF1A237E), // 네이비색 배경
              foregroundColor: Colors.white, // 흰색 텍스트
              elevation: 4,
              icon: const Icon(Icons.edit),
              label: const Text("새 매뉴얼 작성", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

// AdminPage 클래스 내부의 함수
  Widget _buildGuideList({required String status}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('guides')
          .where('status', isEqualTo: status)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  status == 'pending' ? "대기 중인 제안이 없습니다." :
                  status == 'approved' ? "게시된 매뉴얼이 없습니다." : "휴지통이 비었습니다.",
                  style: TextStyle(color: Colors.grey[500], fontSize: 16),
                ),
              ],
            ),
          );
        }

        final guides = docs.map((doc) => Guide.fromFirestore(doc.data() as Map<String, dynamic>)).toList();

        // [핵심 수정] Align과 ConstrainedBox를 사용하여 웹에서 너무 퍼지는 것을 방지
        return Align(
          alignment: Alignment.topCenter, // 상단 중앙 정렬
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1000), // UserPage와 동일하게 최대 너비 1000px 제한
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: guides.length,
              itemBuilder: (context, index) {
                final guide = guides[index];
                final docId = docs[index].id;
                return _buildAdminGuideCard(guide, docId, status);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildAdminGuideCard(Guide guide, String docId, String status) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'pending':
        statusColor = Colors.orange;
        statusText = "승인 대기";
        statusIcon = Icons.priority_high;
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusText = "게시 중단";
        statusIcon = Icons.block;
        break;
      default:
        statusColor = Colors.green;
        statusText = "정상 게시";
        statusIcon = Icons.check_circle;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias, // 상태 바가 카드 밖으로 나가지 않게
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditorPage(guide: guide, user: adminUser, firestoreDocId: docId),
            ),
          );
        },
        child: IntrinsicHeight(
          child: Row(
            children: [
              // 좌측 상태 컬러 바
              Container(width: 6, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(guide.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text("${guide.id} | ${guide.isAnonymous ? '익명' : guide.proposerName}", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                              ],
                            ),
                          ),
                          // 상태 배지
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: statusColor.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 12, color: statusColor),
                                const SizedBox(width: 4),
                                Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("수정: ${guide.updatedAt.split(' ')[0]}", style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                          // 액션 버튼 영역
                          if (status == 'approved')
                            TextButton.icon(
                              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                              label: const Text("휴지통", style: TextStyle(color: Colors.grey, fontSize: 12)),
                              onPressed: () => _moveToTrash(docId, guide.title),
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30)),
                            ),
                          if (status == 'rejected')
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => _restoreGuide(docId, guide.title),
                                  child: const Text("복구", style: TextStyle(fontSize: 12)),
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () => _deletePermanently(docId, guide.title),
                                  child: const Text("영구삭제", style: TextStyle(color: Colors.red, fontSize: 12)),
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(60, 30)),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}