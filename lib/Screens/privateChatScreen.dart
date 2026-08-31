import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Screens/CallScreen.dart';
import 'package:groupify_app/Widgets/Drawer/drawerPage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PrivateChatScreen extends StatefulWidget {
  final String userName;
  final String userEmail;

  const PrivateChatScreen({
    super.key,
    required this.userName,
    required this.userEmail,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {


  final TextEditingController messageController = TextEditingController();
  bool isSearching = false;
  String searchText = "";
  final TextEditingController searchController = TextEditingController();
  // 👇 مهم للـ Scroll
  final ScrollController _scrollController = ScrollController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late User signedInUser;
  String getChatId() {
    List<String> users = [signedInUser.email!, widget.userEmail];

    users.sort();

    return users.join("_");
  }
Future<void> createCall() async {

  final callDoc =
      FirebaseFirestore.instance.collection("calls").doc();


  await callDoc.set({

    "caller": signedInUser.email,

    "callerName": signedInUser.displayName ?? "User",

    "receiver": widget.userEmail,

    "receiverName": widget.userName,

    "status": "ringing",

    "timestamp": FieldValue.serverTimestamp(),

  });

  if (!mounted) return;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => Callscreen(
        callId: callDoc.id,
        userName: widget.userName,
        userEmail: widget.userEmail,
      ),
    ),
  );

}
  void getCurrentUser() {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        signedInUser = user;
      }
    } catch (e) {
      print(e);
    }
  }

  @override
  void initState() {
    super.initState();
    getCurrentUser();
    _markAsRead();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Future<void> _markAsRead() async {
    final myEmail = signedInUser.email;
    if (myEmail == null) return;

    final participants = [myEmail, widget.userEmail]..sort();
    final myIndex = participants.indexOf(myEmail);

    await _firestore.collection("private_chats").doc(getChatId()).set({
      "unreadCount$myIndex": 0,
    }, SetOptions(merge: true));
  }

  Future<void> refreshUser() async {
    await FirebaseAuth.instance.currentUser?.reload();

    setState(() {
      signedInUser = FirebaseAuth.instance.currentUser!;
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void sendMessage() async {
    final text = messageController.text.trim();

    if (text.isEmpty) return;

    final myEmail = signedInUser.email!;
    final myName = signedInUser.displayName ?? "User";
    final participants = [myEmail, widget.userEmail]..sort();
    final myIndex = participants.indexOf(myEmail);
    final otherIndex = myIndex == 0 ? 1 : 0;
    final names = List<String>.filled(2, "");
    names[myIndex] = myName;
    names[otherIndex] = widget.userName;

    final chatDoc = _firestore.collection("private_chats").doc(getChatId());

    await chatDoc.collection("messages").add({
      "text": text,
      "sender": myEmail,
      "name": myName,
      "timestamp": FieldValue.serverTimestamp(),
    });

    await chatDoc.set({
      "participants": participants,
      "participantNames": names,
      "lastMessage": text,
      "lastMessageTime": FieldValue.serverTimestamp(),
      "lastSenderEmail": myEmail,
      "unreadCount$otherIndex": FieldValue.increment(1),
      "unreadCount$myIndex": 0,
    }, SetOptions(merge: true));

    messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final chatId = getChatId();
    return Scaffold(
      drawer: const Drawerpage(showLogout: true),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A00E0),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: isSearching
            ? TextField(
                controller: searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),

                decoration: const InputDecoration(
                  hintText: "... البحث عن الرسائل",
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  setState(() {
                    searchText = value.toLowerCase();
                  });
                },
              )
            : Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, color: Colors.indigo, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                       widget.userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (isSearching) {
                  isSearching = false;
                  searchController.clear();
                  searchText = "";
                } else {
                  isSearching = true;
                }
              });
            },
          ),
          IconButton(
  icon: const Icon(
    Icons.call,
    color: Colors.white,
  ),
  onPressed: () {
    createCall();
  },
),
        ],
      ),

      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            // 🔝 Header

            // 💬 Messages
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(25),
                    topRight: Radius.circular(25),
                  ),
                ),
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection("private_chats")
                      .doc(chatId)
                      .collection("messages")
                      .orderBy("timestamp")
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final messages = snapshot.data!.docs;
                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final data = message.data() as Map<String, dynamic>;

                        final name = data["name"] ?? "مستخدم";
                        final text = data["text"] ?? "";
                        final nameLower = name.toLowerCase();
                        final textLower = text.toLowerCase();
                        final query = searchText.toLowerCase();

                        if (query.isNotEmpty &&
                            !nameLower.contains(query) &&
                            !textLower.contains(query)) {
                          return const SizedBox.shrink();
                        }
                        if (text.trim().isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final sender = data["sender"] ?? "";
                        final isMe = sender == signedInUser.email;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 280,
                                  ),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? Colors.indigo
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(18),
                                      topRight: const Radius.circular(18),
                                      bottomLeft: Radius.circular(
                                        isMe ? 18 : 4,
                                      ),
                                      bottomRight: Radius.circular(
                                        isMe ? 4 : 18,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: isMe
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),

            // ⌨️ Input
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      decoration: InputDecoration(
                        hintText: "اكتب رسالة...",
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    backgroundColor: Colors.indigo,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
