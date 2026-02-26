import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/guide_map_model.dart';
import '../models/user_model.dart';
import '../models/guide_model.dart';
import '../widgets/interactive_map_viewer.dart';
import 'login_page.dart';
import 'admin_page.dart';
import 'editor_page.dart';
import 'guide_detail_page.dart';
import '../models/maintenance_log_model.dart';
import 'map_list_page.dart';

class UserPage extends StatefulWidget {
  final UserModel user;

  const UserPage({super.key, required this.user});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  int _selectedIndex = kIsWeb ? 1 : 0;
  bool _isEmergencyMode = false;
  bool isScanCompleted = false;

  final MobileScannerController cameraController = MobileScannerController();
  final TextEditingController _scanSearchController = TextEditingController();
  final TextEditingController _listSearchController = TextEditingController();
  String _searchText = "";

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
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _isEmergencyMode ? const Color(0xFFFFEBEE) : const Color(0xFFF0F2F5),
        body: Builder(
          builder: (innerContext) {
            if (_isEmergencyMode) return _buildEmergencyUI();
            return _selectedIndex == 0
                ? _buildScanTab(innerContext)
                : _buildDashboardTab(innerContext);
          },
        ),
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
          indicatorColor: const Color(0xFF1A237E).withOpacity(0.1),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.qr_code_scanner_outlined), selectedIcon: Icon(Icons.qr_code_scanner), label: '스캔'),
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: '대시보드'),
          ],
        ),
        floatingActionButton: (_isEmergencyMode || _selectedIndex == 0)
            ? null
            : FloatingActionButton.extended(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => EditorPage(user: widget.user))),
          icon: const Icon(Icons.edit_note),
          label: const Text("가이드 제안"),
          backgroundColor: const Color(0xFFFFC107),
          foregroundColor: Colors.black,
        ),
      ),
    );
  }

  Widget _buildScanTab(BuildContext context) {
    if (kIsWeb) return const Center(child: Text("PC 환경에서는 '대시보드' 탭에서 검색을 이용해주세요."));

    final double topPadding = MediaQuery.of(context).padding.top;
    const double headerHeight = 80;
    final double screenHeight = MediaQuery.of(context).size.height;
    const double scanBoxSize = 260.0;
    final double scanBoxTopPosition = (screenHeight - topPadding - headerHeight - scanBoxSize) / 2 - 40;

    return Stack(
      children: [
        MobileScanner(
          controller: cameraController,
          onDetect: (capture) {
            if (!isScanCompleted && _selectedIndex == 0) {
              final code = capture.barcodes.first.rawValue;
              if (code != null) {
                HapticFeedback.mediumImpact();
                _processScanResult(code);
              }
            }
          },
        ),
        ColorFiltered(
          colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.5), BlendMode.srcOut),
          child: Stack(
            children: [
              Container(decoration: const BoxDecoration(color: Colors.transparent, backgroundBlendMode: BlendMode.dstIn)),
              Positioned(
                top: scanBoxTopPosition + topPadding + headerHeight,
                left: (MediaQuery.of(context).size.width - scanBoxSize) / 2,
                child: Container(height: scanBoxSize, width: scanBoxSize, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(20, topPadding + 10, 20, 20),
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("QR 스캔", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text("장비의 QR코드를 비춰주세요", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.flash_on, color: Colors.white), onPressed: () => cameraController.toggleTorch()),
              ],
            ),
          ),
        ),
        Positioned(
          top: scanBoxTopPosition + topPadding + headerHeight,
          left: (MediaQuery.of(context).size.width - scanBoxSize) / 2,
          child: Container(
            width: scanBoxSize, height: scanBoxSize,
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFFFC107), width: 2), borderRadius: BorderRadius.circular(20)),
            child: Center(child: Icon(Icons.add, color: const Color(0xFFFFC107).withOpacity(0.5), size: 40)),
          ),
        ),
        Positioned(
          bottom: 30, left: 20, right: 20,
          child: ElevatedButton.icon(
            onPressed: () => _showManualInputDialog(),
            icon: const Icon(Icons.keyboard),
            label: const Text("장비 ID 직접 입력"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black87, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardTab(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    const double maxContentWidth = 1000.0;
    final double horizontalPadding = screenWidth > maxContentWidth ? (screenWidth - maxContentWidth) / 2 : 16.0;

    return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('facilities').doc(widget.user.facilityId).snapshots(),
        builder: (context, facilitySnapshot) {
          if (!facilitySnapshot.hasData) return const Center(child: CircularProgressIndicator());

          final facilityData = facilitySnapshot.data!.data() as Map<String, dynamic>?;
          final int maxMaps = facilityData?['maxMaps'] ?? 3;
          final int maxGuides = facilityData?['maxGuides'] ?? 10;
          final String planType = facilityData?['planType'] ?? 'FREE';

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220.0,
                pinned: true,
                backgroundColor: const Color(0xFF1A237E),
                actions: [
                  if (widget.user.role == 'ADMIN' || widget.user.role == 'SUPER_ADMIN')
                    IconButton(
                        icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => AdminPage(user: widget.user))
                        )
                    ),
                  IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: _handleLogout),
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: 40,
                          bottom: -30,
                          child: Icon(Icons.analytics_outlined, size: 180, color: Colors.white.withOpacity(0.08)),
                        ),
                        Positioned(
                          left: horizontalPadding,
                          bottom: 30,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: planType == 'PRO' ? Colors.orange : Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "ScanSol $planType Plan",
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "${widget.user.department} | ${widget.user.facilityId}",
                                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, letterSpacing: -0.5),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "반갑습니다, ${widget.user.name}님",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 0),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    controller: _listSearchController,
                    decoration: InputDecoration(
                      hintText: "가이드 검색 (ID, 제목, 내용)",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),
                sliver: SliverToBoxAdapter(
                  child: SizedBox(
                    height: 135,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        // [교정] 승인된(approved) 가이드만 카운팅하도록 쿼리 수정
                        _buildUsageSummaryCard(
                          collection: 'guides',
                          title: "가이드 슬롯",
                          icon: Icons.library_books,
                          color: Colors.blue,
                          maxLimit: maxGuides,
                          query: FirebaseFirestore.instance
                              .collection('guides')
                              .where('facilityId', isEqualTo: widget.user.facilityId)
                              .where('status', isEqualTo: 'approved'),
                        ),
                        const SizedBox(width: 16),
                        _buildUsageSummaryCard(
                          collection: 'guide_maps',
                          title: "맵 슬롯",
                          icon: Icons.map_rounded,
                          color: Colors.redAccent,
                          maxLimit: maxMaps,
                          query: FirebaseFirestore.instance
                              .collection('guide_maps')
                              .where('facilityId', isEqualTo: widget.user.facilityId),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => MapListPage(user: widget.user, isAdmin: false))
                          ),
                        ),
                        const SizedBox(width: 16),
                        _buildRateSummaryCard(),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                sliver: const SliverToBoxAdapter(
                    child: Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text("최근 현장 활동", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                    )
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                sliver: SliverToBoxAdapter(child: _buildMaintenanceSection(context)),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontalPadding, 32, horizontalPadding, 8),
                sliver: SliverToBoxAdapter(
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("가이드 목록", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(icon: const Icon(Icons.sort), onPressed: () {})
                        ]
                    )
                ),
              ),
              _buildGuideStreamList(horizontalPadding),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          );
        }
    );
  }

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
                    if (isFull)
                      const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
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

  Widget _buildRateSummaryCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('settings').doc('factory_stats').snapshots(),
      builder: (context, snapshot) {
        String rateStr = snapshot.hasData && snapshot.data!.exists
            ? snapshot.data!['operation_rate'].toString()
            : "0";
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
              const Icon(Icons.analytics, color: Colors.green, size: 24),
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

  Widget _buildMaintenanceSection(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // [중요] 색인 생성이 필요한 복합 쿼리 구간입니다.
      stream: FirebaseFirestore.instance
          .collection('maintenance_logs')
          .where('facilityId', isEqualTo: widget.user.facilityId)
          .orderBy('date', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint("Maintenance Section Error: ${snapshot.error}");
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text("색인 생성 대기 중...")));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text("최근 활동 기록이 없습니다.")));

        final logs = docs.map((log) => MaintenanceLog.fromFirestore(log)).toList();

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: logs.length,
            separatorBuilder: (context, index) => const Divider(height: 1, indent: 60),
            itemBuilder: (context, index) => _buildMaintenanceItem(logs[index]),
          ),
        );
      },
    );
  }

  Widget _buildMaintenanceItem(MaintenanceLog log) {
    return ListTile(
      leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.1),
          child: const Icon(Icons.history, color: Colors.blue, size: 20)
      ),
      title: Text(log.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      subtitle: Text("${log.userName} • ${log.date.hour}:${log.date.minute}"),
      trailing: const Icon(Icons.chevron_right, size: 16),
    );
  }

  Widget _buildGuideStreamList(double horizontalPadding) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('guides')
          .where('facilityId', isEqualTo: widget.user.facilityId)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        var guides = snapshot.data!.docs.map((doc) => Guide.fromFirestore(doc.data() as Map<String, dynamic>)).toList();

        if (_searchText.isNotEmpty) {
          guides = guides.where((g) => "${g.title} ${g.id}".toLowerCase().contains(_searchText.toLowerCase())).toList();
        }

        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) => _buildGuideCard(guides[index]), childCount: guides.length)),
        );
      },
    );
  }

  Widget _buildGuideCard(Guide guide) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => GuideDetailPage(guide: guide))),
        title: Text(guide.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(guide.id),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Future<void> _processScanResult(String scannedId) async {
    setState(() => isScanCompleted = true);
    final mapSnapshot = await FirebaseFirestore.instance
        .collection('guide_maps')
        .where('facilityId', isEqualTo: widget.user.facilityId)
        .get();

    GuideMap? targetMap;
    for (var doc in mapSnapshot.docs) {
      final map = GuideMap.fromFirestore(doc);
      if (map.tags.any((tag) => tag.guideId == scannedId)) {
        targetMap = map;
        break;
      }
    }
    if (targetMap != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(appBar: AppBar(title: Text("${targetMap!.title} - 위치 확인")), body: InteractiveMapViewer(guideMap: targetMap!))));
    } else {
      _showResultDialog(scannedId);
    }
  }

  void _showResultDialog(String scannedCode) {
    showDialog(
      context: context,
      builder: (context) => StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('guides')
            .where('facilityId', isEqualTo: widget.user.facilityId)
            .where('id', isEqualTo: scannedCode)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const AlertDialog(content: CircularProgressIndicator());
          var docs = snapshot.data!.docs;
          return AlertDialog(
            title: Text("장비 ID: $scannedCode"),
            content: docs.isEmpty ? const Text("가이드가 없습니다.") : SizedBox(
              width: double.maxFinite, height: 200,
              child: ListView.builder(itemCount: docs.length, itemBuilder: (context, i) {
                var g = Guide.fromFirestore(docs[i].data() as Map<String, dynamic>);
                return ListTile(title: Text(g.title), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => GuideDetailPage(guide: g))));
              }),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("닫기"))],
          );
        },
      ),
    ).then((_) => setState(() => isScanCompleted = false));
  }

  void _showManualInputDialog() {
    _scanSearchController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("장비 ID 입력"),
        content: TextField(controller: _scanSearchController, autofocus: true, onSubmitted: (v) { Navigator.pop(context); _processScanResult(v.trim()); }),
        actions: [ElevatedButton(onPressed: () { Navigator.pop(context); _processScanResult(_scanSearchController.text.trim()); }, child: const Text("조회"))],
      ),
    );
  }

  Widget _buildEmergencyUI() {
    return Container(
      color: Colors.red[900], width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning_rounded, size: 100, color: Colors.yellow),
          const Text("긴급 상황 모드", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 48),
          ElevatedButton(onPressed: () => setState(() => _isEmergencyMode = false), child: const Text("응급 모드 해제")),
        ],
      ),
    );
  }
}