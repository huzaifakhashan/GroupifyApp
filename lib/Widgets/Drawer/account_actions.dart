import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Screens/chatScreen.dart';
import 'package:groupify_app/Screens/homeScreen.dart';

class AccountActions extends StatelessWidget {
  const AccountActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
          Navigator.pop(context);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => Homescreen()),
          );

          try {
            final user = FirebaseAuth.instance.currentUser;

            if (user != null) {
              await user.delete();
              await FirebaseAuth.instance.signOut(); // 👈 مهم جداً
              if (!context.mounted) return;
              Navigator.pop(context);
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
      ],
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
            color: Colors.grey.shade100,
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
