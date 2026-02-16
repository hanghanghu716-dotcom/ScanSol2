// lib/screens/splash_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'login_page.dart';
import 'user_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    try {
      // 1. 최소 노출 시간 확보 (1.5초)
      await Future.delayed(const Duration(milliseconds: 1500));

      // 2. 인스턴스 획득 분리 (예외 발생 가능 지점)
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? savedDocId = prefs.getString('userDocId');

      if (savedDocId != null) {
        // 3. Firestore 데이터 검증 (타임아웃 설정 권장)
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(savedDocId)
            .get();

        if (doc.exists) {
          final user = UserModel.fromFirestore(doc);
          if (user.status == 'approved') {
            if (!mounted) return;
            _navigateToNext(UserPage(user: user));
            return;
          }
        }
      }
    } catch (e) {
      // 에러 발생 시 로그를 남기고 로그인 페이지로 강제 이동
      debugPrint("초기화 및 자동 로그인 중 오류 발생: $e");
    } finally {
      // 어떤 상황에서도 마지막엔 로그인 페이지로 이동하여 화면 멈춤 방지
      if (mounted) {
        _navigateToNext(const LoginPage());
      }
    }
  }

  // 내비게이션 로직 공통화
  void _navigateToNext(Widget page) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A237E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner, size: 80, color: Colors.white),
            const SizedBox(height: 24),
            const Text(
              "ScanSol",
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            const Text(
              "시스템 보안 연결 중...",
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}