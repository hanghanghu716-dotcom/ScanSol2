import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Color kPrimaryBrandColor = Color(0xFF1A237E);

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _auth = FirebaseAuth.instance;
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      // 1. Firebase에 비밀번호 재설정 메일 요청
      await _auth.sendPasswordResetEmail(email: _emailCtrl.text.trim());

      if (!mounted) return;

      // 2. 성공 시에만 성공 다이얼로그 표시
      _showSuccessDialog();

    } on FirebaseAuthException catch (e) {
      // [교정] 없는 이메일일 경우 "링크 송부" 알람 대신 에러 알람 표시
      String message = "메일 발송 중 오류가 발생했습니다.";

      if (e.code == 'user-not-found') {
        message = "해당 이메일로 가입된 계정 정보가 없습니다.";
      } else if (e.code == 'invalid-email') {
        message = "유효하지 않은 이메일 형식입니다.";
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.orange)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("오류: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("메일 발송 완료"),
        content: const Text("비밀번호 재설정 링크가 발송되었습니다.\n메일함을 확인해 주세요."),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text("확인"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return Row(
              children: [
                Expanded(child: _buildBrandingSide()),
                Expanded(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 480),
                      padding: const EdgeInsets.all(48),
                      child: _buildForgotForm(isWeb: true),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: _buildForgotForm(isWeb: false),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildBrandingSide() {
    return Container(
      color: kPrimaryBrandColor,
      padding: const EdgeInsets.all(60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_open, size: 80, color: Colors.white),
          const SizedBox(height: 32),
          const Text("Secure\nRecovery", style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, height: 1.2)),
          const SizedBox(height: 24),
          const Text("비밀번호를 잊으셨나요?\n등록된 이메일 주소로 안전하게 초기화 링크를 보내드립니다.", style: TextStyle(fontSize: 18, color: Colors.white70, height: 1.6)),
          const Spacer(),
          const Text("ScanSol Security Team", style: TextStyle(fontSize: 12, color: Colors.white30)),
        ],
      ),
    );
  }

  Widget _buildForgotForm({required bool isWeb}) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!isWeb) const Center(child: Icon(Icons.lock_reset, size: 64, color: kPrimaryBrandColor)),
          const SizedBox(height: 24),
          const Text("비밀번호 찾기", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: kPrimaryBrandColor)),
          const SizedBox(height: 40),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: "가입 시 사용한 이메일", prefixIcon: Icon(Icons.email_outlined)),
            validator: (v) => (v == null || v.isEmpty) ? "이메일을 입력해 주세요." : null,
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendResetEmail,
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBrandColor, foregroundColor: Colors.white),
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("재설정 메일 보내기"),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("로그인 화면으로 돌아가기")),
        ],
      ),
    );
  }
}