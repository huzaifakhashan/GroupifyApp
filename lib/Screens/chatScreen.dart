import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:groupify_app/Screens/IncomingCallScreen.dart';
import 'package:groupify_app/Screens/myChatsScreen.dart';
import 'package:groupify_app/Screens/searchUsersScreen.dart';
import 'package:groupify_app/Screens/callsScreen.dart';
import 'package:groupify_app/Screens/profileScreen.dart';
import 'package:groupify_app/Screens/groupsScreen.dart';
import 'package:groupify_app/Screens/statusScreen.dart';
import 'package:groupify_app/Widgets/Drawer/drawerPage.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _auth = FirebaseAuth.instance;
  User? signedInUser;
  final Set<String> _shownCallIds = <String>{};

  void getCurrentUser() {
    final user = _auth.currentUser;
    if (user != null) signedInUser = user;
  }

  void listenForCalls() {
    final receiverEmail = FirebaseAuth.instance.currentUser?.email;
    if (receiverEmail == null) return;

    FirebaseFirestore.instance
        .collection("calls")
        .where("receiver", isEqualTo: receiverEmail)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        var data = doc.data();
        if (data["status"] == "ringing" && !_shownCallIds.contains(doc.id)) {
          _shownCallIds.add(doc.id);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IncomingCallScreen(
                callId: doc.id,
                callerName: data["callerName"] ?? data["caller"] ?? "مجهول",
                callerEmail: data["caller"] ?? "",
                isVideoCall: data["isVideo"] ?? false,
              ),
            ),
          );
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    getCurrentUser();
    listenForCalls();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        drawer: const Drawerpage(showLogout: true),
        appBar: AppBar(
          backgroundColor: const Color(0xFF4A00E0),
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.chat_bubble_outline, size: 18), text: "دردشاتي"),
              Tab(icon: Icon(Icons.auto_awesome_motion_outlined, size: 18), text: "الحالات"),
              Tab(icon: Icon(Icons.groups_outlined, size: 18), text: "المجموعات"),
              Tab(icon: Icon(Icons.call_outlined, size: 18), text: "المكالمات"),
            ],
          ),
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white,
                backgroundImage: signedInUser?.photoURL == null
                    ? null
                    : CachedNetworkImageProvider(signedInUser!.photoURL!),
                child: signedInUser?.photoURL == null
                    ? const Icon(Icons.person, color: Colors.indigo, size: 20)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfileScreen(),
                      ),
                    );
                  },
                  child: Text(
                    signedInUser?.displayName ??
                        signedInUser?.email ??
                        "المستخدم",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_search),
              tooltip: "البحث عن مستخدم",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SearchUsersScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        body: const TabBarView(
          children: [
            MyChatsList(),
            StatusList(),
            GroupsList(),
            CallsList(),
          ],
        ),
      ),
    );
  }
}
