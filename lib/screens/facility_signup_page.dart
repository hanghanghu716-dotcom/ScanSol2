import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const Color kPrimaryBrandColor = Color(0xFF1A237E);

class FacilitySignUpPage extends StatefulWidget {
  const FacilitySignUpPage({super.key});

  @override
  State<FacilitySignUpPage> createState() => _FacilitySignUpPageState();
}

class _FacilitySignUpPageState extends State<FacilitySignUpPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  final _facilityIdCtrl = TextEditingController();
  final _facilityNameCtrl = TextEditingController();
  final _adminNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();

  String _selectedPlan = 'FREE';
  bool _isLoading = false;

  // 실시간 비밀번호 일치 확인을 위한 노티파이어
  final ValueNotifier<bool?> _isPwMatchNotifier = ValueNotifier<bool?>(null);

  @override
  void dispose() {
    _facilityIdCtrl.dispose();
    _facilityNameCtrl.dispose();
    _adminNameCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    _isPwMatchNotifier.dispose();
    super.dispose();
  }

  // 비밀번호 실시간 체크
  void _checkPasswordMatch() {
    if (_pwConfirmCtrl.text.isEmpty) {
      _isPwMatchNotifier.value = null;
    } else {
      _isPwMatchNotifier.value = _pwCtrl.text == _pwConfirmCtrl.text;
    }
  }

  // 비밀번호 복잡성 검증 (영문+숫자+특수문자 8자 이상)
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return "비밀번호를 입력하세요.";
    final regExp = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[@$!%*#?&])[A-Za-z\d@$!%*#?&]{8,}$');
    if (!regExp.hasMatch(value)) return "양식을 확인해 주세요.";
    return null;
  }

  // [중요] 복구/전환 안내 다이얼로그
  void _showRecoveryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("이미 등록된 계정"),
        content: const Text("이 이메일은 이미 일반 사용자로 가입 신청이 되어 있습니다.\n기존 신청을 취소하고 이 사업장의 '최고 관리자'로 전환하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("아니오")),
          ElevatedButton(
            onPressed: () {
              // 복구 프로세스: 관리자 안내 메시지 노출
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("기존 계정 정보를 관리자에게 문의하여 초기화한 후 재시도하십시오."),
                    duration: Duration(seconds: 5),
                  )
              );
            },
            child: const Text("전환 방법 확인"),
          ),
        ],
      ),
    );
  }

  Future<void> _registerFacility() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_pwCtrl.text != _pwConfirmCtrl.text) return;

    setState(() => _isLoading = true);

    try {
      // 1. 사업장 코드 중복 체크
      final facilityDoc = await _firestore.collection('facilities').doc(_facilityIdCtrl.text.trim()).get();
      if (facilityDoc.exists) throw '이미 존재하는 사업장 코드입니다.';

      // 2. Firebase Auth 계정 생성
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text.trim(),
      );

      User? user = userCredential.user;

      if (user != null) {
        // 3. 이메일 인증 발송
        await user.sendEmailVerification();

        // 4. Batch 작업으로 사업장 정보 + 사용자 정보 저장
        WriteBatch batch = _firestore.batch();
        int maxMaps = _selectedPlan == 'PRO' ? 100 : 3;
        int maxGuides = _selectedPlan == 'PRO' ? 300 : 10;

        batch.set(_firestore.collection('facilities').doc(_facilityIdCtrl.text.trim()), {
          'facilityId': _facilityIdCtrl.text.trim(),
          'facilityName': _facilityNameCtrl.text.trim(),
          'planType': _selectedPlan,
          'maxMaps': maxMaps,
          'maxGuides': maxGuides,
          'adminEmail': _emailCtrl.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        batch.set(_firestore.collection('users').doc(user.uid), {
          'email': _emailCtrl.text.trim(),
          'facilityId': _facilityIdCtrl.text.trim(),
          'name': _adminNameCtrl.text.trim(),
          'department': '관리본부',
          'role': 'SUPER_ADMIN',
          'status': 'approved',
          'createdAt': FieldValue.serverTimestamp(),
        });

        await batch.commit();
        if (!mounted) return;
        _showSuccessDialog();
      }
    } on FirebaseAuthException catch (e) {
      // [교정] 이메일 중복 시 복구 다이얼로그 호출
      if (e.code == 'email-already-in-use') {
        _showRecoveryDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("오류: ${e.message}"), backgroundColor: Colors.red)
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("오류: $e"), backgroundColor: Colors.red)
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("사업장 등록 완료"),
        content: const Text("최고 관리자 계정 생성 및 사업장 등록이 완료되었습니다.\n이메일 인증 후 로그인이 가능합니다."),
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
          const Icon(Icons.business_center, size: 80, color: Colors.white),
          const SizedBox(height: 32),
          const Text("Partner with\nScanSol", style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, height: 1.2)),
          const SizedBox(height: 24),
          const Text("새로운 사업장을 등록하고 스마트한 안전 관리를 시작하세요.\n최고 관리자 계정은 요금제 관리 및 전 직원의 승인 권한을 가집니다.", style: TextStyle(fontSize: 18, color: Colors.white70)),
          const Spacer(),
          const Text("© 2026 ScanSol B2B Solution.", style: TextStyle(fontSize: 12, color: Colors.white54)),
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
          const Text("신규 사업장 등록", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: kPrimaryBrandColor)),
          const SizedBox(height: 32),
          _buildTextField(_facilityIdCtrl, "사업장 고유 코드", Icons.vpn_key),
          const SizedBox(height: 16),
          _buildTextField(_facilityNameCtrl, "사업장 명칭", Icons.domain),
          const SizedBox(height: 16),
          _buildPlanDropdown(),
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider()),
          const Text("최고 관리자 정보", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildTextField(_adminNameCtrl, "관리자 성명", Icons.person_outline),
          const SizedBox(height: 16),
          _buildTextField(_emailCtrl, "관리자 이메일 주소", Icons.email_outlined, keyboardType: TextInputType.emailAddress),
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
              onPressed: _isLoading ? null : _registerFacility,
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBrandColor, foregroundColor: Colors.white),
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("사업장 개설 및 가입하기"),
            ),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소하고 돌아가기")),
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
      validator: validator ?? (v) => v == null || v.isEmpty ? "필수 입력 항목입니다." : null,
    );
  }

  Widget _buildPlanDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedPlan,
      decoration: const InputDecoration(labelText: "구독 요금제 선택", prefixIcon: Icon(Icons.credit_card)),
      items: const [
        DropdownMenuItem(value: 'FREE', child: Text("FREE (맵 3 / 가이드 10)")),
        DropdownMenuItem(value: 'PRO', child: Text("PRO (맵 100 / 가이드 300)")),
      ],
      onChanged: (v) => setState(() => _selectedPlan = v!),
    );
  }
}