import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Screens/createGroupScreen.dart';
import 'package:groupify_app/Screens/groupChatScreen.dart';
import 'package:groupify_app/Screens/joinGroupScreen.dart';
import 'package:groupify_app/Screens/publicGroupScreen.dart';
import 'package:groupify_app/Screens/searchGroupsScreen.dart';

class GroupsList extends StatelessWidget {
  const GroupsList({super.key});

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

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.groups_outlined, color: Colors.indigo.shade300, size: 50),
          const SizedBox(height: 10),
          Text(
            "ما في مجموعات ثانية بعد",
            style: TextStyle(color: Colors.indigo.shade300, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            "أنشئ مجموعة جديدة أو انضم لمجموعة بكود الدعوة",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _actionsRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("إنشاء مجموعة"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text("الانضمام لمجموعة"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const JoinGroupScreen()),
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            icon: const Icon(Icons.search),
            tooltip: "البحث عن مجموعة",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchGroupsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _mainGroupTile(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(
        radius: 24,
        backgroundColor: Colors.deepPurple,
        child: Icon(Icons.forum, color: Colors.white),
      ),
      title: const Text(
        "المجموعة الأساسية",
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        "الدردشة العامة لكل مستخدمي التطبيق",
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey.shade600),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PublicGroupScreen()),
        );
      },
    );
  }

  Widget _groupTile(BuildContext context, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final name = (data["name"] ?? "مجموعة").toString();
    final photoUrl = data["photoUrl"] as String?;
    final lastMessage = (data["lastMessage"] ?? "").toString();
    final lastSenderName = (data["lastSenderName"] ?? "").toString();
    final timestamp = data["lastMessageTime"] as Timestamp?;

    final subtitle = lastMessage.isEmpty
        ? "ابدأ محادثة..."
        : (lastSenderName.isEmpty ? lastMessage : "$lastSenderName: $lastMessage");

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.indigo,
        backgroundImage: photoUrl == null ? null : CachedNetworkImageProvider(photoUrl),
        child: photoUrl == null ? const Icon(Icons.groups, color: Colors.white) : null,
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey.shade600),
      ),
      trailing: timestamp != null
          ? Text(
              _formatTime(timestamp.toDate()),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            )
          : null,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupChatScreen(groupId: doc.id, groupName: name),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

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
        child: Column(
          children: [
            _actionsRow(context),
            const Divider(height: 1),
            _mainGroupTile(context),
            const Divider(height: 1, indent: 72),
            Expanded(
              child: myUid == null
                  ? const Center(child: Text("سجّل الدخول لعرض مجموعاتك"))
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection("groups")
                          .where("memberUids", arrayContains: myUid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(child: Text("خطأ: ${snapshot.error}"));
                        }
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final docs = (snapshot.data?.docs ?? []).toList()
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

                        if (docs.isEmpty) return _emptyState();

                        return ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                          itemBuilder: (context, index) => _groupTile(context, docs[index]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
