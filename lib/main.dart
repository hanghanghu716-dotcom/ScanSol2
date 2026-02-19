import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 패키지 설치 후 에러가 사라집니다.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

// [중요] 사용자님의 프로젝트 실제 폴더 구조에 맞게 아래 import 경로를 확인하십시오.
import 'firebase_options.dart';
import 'models/user_model.dart';
import 'screens/splash_page.dart';
import 'screens/login_page.dart';
import 'screens/user_page.dart'; // UserPage로 연결

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 웹에서 폰트를 가져오는 기능을 꺼서 로딩 속도를 향상시킵니다.
  GoogleFonts.config.allowRuntimeFetching = false;

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
      // [기존 테마 설정] 사용자님의 디자인 시스템 보존
      // -----------------------------------------------------------
      theme: ThemeData(
        useMaterial3: true,
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

        iconTheme: const IconThemeData(
          color: Color(0xFF1A237E),
          size: 24,
        ),

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

        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          },
        ),
      ),

      // -----------------------------------------------------------
      // [핵심 로직] 새로고침 시 인증 상태 유지 및 UserPage 분기
      // -----------------------------------------------------------
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          // 1. Firebase Auth가 토큰을 확인 중인 상태
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const SplashPage();
          }

          // 2. 로그인 세션이 발견된 경우
          if (authSnapshot.hasData && authSnapshot.data != null) {
            return FutureBuilder<DocumentSnapshot>(
              // Firebase Auth UID와 일치하는 Firestore 문서 조회
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(authSnapshot.data!.uid)
                  .get(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const SplashPage();
                }

                // Firestore에 사용자 데이터가 존재하는 경우
                if (userSnapshot.hasData && userSnapshot.data!.exists) {
                  final userModel = UserModel.fromFirestore(userSnapshot.data!);
                  // UserPage로 유저 정보를 전달하며 화면 이동
                  return UserPage(user: userModel);
                }

                // 인증은 되었으나 데이터베이스에 정보가 없는 경우 로그인 화면으로
                return const LoginPage();
              },
            );
          }

          // 3. 로그아웃 상태이거나 세션이 없는 경우
          return const LoginPage();
        },
      ),
    );
  }
}