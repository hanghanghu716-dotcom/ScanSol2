// [설명] 가이드 데이터의 형식을 정의하는 파일입니다.
import 'package:cloud_firestore/cloud_firestore.dart';

class Guide {
  String id;
  String companyId;
  String title;
  String content;
  String date;
  List<String> imageUrls;
  String originalTitle;
  String originalContent;
  String proposerName;
  bool isAnonymous;
  String status;
  String partsInfo;
  String specInfo;
  String relationInfo;
  String createdAt;
  String updatedAt;

  Guide({
    required this.id,
    required this.companyId,
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

  // Firestore(클라우드)에서 데이터를 가져올 때 사용하는 도구입니다.
  factory Guide.fromFirestore(Map<String, dynamic> json) {
    // 어떤 타입이 들어와도 문자열로 안전하게 바꿔주는 로직
    String toStr(dynamic value) {
      if (value is Timestamp) return value.toDate().toString(); // 타임스탬프면 변환
      return value?.toString() ?? ''; // 나머지는 문자열화
    }

    return Guide(
      id: json['id'] ?? '',
      companyId: json['companyId'] ?? 'KOGAS_WANJU',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      date: json['date'] ?? '',
      imageUrls: List<String>.from(json['imageUrls'] ?? []),
      originalTitle: json['originalTitle'] ?? json['title'] ?? '',
      originalContent: json['originalContent'] ?? json['content'] ?? '',
      proposerName: json['proposerName'] ?? '관리자',
      isAnonymous: json['isAnonymous'] ?? false,
      status: json['status'] ?? 'approved',
      partsInfo: json['partsInfo'] ?? '',
      specInfo: json['specInfo'] ?? '',
      relationInfo: json['relationInfo'] ?? '',
      // 수정 포인트: 안전하게 변환하여 대입
      createdAt: toStr(json['createdAt'] ?? json['date']),
      updatedAt: toStr(json['updatedAt'] ?? json['date']),
    );
  }
  // 데이터를 Firestore(클라우드)에 저장하기 쉬운 형태로 변환하는 도구입니다.
  Map<String, dynamic> toFirestore() => {
    'id': id,
    'companyId': companyId,
    'title': title,
    'content': content,
    'date': date,
    'imageUrls': imageUrls,
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