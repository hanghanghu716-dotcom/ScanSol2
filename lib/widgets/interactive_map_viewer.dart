import 'package:flutter/material.dart';
import '../models/guide_map_model.dart';

class InteractiveMapViewer extends StatefulWidget {
  final GuideMap guideMap;

  const InteractiveMapViewer({super.key, required this.guideMap});

  @override
  State<InteractiveMapViewer> createState() => _InteractiveMapViewerState();
}

class _InteractiveMapViewerState extends State<InteractiveMapViewer> {
  // [핵심] 이미지의 실제 렌더링 크기를 측정하기 위한 GlobalKey와 변수
  final GlobalKey _imageKey = GlobalKey();
  final TransformationController _transformationController = TransformationController();
  Size _renderedImageSize = Size.zero;

  @override
  void initState() {
    super.initState();
    // [정석] 화면이 그려진 직후 이미지의 크기를 측정하여 좌표를 동기화합니다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateImageSize());
  }

  // 실제 이미지 위젯의 크기를 계산하여 상태를 업데이트하는 함수
  void _updateImageSize() {
    final RenderBox? renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && mounted) {
      final size = renderBox.size;
      if (_renderedImageSize != size) {
        setState(() {
          _renderedImageSize = size;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return InteractiveViewer(
          transformationController: _transformationController,
          maxScale: 5.0,
          minScale: 1.0,
          child: Center(
            child: Stack(
              children: [
                // 1. [핵심] 에디터와 동일한 GlobalKey와 fit 옵션을 사용하여 기준점을 일치시킵니다.
                Image.network(
                  widget.guideMap.imageUrl,
                  key: _imageKey,
                  fit: BoxFit.contain,
                  // 이미지가 로드될 때마다 크기를 재측정하여 오차를 방지합니다.
                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                    if (frame != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => _updateImageSize());
                    }
                    return child;
                  },
                ),

                // 2. [핵심] 이미지 크기가 정확히 측정된 후에만 태그를 배치합니다.
                if (_renderedImageSize != Size.zero)
                // [교정] 75행 부근의 Positioned 내부 코드
                  ...widget.guideMap.tags.map((tag) => Positioned(
                    left: tag.dx * _renderedImageSize.width,
                    top: tag.dy * _renderedImageSize.height,
                    child: InkWell(
                      onTap: () => _handleTagTap(context, tag.guideId),
                      child: Stack(
                        clipBehavior: Clip.none, // 아이콘이 박스 밖으로 튀어나와도 잘리지 않게 설정
                        children: [
                          // 1. 노란 박스 (내부 텍스트 제거 및 투명도 최적화)
                          Container(
                            width: tag.width * _renderedImageSize.width,
                            height: tag.height * _renderedImageSize.height,
                            decoration: BoxDecoration(
                              color: Colors.yellow.withOpacity(0.05), // 현장 사진 시야 확보
                              border: Border.all(color: Colors.yellow, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          // 2. [교정 핵심] 우측 상단 QR 아이콘 대폭 확대 (14 -> 30)
                          Positioned(
                            top: -15, // 아이콘이 커진 만큼 위치 조정
                            right: -15,
                            child: Container(
                              padding: const EdgeInsets.all(6), // 터치 및 시인성 확보
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A237E),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, spreadRadius: 1)
                                ],
                              ),
                              child: const Icon(
                                Icons.qr_code_2,
                                color: Colors.white,
                                size: 24, // [결정적 교정] 이제 현장에서 확실히 보입니다.
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleTagTap(BuildContext context, String guideId) {
    // [향후 확장] 여기서 가이드 상세 페이지로 바로 이동하도록 구현 예정입니다.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("장비 ID: $guideId 상세 정보 조회 중..."),
        backgroundColor: const Color(0xFF1A237E),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}