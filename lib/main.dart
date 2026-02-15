import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';

// [중요] 분리된 설정 및 첫 페이지 연결
import 'firebase_options.dart';
import 'package:scansol2/screens/splash_page.dart';

void main() async {
  // Flutter 엔진 초기화
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화 (DefaultFirebaseOptions는 firebase_options.dart에서 제공)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const ScanSolApp());
}

class ScanSolApp extends StatelessWidget {
  const ScanSolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScanSol',
      debugShowCheckedModeBanner: false,

      // -----------------------------------------------------------
      // [전역 테마 설정] 앱 전체의 일관된 디자인 가이드를 정의합니다.
      // -----------------------------------------------------------
      theme: ThemeData(
        useMaterial3: true,
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

        // 폰트 깨짐 방지를 위한 Noto Sans KR 및 Fallback 설정
        textTheme: GoogleFonts.notoSansKrTextTheme().apply(
          fontFamilyFallback: [
            'Malgun Gothic',
            'Apple SD Gothic Neo',
            'Dotum',
            'sans-serif',
          ],
        ).copyWith(
          headlineLarge: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Color(0xFF1A237E)),
          titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.25, color: Color(0xFF212121)),
          bodyLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5, color: Color(0xFF424242)),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A237E),
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 2,
        ),

        cardTheme: CardTheme(
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