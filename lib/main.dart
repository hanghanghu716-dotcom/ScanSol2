import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';

// [중요] 분리된 설정 및 첫 페이지 연결
import 'firebase_options.dart';
import 'package:scansol2/screens/splash_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // [수정] 웹에서 폰트를 가져오는 기능을 완전히 끕니다.
  // pubspec.yaml에 등록된 로컬 에셋만 사용하게 되어 로딩 속도가 비약적으로 향상됩니다.
  GoogleFonts.config.allowRuntimeFetching = false;

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ScanSolApp());
}

class ScanSolApp extends StatelessWidget {
  const ScanSolApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 폰트 패밀리명을 변수로 추출하여 일관성을 확보합니다.

    return MaterialApp(
      title: 'ScanSol',
      debugShowCheckedModeBanner: false,

      // -----------------------------------------------------------
      // [전역 테마 설정] 모바일 디자인 오류 해결을 위한 보강
      // -----------------------------------------------------------
      theme: ThemeData(
        useMaterial3: true,
        // [확인] 아래의 family 이름이 pubspec.yaml의 family 이름과 정확히 일치해야 합니다.
        fontFamily: 'NotoSansKR',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E),
          primary: const Color(0xFF1A237E),
          onPrimary: Colors.white,
          secondary: const Color(0xFFFFA000),
          onSecondary: Colors.black,
          error: const Color(0xFFD32F2F),
          background: const Color(0xFFF0F2F5),
          surface: Colors.white,
          outline: const Color(0xFFBDBDBD),
        ),

        // [보강] 아이콘이 깨지는 현상을 방지하기 위한 아이콘 테마 설정
        iconTheme: const IconThemeData(
          color: Color(0xFF1A237E),
          size: 24,
        ),

        // [최적화] 모바일 및 웹 공용 텍스트 테마 설정
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFF1A237E)),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF212121)),
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: Color(0xFF424242)),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A237E),
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 2,
        ),

        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2)),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),

        // 플랫폼별 최적화된 페이지 전환 애니메이션
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          },
        ),
      ),

      // 앱 시작 시 가장 먼저 보여줄 화면
      home: const SplashPage(),
    );
  }
}