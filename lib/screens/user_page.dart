import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 아까 만든 모델과 위젯들을 가져옵니다.
import '../models/user_model.dart';
import '../models/guide_model.dart';
import 'login_page.dart';
import 'admin_page.dart'; // 곧 만들 파일
import 'editor_page.dart'; // 곧 만들 파일
import 'guide_detail_page.dart';

// -----------------------------------------------------------
// [리디자인] 3. 작업자 메인 페이지 (대시보드형 UI + 에러 방지 로직 포함)
// -----------------------------------------------------------
class UserPage extends StatefulWidget {
  final UserModel user;

  const UserPage({super.key, required this.user});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  // 상태 관리 변수
  int _selectedIndex = kIsWeb ? 1 : 0;
  bool _isEmergencyMode = false;
  bool isScanCompleted = false;

  final MobileScannerController cameraController = MobileScannerController();
  final TextEditingController _scanSearchController = TextEditingController();
  final TextEditingController _listSearchController = TextEditingController();
  String _searchText = "";
  String _sortBy = "Date";

  @override
  void initState() {
    super.initState();
    _listSearchController.addListener(() {
      if (mounted) setState(() => _searchText = _listSearchController.text);
    });
  }

  @override
  void dispose() {
    cameraController.dispose();
    _scanSearchController.dispose();
    _listSearchController.dispose();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userDocId');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // [디자인] 탭 전환 시 부드러운 애니메이션을 위해 AnimatedSwitcher 사용 가능하나,
    // 성능을 위해 IndexedStack 또는 조건부 렌더링 유지.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        // 응급 모드일 때 배경색 변경
        backgroundColor: _isEmergencyMode ? const Color(0xFFFFEBEE) : Theme.of(context).colorScheme.background,

        // [구조] Builder를 사용하여 하위 Context 확보 (에러 방지 핵심)
        body: Builder(
          builder: (innerContext) {
            if (_isEmergencyMode) return _buildEmergencyUI();

            // 탭에 따라 다른 화면 표시
            return _selectedIndex == 0
                ? _buildScanTab(innerContext)
                : _buildDashboardTab(innerContext);
          },
        ),

        // [디자인] 현대적인 하단 네비게이션 바
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
              isScanCompleted = false;
            });
          },
          backgroundColor: Colors.white,
          elevation: 3,
          indicatorColor: Theme.of(context).colorScheme.secondary.withOpacity(0.2),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_outlined),
              selectedIcon: Icon(Icons.qr_code_scanner),
              label: '스캔',
            ),
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: '대시보드',
            ),
          ],
        ),

