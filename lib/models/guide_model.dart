// [운영 배포용] 가이드 데이터 모델 - 데이터 무결성 및 필드 표준화 버전
import 'package:cloud_firestore/cloud_firestore.dart';

class Guide {
  final String id;
  final String facilityId; // 프로젝트 표준 식별자
  final String title;
  final String content;
  final String date;
  final List<String> imageUrls; // 표준화된 사진 리스트 필드명
  final String originalTitle;
  final String originalContent;
  final String proposerName;
  final bool isAnonymous; // 익명 제안 여부
  final String status; // approved, pending, deleted
  final String partsInfo;
  final String specInfo;
  final String relationInfo;
  final String createdAt;
  final String updatedAt;

  Guide({
    required this.id,
    required this.facilityId,
    required this.title,
    required this.content,
    required this.date,
    required this.imageUrls,
    required this.originalTitle,
    required this.originalContent,
    required this.proposerName,
    required this.isAnonymous,
    required this.status,
    required this.partsInfo,
    required this.specInfo,
    required this.relationInfo,
    required this.createdAt,
    required this.updatedAt,
  });

  // Firestore 데이터를 앱 객체로 변환 (역직렬화 및 데이터 복구)
  factory Guide.fromFirestore(Map<String, dynamic> json) {
    // 날짜 및 시간 데이터의 타입 안전성 확보
    String toSafeString(dynamic value) {
      if (value is Timestamp) return value.toDate().toString();
      return value?.toString() ?? '';
    }

    return Guide(
      id: json['id'] ?? '',
      // facilityId와 구버전 필드(companyId)를 통합하여 데이터 유실 방지
      facilityId: json['facilityId'] ?? json['companyId'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      date: json['date'] ?? '',
      // imageUrls와 구버전 필드(images)를 검색하여 사진 데이터 복구
      imageUrls: json['imageUrls'] != null
          ? List<String>.from(json['imageUrls'])
          : (json['images'] != null ? List<String>.from(json['images']) : []),
      originalTitle: json['originalTitle'] ?? json['title'] ?? '',
      originalContent: json['originalContent'] ?? json['content'] ?? '',
      proposerName: json['proposerName'] ?? '시스템',
      // 익명성 필드의 논리값 정밀 매핑
      isAnonymous: json['isAnonymous'] == true,
      status: json['status'] ?? 'approved',
      partsInfo: json['partsInfo'] ?? '',
      specInfo: json['specInfo'] ?? '',
      relationInfo: json['relationInfo'] ?? '',
      createdAt: toSafeString(json['createdAt'] ?? json['date']),
      updatedAt: toSafeString(json['updatedAt'] ?? json['date']),
    );
  }

  // 앱 데이터를 Firestore 저장 형식으로 변환 (직렬화)
  Map<String, dynamic> toFirestore() => {
    'id': id,
    'facilityId': facilityId, // 표준 명칭으로 일원화하여 저장
    'title': title,
    'content': content,
    'date': date,
    'imageUrls': imageUrls, // 'images' 대신 'imageUrls'로 필드명 고정
    'originalTitle': originalTitle,
    'originalContent': originalContent,
    'proposerName': proposerName,
    'isAnonymous': isAnonymous,
    'status': status,
    'partsInfo': partsInfo,
    'specInfo': specInfo,
    'relationInfo': relationInfo,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}