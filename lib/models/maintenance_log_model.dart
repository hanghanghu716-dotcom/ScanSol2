import 'package:cloud_firestore/cloud_firestore.dart';

// [설명] 현장의 정비 활동을 기록하기 위한 데이터 규격입니다.
class MaintenanceLog {
  final String id;        // 로그의 고유 번호
  final String type;      // 유형 (REPAIR: 수리, CHECK: 점검, ISSUE: 장애)
  final String title;     // 로그 제목
  final String userName;  // 기록한 사람 이름
  final DateTime date;    // 발생한 시각

  MaintenanceLog({
    required this.id,
    required this.type,
    required this.title,
    required this.userName,
    required this.date,
  });

  // [중요] Firestore(서버)에서 받은 데이터를 앱에서 쓸 수 있게 변환하는 도구입니다.
  factory MaintenanceLog.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return MaintenanceLog(
      id: doc.id,
      type: data['type'] ?? 'CHECK',
      title: data['title'] ?? '',
      userName: data['userName'] ?? '관리자',
      // 서버의 타임스탬프 형식을 앱의 시각 형식으로 바꿉니다.
      date: (data['date'] as Timestamp? ?? Timestamp.now()).toDate(),
    );
  }
}