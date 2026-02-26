import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Firebase Auth 추가
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import 'facility_signup_page.dart';
import 'forgot_password_page.dart';
import 'signup_page.dart';
import 'user_page.dart';

const String kUsersCollection = 'users';
const String kKeyUserDocId = 'userDocId';
const Color kPrimaryBrandColor = Color(0xFF1A237E);

// -----------------------------------------------------------
// [비즈니스 로직] Firebase Auth 연동으로 인증 강화
// -----------------------------------------------------------
// lib/services/auth_service.dart (또는 login_page.dart 내 클래스)

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<UserModel?> login(String facilityId, String email, String password, bool keepLogin) async {
    try {
      // 1. Firebase Auth 인증 시도
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? firebaseUser = userCredential.user;

      if (firebaseUser == null) throw 'user-not-found';

      // 2. 이메일 인증 여부 확인 [신규Requirement 반영]
      if (!firebaseUser.emailVerified) {
        throw 'email-not-verified';
      }

      // 3. Firestore에서 소속 및 승인 상태 확인
      final doc = await _firestore.collection('users').doc(firebaseUser.uid).get();
      if (!doc.exists) throw 'user-not-found';

      final user = UserModel.fromFirestore(doc);

      // 시설 코드 대조 및 승인 상태 확인
      if (user.facilityId != facilityId) throw 'wrong-facility';
      if (user.status != 'approved') throw 'pending-user';

      // 4. 로그인 유지 설정 (보안 스토리지)
      if (keepLogin) {
        await _secureStorage.write(key: 'userDocId', value: firebaseUser.uid);
      } else {
        await _secureStorage.delete(key: 'userDocId');
      }

      return user;
    } on FirebaseAuthException catch (e) {
      // Firebase Auth 전용 에러 전달
      throw e.code;
    } catch (e) {
      // 기타(이메일 미인증 등) 커스텀 에러 전달
      rethrow;
    }
  }

  // 인증 메일 재발송 (남용 방지는 UI에서 쿨타임으로 제어)
  Future<void> resendVerificationEmail(User user) async {
    await user.sendEmailVerification();
  }
}
// -----------------------------------------------------------
// [UI 레이어] 이메일 기반 로그인 UI 개편
// -----------------------------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _facilityCtrl = TextEditingController();
  final _emailCtrl = TextEditingController(); // id에서 email로 변경
  final _pwCtrl = TextEditingController();

  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isAutoLoginNotifier = ValueNotifier<bool>(false);
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _facilityCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _isLoadingNotifier.dispose();
    _isAutoLoginNotifier.dispose();
    super.dispose();
  }

  // LoginPage 클래스 내부에 추가될 함수
  void _showVerificationResendDialog(User user) {
    int cooldown = 60; // 60초 쿨타임

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("이메일 인증 필요"),
        content: const Text("가입하신 이메일의 소유권 확인이 완료되지 않았습니다.\n메일함(스팸함 포함)을 확인해 주십시오."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("닫기")),
          ElevatedButton(
            onPressed: () async {
              // [서버사이드 제한 체크 로직 필요]
              await user.sendEmailVerification();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("인증 메일이 재발송되었습니다. (다음 발송은 1분 후 가능)"))
                );
              }
            },
            child: const Text("인증 메일 재발송"),
          ),
        ],
      ),
    );
  }

  // login_page.dart 내 _LoginPageState 클래스 내부

  // 재발송 쿨타임 관리를 위한 변수
  DateTime? _lastResendTime;

  Future<void> _handleLogin() async {
    // 폼 유효성 검사
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _isLoadingNotifier.value = true;

    try {
      // AuthService를 통한 로그인 시도
      final user = await _authService.login(
        _facilityCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _pwCtrl.text.trim(),
        _isAutoLoginNotifier.value,
      );

      if (mounted && user != null) {
        // 로그인 성공 시 대시보드로 이동
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => UserPage(user: user))
        );
      }
    } catch (e) {
      if (!mounted) return;

      // [교정] 에러 코드별 상세 메시지 할당
      String message = "로그인에 실패했습니다.";

      if (e == 'email-not-verified') {
        _showResendVerificationDialog(); // 이메일 인증 미완료 다이얼로그
        return;
      } else if (e == 'user-not-found' || e == 'invalid-email') {
        message = "등록되지 않은 이메일 주소이거나 이메일 형식이 잘못되었습니다.";
      } else if (e == 'wrong-password' || e == 'invalid-credential') {
        message = "비밀번호가 틀렸습니다. 다시 확인해 주세요.";
      } else if (e == 'wrong-facility') {
        message = "입력하신 시설 번호가 소속 정보와 일치하지 않습니다.";
      } else if (e == 'pending-user') {
        message = "아직 관리자의 승인이 완료되지 않은 계정입니다.";
      } else if (e == 'user-disabled') {
        message = "관리자에 의해 비활성화된 계정입니다.";
      } else if (e == 'too-many-requests') {
        message = "너무 많은 로그인 시도가 감지되었습니다. 잠시 후 다시 시도해 주세요.";
      }

      // 사용자에게 실패 원인 알림
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          )
      );
    } finally {
      _isLoadingNotifier.value = false;
    }
  }
  // [신규] 이메일 인증 재발송 다이얼로그 (쿨타임 적용)
  void _showResendVerificationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("이메일 인증 확인"),
        content: const Text("가입하신 이메일의 인증이 완료되지 않았습니다.\n인증 메일을 받지 못하셨나요?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          ElevatedButton(
            onPressed: () async {
              // 남용 방지: 60초 쿨타임 체크
              if (_lastResendTime != null && DateTime.now().difference(_lastResendTime!).inSeconds < 60) {
                int remain = 60 - DateTime.now().difference(_lastResendTime!).inSeconds;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$remain초 후에 다시 시도할 수 있습니다.")));
                return;
              }

              final User? currentUser = FirebaseAuth.instance.currentUser;
              if (currentUser != null) {
                await _authService.resendVerificationEmail(currentUser);
                _lastResendTime = DateTime.now();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("인증 메일을 재발송했습니다. 메일함을 확인해주세요.")));
                }
              }
            },
            child: const Text("인증 메일 재발송"),
          ),
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

  Widget _buildBrandingSide() {
    return Container(
      color: kPrimaryBrandColor,
      padding: const EdgeInsets.all(60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_scanner, size: 80, color: Colors.white),
          const SizedBox(height: 32),
          const Text("Smart Safety\nSolution", style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, height: 1.2)),
          const SizedBox(height: 24),
          Text(
            "산업 현장의 설비 이력을 QR코드로 한눈에.\n안전하고 효율적인 유지보수를 위한 최고의 파트너 ScanSol입니다.",
            style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.8), height: 1.6),
          ),
          const Spacer(),
          Text(
            "© 2026 ScanSol Project. All rights reserved.",
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm({required bool isWeb}) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!isWeb) ...[
            const Center(child: Icon(Icons.qr_code_scanner, size: 64, color: kPrimaryBrandColor)),
            const SizedBox(height: 24),
            const Center(child: Text("ScanSol", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: kPrimaryBrandColor))),
            const SizedBox(height: 40),
          ],
          Text("로그인", style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 32),

          _buildTextFormField(
            controller: _facilityCtrl,
            label: "시설 번호",
            icon: Icons.domain,
            textInputAction: TextInputAction.next,
            validator: (value) => value == null || value.isEmpty ? '시설 번호를 입력해주세요.' : null,
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _emailCtrl, // 이메일 입력 필드
            label: "이메일 주소",
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.isEmpty) return '이메일을 입력해주세요.';
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) return '유효한 이메일 형식이 아닙니다.';
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _pwCtrl,
            label: "비밀번호",
            icon: Icons.lock_outline,
            isObscure: true,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleLogin(),
            validator: (value) => value == null || value.isEmpty ? '비밀번호를 입력해주세요.' : null,
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _isAutoLoginNotifier,
                builder: (context, isChecked, child) {
                  return Checkbox(
                    value: isChecked,
                    onChanged: (v) => _isAutoLoginNotifier.value = v ?? false,
                    activeColor: kPrimaryBrandColor,
                  );
                },
              ),
              const Text("로그인 상태 유지"),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ForgotPasswordPage()),
                  );
                },
                child: const Text("비밀번호 찾기", style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
          const SizedBox(height: 32),

          SizedBox(
            height: 56,
            child: ValueListenableBuilder<bool>(
              valueListenable: _isLoadingNotifier,
              builder: (context, isLoading, child) {
                return ElevatedButton(
                  onPressed: isLoading ? null : _handleLogin,
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("로그인"),
                );
              },
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

          // login_page.dart의 회원가입 신청 Row 하단에 추가

          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FacilitySignUpPage())),
            child: const Text("신규 사업장 등록 (최고 관리자)", style: TextStyle(color: Colors.blueGrey, fontSize: 13)),
          ),
          // [수정] 관리자 생성 디버그 버튼 제거 완료
        ],
      ),
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isObscure = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isObscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }
}