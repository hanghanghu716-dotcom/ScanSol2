import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guide_model.dart';
import '../models/user_model.dart';
import 'editor_page.dart';
import 'admin_user_page.dart';
import '../qr_print_page.dart';
import 'map_list_page.dart';

class AdminPage extends StatefulWidget {
  final UserModel user;

  const AdminPage({super.key, required this.user});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final TextEditingController _rateController = TextEditingController();
  String _selectedFilter = 'pending'; // 기본값: 승인 대기

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

  Future<void> _updateGuideStatus(String docId, String newStatus) async {
    try {
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

    // [신규] 사업장의 요금제 한도 정보를 실시간으로 가져오는 Stream
    return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('facilities').doc(widget.user.facilityId).snapshots(),
        builder: (context, facilitySnapshot) {
          final facilityData = facilitySnapshot.data?.data() as Map<String, dynamic>?;
          final int maxMaps = facilityData?['maxMaps'] ?? 3;
          final int maxGuides = facilityData?['maxGuides'] ?? 10;

          return Scaffold(
            backgroundColor: const Color(0xFFF0F2F5),
            body: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 200,
                  pinned: true,
                  backgroundColor: const Color(0xFF1A237E),
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
                      height: 135, // Progress Bar 추가로 인해 높이 상향 조정
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // [UI 통일] 가이드 슬롯 사용량 카드
                          _buildUsageSummaryCard(
                              collection: 'guides',
                              title: "가이드 슬롯",
                              icon: Icons.library_books,
                              color: Colors.blue,
                              maxLimit: maxGuides,
                              query: FirebaseFirestore.instance
                                  .collection('guides')
                                  .where('facilityId', isEqualTo: widget.user.facilityId)
                                  .where('status', isEqualTo: 'approved')
                          ),
                          const SizedBox(width: 16),
                          // [UI 통일] 맵 슬롯 사용량 카드
                          _buildUsageSummaryCard(
                            collection: 'guide_maps',
                            title: "맵 슬롯",
                            icon: Icons.map_rounded,
                            color: Colors.redAccent,
                            maxLimit: maxMaps,
                            query: FirebaseFirestore.instance
                                .collection('guide_maps')
                                .where('facilityId', isEqualTo: widget.user.facilityId),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MapListPage(user: widget.user, isAdmin: true))),
                          ),
                          const SizedBox(width: 16),
                          // [UI 통일] 가동률 카드 (ProgressBar 포함)
                          _buildRateSummaryCard(),
                          const SizedBox(width: 16),
                          // 정비 이력 (단순 카운트)
                          _buildCountSummaryCard('maintenance_logs', "정비 이력", Icons.history, Colors.orange),
                          const SizedBox(width: 16),
                          // 인력 관리 바로가기
                          _buildActionSummaryCard(
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
                        Text(
                          _selectedFilter == 'pending' ? "승인 대기 가이드" :
                          _selectedFilter == 'approved' ? "전체 가이드 목록" : "삭제된 가이드 내역",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
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

                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  sliver: _buildDeleteNotice(),
                ),

                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  sliver: _buildAdminGuideList(),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
            floatingActionButton: _buildFab(),
          );
        }
    );
  }

  // [신규] UserPage와 동일한 규격의 슬롯 사용량 카드 (LinearProgressIndicator 포함)
  Widget _buildUsageSummaryCard({
    required String collection,
    required String title,
    required IconData icon,
    required Color color,
    required int maxLimit,
    required Query query,
    VoidCallback? onTap,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        double usageRatio = count / maxLimit;
        bool isFull = count >= maxLimit;

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 160,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isFull ? Colors.red.withOpacity(0.5) : Colors.grey.shade200,
                width: isFull ? 2 : 1,
              ),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: isFull ? Colors.red : color, size: 24),
                    if (isFull) const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                  ],
                ),
                const Spacer(),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
                    children: [
                      TextSpan(text: "$count", style: TextStyle(color: isFull ? Colors.red : Colors.black)),
                      TextSpan(
                          text: " / $maxLimit",
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.normal)
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: usageRatio.clamp(0.0, 1.0),
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(isFull ? Colors.red : color),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        );
      },
    );
  }

  // [교정] 가동률 카드 - Progress Bar 및 시각적 강조 추가
  Widget _buildRateSummaryCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('settings').doc('factory_stats').snapshots(),
      builder: (context, snapshot) {
        String rateStr = snapshot.hasData && snapshot.data!.exists ? snapshot.data!['operation_rate'].toString() : "0";
        double rateValue = double.tryParse(rateStr) ?? 0;
        double progress = rateValue / 100.0;

        return Container(
          width: 160,
          padding: const EdgeInsets.all(16),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.analytics, color: Colors.green, size: 24),
                  GestureDetector(
                    onTap: () => _showRateEditDialog(context, rateStr),
                    child: const Icon(Icons.edit, size: 16, color: Colors.grey),
                  ),
                ],
              ),
              const Spacer(),
              Text("$rateStr%", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(progress > 0.8 ? Colors.green : Colors.orange),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 4),
              const Text("실시간 가동률", style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }

  // 단순 카운트용 카드
  Widget _buildCountSummaryCard(String collection, String title, IconData icon, Color color) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection(collection).snapshots(),
      builder: (context, snapshot) {
        int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _buildActionSummaryCard("${count}건", title, icon, color);
      },
    );
  }

  // 액션 버튼용 카드
  Widget _buildActionSummaryCard(String value, String title, IconData icon, Color color, {VoidCallback? onTap}) {
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
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

  Widget _buildFilterChip(String filter, String label, Color color) {
    bool isSelected = _selectedFilter == filter;
    return ChoiceChip(
      visualDensity: VisualDensity.compact,
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
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide.none,
    );
  }

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

  Widget _buildAdminGuideList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('guides')
          .where('facilityId', isEqualTo: widget.user.facilityId)
          .where('status', isEqualTo: _selectedFilter)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Text("'${_selectedFilter}' 내역이 없습니다.", style: const TextStyle(color: Colors.grey)),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(guide.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${guide.id} | 제안자: ${guide.proposerName}"),
        trailing: _selectedFilter == 'deleted'
            ? IconButton(icon: const Icon(Icons.restore, color: Colors.green), onPressed: () => _updateGuideStatus(docId, 'approved'))
            : IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _updateGuideStatus(docId, 'deleted')),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditorPage(guide: guide, user: widget.user, firestoreDocId: docId))),
      ),
    );
  }

  Widget _buildDeleteNotice() {
    if (_selectedFilter != 'deleted') return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red[100]!)),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.red[700], size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text("삭제된 가이드는 30일 후 영구 제거됩니다. 복구가 필요한 경우 우측 아이콘을 클릭하십시오.", style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500))),
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
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditorPage(user: widget.user))),
          label: const Text("가이드 작성"),
          icon: const Icon(Icons.add),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
      ],
    );
  }
}