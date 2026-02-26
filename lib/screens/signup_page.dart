import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'facility_signup_page.dart';

const Color kPrimaryBrandColor = Color(0xFF1A237E);

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  final _facilityCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();

  bool _isLoading = false;

  // 실시간 피드백을 위한 ValueNotifier
  final ValueNotifier<bool?> _isPwMatchNotifier = ValueNotifier<bool?>(null);

  @override
  void dispose() {
    _facilityCtrl.dispose();
    _deptCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    _isPwMatchNotifier.dispose();
    super.dispose();
  }

  void _checkPasswordMatch() {
    if (_pwConfirmCtrl.text.isEmpty) {
      _isPwMatchNotifier.value = null;
    } else {
      _isPwMatchNotifier.value = _pwCtrl.text == _pwConfirmCtrl.text;
    }
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return "비밀번호를 입력하세요.";
    final regExp = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[@$!%*#?&])[A-Za-z\d@$!%*#?&]{8,}$');
    if (!regExp.hasMatch(value)) return "양식을 확인해 주세요.";
    return null;
  }

  Future<void> _submitSignUp() async {
    // 1. 기본 입력 유효성 및 비밀번호 일치 확인
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_pwCtrl.text != _pwConfirmCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("비밀번호가 일치하지 않습니다."), backgroundColor: Colors.red)
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // -----------------------------------------------------------
      // [신규 보완] 사업장 코드(시설 번호) 존재 여부 사전 검증
      // -----------------------------------------------------------
      final String inputFacilityId = _facilityCtrl.text.trim();

      // facilities 컬렉션에서 해당 ID를 문서명(Doc ID)으로 가진 데이터를 조회합니다.
      final facilityDoc = await _firestore.collection('facilities').doc(inputFacilityId).get();

      if (!facilityDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("존재하지 않는 시설 번호입니다. 관리자에게 문의하여 정확한 코드를 입력해 주세요."),
                backgroundColor: Colors.orange,
              )
          );
        }
        setState(() => _isLoading = false);
        return; // 존재하지 않는 코드일 경우 가입 절차를 즉시 중단합니다.
      }
      // -----------------------------------------------------------

      // 2. Firebase Auth 계정 생성
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text.trim(),
      );

      User? user = userCredential.user;

      if (user != null) {
        // 3. 이메일 인증 메일 발송
        await user.sendEmailVerification();

        // 4. Firestore에 사용자 상세 정보 저장 (status: pending)
        await _firestore.collection('users').doc(user.uid).set({
          'email': _emailCtrl.text.trim(),
          'facilityId': inputFacilityId,
          'name': _nameCtrl.text.trim(),
          'department': _deptCtrl.text.trim(),
          'role': 'USER',
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        _showSuccessDialog();
      }
    } on FirebaseAuthException catch (e) {
      String message = "회원가입 실패";
      if (e.code == 'email-already-in-use') {
        message = "이미 사용 중인 이메일입니다.";
      } else if (e.code == 'weak-password') {
        message = "비밀번호가 너무 취약합니다.";
      } else {
        message = "인증 오류: ${e.message}";
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.red)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("오류 발생: $e"), backgroundColor: Colors.red)
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
        title: const Text("가입 신청 완료"),
        content: const Text("이메일 인증 후, 관리자 승인이 완료되면 서비스 이용이 가능합니다."),
        actions: [TextButton(onPressed: () { Navigator.pop(context); Navigator.pop(context); }, child: const Text("확인"))],
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
                      constraints: const BoxConstraints(maxWidth: 550),
                      padding: const EdgeInsets.all(48),
                      child: _buildSignUpForm(isWeb: true),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: _buildSignUpForm(isWeb: false),
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
          const Icon(Icons.person_add_alt_1, size: 80, color: Colors.white),
          const SizedBox(height: 32),
          const Text("Join\nScanSol", style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, height: 1.2)),
          const SizedBox(height: 24),
          const Text("스마트 안전 관리의 시작.\n소속 사업장 코드를 입력하여 팀에 합류하세요.", style: TextStyle(fontSize: 18, color: Colors.white70)),
          const Spacer(),
          const Text("© 2026 ScanSol System.", style: TextStyle(fontSize: 12, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildSignUpForm({required bool isWeb}) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("사용자 회원가입", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: kPrimaryBrandColor)),
          const SizedBox(height: 32),
          _buildTextField(_facilityCtrl, "시설 번호", Icons.business),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildTextField(_deptCtrl, "소속 부서", Icons.group)),
              const SizedBox(width: 16),
              Expanded(child: _buildTextField(_nameCtrl, "성명", Icons.badge)),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(_emailCtrl, "이메일 주소", Icons.email_outlined, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 16),
          _buildTextField(
            _pwCtrl, "비밀번호", Icons.lock_outline,
            isObscure: true,
            validator: _validatePassword,
            helperText: "영문, 숫자, 특수문자 포함 8자 이상",
            onChanged: (_) => _checkPasswordMatch(),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<bool?>(
            valueListenable: _isPwMatchNotifier,
            builder: (context, isMatch, child) {
              return TextFormField(
                controller: _pwConfirmCtrl,
                obscureText: true,
                onChanged: (_) => _checkPasswordMatch(),
                decoration: InputDecoration(
                  labelText: "비밀번호 확인",
                  prefixIcon: const Icon(Icons.lock_reset),
                  suffixIcon: isMatch == null
                      ? null
                      : Icon(isMatch ? Icons.check_circle : Icons.error, color: isMatch ? Colors.green : Colors.red),
                ),
                validator: (v) => v != _pwCtrl.text ? "비밀번호가 일치하지 않습니다." : null,
              );
            },
          ),
          const SizedBox(height: 40),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitSignUp,
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBrandColor, foregroundColor: Colors.white),
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("가입 신청하기"),
            ),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("로그인으로 돌아가기")),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, {bool isObscure = false, TextInputType? keyboardType, String? Function(String?)? validator, String? helperText, void Function(String)? onChanged}) {
    return TextFormField(
      controller: ctrl,
      obscureText: isObscure,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), helperText: helperText),
      validator: validator ?? (v) => v == null || v.isEmpty ? "필수 입력입니다." : null,
    );
  }
}