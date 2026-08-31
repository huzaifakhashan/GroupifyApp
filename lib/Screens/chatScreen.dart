import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Screens/IncomingCallScreen.dart';
import 'package:groupify_app/Screens/privateChatScreen.dart';
import 'package:groupify_app/Screens/myChatsScreen.dart';
import 'package:groupify_app/Screens/searchUsersScreen.dart';
import 'package:groupify_app/Screens/callsScreen.dart';
import 'package:groupify_app/Widgets/Drawer/drawerPage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController messageController = TextEditingController();
  bool isSearching = false;
  String searchText = "";
  final TextEditingController searchController = TextEditingController();
  // 👇 مهم للـ Scroll
  final ScrollController _scrollController = ScrollController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  User? signedInUser;
  
  void getCurrentUser() {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        signedInUser = user;
        String userInfo = user.displayName ?? 
                         user.email ?? 
                         (user.isAnonymous ? "مستخدم مجهول" : "مستخدم");
        print("✅ المستخدم: $userInfo");
        print("✅ معرّف المستخدم: ${user.uid}");
        print("✅ نوع المستخدم: ${user.isAnonymous ? "مجهول" : "عادي"}");
      } else {
        print("❌ لا يوجد مستخدم مسجل");
      }
    } catch (e) {
      print("❌ خطأ في الحصول على المستخدم: $e");
    }
  }
void listenForCalls(){

final receiverEmail = FirebaseAuth.instance.currentUser?.email;
if (receiverEmail == null) return;

FirebaseFirestore.instance
.collection("calls")
.where(
"receiver",
isEqualTo: receiverEmail
)
.snapshots()
.listen((snapshot){


for(var doc in snapshot.docs){


var data = doc.data();


if(data["status"]=="ringing"){


Navigator.push(
context,
MaterialPageRoute(
builder:(_)=>
IncomingCallScreen(
callId: doc.id,
callerName:
data["callerName"] ?? data["caller"] ?? "مجهول",
callerEmail:
data["caller"] ?? "",
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
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

    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("الرجاء كتابة رسالة"),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (signedInUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("خطأ: لم تسجل دخول"),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      print("🔄 جاري إرسال الرسالة...");
      
      // حدد اسم المرسل
      String senderName = signedInUser!.displayName ?? 
                         (signedInUser!.isAnonymous ? "مستخدم مجهول" : "مستخدم");
      String senderEmail = signedInUser!.email ?? 
                          (signedInUser!.isAnonymous ? "anonymous_${signedInUser!.uid}" : "unknown");
      
      print("المرسل: $senderEmail");
      print("اسم المرسل: $senderName");
      print("النص: $text");
      
      final messageDoc = await _firestore.collection("messages").add({
        "text": text,
        "sender": senderEmail,
        "name": senderName,
        "photoUrl": signedInUser!.photoURL,
        "userId": signedInUser!.uid,
        "timestamp": FieldValue.serverTimestamp(),
        "createdAt": DateTime.now().millisecondsSinceEpoch,
        "isAnonymous": signedInUser!.isAnonymous,
      });
      
      print("✅ تم إرسال الرسالة بنجاح - ID: ${messageDoc.id}");
      messageController.clear();

      // انتظر قليلاً ثم اسحب للأسفل
      await Future.delayed(const Duration(milliseconds: 200));
      _scrollToBottom();
    } on FirebaseException catch (e) {
      print("❌ خطأ Firebase: ${e.code} - ${e.message}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("خطأ: ${e.message}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print("❌ خطأ في إرسال الرسالة: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("خطأ: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
      drawer: const Drawerpage(showLogout: true),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A00E0),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: const TabBar(
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: "المجموعة"),
            Tab(text: "دردشاتي"),
            Tab(text: "المكالمات"),
          ],
        ),
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
                      signedInUser?.displayName ?? signedInUser?.email ?? "المستخدم",
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
        ],
      ),

      body: TabBarView(
        children: [
          Container(
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
                      .collection("messages")
                      .orderBy("timestamp", descending: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 50,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "خطأ: ${snapshot.error}",
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              color: Colors.indigo.shade300,
                              size: 50,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "لا توجد رسائل حتى الآن",
                              style: TextStyle(
                                color: Colors.indigo.shade300,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      );
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
                        final photoUrl = data["photoUrl"] as String?;
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
                        final isMe = sender == (signedInUser?.email ?? "");

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: isMe
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isMe) ...[
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.indigo.shade100,
                                  backgroundImage:
                                      (photoUrl != null && photoUrl.isNotEmpty)
                                          ? NetworkImage(photoUrl)
                                          : null,
                                  child: (photoUrl == null || photoUrl.isEmpty)
                                      ? Icon(Icons.person,
                                          size: 18,
                                          color: Colors.indigo.shade700)
                                      : null,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              // يظهر الاسم فقط إذا كانت الرسالة ليست رسالتك
                              if (!isMe)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PrivateChatScreen(
                                            userName: name,
                                            userEmail: sender,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo.shade700,
                                      ),
                                    ),
                                  ),
                                ),

                              if (!isMe) const SizedBox(height: 4),

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
          const MyChatsList(),
          const CallsList(),
        ],
      ),
      ),
    );
  }
}
