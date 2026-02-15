import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

// -----------------------------------------------------------
// [리디자인] 5-2. 직원 관리 페이지 (카드형 UI 및 명확한 액션)
// -----------------------------------------------------------
class AdminUserPage extends StatefulWidget {
  const AdminUserPage({super.key});

  @override
  State<AdminUserPage> createState() => _AdminUserPageState();
}

class _AdminUserPageState extends State<AdminUserPage> {
  Future<void> _approveUser(String docId, String name) async {
    await FirebaseFirestore.instance.collection('users').doc(docId).update({'status': 'approved'});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$name 님 승인 완료")));
  }

  void _deleteUser(String docId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("계정 삭제"),
        content: Text("'$name' 님의 계정을 삭제(거절)하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('users').doc(docId).delete();
              if (mounted) Navigator.pop(context);
            },
            child: const Text("삭제", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text("직원 계정 관리"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "승인 요청", icon: Icon(Icons.person_add)),
              Tab(text: "직원 목록", icon: Icon(Icons.people)),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.orange,
          ),
        ),
        body: TabBarView(
          children: [
            _buildUserList(isPending: true),
            _buildUserList(isPending: false),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList({required bool isPending}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('status', isEqualTo: isPending ? 'pending' : 'approved')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isPending ? Icons.how_to_reg : Icons.groups, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(isPending ? "승인 대기 중인 요청이 없습니다." : "등록된 직원이 없습니다.", style: TextStyle(color: Colors.grey[500])),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final user = UserModel.fromFirestore(docs[index]);
            return _buildUserCard(user, isPending);
          },
        );
      },
    );
  }

  Widget _buildUserCard(UserModel user, bool isPending) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: isPending ? Colors.orange[100] : Colors.blue[100],
              child: Icon(isPending ? Icons.priority_high : Icons.person, color: isPending ? Colors.orange : Colors.blue),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text("${user.department} | ${user.facilityId}", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  Text("ID: ${user.userId}", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ],
              ),
            ),
            if (isPending)
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _deleteUser(user.docId, user.name),
                    tooltip: "거절",
                  ),
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _approveUser(user.docId, user.name),
                    tooltip: "승인",
                  ),
                ],
              )
            else
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                onPressed: () => _deleteUser(user.docId, user.name),
                tooltip: "계정 삭제",
              ),
          ],
        ),
      ),
    );
  }
}
