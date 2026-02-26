import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/guide_model.dart'; // [참고] 아까 만든 가이드 모델을 가져옵니다.

class FirebaseService {
  // Firestore 데이터베이스에 접근하기 위한 통로입니다.
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // [설명] 가이드 데이터를 클라우드에 저장하는 전용 함수입니다.
  // 기존의 saveGuideToCloud 기능을 이쪽으로 옮겨왔습니다.
  static Future<void> saveGuideToCloud(Guide guide) async {
    try {
      // 'guides'라는 문서함에 업체ID와 장비ID를 조합한 이름으로 저장합니다.
      await _firestore
          .collection('guides')
          .doc('${guide.facilityId}_${guide.id}')
          .set(guide.toFirestore());

      print("클라우드 저장 성공: ${guide.id}");
    } catch (e) {
      print("클라우드 저장 실패: $e");
      rethrow; // 오류가 발생하면 호출한 곳으로 알립니다.
    }
  }
}