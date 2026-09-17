import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Widgets/userMultiSelectList.dart';
import 'package:groupify_app/Screens/groupChatScreen.dart';
import 'package:groupify_app/Services/groupInviteService.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  List<SelectedUser> _selected = [];
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// بتحاول تحجز كود دعوة عشوائي بربطه بالمجموعة بمجموعة groupInviteCodes.
  /// الكود هو معرّف المستند نفسه، فـ Firestore بيرفض العملية تلقائياً (قاعدة
  /// update ممنوعة) إذا الكود محجوز مسبقاً، وهيك منضمن ما في تكرار.
  Future<String> _createInviteCode(String groupId) async {
    final rand = Random();
    for (var attempt = 0; attempt < 8; attempt++) {
      final code = (100000 + rand.nextInt(900000)).toString();
      try {
        await FirebaseFirestore.instance
            .collection("groupInviteCodes")
            .doc(code)
            .set({"groupId": groupId});
        return code;
      } on FirebaseException catch (e) {
        if (e.code == "permission-denied") continue; // الكود محجوز، جرب غيره
        rethrow;
      }
    }
    throw Exception("تعذّر توليد كود دعوة فريد، حاول مرة ثانية");
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("اكتب اسم للمجموعة"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    setState(() => _isCreating = true);
    try {
      final myName = me.displayName ?? me.email ?? "مستخدم";
      final groupRef = FirebaseFirestore.instance.collection("groups").doc();

      // بيتم إنشاء المجموعة بعضوية المنشئ لحاله بس؛ أي عضو إضافي بينضاف
      // بعدين عبر GroupInviteService.addMembers يلي بيتحقق من خاصية "منع
      // الإضافة إلى المجموعات" (قواعد Firestore ما بتسمح بإنشاء المجموعة
      // بأعضاء إضافيين مباشرة من العميل).
      await groupRef.set({
        "name": name,
        "isPrivate": false,
        "admins": <String>[],
        "memberUids": [me.uid],
        "memberEmails": [me.email],
        "memberNames": [myName],
        "createdBy": me.uid,
        "createdByName": myName,
        "createdAt": FieldValue.serverTimestamp(),
        "lastMessage": "",
        "lastMessageTime": FieldValue.serverTimestamp(),
        "lastSenderName": "",
      });

      final joinCode = await _createInviteCode(groupRef.id);
      await groupRef.update({"joinCode": joinCode});

      if (_selected.isNotEmpty) {
        final result = await GroupInviteService.addMembers(
          groupId: groupRef.id,
          users: _selected,
        );
        if (result.skipped.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "${result.skipped.length} ما انضافوا للمجموعة لأنهم مفعّلين خاصية منع الإضافة",
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("كود دعوة المجموعة: $joinCode")),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(groupId: groupRef.id, groupName: name),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A00E0),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("مجموعة جديدة", style: TextStyle(color: Colors.white)),
        actions: [
          _isCreating
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.check, color: Colors.white),
                  tooltip: "إنشاء",
                  onPressed: _createGroup,
                ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: "اسم المجموعة",
                prefixIcon: const Icon(Icons.groups),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  "${_selected.length} محدد",
                  style: TextStyle(color: Colors.indigo.shade400, fontSize: 12),
                ),
              ),
            ),
          Expanded(
            child: UserMultiSelectList(
              onSelectionChanged: (selected) {
                setState(() => _selected = selected);
              },
            ),
          ),
        ],
      ),
    );
  }
}
