import 'package:cloud_firestore/cloud_firestore.dart';

/// [설명] Firebase Auth 및 이메일 기반 인증 체계로 개편된 사용자 모델입니다.
/// 보안을 위해 비밀번호는 모델에 포함하지 않으며, Firebase Auth에서 관리합니다.
class UserModel {
  final String docId;      // Firestore 문서 ID (Auth UID와 일치 권장)
  final String email;      // 로그인용 이메일 주소 [신규]
  final String facilityId; // 소속 사업장 고유 코드
  final String name;       // 성명
  final String department; // 소속 부서
  final String role;       // 권한: SUPER_ADMIN, ADMIN, USER [확장]
  final String status;     // 상태: approved, pending

  UserModel({
    required this.docId,
    required this.email,
    required this.facilityId,
    required this.name,
    required this.department,
    required this.role,
    required this.status,
  });

  /// Firestore 문서를 클래스 인스턴스로 변환하는 팩토리 생성자
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return UserModel(
      docId: doc.id,
      email: data['email'] ?? '',
      facilityId: data['facilityId'] ?? '',
      name: data['name'] ?? '',
      department: data['department'] ?? '미소속',
      role: data['role'] ?? 'USER',
      status: data['status'] ?? 'pending', // 기본값은 승인 대기로 설정
    );
  }

  /// 인스턴스를 Firestore에 저장하기 위한 Map 형태로 변환
  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'facilityId': facilityId,
      'name': name,
      'department': department,
      'role': role,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}