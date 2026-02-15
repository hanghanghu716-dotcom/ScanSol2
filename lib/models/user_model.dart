import 'package:cloud_firestore/cloud_firestore.dart';

// [설명] 로그인한 사용자(직원)의 정보를 정의하는 파일입니다.
class UserModel {
  String docId;
  String facilityId;
  String userId;
  String password;
  String role;
  String name;
  String department;
  String status;

  UserModel({
    required this.docId,
    required this.facilityId,
    required this.userId,
    required this.password,
    required this.role,
    required this.name,
    required this.department,
    required this.status,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      docId: doc.id,
      facilityId: data['facilityId'] ?? '',
      userId: data['userId'] ?? '',
      password: data['password'] ?? '',
      role: data['role'] ?? 'USER',
      name: data['name'] ?? '',
      department: data['department'] ?? '미소속',
      status: data['status'] ?? 'approved',
    );
  }
}