import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// -----------------------------------------------------------
// [리디자인] 회원가입 페이지 (깔끔한 중앙 집중형 폼)
// -----------------------------------------------------------
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _facilityCtrl = TextEditingController(text: "KOGAS");
  final _deptCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();
  Color _iconColor = Colors.grey;

  void _checkPasswordMatch() {
    String pw = _pwCtrl.text;
    String confirm = _pwConfirmCtrl.text;
    setState(() {
      if (confirm.isEmpty) _iconColor = Colors.grey;
      else if (pw == confirm) _iconColor = Colors.green;
      else _iconColor = Theme.of(context).colorScheme.error;
    });
  }

  Future<void> _submitSignUp() async {
    // (기존 로직 동일)
    if (_idCtrl.text.isEmpty || _pwCtrl.text.isEmpty || _pwConfirmCtrl.text.isEmpty || _nameCtrl.text.isEmpty || _deptCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("모든 정보를 입력해주세요.")));
      return;
    }
    if (_pwCtrl.text != _pwConfirmCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("비밀번호가 일치하지 않습니다."), backgroundColor: Theme.of(context).colorScheme.error));
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').add({
        'facilityId': _facilityCtrl.text, 'userId': _idCtrl.text, 'password': _pwCtrl.text,
        'name': _nameCtrl.text, 'department': _deptCtrl.text, 'role': 'USER', 'status': 'pending',
        'createdAt': DateTime.now().toString(),
      });
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("신청 완료"),
          content: const Text("회원가입 신청이 완료되었습니다.\n관리자 승인 후 로그인이 가능합니다."),
          actions: [TextButton(onPressed: () {Navigator.pop(context); Navigator.pop(context);}, child: const Text("확인"))],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("오류 발생: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("회원가입"), centerTitle: true),
      backgroundColor: Colors.white,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600), // 너무 넓어지지 않게 제한
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("기본 정보 입력", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text("원활한 업무 처리를 위해 정확한 정보를 입력해 주세요.", style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 32),

                _buildTextField(_facilityCtrl, "시설 번호", Icons.business, false),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildTextField(_deptCtrl, "소속 (예: 기계팀)", Icons.group, false)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildTextField(_nameCtrl, "성명", Icons.badge, false)),
                  ],
                ),
                const SizedBox(height: 32),

                Text("계정 정보", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                _buildTextField(_idCtrl, "희망 아이디", Icons.account_circle, false),
                const SizedBox(height: 16),
                _buildTextField(_pwCtrl, "비밀번호", Icons.lock, true, onChanged: (_) => _checkPasswordMatch()),
                const SizedBox(height: 16),
                TextField(
                  controller: _pwConfirmCtrl,
                  obscureText: true,
                  onChanged: (_) => _checkPasswordMatch(),
                  decoration: InputDecoration(
                    labelText: "비밀번호 확인",
                    prefixIcon: const Icon(Icons.lock_reset),
                    suffixIcon: Icon(Icons.check_circle, color: _iconColor),
                  ),
                ),

                const SizedBox(height: 40),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _submitSignUp,
                    child: const Text("가입 신청하기"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, bool isObscure, {Function(String)? onChanged}) {
    return TextField(
      controller: ctrl,
      obscureText: isObscure,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }
}
