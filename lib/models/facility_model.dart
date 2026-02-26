class FacilityModel {
  final String facilityId;
  final String facilityName;
  final String planType; // 'FREE', 'PRO'
  final int maxMaps;
  final int maxGuides;

  FacilityModel({
    required this.facilityId,
    required this.facilityName,
    required this.planType,
    required this.maxMaps,
    required this.maxGuides,
  });

  Map<String, dynamic> toMap() {
    return {
      'facilityId': facilityId,
      'facilityName': facilityName,
      'planType': planType,
      'maxMaps': maxMaps,
      'maxGuides': maxGuides,
    };
  }

  factory FacilityModel.fromFirestore(Map<String, dynamic> data) {
    return FacilityModel(
      facilityId: data['facilityId'] ?? '',
      facilityName: data['facilityName'] ?? '',
      planType: data['planType'] ?? 'FREE',
      maxMaps: data['maxMaps'] ?? 3,
      maxGuides: data['maxGuides'] ?? 10,
    );
  }
}