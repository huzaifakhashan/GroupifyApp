import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SelectedUser {
  final String uid;
  final String email;
  final String name;

  const SelectedUser({
    required this.uid,
    required this.email,
    required this.name,
  });
}

/// قائمة مستخدمين قابلة للبحث مع تحديد متعدد (Checkbox)، تُستخدم لبناء
/// مجموعة جديدة أو لإضافة أعضاء لمجموعة موجودة. بتستثني المستخدم الحالي
/// وأي حدا موجود مسبقاً بـ [excludeUids].
class UserMultiSelectList extends StatefulWidget {
  final Set<String> excludeUids;
  final void Function(List<SelectedUser> selected) onSelectionChanged;

  const UserMultiSelectList({
    super.key,
    this.excludeUids = const {},
    required this.onSelectionChanged,
  });

  @override
  State<UserMultiSelectList> createState() => _UserMultiSelectListState();
}

class _UserMultiSelectListState extends State<UserMultiSelectList> {
  final TextEditingController _searchController = TextEditingController();
  String _query = "";
  final Map<String, SelectedUser> _selected = {};

  void _toggle(SelectedUser user, bool? checked) {
    setState(() {
      if (checked == true) {
        _selected[user.uid] = user;
      } else {
        _selected.remove(user.uid);
      }
    });
    widget.onSelectionChanged(_selected.values.toList());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "ابحث بالاسم أو المعرف الفريد @...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() => _query = value.trim().toLowerCase());
            },
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection("users").snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text("خطأ: ${snapshot.error}"));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final users = (snapshot.data?.docs ?? []).where((doc) {
                if (doc.id == myUid) return false;
                if (widget.excludeUids.contains(doc.id)) return false;
                final data = doc.data() as Map<String, dynamic>;
                if (data["blockGroupInvites"] == true) return false;
                final isPrivate = data["isPrivate"] == true;
                final name = (data["name"] ?? "").toString().toLowerCase();
                final username =
                    (data["username"] ?? "").toString().toLowerCase();

                if (_query.isEmpty) return !isPrivate;
                if (_query.startsWith('@')) {
                  final usernameQuery = _query.substring(1);
                  if (usernameQuery.isEmpty) return false;
                  if (isPrivate) return username == usernameQuery;
                  return username.contains(usernameQuery);
                }
                if (isPrivate) return false;
                return name.contains(_query);
              }).toList()
                ..sort((a, b) {
                  final nameA = (a.data() as Map<String, dynamic>)["name"] ?? "";
                  final nameB = (b.data() as Map<String, dynamic>)["name"] ?? "";
                  return nameA.toString().compareTo(nameB.toString());
                });

              if (users.isEmpty) {
                return Center(
                  child: Text(
                    _query.isEmpty ? "لا يوجد مستخدمين" : "ما في نتائج لـ \"$_query\"",
                    style: TextStyle(color: Colors.indigo.shade300, fontSize: 16),
                  ),
                );
              }

              return ListView.separated(
                itemCount: users.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) {
                  final doc = users[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data["name"] ?? "مستخدم").toString();
                  final email = (data["email"] ?? "").toString();
                  final username = (data["username"] ?? "").toString();
                  final isSelected = _selected.containsKey(doc.id);

                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (checked) => _toggle(
                      SelectedUser(uid: doc.id, email: email, name: name),
                      checked,
                    ),
                    secondary: const CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.indigo,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: username.isNotEmpty ? Text("@$username") : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
