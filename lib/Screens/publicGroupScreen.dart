import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:groupify_app/Screens/privateChatScreen.dart';
import 'package:groupify_app/Screens/groupCallScreen.dart';
import 'package:groupify_app/Widgets/audioMessageWidget.dart';
import 'package:groupify_app/Widgets/imageMessageWidget.dart';
import 'package:groupify_app/Widgets/videoMessageWidget.dart';
import 'package:groupify_app/Widgets/audioComposerBar.dart';
import 'package:groupify_app/Widgets/messageReactions.dart';
import 'package:groupify_app/Widgets/linkifiedText.dart';
import 'package:groupify_app/Services/notificationService.dart';
import 'package:groupify_app/Services/groupCallLink.dart';
import 'package:groupify_app/Services/chatMuteService.dart';

/// "المجموعة الأساسية" - الدردشة العامة لكل مستخدمي التطبيق.
class PublicGroupScreen extends StatefulWidget {
  const PublicGroupScreen({super.key});

  @override
  State<PublicGroupScreen> createState() => _PublicGroupScreenState();
}

class _PublicGroupScreenState extends State<PublicGroupScreen> {
  final TextEditingController messageController = TextEditingController();
  bool isSearching = false;
  String searchText = "";
  final TextEditingController searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  User? signedInUser;
  String? _replyMessageId;
  String? _highlightedMessageId;
  List<QueryDocumentSnapshot>? _currentMessages;
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  String? _replyText;
  String? _replySender;

  final Set<String> _selectedMessageIds = {};
  bool get _isSelecting => _selectedMessageIds.isNotEmpty;

  static const String _chatKey = "public";

