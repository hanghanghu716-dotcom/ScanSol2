import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guide_model.dart';
import '../models/user_model.dart';
import 'editor_page.dart';
import 'admin_user_page.dart';
import '../qr_print_page.dart';
import 'map_list_page.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final TextEditingController _rateController = TextEditingController();
  String _selectedFilter = 'pending'; // 기본값: 승인 대기

  // [정석 세팅] 이미 정의되어 있는 관리자 객체를 활용합니다.
  final UserModel adminUser = UserModel(
    docId: 'admin',
    facilityId: 'KOGAS',
    userId: 'admin',
    password: '',
    role: 'ADMIN',
    name: '최고관리자',
    department: '본사',
    status: 'approved',
  );

  Future<void> _updateOperationRate() async {
    if (_rateController.text.isEmpty) return;
    await FirebaseFirestore.instance.collection('settings').doc('factory_stats').set({
      'operation_rate': int.parse(_rateController.text),
      'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("가동률이 업데이트되었습니다.")));
      _rateController.clear();
    }
  }

  // [추가] 가이드의 상태(대기/승인/삭제)를 변경하는 함수
  Future<void> _updateGuideStatus(String docId, String newStatus) async {
    try {
      // Firestore의 해당 가이드 문서에서 status 필드만 업데이트합니다.
      await FirebaseFirestore.instance.collection('guides').doc(docId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        String message = newStatus == 'deleted' ? "삭제 목록으로 이동되었습니다." : "상태가 변경되었습니다.";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      debugPrint("상태 업데이트 에러: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("업데이트에 실패했습니다.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double horizontalPadding = screenWidth > 1200 ? (screenWidth - 1000) / 2 : 16;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: const Color(0xFF1A237E),
            // [교정] 앱바의 인력관리 아이콘을 제거하고 대시보드 카드로 통합했습니다.
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.only(left: horizontalPadding, bottom: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                        child: const Text("Admin Control Center", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      const Text("관리자 관제 대시보드", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),


          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                height: 125, // 카드 높이 통일
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // 1. 전체 가이드 (Stream 데이터)
                    _buildStreamSummaryCard(
                        'guides',
                        "전체 가이드",
                        Icons.library_books,
                        Colors.blue,
                        query: FirebaseFirestore.instance.collection('guides').where('status', isEqualTo: 'approved')
                    ),
                    const SizedBox(width: 16),

                    // 2. 오늘의 로그 (Stream 데이터)
                    _buildStreamSummaryCard('maintenance_logs', "정비 이력", Icons.history, Colors.orange),
                    const SizedBox(width: 16),

                    // 3. 현재 가동률 (Stream 데이터)
                    _buildRateSummaryCard(),
                    const SizedBox(width: 16),

                    // 4. 현장 가이드 맵 (페이지 이동 - 기존 디자인 통합)
                    _buildSummaryCard(
                      "MAP",
                      "현장 가이드 맵",
                      Icons.map_rounded,
                      Colors.redAccent,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MapListPage(user: adminUser, isAdmin: true))),
                    ),
                    const SizedBox(width: 16),

                    // 5. 인력 관리 (페이지 이동 - 기존 디자인 통합)
                    _buildSummaryCard(
                      "USER",
                      "인력 관리",
                      Icons.manage_accounts,
                      Colors.teal,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminUserPage())),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 1. 좌측 타이틀 (선택된 필터에 따라 텍스트 변경)
                  Text(
                    _selectedFilter == 'pending' ? "승인 대기 가이드" :
                    _selectedFilter == 'approved' ? "전체 가이드 목록" : "삭제된 가이드 내역",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  // 2. 우측 필터 칩 병렬 배치
                  Row(
                    children: [
                      _buildFilterChip('pending', '대기', Colors.orange),
                      const SizedBox(width: 8),
                      _buildFilterChip('approved', '전체', Colors.blue),
                      const SizedBox(width: 8),
                      _buildFilterChip('deleted', '삭제', Colors.redAccent),
                    ],
                  ),
                ],
              ),
            ),
          ),


// 2. 삭제 안내 문구 (SliverPadding으로 감싸서 여백 통일)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            sliver: _buildDeleteNotice(),
          ),

          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            sliver: _buildAdminGuideList(), // 매개변수 제거
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildFilterChip(String filter, String label, Color color) {
    bool isSelected = _selectedFilter == filter;
    return ChoiceChip(
      visualDensity: VisualDensity.compact, // 칩 크기를 조절하여 타이틀과 높이 맞춤
      label: Text(label, style: TextStyle(
        color: isSelected ? Colors.white : Colors.grey[700],
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      )),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: Colors.grey[200],
      onSelected: (bool selected) {
        if (selected) setState(() => _selectedFilter = filter);
      },
      // 체크 표시 제거하여 깔끔하게 유지
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide.none,
    );
  }

  Widget _buildStreamSummaryCard(String collection, String title, IconData icon, Color color, {Query? query}) {
    return StreamBuilder<QuerySnapshot>(
      stream: (query ?? FirebaseFirestore.instance.collection(collection)).snapshots(),
      builder: (context, snapshot) {
        int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _buildSummaryCard(title, "${count}건", icon, color);
      },
    );
  }

  // [교정] 다른 카드들과 디자인 언어를 완벽히 통일한 가동률 카드
  Widget _buildRateSummaryCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('settings').doc('factory_stats').snapshots(),
      builder: (context, snapshot) {
        String rate = snapshot.hasData && snapshot.data!.exists ? snapshot.data!['operation_rate'].toString() : "0";

        return Container(
          width: 150, // 다른 카드들과 동일한 너비 고정
          padding: const EdgeInsets.all(16), // 패딩 통일
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. 상단 아이콘 (규격 일치)
              const Icon(Icons.analytics, color: Colors.green, size: 24),
              const Spacer(),

              // 2. 중앙 수치 (규격 일치)
              Text("$rate%", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),

              // 3. 하단 제목 및 입력창 통합
              const SizedBox(height: 4),
              Row(
                children: [
                  const Expanded(
                    child: Text("가동률", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                  // 아주 작은 수정 아이콘 버튼으로 입력창 유도 (디자인 보존용)
                  GestureDetector(
                    onTap: () => _showRateEditDialog(context, rate), // 팝업 방식으로 전환 제안
                    child: const Icon(Icons.edit, size: 14, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

// [추가] 디자인을 해치지 않기 위해 입력창은 팝업 다이얼로그로 분리합니다.
  void _showRateEditDialog(BuildContext context, String currentRate) {
    _rateController.text = currentRate;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("가동률 수정"),
        content: TextField(
          controller: _rateController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: "%", hintText: "새 가동률 입력"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          ElevatedButton(
            onPressed: () {
              _updateOperationRate();
              Navigator.pop(context);
            },
            child: const Text("확인"),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String value, String title, IconData icon, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

// [수정] 필터 선택값에 따라 가이드 목록을 실시간으로 변경하는 로직
  Widget _buildAdminGuideList() {
    return StreamBuilder<QuerySnapshot>(
      // 필터값(_selectedFilter)을 쿼리 조건으로 바로 사용합니다.
      stream: FirebaseFirestore.instance
          .collection('guides')
          .where('status', isEqualTo: _selectedFilter)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Center(child: Padding(
              padding: EdgeInsets.all(40.0),
              child: CircularProgressIndicator(),
            )),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Text(
                  "'${_selectedFilter == 'pending' ? '승인 대기' : _selectedFilter == 'approved' ? '전체' : '삭제'}' 내역이 없습니다.",
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return SliverList(
          delegate: SliverChildBuilderDelegate(
                (context, index) {
              final guide = Guide.fromFirestore(docs[index].data() as Map<String, dynamic>);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildUserStyleGuideCard(guide, docs[index].id),
              );
            },
            childCount: docs.length,
          ),
        );
      },
    );
  }

  Widget _buildUserStyleGuideCard(Guide guide, String docId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(guide.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${guide.id} | 제안자: ${guide.proposerName}"),

        // [핵심] 현재 필터가 '삭제'라면 복구 버튼을, 아니라면 삭제 버튼을 표시하고 함수를 연결합니다.
        trailing: _selectedFilter == 'deleted'
            ? IconButton(
          icon: const Icon(Icons.restore, color: Colors.green),
          onPressed: () => _updateGuideStatus(docId, 'approved'), // '전체'로 복구
        )
            : IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: () => _updateGuideStatus(docId, 'deleted'), // '삭제'로 이동
        ),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => EditorPage(guide: guide, user: adminUser, firestoreDocId: docId))
        ),
      ),
    );
  }

// [추가] 가이드 삭제 확인 및 처리 함수
  Future<void> _showDeleteConfirmDialog(String docId, String title) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("가이드 삭제"),
        content: Text("'$title' 가이드를 정말로 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('guides').doc(docId).delete();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("가이드가 삭제되었습니다.")));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("삭제"),
          ),
        ],
      ),
    );
  }

// [수정] _buildDeleteNotice 함수
  Widget _buildDeleteNotice() {
    // '삭제' 필터가 아닐 때는 아예 렌더링하지 않음
    if (_selectedFilter != 'deleted') return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter( // 핵심: 일반 위젯을 Sliver 영역에서 쓸 수 있게 변환
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red[100]!),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.red[700], size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "삭제된 가이드는 30일 후 영구 제거됩니다. 복구가 필요한 경우 우측 아이콘을 클릭하십시오.",
                style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFab() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton.extended(
          heroTag: 'qr',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const QrPrintPage())),
          label: const Text("QR 인쇄"),
          icon: const Icon(Icons.print),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1A237E),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'new',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditorPage(user: adminUser))),
          label: const Text("가이드 작성"),
          icon: const Icon(Icons.add),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
      ],
    );
  }
}