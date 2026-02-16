import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guide_map_model.dart';
import '../models/user_model.dart'; // [추가] 유저 모델 임포트
import '../widgets/interactive_map_viewer.dart';
import 'admin_map_editor_page.dart';

class MapListPage extends StatelessWidget {
  final bool isAdmin;
  final UserModel user; // [추가] 현재 로그인한 사용자 정보 필드

  // [수정] 생성자에서 user를 필수로 받도록 변경
  const MapListPage({super.key, required this.user, this.isAdmin = false});

  @override
  Widget build(BuildContext context) {
    // [교정] AdminPage와 동일하게 화면 너비에 따른 중앙 정렬 패딩 계산 (좌우 늘어짐 방지)
    double screenWidth = MediaQuery.of(context).size.width;
    double horizontalPadding = screenWidth > 1200 ? (screenWidth - 1000) / 2 : 16;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5), // 배포용 배경색 지정
      body: CustomScrollView(
        slivers: [
          // 1. AdminPage 컨셉의 그라디언트 헤더 적용
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
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
                  padding: EdgeInsets.only(left: horizontalPadding, bottom: 30),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "ScanSol Mapping System",
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "현장 가이드 맵 목록",
                        style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. 리스트 영역 (SliverPadding으로 감싸서 중앙으로 모음)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),
            sliver: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('guide_maps')
                  .orderBy('createdAt', descending: true) // 최신 등록순 정렬
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const SliverToBoxAdapter(child: Center(child: Text("데이터를 불러오지 못했습니다.")));
                if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) return const SliverToBoxAdapter(child: Center(child: Text("등록된 현장 맵이 없습니다.")));

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      final mapData = GuideMap.fromFirestore(docs[index]);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            leading: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8EAF6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.map_rounded, color: Color(0xFF1A237E)),
                            ),
                            title: Text(
                              mapData.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                "등록된 장비 태그: ${mapData.tags.length}개",
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                            trailing: isAdmin
                                ? IconButton(
                              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                              onPressed: () => _deleteMap(context, mapData),
                            )
                                : const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.grey),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdminMapEditorPage(
                                    user: user,
                                    mapId: mapData.id,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                    childCount: docs.length,
                  ),
                );
              },
            ),
          ),
          // 하단 여유 공간
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),

      // 신규 지도 추가 버튼 (관리자 전용)
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => AdminMapEditorPage(user: user, mapId: null)),
        ),
        backgroundColor: const Color(0xFF1A237E),
        icon: const Icon(Icons.add_a_photo, color: Colors.white),
        label: const Text("새 지도 등록", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      )
          : null,
    );
  }

  // [신규] 맵 데이터 및 사진 파일 동시 삭제 함수
  Future<void> _deleteMap(BuildContext context, GuideMap mapData) async {
    try {
      // 1. 실수 방지를 위한 최종 확인 다이얼로그
      bool? confirm = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("지도 삭제"),
          content: Text("'${mapData.title}' 지도를 완전히 삭제하시겠습니까?\n등록된 태그 정보도 모두 삭제됩니다."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소")),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("삭제", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // 2. 삭제 중 로딩 표시
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      // 3. [핵심] Firebase Storage의 실제 사진 파일 삭제
      if (mapData.imageUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(mapData.imageUrl).delete();
        } catch (e) {
          debugPrint("이미지 삭제 실패(이미 없을 수 있음): $e");
        }
      }

      // 4. Firestore의 맵 문서 삭제
      await FirebaseFirestore.instance.collection('guide_maps').doc(mapData.id).delete();

      if (context.mounted) {
        Navigator.pop(context); // 로딩 창 닫기
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("지도가 안전하게 삭제되었습니다.")));
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("삭제 실패: $e")));
    }
  }
}