  void _toggleSelected(String messageId) {
    setState(() {
      if (!_selectedMessageIds.remove(messageId)) {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedMessageIds.clear());

  bool get _canDeleteSelectedForEveryone {
    if (_selectedMessageIds.isEmpty || _currentMessages == null) return false;
    final myEmail = signedInUser?.email ?? "";
    for (final id in _selectedMessageIds) {
      final match = _currentMessages!.where((m) => m.id == id);
      if (match.isEmpty) return false;
      final data = match.first.data() as Map<String, dynamic>;
      if ((data["sender"] ?? "") != myEmail) return false;
    }
    return true;
  }

  Future<void> _deleteSelected({required bool forEveryone}) async {
    final ids = _selectedMessageIds.toList();
    final myUid = signedInUser?.uid ?? "";
    for (final id in ids) {
      final ref = _firestore.collection("messages").doc(id);
      try {
        if (forEveryone) {
          await ref.delete();
        } else {
          await ref.update({
            "deletedFor": FieldValue.arrayUnion([myUid]),
          });
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _selectedMessageIds.clear());
  }

  Future<void> _confirmDeleteSelectedForEveryone() async {
    final count = _selectedMessageIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("حذف لدى الجميع"),
        content: Text(
          "رح تنحذف $count ${count == 1 ? 'رسالة' : 'رسائل'} عند كل الأطراف ولا تقدر ترجعها. متأكد؟",
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
    if (confirmed == true) await _deleteSelected(forEveryone: true);
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF4A00E0),
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _clearSelection,
      ),
      title: Text(
        "${_selectedMessageIds.length} محدد",
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: "حذف لدي",
          onPressed: () => _deleteSelected(forEveryone: false),
        ),
        if (_canDeleteSelectedForEveryone)
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: "حذف لدى الجميع",
            onPressed: _confirmDeleteSelectedForEveryone,
          ),
      ],
    );
  }

  Map<String, dynamic> _replyFields() {
    return {
      if (_replyText != null) "replyText": _replyText,
      if (_replySender != null) "replySender": _replySender,
      if (_replyMessageId != null) "replyToId": _replyMessageId,
    };
  }

  void _setReply(Map<String, dynamic> data, String messageId) {
    final type = data["type"] ?? "text";
    final content = type == "image"
        ? "📷 صورة"
        : type == "video"
            ? "🎥 فيديو"
            : type == "audio"
                ? "🎤 رسالة صوتية"
                : (data["text"] ?? "").toString();
    setState(() {
      _replyText = content;
      _replySender = (data["name"] ?? "مستخدم").toString();
      _replyMessageId = messageId;
    });
  }

  void _clearReply() {
    setState(() {
      _replyText = null;
      _replySender = null;
      _replyMessageId = null;
    });
  }

  void _scrollToRepliedMessage(String? messageId) {
    if (messageId == null || _currentMessages == null) return;
    final messageKey = _messageKeys[messageId];
    final messageContext = messageKey?.currentContext;
    if (messageContext == null) return;
    Scrollable.ensureVisible(
      messageContext,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: 0.35,
    );
    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  Widget _replyPreview() {
    if (_replyText == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        border: const Border(left: BorderSide(color: Colors.indigo, width: 4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_replySender ?? "مستخدم",
                    style: const TextStyle(
                        color: Colors.indigo, fontWeight: FontWeight.bold)),
                Text(_replyText!, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _clearReply,
          ),
        ],
      ),
    );
  }

  Widget _quotedMessage(Map<String, dynamic> data, bool isMe) {
    final quoted = data["replyText"]?.toString();
    if (quoted == null || quoted.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _scrollToRepliedMessage(data["replyToId"]?.toString()),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isMe ? Colors.white24 : Colors.black12,
          border: Border(
            left: BorderSide(
              color: isMe ? Colors.white70 : Colors.indigo,
              width: 3,
            ),
          ),
        ),
        child: Text(
          "${data["replySender"] ?? "مستخدم"}: $quoted",
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: isMe ? Colors.white70 : Colors.black54,
          ),
        ),
      ),
    );
  }

  void getCurrentUser() {
    final user = _auth.currentUser;
    if (user != null) signedInUser = user;
  }

  @override
  void initState() {
    super.initState();
    getCurrentUser();
    NotificationService.currentOpenChatKey = _chatKey;
  }

  @override
  void dispose() {
    if (NotificationService.currentOpenChatKey == _chatKey) {
      NotificationService.currentOpenChatKey = null;
    }
    messageController.dispose();
    searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// وقت الرسالة بالميلي ثانية للترتيب: createdAt (وقت محلي فوري، متوفر
  /// دايماً من لحظة الإرسال) إذا موجودة، وإلا نرجع لـ timestamp (السيرفر،
  /// ومتوفرة أكيد للرسائل القديمة يلي خلص السيرفر عليها من زمان).
  int _messageMillis(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final createdAt = data["createdAt"];
    if (createdAt is int) return createdAt;
    final ts = data["timestamp"] as Timestamp?;
    return ts?.millisecondsSinceEpoch ?? 0;
  }

  /// القائمة reverse (بترسم من الأسفل)، فـ"آخر رسالة" هي offset 0 - مش
  /// maxScrollExtent متل قائمة عادية.
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
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

    final replyFields = _replyFields();
    messageController.clear();
    _clearReply();
    await Future.delayed(const Duration(milliseconds: 50));
    _scrollToBottom();

    try {
      String senderName = signedInUser!.displayName ??
          (signedInUser!.isAnonymous ? "مستخدم مجهول" : "مستخدم");
      String senderEmail = signedInUser!.email ??
          (signedInUser!.isAnonymous
              ? "anonymous_${signedInUser!.uid}"
              : "unknown");

      await _firestore.collection("messages").add({
        "text": text,
        ...replyFields,
        "sender": senderEmail,
        "chatType": "public",
        "name": senderName,
        "photoUrl": signedInUser!.photoURL,
        "userId": signedInUser!.uid,
        "timestamp": FieldValue.serverTimestamp(),
        "createdAt": DateTime.now().millisecondsSinceEpoch,
        "isAnonymous": signedInUser!.isAnonymous,
      });

      NotificationService.notifyForNewMessage(
        senderEmail: senderEmail,
        senderName: senderName,
        type: "text",
        text: text,
      );

      await Future.delayed(const Duration(milliseconds: 200));
      _scrollToBottom();
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("خطأ: ${e.message}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
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

  Future<void> _sendAudioMessage(String audioUrl, int durationSeconds) async {
    if (signedInUser == null) return;

    String senderName = signedInUser!.displayName ??
        (signedInUser!.isAnonymous ? "مستخدم مجهول" : "مستخدم");
    String senderEmail = signedInUser!.email ??
        (signedInUser!.isAnonymous
            ? "anonymous_${signedInUser!.uid}"
            : "unknown");

    await _firestore.collection("messages").add({
      "audioUrl": audioUrl,
      ..._replyFields(),
      "type": "audio",
      "duration": durationSeconds,
      "sender": senderEmail,
      "chatType": "public",
      "name": senderName,
      "photoUrl": signedInUser!.photoURL,
      "userId": signedInUser!.uid,
      "timestamp": FieldValue.serverTimestamp(),
      "createdAt": DateTime.now().millisecondsSinceEpoch,
      "isAnonymous": signedInUser!.isAnonymous,
    });
    NotificationService.notifyForNewMessage(
      senderEmail: senderEmail,
      senderName: senderName,
      type: "audio",
    );

    if (mounted) _clearReply();
    await Future.delayed(const Duration(milliseconds: 200));
    _scrollToBottom();
  }

  Future<void> _sendImageMessage(String imageUrl) async {
    if (signedInUser == null) return;

    String senderName = signedInUser!.displayName ??
        (signedInUser!.isAnonymous ? "مستخدم مجهول" : "مستخدم");
    String senderEmail = signedInUser!.email ??
        (signedInUser!.isAnonymous
            ? "anonymous_${signedInUser!.uid}"
            : "unknown");

    await _firestore.collection("messages").add({
      "imageUrl": imageUrl,
      ..._replyFields(),
      "type": "image",
      "sender": senderEmail,
      "chatType": "public",
      "name": senderName,
      "photoUrl": signedInUser!.photoURL,
      "userId": signedInUser!.uid,
      "timestamp": FieldValue.serverTimestamp(),
      "createdAt": DateTime.now().millisecondsSinceEpoch,
      "isAnonymous": signedInUser!.isAnonymous,
    });
    NotificationService.notifyForNewMessage(
      senderEmail: senderEmail,
      senderName: senderName,
      type: "image",
    );

    if (mounted) _clearReply();
    await Future.delayed(const Duration(milliseconds: 200));
    _scrollToBottom();
  }

  Future<void> _sendVideoMessage(String videoUrl) async {
    if (signedInUser == null) return;

    String senderName = signedInUser!.displayName ??
        (signedInUser!.isAnonymous ? "مستخدم مجهول" : "مستخدم");
    String senderEmail = signedInUser!.email ??
        (signedInUser!.isAnonymous
            ? "anonymous_${signedInUser!.uid}"
            : "unknown");

    await _firestore.collection("messages").add({
      "videoUrl": videoUrl,
      ..._replyFields(),
      "type": "video",
      "sender": senderEmail,
      "chatType": "public",
      "name": senderName,
      "photoUrl": signedInUser!.photoURL,
      "userId": signedInUser!.uid,
      "timestamp": FieldValue.serverTimestamp(),
      "createdAt": DateTime.now().millisecondsSinceEpoch,
      "isAnonymous": signedInUser!.isAnonymous,
    });
    NotificationService.notifyForNewMessage(
      senderEmail: senderEmail,
      senderName: senderName,
      type: "video",
    );

    if (mounted) _clearReply();
    await Future.delayed(const Duration(milliseconds: 200));
    _scrollToBottom();
  }

  Future<void> _startGroupCall(bool isVideoCall) async {
    if (signedInUser == null) return;
    final hostName =
        signedInUser!.displayName ?? signedInUser!.email ?? "مستخدم";
    final callRef = _firestore.collection("group_calls").doc();

    await callRef.set({
      "hostEmail": signedInUser!.email,
      "hostName": hostName,
      "isVideoCall": isVideoCall,
      "createdAt": FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          callId: callRef.id,
          isVideoCall: isVideoCall,
        ),
      ),
    );

    GroupCallLink.share(
      callId: callRef.id,
      isVideoCall: isVideoCall,
      hostName: hostName,
    );
  }

  void _showStartGroupCallDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("مكالمة جماعية"),
        content: const Text("ابدأ مكالمة جديدة وشارك رابطها، أو انضم لمكالمة حدا دعاك إلها."),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.call),
            label: const Text("صوت"),
            onPressed: () {
              Navigator.pop(dialogContext);
              _startGroupCall(false);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.videocam),
            label: const Text("فيديو"),
            onPressed: () {
              Navigator.pop(dialogContext);
              _startGroupCall(true);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.link),
            label: const Text("انضم برابط"),
            onPressed: () {
              Navigator.pop(dialogContext);
              _showJoinGroupCallDialog();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleLinkTap(String url) async {
    final parsed = url.startsWith('groupify://')
        ? GroupCallLink.parseFromText(url)
        : null;
    if (parsed != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(
            callId: parsed.callId,
            isVideoCall: parsed.isVideoCall,
          ),
        ),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("ما قدرت افتح الرابط"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showJoinGroupCallDialog() {
    final linkController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("الانضمام لمكالمة جماعية"),
        content: TextField(
          controller: linkController,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            hintText: "الصق رابط الدعوة هون...",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("إلغاء"),
          ),
          FilledButton(
            onPressed: () {
              final parsed = GroupCallLink.parseFromText(linkController.text);
              Navigator.pop(dialogContext);
              if (parsed == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("رابط الدعوة مش صحيح"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupCallScreen(
                    callId: parsed.callId,
                    isVideoCall: parsed.isVideoCall,
                  ),
                ),
              );
            },
            child: const Text("انضم"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelecting
          ? _buildSelectionAppBar()
          : AppBar(
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
            : const Text(
                "المجموعة الأساسية",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
        actions: [
          if (isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  isSearching = false;
                  searchController.clear();
                  searchText = "";
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: "مكالمة جماعية",
            onPressed: _showStartGroupCallDialog,
          ),
          IconButton(
            icon: Icon(
              ChatMuteService.instance.isMuted(_chatKey)
                  ? Icons.notifications_off
                  : Icons.notifications_active,
            ),
            tooltip: ChatMuteService.instance.isMuted(_chatKey)
                ? "إلغاء كتم إشعارات المجموعة العامة"
                : "كتم إشعارات المجموعة العامة",
            onPressed: () async {
              await ChatMuteService.instance.toggleMute(_chatKey);
              if (mounted) setState(() {});
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'search') setState(() => isSearching = true);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'search', child: Text('البحث عن رسائل')),
            ],
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
                  // limitToLast بيمنع تحميل كل تاريخ المحادثة كل مرة - بس
                  // آخر 200 رسالة، وهاد أكبر سبب بطء بمحادثة قديمة وكبيرة.
                  // الترتيب هون على timestamp (تضل كل الرسائل القديمة
                  // ظاهرة - Firestore بيستبعد أي مستند ما فيه الحقل يلي
                  // بترتب عليه)، وبعيد الترتيب النهائي محلياً بالـ Dart
                  // فوق createdAt لتفادي الفلاشة.
                  stream: _firestore
                      .collection("messages")
                      .orderBy("timestamp", descending: false)
                      .limitToLast(200)
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

                    // الأحدث أول (index 0) عشان القائمة reverse: true -
                    // هيك بتنرسم دايماً "ملتصقة" بآخر رسالة من غير ما
                    // نحتاج نقفز لأي مكان يدوياً بعد أول فتح أو بعد إرسال.
                    final messages = List<QueryDocumentSnapshot>.from(
                      snapshot.data!.docs,
                    )..sort((a, b) => _messageMillis(b).compareTo(_messageMillis(a)));
                    _currentMessages = messages;

                    return ListView.builder(
                      reverse: true,
                      controller: _scrollController,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final data = message.data() as Map<String, dynamic>;

                        final name = data["name"] ?? "مستخدم";
                        final text = data["text"] ?? "";
                        final audioUrl = data["audioUrl"] as String?;
                        final imageUrl = data["imageUrl"] as String?;
                        final videoUrl = data["videoUrl"] as String?;
                        final messageType = data["type"] ?? "text";
                        final photoUrl = data["photoUrl"] as String?;
                        final nameLower = name.toLowerCase();
                        final textLower = text.toLowerCase();
                        final query = searchText.toLowerCase();

                        if (query.isNotEmpty &&
                            !nameLower.contains(query) &&
                            !textLower.contains(query)) {
                          return const SizedBox.shrink();
                        }

                        if (messageType == "text" && text.trim().isEmpty) {
                          return const SizedBox.shrink();
                        }
                        if (messageType == "audio" && audioUrl == null) {
                          return const SizedBox.shrink();
                        }
                        if (messageType == "image" && imageUrl == null) {
                          return const SizedBox.shrink();
                        }
                        if (messageType == "video" && videoUrl == null) {
                          return const SizedBox.shrink();
                        }
                        final deletedFor = List<String>.from(data["deletedFor"] ?? []);
                        if (deletedFor.contains(signedInUser?.uid)) {
                          return const SizedBox.shrink();
                        }

                        final sender = data["sender"] ?? "";
                        final isMe = sender == (signedInUser?.email ?? "");
                        // القائمة reverse (index 0 = الأحدث)، فالرسالة
                        // "قبل" هاي زمنياً (الأقدم) موجودة بعدها بالقائمة
                        // (index + 1) مش قبلها.
                        final previousSender = index + 1 < messages.length
                            ? ((messages[index + 1].data()
                                    as Map<String, dynamic>)["sender"] ??
                                "")
                            : null;
                        final isFirstFromSender = previousSender != sender;
                        final isSelected = _selectedMessageIds.contains(message.id);

                        return KeyedSubtree(
                          key: _messageKeys.putIfAbsent(
                            message.id,
                            () => GlobalKey(),
                          ),
                          child: Builder(
                            builder: (messageContext) => GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _isSelecting
                                  ? () => _toggleSelected(message.id)
                                  : null,
                              onLongPressStart: (_) {
                                HapticFeedback.mediumImpact();
                                if (_isSelecting) {
                                  _toggleSelected(message.id);
                                  return;
                                }
                                showReactionPicker(
                                  messageContext,
                                  messageRef: message.reference,
                                  data: data,
                                  currentUserId: signedInUser?.uid ?? '',
                                  isMe: isMe,
                                  onSelectRequested: () => _toggleSelected(message.id),
                                );
                              },
                              onHorizontalDragEnd: (details) {
                                if ((details.primaryVelocity ?? 0).abs() > 250) {
                                  _setReply(data, message.id);
                                }
                              },
                              child: Container(
                                color: isSelected
                                    ? Colors.indigo.withValues(alpha: 0.12)
                                    : null,
                                padding: EdgeInsets.only(
                                  top: isFirstFromSender ? 6 : 1,
                                  bottom: isFirstFromSender ? 6 : 1,
                                ),
                                child: Row(
                                  mainAxisAlignment: isMe
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment: isMe
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          if (!isMe && isFirstFromSender)
                                            Padding(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  CircleAvatar(
                                                    radius: 16,
                                                    backgroundColor:
                                                        Colors.indigo.shade100,
                                                    backgroundImage: (photoUrl !=
                                                                null &&
                                                            photoUrl.isNotEmpty)
                                                        ? CachedNetworkImageProvider(
                                                            photoUrl)
                                                        : null,
                                                    child: (photoUrl == null ||
                                                            photoUrl.isEmpty)
                                                        ? Icon(Icons.person,
                                                            size: 18,
                                                            color: Colors
                                                                .indigo.shade700)
                                                        : null,
                                                  ),
                                                  const SizedBox(width: 7),
                                                  GestureDetector(
                                                    onTap: () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (_) =>
                                                              PrivateChatScreen(
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
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors
                                                            .indigo.shade700,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (!isMe && isFirstFromSender)
                                            const SizedBox(height: 4),
                                          if (messageType == "audio" &&
                                              audioUrl != null)
                                            Padding(
                                              padding: EdgeInsets.only(
                                                left: isMe ? 0 : 38,
                                              ),
                                              child: AudioMessageWidget(
                                                audioUrl: audioUrl,
                                                isMe: isMe,
                                                senderName: name,
                                              ),
                                            )
                                          else if (messageType == "image" &&
                                              imageUrl != null)
                                            Padding(
                                              padding: EdgeInsets.only(
                                                left: isMe ? 0 : 38,
                                              ),
                                              child: ImageMessageWidget(
                                                imageUrl: imageUrl,
                                                isMe: isMe,
                                              ),
                                            )
                                          else if (messageType == "video" &&
                                              videoUrl != null)
                                            Padding(
                                              padding: EdgeInsets.only(
                                                left: isMe ? 0 : 38,
                                              ),
                                              child: VideoMessageWidget(
                                                videoUrl: videoUrl,
                                                isMe: isMe,
                                              ),
                                            )
                                          else
                                            Align(
                                              alignment: isMe
                                                  ? Alignment.centerRight
                                                  : Alignment.centerLeft,
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                    milliseconds: 300),
                                                constraints: const BoxConstraints(
                                                  maxWidth: 280,
                                                ),
                                                margin: EdgeInsets.only(
                                                  left: isMe ? 8 : 46,
                                                  right: 8,
                                                ),
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                  horizontal: 14,
                                                  vertical: 10,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _highlightedMessageId ==
                                                          message.id
                                                      ? Colors.amber.shade300
                                                      : (isMe
                                                          ? Colors.indigo
                                                          : Colors
                                                              .grey.shade200),
                                                  borderRadius:
                                                      BorderRadius.only(
                                                    topLeft:
                                                        const Radius.circular(18),
                                                    topRight:
                                                        const Radius.circular(18),
                                                    bottomLeft: Radius.circular(
                                                      isMe ? 18 : 4,
                                                    ),
                                                    bottomRight: Radius.circular(
                                                      isMe ? 4 : 18,
                                                    ),
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    _quotedMessage(data, isMe),
                                                    LinkifiedText(
                                                      text: text,
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        color: isMe
                                                            ? Colors.white
                                                            : Colors.black87,
                                                      ),
                                                      linkColor: isMe
                                                          ? Colors
                                                              .lightBlueAccent
                                                          : Colors.blue,
                                                      onLinkTap: _handleLinkTap,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          MessageReactionsBadge(
                                            data: data,
                                            isMe: isMe,
                                            currentUserId:
                                                signedInUser?.uid ?? '',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _replyPreview(),
                  AudioComposerBar(
                    controller: messageController,
                    onSendText: sendMessage,
                    userId: signedInUser?.uid ?? '',
                    onAudioRecorded: _sendAudioMessage,
                    onImageSent: _sendImageMessage,
                    onVideoSent: _sendVideoMessage,
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
