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
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text("خطأ: ${snapshot.error}"));
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final chats = [...snapshot.data?.docs ?? []];
                  chats.sort((a, b) {
                    final aTime =
                        (a.data() as Map<String, dynamic>)["lastMessageTime"]
                            as Timestamp?;
                    final bTime =
                        (b.data() as Map<String, dynamic>)["lastMessageTime"]
                            as Timestamp?;
                    if (aTime == null && bTime == null) return 0;
                    if (aTime == null) return 1;
                    if (bTime == null) return -1;
                    return bTime.compareTo(aTime);
                  });

                  if (chats.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              color: Colors.indigo.shade300, size: 50),
                          const SizedBox(height: 10),
                          Text(
                            "لا يوجد دردشات بعد",
                            style: TextStyle(
                                color: Colors.indigo.shade300, fontSize: 16),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: chats.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) {
                      final data =
                          chats[index].data() as Map<String, dynamic>;
                      final participants =
                          List<String>.from(data["participants"] ?? []);
                      final names =
                          List<String>.from(data["participantNames"] ?? []);

                      final myIndex = participants.indexOf(myEmail);
                      if (myIndex == -1) return const SizedBox.shrink();
                      final otherIndex = myIndex == 0 ? 1 : 0;

                      final otherEmail = participants.length > otherIndex
                          ? participants[otherIndex]
                          : "";
                      final otherName = names.length > otherIndex &&
                              names[otherIndex].isNotEmpty
                          ? names[otherIndex]
                          : otherEmail;

                      final lastMessage = data["lastMessage"] ?? "";
                      final lastSender = data["lastSenderEmail"] ?? "";
                      final unread =
                          (data["unreadCount$myIndex"] ?? 0) as int;
                      final hasUnread = unread > 0;
                      final timestamp =
                          data["lastMessageTime"] as Timestamp?;

                      return ListTile(
                        leading: const CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.indigo,
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(
                          otherName,
                          style: TextStyle(
                            fontWeight:
                                hasUnread ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            if (lastSender == myEmail && lastMessage != "")
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(Icons.done_all,
                                    size: 16,
                                    color: hasUnread
                                        ? Colors.grey
                                        : Colors.blue),
                              ),
                            Expanded(
                              child: Text(
                                lastMessage.isEmpty
                                    ? "ابدأ محادثة..."
                                    : lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: hasUnread
                                      ? Colors.black87
                                      : Colors.grey.shade600,
                                  fontWeight: hasUnread
                                      ? FontWeight.w600
                                      : FontWeight.normal,
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
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      hasUnread ? Colors.indigo : Colors.grey,
                                ),
                              ),
                            if (hasUnread) ...[
                              const SizedBox(height: 4),
                              CircleAvatar(
                                radius: 9,
                                backgroundColor: Colors.indigo,
                                child: Text(
                                  unread > 9 ? "9+" : "$unread",
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 10),
                                ),
                              ),
                            ],
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PrivateChatScreen(
                                userName: otherName,
                                userEmail: otherEmail,
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
    );
  }
}