// [수정] 스캔 화면(0번 탭)이거나 응급 모드일 때는 버튼 숨김
        floatingActionButton: (_isEmergencyMode || _selectedIndex == 0)
            ? null
            : FloatingActionButton.extended(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditorPage(user: widget.user))),
          icon: const Icon(Icons.edit_note),
          label: const Text("가이드 제안"),
          backgroundColor: Theme.of(context).colorScheme.secondary,
          foregroundColor: Colors.black, // 앰버색 배경엔 검은 글씨가 가독성이 좋음
        ),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // [탭 1] QR 스캔 화면 (UI 개선 + 에러 방지)
  // ----------------------------------------------------------------------
  Widget _buildScanTab(BuildContext context) {
    if (kIsWeb) return const Center(child: Text("PC 환경에서는 '대시보드' 탭에서 검색을 이용해주세요."));

    // [핵심] MediaQuery로 높이 계산 (Scaffold.of 에러 방지)
    final double topPadding = MediaQuery.of(context).padding.top;
    final double headerHeight = 80;
    final double screenHeight = MediaQuery.of(context).size.height;
    final double scanBoxSize = 260.0;
    // 스캔 박스 위치 조정
    final double scanBoxTopPosition = (screenHeight - topPadding - headerHeight - scanBoxSize) / 2 - 40;

    return Stack(
      children: [
        // 1. 카메라 뷰
        MobileScanner(
          controller: cameraController,
          onDetect: (capture) {
            if (!isScanCompleted && _selectedIndex == 0) {
              for (final barcode in capture.barcodes) {
                if (barcode.rawValue != null) {
                  setState(() => isScanCompleted = true);
                  HapticFeedback.mediumImpact();
                  _showResultDialog(barcode.rawValue!);
                  break;
                }
              }
            }
          },
        ),

        // 2. 반투명 오버레이 (집중 효과)
        ColorFiltered(
          colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.5), BlendMode.srcOut),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                  backgroundBlendMode: BlendMode.dstIn,
                ),
              ),
              Positioned(
                top: scanBoxTopPosition + topPadding + headerHeight,
                left: (MediaQuery.of(context).size.width - scanBoxSize) / 2,
                child: Container(
                  height: scanBoxSize,
                  width: scanBoxSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3. 상단 헤더 및 컨트롤
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(20, topPadding + 10, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("QR 스캔", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text("장비의 QR코드를 비춰주세요", style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
                  ],
                ),
                // 플래시 버튼
                IconButton(
                  icon: const Icon(Icons.flash_on, color: Colors.white),
                  onPressed: () => cameraController.toggleTorch(),
                ),
              ],
            ),
          ),
        ),

        // 4. 스캔 가이드 라인
        Positioned(
          top: scanBoxTopPosition + topPadding + headerHeight,
          left: (MediaQuery.of(context).size.width - scanBoxSize) / 2,
          child: Container(
            width: scanBoxSize, height: scanBoxSize,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.secondary, width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Icon(Icons.add, color: Theme.of(context).colorScheme.secondary.withOpacity(0.5), size: 40),
            ),
          ),
        ),

        // 5. 하단 직접 입력 버튼
        Positioned(
          bottom: 30, left: 20, right: 20,
          child: ElevatedButton.icon(
            onPressed: () => _showManualInputDialog(),
            icon: const Icon(Icons.keyboard),
            label: const Text("장비 ID 직접 입력"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
            ),
          ),
        ),

        // 6. 응급 모드 토글 (상단 중앙)
        Positioned(
          top: topPadding + 10,
          right: 60, // 플래시 버튼 옆
          child: InkWell(
            onTap: () => setState(() => _isEmergencyMode = !_isEmergencyMode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isEmergencyMode ? Colors.red : Colors.black45,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white30),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _isEmergencyMode ? "응급 ON" : "응급 OFF",
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

// ----------------------------------------------------------------------
  // [탭 2] 대시보드 탭 (수정: 카드 높이 Overflow 해결 - 높이 210으로 변경)
  // ----------------------------------------------------------------------
  Widget _buildDashboardTab(BuildContext context) {
    // 화면 너비 계산 (반응형 여백 계산용)
    final double screenWidth = MediaQuery.of(context).size.width;
    const double maxContentWidth = 1000.0; // 웹에서 콘텐츠가 퍼지지 않게 잡을 최대 너비
    final double horizontalPadding = screenWidth > maxContentWidth
        ? (screenWidth - maxContentWidth) / 2
        : 16.0;

    return CustomScrollView(
      slivers: [
        // 1. 확장형 앱바
        SliverAppBar(
          expandedHeight: 200.0,
          floating: false,
          pinned: true,
          backgroundColor: Theme.of(context).colorScheme.primary,
          actions: [
            if (widget.user.role == 'ADMIN')
              IconButton(
                icon: const Icon(Icons.admin_panel_settings),
                tooltip: "관리자 설정",
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPage())),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: "로그아웃",
              onPressed: _handleLogout,
            ),
            const SizedBox(width: 8),
          ],
          flexibleSpace: FlexibleSpaceBar(
            centerTitle: false,
            titlePadding: EdgeInsets.symmetric(
                horizontal: screenWidth > maxContentWidth ? (screenWidth - maxContentWidth) / 2 : 20,
                vertical: 16
            ),
            title: Text(
              "안녕하세요, ${widget.user.name}님",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1A237E),
                    const Color(0xFF283593),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    bottom: -40,
                    child: Icon(
                      Icons.analytics_outlined,
                      size: 200,
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  Positioned(
                    left: screenWidth > maxContentWidth ? (screenWidth - maxContentWidth) / 2 : 20,
                    bottom: 50,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                              "ScanSol Dashboard",
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "${widget.user.department} | ${widget.user.facilityId}",
                          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 2. 검색바
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
          sliver: SliverToBoxAdapter(
            child: TextField(
              controller: _listSearchController,
              decoration: InputDecoration(
                hintText: "가이드 검색 (ID, 제목, 내용)",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchText.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _listSearchController.clear())
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
                ),
              ),
            ),
          ),
        ),

        // 3. 통계 요약 카드
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),
          sliver: SliverToBoxAdapter(
            child: SizedBox(
              height: 125,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildSummaryCard("전체 가이드", "12건", Icons.library_books, Colors.blue),
                  const SizedBox(width: 16),
                  _buildSummaryCard("이번 달 정비", "5건", Icons.build_circle, Colors.orange),
                  const SizedBox(width: 16),
                  _buildSummaryCard("가동률", "98%", Icons.analytics, Colors.green),
                ],
              ),
            ),
          ),
        ),

        // 4. 최근 정비 활동 (Maintenance Log)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("최근 현장 활동", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                _buildMaintenanceSection(context),
              ],
            ),
          ),
        ),

        // 5. 가이드 목록 헤더
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 32, horizontalPadding, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("가이드 목록", style: Theme.of(context).textTheme.titleLarge),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort),
                  onSelected: (value) => setState(() => _sortBy = value),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: "Date", child: Text("최신순")),
                    const PopupMenuItem(value: "ID", child: Text("ID순")),
                  ],
                ),
              ],
            ),
          ),
        ),

        // 6. 메인 리스트
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('guides').where('status', isEqualTo: 'approved').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())));
            }

            var docs = snapshot.data!.docs;
            List<Guide> guides = docs.map((doc) => Guide.fromFirestore(doc.data() as Map<String, dynamic>)).toList();

            if (_searchText.isNotEmpty) {
              guides = guides.where((g) => "${g.title} ${g.id} ${g.content}".toLowerCase().contains(_searchText.toLowerCase())).toList();
            }
            if (_sortBy == 'Date') {
              guides.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            } else {
              guides.sort((a, b) => a.id.compareTo(b.id));
            }

            if (guides.isEmpty) {
              return const SliverToBoxAdapter(
                child: Center(child: Padding(padding: EdgeInsets.all(40), child: Text("검색 결과가 없습니다."))),
              );
            }

            return SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
              sliver: screenWidth > 900
                  ? SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 240,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildGuideCard(guides[index]),
                  childCount: guides.length,
                ),
              )
                  : SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildGuideCard(guides[index]),
                  childCount: guides.length,
                ),
              ),
            );
          },
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }


  // ------------------------------------------------------------------------
  // [신규] 최근 정비 활동 섹션 UI (더미 데이터 사용)
  // ------------------------------------------------------------------------
  Widget _buildMaintenanceSection(BuildContext context) {
    // 추후 DB에서 가져올 데이터 모델 (더미)
    final List<Map<String, String>> dummyLogs = [
      {'type': 'REPAIR', 'title': 'M-101 밸브 O-ring 교체', 'date': '방금 전', 'user': '김철수'},
      {'type': 'CHECK', 'title': 'P-203 진동 수치 점검', 'date': '2시간 전', 'user': '이영희'},
      {'type': 'ISSUE', 'title': 'H-305 온도 센서 이상 알림', 'date': '어제', 'user': '시스템'},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Column(
        children: dummyLogs.map((log) => _buildMaintenanceItem(log)).toList(),
      ),
    );
  }

  Widget _buildMaintenanceItem(Map<String, String> log) {
    IconData icon;
    Color color;
    String typeText;

    switch (log['type']) {
      case 'REPAIR':
        icon = Icons.build_circle;
        color = Colors.orange;
        typeText = "수리";
        break;
      case 'CHECK':
        icon = Icons.check_circle;
        color = Colors.green;
        typeText = "점검";
        break;
      default:
        icon = Icons.warning_rounded;
        color = Colors.red;
        typeText = "장애";
    }

    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(log['title']!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          subtitle: Text("${log['user']} • ${log['date']}", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(typeText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700])),
          ),
          onTap: () {
            // 추후 해당 이력 상세 페이지로 이동
          },
        ),
        if (log != {'type': 'ISSUE', 'title': 'H-305 온도 센서 이상 알림', 'date': '어제', 'user': '시스템'}) // 마지막 아이템이 아니면 구분선 (더미 로직)
          const Divider(height: 1, indent: 60, endIndent: 20),
      ],
    );
  }

  // 통계 요약 카드 위젯
  Widget _buildSummaryCard(String title, String count, IconData icon, Color color) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const Spacer(),
          Text(count, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  // 가이드 카드 위젯 (리디자인 적용)
  Widget _buildGuideCard(Guide guide) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      // Theme에서 정의한 CardTheme 자동 적용
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => GuideDetailPage(guide: guide))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 장비 ID 배지
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      guide.id,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    guide.date, // 또는 relative time (예: 2시간 전)
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                guide.title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                guide.content,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(guide.isAnonymous ? "익명" : guide.proposerName, style: Theme.of(context).textTheme.bodySmall),
                  if (guide.imageUrls.isNotEmpty) ...[
                    const Spacer(),
                    const Icon(Icons.image_outlined, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text("사진 ${guide.imageUrls.length}", style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 응급 상황 UI
  Widget _buildEmergencyUI() {
    return Container(
      color: const Color(0xFFD32F2F),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning_rounded, size: 100, color: Colors.yellow),
          const SizedBox(height: 24),
          const Text("긴급 상황 모드", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          const Text("즉시 안전 관리자에게 연락하세요.", style: TextStyle(fontSize: 18, color: Colors.white70)),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: () => setState(() => _isEmergencyMode = false),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFD32F2F),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            ),
            child: const Text("응급 모드 해제", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 직접 입력 다이얼로그 (스캔 탭용)
  void _showManualInputDialog() {
    _scanSearchController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("장비 ID 입력"),
        content: TextField(
          controller: _scanSearchController,
          autofocus: true,
          decoration: const InputDecoration(hintText: "예: M-101", prefixIcon: Icon(Icons.keyboard)),
          onSubmitted: (v) {
            Navigator.pop(context);
            if (v.trim().isNotEmpty) _showResultDialog(v.trim());
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (_scanSearchController.text.trim().isNotEmpty) _showResultDialog(_scanSearchController.text.trim());
            },
            child: const Text("조회"),
          ),
        ],
      ),
    );
  }

  // 결과 다이얼로그 (기존 로직 유지)
  void _showResultDialog(String scannedCode) {
    FocusScope.of(context).unfocus();
    // (기존의 다이얼로그 로직 사용 - Firebase 연동 필요 시 StreamBuilder나 FutureBuilder 사용 권장)
    // 여기서는 간략히 구현
    showDialog(
      context: context,
      builder: (context) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('guides').where('id', isEqualTo: scannedCode).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const AlertDialog(content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())));

            var docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return AlertDialog(
                title: const Text("등록되지 않은 장비"),
                content: Text("ID: $scannedCode\n해당 장비의 가이드가 없습니다."),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인")),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (context) => EditorPage(user: widget.user))); // ID 자동입력 추가 가능
                    },
                    child: const Text("새 가이드 작성"),
                  ),
                ],
              );
            }

            // 가이드가 있는 경우
            return AlertDialog(
              title: Text("장비 ID: $scannedCode"),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    var guide = Guide.fromFirestore(docs[index].data() as Map<String, dynamic>);
                    return ListTile(
                      title: Text(guide.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(guide.date),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (context) => GuideDetailPage(guide: guide)));
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("닫기")),
              ],
            );
          },
        );
      },
    ).then((_) => setState(() => isScanCompleted = false));
  }
}
// ---