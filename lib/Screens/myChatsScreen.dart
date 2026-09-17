import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Screens/privateChatScreen.dart';

class MyChatsList extends StatelessWidget {
  const MyChatsList({super.key});

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final isToday = now.year == time.year &&
        now.month == time.month &&
        now.day == time.day;
    if (isToday) {
      final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
      final minute = time.minute.toString().padLeft(2, '0');
      final period = time.hour >= 12 ? "م" : "ص";
      return "$hour:$minute $period";
    }
    return "${time.day}/${time.month}/${time.year}";
  }

  Timestamp? _laterOf(Timestamp? a, Timestamp? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.compareTo(b) >= 0 ? a : b;
  }

  // بمجرد ما جهاز المستلم يشوف تحديث المحادثة (حتى لو ماكان فاتح
  // الشات بعينها) بنعتبرها "وصلت" ونرفع الحالة لصحين رماديين، بدون
  // ما نلمس القراءة (صح مرتين أزرق) يلي لازم تبقى مربوطة بفتح الشات فعلياً.
  Future<void> _markChatDelivered(String chatId, String myEmail) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection("private_chats")
          .doc(chatId)
          .collection("messages")
          .where("status", isEqualTo: 1)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      var updates = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data["sender"] == myEmail) continue;
        batch.update(doc.reference, {
          "status": 2,
          "deliveredAt": FieldValue.serverTimestamp(),
        });
        updates++;
      }
      if (updates == 0) return;

      batch.set(
        FirebaseFirestore.instance.collection("private_chats").doc(chatId),
        {"lastMessageStatus": 2},
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (e) {
      print("⚠️ تعذر تحديث حالة التسليم: $e");
    }
  }

  bool _isHiddenForMe(Map<String, dynamic> data, String myEmail) {
    final participants = List<String>.from(data["participants"] ?? []);
    final myIndex = participants.indexOf(myEmail);
    if (myIndex == -1) return true;

    final cutoff = _laterOf(
      data["clearedAt$myIndex"] as Timestamp?,
      data["deletedForEveryoneAt"] as Timestamp?,
    );
    if (cutoff == null) return false;

    final lastMessageTime = data["lastMessageTime"] as Timestamp?;
    if (lastMessageTime == null) return true;
    return lastMessageTime.compareTo(cutoff) <= 0;
  }

  void _showDeleteChatSheet(
    BuildContext context, {
    required String chatId,
    required String otherName,
    required int myIndex,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text("حذف لدي فقط"),
              onTap: () async {
                Navigator.pop(sheetContext);
                await FirebaseFirestore.instance
                    .collection("private_chats")
                    .doc(chatId)
                    .set({
                  "clearedAt$myIndex": FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text(
                "حذف لدى الطرفين",
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text("حذف لدى الطرفين"),
                    content: Text(
                      "رح تنحذف كل الرسائل عندك وعند $otherName ولا تقدر ترجعها. متأكد؟",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text("إلغاء"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text("حذف", style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await FirebaseFirestore.instance
                      .collection("private_chats")
                      .doc(chatId)
                      .set({
                    "deletedForEveryoneAt": FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, color: Colors.indigo.shade300, size: 50),
          const SizedBox(height: 10),
          Text(
            "لا يوجد دردشات بعد",
            style: TextStyle(color: Colors.indigo.shade300, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _privateChatTile(BuildContext context, QueryDocumentSnapshot doc, String myEmail) {
    final data = doc.data() as Map<String, dynamic>;
    final participants = List<String>.from(data["participants"] ?? []);
    final names = List<String>.from(data["participantNames"] ?? []);

    final myIndex = participants.indexOf(myEmail);
    if (myIndex == -1) return const SizedBox.shrink();
    final otherIndex = myIndex == 0 ? 1 : 0;

    final otherEmail = participants.length > otherIndex ? participants[otherIndex] : "";
    final otherName =
        names.length > otherIndex && names[otherIndex].isNotEmpty ? names[otherIndex] : otherEmail;

    final lastMessage = data["lastMessage"] ?? "";
    final lastSender = data["lastSenderEmail"] ?? "";
    final unread = (data["unreadCount$myIndex"] ?? 0) as int;
    final hasUnread = unread > 0;
    final lastMessageStatus =
        (data["lastMessageStatus"] as num?)?.toInt() ?? (hasUnread ? 1 : 2);
    final timestamp = data["lastMessageTime"] as Timestamp?;

    if (lastSender.isNotEmpty && lastSender != myEmail && lastMessageStatus < 2) {
      _markChatDelivered(doc.id, myEmail);
    }

    return ListTile(
      leading: const CircleAvatar(
        radius: 24,
        backgroundColor: Colors.indigo,
        child: Icon(Icons.person, color: Colors.white),
      ),
      title: Text(
        otherName,
        style: TextStyle(fontWeight: hasUnread ? FontWeight.bold : FontWeight.w500),
      ),
      subtitle: Row(
        children: [
          if (lastSender == myEmail && lastMessage != "")
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  lastMessageStatus >= 2 ? 2 : 1,
                  (_) => Icon(
                    Icons.done,
                    size: 16,
                    color: lastMessageStatus >= 3 ? Colors.blue : Colors.grey,
                  ),
                ),
              ),
            ),
          Expanded(
            child: Text(
              lastMessage.isEmpty ? "ابدأ محادثة..." : lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasUnread ? Colors.black87 : Colors.grey.shade600,
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (timestamp != null)
            Text(
              _formatTime(timestamp.toDate()),
              style: TextStyle(fontSize: 11, color: hasUnread ? Colors.indigo : Colors.grey),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            CircleAvatar(
              radius: 9,
              backgroundColor: Colors.indigo,
              child: Text(
                unread > 9 ? "9+" : "$unread",
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ],
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PrivateChatScreen(userName: otherName, userEmail: otherEmail),
          ),
        );
      },
      onLongPress: () => _showDeleteChatSheet(
        context,
        chatId: doc.id,
        otherName: otherName,
        myIndex: myIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myEmail = FirebaseAuth.instance.currentUser?.email;

    return Container(
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
          child: myEmail == null
              ? const Center(child: Text("سجّل الدخول لعرض دردشاتك"))
              : StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection("private_chats")
                      .where("participants", arrayContains: myEmail)
                      .snapshots(),
                  builder: (context, chatSnapshot) {
                    if (chatSnapshot.hasError) {
                      return Center(child: Text("خطأ: ${chatSnapshot.error}"));
                    }
                    if (chatSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final chatDocs = (chatSnapshot.data?.docs ?? []).where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return !_isHiddenForMe(data, myEmail);
                    }).toList()
                      ..sort((a, b) {
                        final ta = (a.data() as Map<String, dynamic>)["lastMessageTime"]
                            as Timestamp?;
                        final tb = (b.data() as Map<String, dynamic>)["lastMessageTime"]
                            as Timestamp?;
                        if (ta == null && tb == null) return 0;
                        if (ta == null) return 1;
                        if (tb == null) return -1;
                        return tb.compareTo(ta);
                      });

                    if (chatDocs.isEmpty) return _emptyState();

                    return ListView.separated(
                      itemCount: chatDocs.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                      itemBuilder: (context, index) =>
                          _privateChatTile(context, chatDocs[index], myEmail),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
