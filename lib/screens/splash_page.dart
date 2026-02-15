import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'login_page.dart';
import 'user_page.dart'; // 곧 만들 파일이므로 미리 임포트합니다.

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
    await Future.delayed(const Duration(milliseconds: 1500));
    final prefs = await SharedPreferences.getInstance();
    final String? savedDocId = prefs.getString('userDocId');

    if (savedDocId != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(savedDocId).get();
        if (doc.exists) {
          final user = UserModel.fromFirestore(doc);
          if (user.status == 'approved') {
            if (!mounted) return;
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => UserPage(user: user)));
            return;
          }
        }
      } catch (e) { print("자동 로그인 실패: $e"); }
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.qr_code_scanner, size: 100, color: Colors.blue),
            SizedBox(height: 20),
            Text("ScanSol", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 10),
            Text("사용자 확인 중...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}