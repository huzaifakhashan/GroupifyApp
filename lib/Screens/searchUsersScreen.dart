import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Screens/privateChatScreen.dart';

class SearchUsersScreen extends StatefulWidget {
  const SearchUsersScreen({super.key});

  @override
  State<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = "";

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "غير معروف";
    final date = timestamp.toDate();
    return "${date.day}/${date.month}/${date.year}";
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A00E0),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "ابحث بالاسم أو المعرف الفريد @...",
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
          onChanged: (value) {
            setState(() {
              _query = value.trim().toLowerCase();
            });
          },
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(25),
            topRight: Radius.circular(25),
          ),
          child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance.collection("users").snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text("خطأ: ${snapshot.error}"));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final users = (snapshot.data?.docs ?? []).where((doc) {
                if (doc.id == myUid) return false;
                final data = doc.data() as Map<String, dynamic>;
                final isPrivate = data["isPrivate"] == true;
                final name = (data["name"] ?? "").toString().toLowerCase();
                final username =
                    (data["username"] ?? "").toString().toLowerCase();

                if (_query.isEmpty) return !isPrivate;

                // البحث بالمعرف الفريد بيصير بس إذا الكتابة بادئة بـ @
                if (_query.startsWith('@')) {
                  final usernameQuery = _query.substring(1);
                  if (usernameQuery.isEmpty) return false;

                  final matchesUsernameExact =
                      username.isNotEmpty && username == usernameQuery;

                  // الحساب الخاص ما بيظهر إلا إذا كتبت معرفه الفريد بالكامل
                  if (isPrivate) return matchesUsernameExact;

                  return username.contains(usernameQuery);
                }

                // بدون @ البحث بالاسم فقط، والحسابات الخاصة مستثناة
                if (isPrivate) return false;
                return name.contains(_query);
              }).toList()
                ..sort((a, b) {
                  final nameA =
                      (a.data() as Map<String, dynamic>)["name"] ?? "";
                  final nameB =
                      (b.data() as Map<String, dynamic>)["name"] ?? "";
                  return nameA.toString().compareTo(nameB.toString());
                });

              if (users.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_search,
                          color: Colors.indigo.shade300, size: 50),
                      const SizedBox(height: 10),
                      Text(
                        _query.isEmpty
                            ? "لا يوجد مستخدمين"
                            : "ما في نتائج لـ \"$_query\"",
                        style: TextStyle(
                            color: Colors.indigo.shade300, fontSize: 16),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                itemCount: users.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) {
                  final data = users[index].data() as Map<String, dynamic>;
                  final name = data["name"] ?? "مستخدم";
                  final email = data["email"] ?? "";
                  final username = (data["username"] ?? "").toString();
                  final createdAt = data["createdAt"] as Timestamp?;
                  final isPrivate = data["isPrivate"] == true;

                  return ListTile(
                    leading: const CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.indigo,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isPrivate) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.lock,
                              size: 14, color: Colors.grey),
                        ],
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (username.isNotEmpty)
                          Text(
                            "@$username",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.indigo,
                            ),
                          ),
                        Text(
                          "تاريخ إنشاء الحساب: ${_formatDate(createdAt)}",
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PrivateChatScreen(
                            userName: name,
                            userEmail: email,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
          ),
        ),
      ),
    );
  }
}
