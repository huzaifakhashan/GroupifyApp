import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:groupify_app/Widgets/Drawer/account_actions.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("سجّل الدخول لعرض الملف الشخصي")),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final photoUrl = (data["photoUrl"] ?? user.photoURL ?? "").toString();
        final name = (data["name"] ?? user.displayName ?? "المستخدم").toString();

        return Scaffold(
          appBar: AppBar(title: const Text("الملف الشخصي")),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.only(top: 28, bottom: 24),
              children: [
            Center(
              child: CircleAvatar(
                radius: 58,
                backgroundColor: Colors.indigo.shade100,
                backgroundImage:
                    photoUrl.isEmpty ? null : CachedNetworkImageProvider(photoUrl),
                child: photoUrl.isEmpty
                    ? Icon(Icons.person,
                        size: 58, color: Colors.indigo.shade700)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                user.email ?? "",
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 20),
                const AccountActions(),
              ],
            ),
          ),
        );
      },
    );
  }
}
