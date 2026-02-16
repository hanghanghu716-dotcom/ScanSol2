import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'signup_page.dart';
import 'user_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

// -----------------------------------------------------------
// [리디자인] 2. 로그인 페이지 (엔터프라이즈 분할 레이아웃)
// -----------------------------------------------------------
class _LoginPageState extends State<LoginPage> {
  final _facilityCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isAutoLoginChecked = false;

  Future<void> _handleLogin() async {
    // (기존 로직과 동일)
    String inputFacility = _facilityCtrl.text.trim();
    String inputId = _idCtrl.text.trim();
    String inputPw = _pwCtrl.text.trim();

    if (inputFacility.isEmpty || inputId.isEmpty || inputPw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("모든 정보를 입력해주세요.")));
      return;
    }
    setState(() => _isLoading = true);

    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('facilityId', isEqualTo: inputFacility)
          .where('userId', isEqualTo: inputId)
          .where('password', isEqualTo: inputPw)
          .get();

      if (query.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("일치하는 정보가 없거나 승인 대기 중입니다.")),
        );
      } else {
        final doc = query.docs.first;
        final user = UserModel.fromFirestore(doc);

        // [핵심 수정 부분] 로그인 정보 저장 로직 추가
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        if (_isAutoLoginChecked) {
          // 체크박스가 선택된 경우 기기에 고유 ID 저장
          await prefs.setString('userDocId', doc.id);
        } else {
          // 체크 해제 시 기존 저장 정보 삭제
          await prefs.remove('userDocId');
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => UserPage(user: user)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("로그인 중 오류 발생: $e")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 개발용 관리자 생성 (필요시 사용)
  Future<void> _createInitialAdmin() async {
    await FirebaseFirestore.instance.collection('users').add({
      'facilityId': 'KOGAS', 'userId': 'admin', 'password': '1234', 'role': 'ADMIN',
      'name': '최고관리자', 'department': '본사', 'status': 'approved',
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("관리자 계정 생성 완료")));
  }

  @override
  Widget build(BuildContext context) {
    // 반응형 레이아웃 분기
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return Row(
              children: [
                // [보강] 좌측 영역을 독립된 레이어로 분리하여 입력 시 버벅임 방지
                Expanded(child: RepaintBoundary(child: _buildBrandingSide())),
                Expanded(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 480),
                      padding: const EdgeInsets.all(48),
                      child: _buildLoginForm(isWeb: true),
                    ),
                  ),
                ),
              ],
            );
          } else {
            // [모바일] 수직 레이아웃
            return SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                  child: _buildLoginForm(isWeb: false),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  // [좌측] 브랜드 아이덴티티 영역 (웹 전용)
  Widget _buildBrandingSide() {
    return Container(
      color: const Color(0xFF1A237E), // Deep Navy
      padding: const EdgeInsets.all(60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_scanner, size: 80, color: Colors.white),
          const SizedBox(height: 32),
          Text("Smart Safety\nSolution", style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, height: 1.2)),
          const SizedBox(height: 24),
          Text(
            "산업 현장의 설비 이력을 QR코드로 한눈에.\n안전하고 효율적인 유지보수를 위한 최고의 파트너 ScanSol입니다.",
            style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.8), height: 1.6),
          ),
          const Spacer(),
          Text(
            "© 2026 KOGAS-Tech & ScanSol. All rights reserved.",
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
          ),
        ],
      ),
    );
  }

  // [우측] 로그인 폼 영역 (공통)
  Widget _buildLoginForm({required bool isWeb}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!isWeb) ...[
          const Center(child: Icon(Icons.qr_code_scanner, size: 64, color: Color(0xFF1A237E))),
          const SizedBox(height: 24),
          Center(
            child: Text(
              "ScanSol",
    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: const Color(0xFF1A237E)),

            ),
          ),
          const SizedBox(height: 40),
        ],
        Text(
          "로그인",
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          "계정 정보를 입력하여 시스템에 접속하세요.",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),

        _buildTextField(_facilityCtrl, "시설 번호", Icons.domain, false),
        const SizedBox(height: 16),
        _buildTextField(_idCtrl, "아이디", Icons.person_outline, false),
        const SizedBox(height: 16),
        _buildTextField(_pwCtrl, "비밀번호", Icons.lock_outline, true),

        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              height: 24, width: 24,
              child: Checkbox(
                value: _isAutoLoginChecked,
                onChanged: (v) => setState(() => _isAutoLoginChecked = v!),
                activeColor: const Color(0xFF1A237E),
              ),
            ),
            const SizedBox(width: 8),
            const Text("로그인 상태 유지"),
            const Spacer(),
            TextButton(
              onPressed: () {}, // 비밀번호 찾기 기능 연결 가능
              child: const Text("비밀번호 찾기", style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
        const SizedBox(height: 32),

        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading
                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("로그인"),
          ),
        ),

        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("계정이 없으신가요?"),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SignUpPage())),
              child: const Text("회원가입 신청", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        if (kDebugMode && !isWeb) // 모바일 디버그용
          TextButton(onPressed: _createInitialAdmin, child: const Text("관리자 생성 (Debug)")),
      ],
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, bool isObscure) {
    return TextField(
      controller: ctrl,
      obscureText: isObscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        // 테마에서 정의한 inputDecorationTheme이 자동 적용됨
      ),
    );
  }
}
