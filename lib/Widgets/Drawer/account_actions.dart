import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:groupify_app/Screens/chatScreen.dart';
import 'package:groupify_app/Screens/homeScreen.dart';
import 'package:groupify_app/Screens/loginScreen.dart';
import 'package:groupify_app/Services/usernameService.dart';
import 'package:groupify_app/Services/imageService.dart';

class AccountActions extends StatelessWidget {
  const AccountActions({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      children: [
        if (uid != null) _buildPrivacyToggle(uid),
        if (uid != null) _buildGroupInvitePrivacyToggle(uid),
        if (uid != null) _buildUsernameTile(context, uid),
        if (uid != null)
          _buildItem(
            context,
            Icons.photo_camera_outlined,
            "تغيير الصورة الشخصية",
            () => _changeProfilePicture(context, uid),
          ),
        _buildItem(context, Icons.edit, "تعديل الحساب", () {
          final controller = TextEditingController(
            text: FirebaseAuth.instance.currentUser?.displayName ?? "",
          );

          showDialog(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: const Text("تعديل الاسم"),

                content: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: "أدخل الاسم الجديد",
                    border: OutlineInputBorder(),
                  ),
                ),

                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    child: const Text("إلغاء"),
                  ),

                  ElevatedButton(
                    onPressed: () async {
                      final user = FirebaseAuth.instance.currentUser;

                      if (user != null && controller.text.trim().isNotEmpty) {
                        await user.updateDisplayName(controller.text.trim());

                        await user.reload();

                        Navigator.pop(dialogContext);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => ChatScreen()),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("تم تعديل الاسم بنجاح")),
                        );
                      }
                    },
                    child: const Text("حفظ"),
                  ),
                ],
              );
            },
          );
        }),
        _buildItem(context, Icons.delete, "حذف الحساب", () async {
          try {
            final user = FirebaseAuth.instance.currentUser;

            if (user != null) {
              await user.delete();
              await FirebaseAuth.instance.signOut(); // 👈 مهم جداً
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const Homescreen()),
                (route) => false,
              );
            }
          } on FirebaseAuthException catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  e.code == "requires-recent-login"
                      ? "يجب تسجيل الدخول مرة أخرى قبل حذف الحساب"
                      : "فشل حذف الحساب",
                ),
              ),
            );
          }
        }),
        _buildItem(context, Icons.logout, "تسجيل الخروج", () async {
          await FirebaseAuth.instance.signOut();
          if (!context.mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => LoginPage()),
            (route) => false,
          );
        }),
      ],
    );
  }

  Widget _buildPrivacyToggle(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final isPrivate = data?["isPrivate"] == true;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, color: Colors.indigo),
                const SizedBox(width: 15),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "حساب خاص",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        "ما حدا رح يقدر يلاقيك بالبحث عن اسمك",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isPrivate,
                  activeThumbColor: Colors.indigo,
                  onChanged: (value) {
                    FirebaseFirestore.instance
                        .collection("users")
                        .doc(uid)
                        .set({"isPrivate": value}, SetOptions(merge: true));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupInvitePrivacyToggle(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final blockInvites = data?["blockGroupInvites"] == true;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                const Icon(Icons.group_off, color: Colors.indigo),
                const SizedBox(width: 15),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "منع الإضافة إلى المجموعات",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        "ما حدا غيرك رح يقدر يضيفك على مجموعة، وبتضل قادر تنضم بنفسك عبر كود الدعوة",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: blockInvites,
                  activeThumbColor: Colors.indigo,
                  onChanged: (value) {
                    FirebaseFirestore.instance
                        .collection("users")
                        .doc(uid)
                        .set({"blockGroupInvites": value}, SetOptions(merge: true));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _changeProfilePicture(BuildContext context, String uid) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 800,
      );
      if (picked == null) return;

      final url = await ImageService().uploadImageToSupabase(
        imageFile: File(picked.path),
        userId: uid,
      );
      if (url == null || url.isEmpty) {
        throw Exception("تعذّر الحصول على رابط الصورة");
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updatePhotoURL(url);
        await user.reload();
      }

      await FirebaseFirestore.instance.collection("users").doc(uid).set(
        {"photoUrl": url},
        SetOptions(merge: true),
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم تحديث الصورة الشخصية")),
      );
    } on FirebaseException catch (e) {
      if (!context.mounted) return;
      final message = e.code == "permission-denied"
          ? "لا تملك صلاحية رفع الصورة. انشر قواعد Storage في Firebase."
          : "فشل رفع الصورة: ${e.message ?? e.code}";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("فشل رفع الصورة: $e")),
      );
    }
  }

  Widget _buildUsernameTile(BuildContext context, String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final username = (data?["username"] ?? "").toString();

        return _buildItem(
          context,
          Icons.alternate_email,
          username.isEmpty ? "تعيين معرف فريد" : "المعرف الفريد: @$username",
          () => _showEditUsernameDialog(context, uid, username),
        );
      },
    );
  }

  void _showEditUsernameDialog(
    BuildContext context,
    String uid,
    String currentUsername,
  ) {
    final controller = TextEditingController(text: currentUsername);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("تغيير المعرف الفريد"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: "معرف فريد (حروف وأرقام)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "هاد المعرف بيميّزك عن أي حدا عندو نفس اسمك، وفيك تغيّرو وقت ما بدك",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              onPressed: () async {
                final newUsername = controller.text.trim();
                if (newUsername.isEmpty) return;

                final error = await UsernameService.changeUsername(
                  uid: uid,
                  oldUsername: currentUsername,
                  newUsername: newUsername,
                );

                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error ?? "تم تغيير المعرف بنجاح")),
                );
              },
              child: const Text("حفظ"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildItem(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.indigo),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
