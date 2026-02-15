import 'package:flutter/material.dart';
import '../models/guide_model.dart';


//--------------------------------------------------------
// [리디자인] 4-1. 가이드 상세 페이지 (엔지니어링 리포트 스타일)
// -----------------------------------------------------------
class GuideDetailPage extends StatelessWidget {
  final Guide guide;
  const GuideDetailPage({super.key, required this.guide});

  @override
  Widget build(BuildContext context) {
    // 엔지니어링 정보가 있는지 확인
    bool hasSpec = guide.partsInfo.isNotEmpty || guide.specInfo.isNotEmpty || guide.relationInfo.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // 배경과 카드를 분리하기 위해 회색 배경
      appBar: AppBar(
        title: const Text("매뉴얼 상세 정보"),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // 공유 기능 (추후 구현)
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("링크가 복사되었습니다.")));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800), // 가독성을 위해 최대 너비 제한
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 헤더 카드 (제목, 상태, 등록자)
                _buildHeaderCard(context),
                const SizedBox(height: 16),

                // 2. 사진 갤러리 (있을 경우만)
                if (guide.imageUrls.isNotEmpty) ...[
                  _buildSectionTitle(context, "현장 사진", Icons.camera_alt),
                  _buildPhotoGallery(context),
                  const SizedBox(height: 24),
                ],

                // 3. 엔지니어링 스펙 (있을 경우만)
                if (hasSpec) ...[
                  _buildSectionTitle(context, "기술 사양 및 로직", Icons.settings_input_component),
                  _buildSpecCard(context),
                  const SizedBox(height: 24),
                ],

                // 4. 상세 조치 내용
                _buildSectionTitle(context, "상세 조치 방법", Icons.build),
                _buildContentCard(context),

                // 5. 원본 이력 (수정된 경우)
                if (guide.originalContent != guide.content) ...[
                  const SizedBox(height: 24),
                  ExpansionTile(
                    title: const Text("수정 전 원본 기록 보기", style: TextStyle(fontSize: 14, color: Colors.grey)),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        color: Colors.grey[200],
                        child: Text(guide.originalContent, style: const TextStyle(color: Colors.black54)),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  guide.id,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const Spacer(),
              Text(
                guide.date,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            guide.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.grey[200]),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: Colors.grey[200],
                child: const Icon(Icons.person, size: 14, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              Text(
                guide.isAnonymous ? "익명 제안" : guide.proposerName,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 16),
              if (guide.status == 'approved')
                const Icon(Icons.check_circle, size: 16, color: Colors.green)
              else
                const Icon(Icons.pending, size: 16, color: Colors.orange),
              const SizedBox(width: 4),
              Text(
                guide.status == 'approved' ? "승인됨" : "검토 중",
                style: TextStyle(
                  color: guide.status == 'approved' ? Colors.green : Colors.orange,
                  fontSize: 13, fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoGallery(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: guide.imageUrls.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              guide.imageUrls[index],
              height: 200,
              width: 280,
              fit: BoxFit.cover,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSpecCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA), // 아주 연한 회색 배경
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9ECEF)),
      ),
      child: Column(
        children: [
          if (guide.partsInfo.isNotEmpty) _buildSpecRow(context, "필요 자재", guide.partsInfo, isFirst: true),
          if (guide.specInfo.isNotEmpty) _buildSpecRow(context, "정상 범위", guide.specInfo),
          if (guide.relationInfo.isNotEmpty) _buildSpecRow(context, "상관 로직", guide.relationInfo, isLast: true),
        ],
      ),
    );
  }

  Widget _buildSpecRow(BuildContext context, String key, String value, {bool isFirst = false, bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE9ECEF))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(key, style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Color(0xFF212121), fontSize: 15, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildContentCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        guide.content,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.8),
      ),
    );
  }
}