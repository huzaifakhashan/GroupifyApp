import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Screens/CallScreen.dart';
import 'package:groupify_app/Screens/groupCallScreen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:groupify_app/Widgets/audioMessageWidget.dart';
import 'package:groupify_app/Widgets/imageMessageWidget.dart';
import 'package:groupify_app/Widgets/videoMessageWidget.dart';
import 'package:groupify_app/Widgets/audioComposerBar.dart';
import 'package:groupify_app/Widgets/messageReactions.dart';
import 'package:groupify_app/Widgets/linkifiedText.dart';
import 'package:groupify_app/Services/notificationService.dart';
import 'package:groupify_app/Services/groupCallLink.dart';
import 'package:groupify_app/Services/chatMuteService.dart';
import 'package:groupify_app/Services/statusService.dart';
import 'package:groupify_app/Screens/statusViewerScreen.dart';

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
  bool _statusUpdateInProgress = false;
  String? _replyText;
  String? _replySender;
  String? _replyMessageId;
  String? _highlightedMessageId;
  List<QueryDocumentSnapshot>? _currentMessages;
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};

  final Set<String> _selectedMessageIds = {};
  bool get _isSelecting => _selectedMessageIds.isNotEmpty;

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
    for (final id in _selectedMessageIds) {
      final match = _currentMessages!.where((m) => m.id == id);
      if (match.isEmpty) return false;
      final data = match.first.data() as Map<String, dynamic>;
      if ((data["sender"] ?? "") != signedInUser.email) return false;
    }
    return true;
  }

  Future<void> _deleteSelected({required bool forEveryone}) async {
    final ids = _selectedMessageIds.toList();
    final chatRef = _firestore.collection("private_chats").doc(getChatId());
    for (final id in ids) {
      final ref = chatRef.collection("messages").doc(id);
      try {
        if (forEveryone) {
          await ref.delete();
        } else {
          await ref.update({
            "deletedFor": FieldValue.arrayUnion([signedInUser.uid]),
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

  bool _amIBlockedByThem = false;
  String? _otherUserUid;
  Timestamp? _myClearedAt;
  Timestamp? _deletedForEveryoneAt;
  StreamSubscription<QuerySnapshot>? _otherUserSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _chatMetaSub;

  Timestamp? _laterOf(Timestamp? a, Timestamp? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.compareTo(b) >= 0 ? a : b;
  }

  Future<void> _updateMessageStatus(
    List<QueryDocumentSnapshot> messages, {
    required int status,
  }) async {
    final batch = _firestore.batch();
    var updates = 0;

    for (final message in messages) {
      final data = message.data() as Map<String, dynamic>;
      if (data["sender"] == signedInUser.email) continue;
      final currentStatus = (data["status"] as num?)?.toInt() ?? 1;
      if (currentStatus >= status) continue;

      batch.update(message.reference, {
        "status": status,
        if (status == 2) "deliveredAt": FieldValue.serverTimestamp(),
        if (status == 3) "readAt": FieldValue.serverTimestamp(),
      });
      batch.set(
        _firestore.collection("private_chats").doc(getChatId()),
        {"lastMessageStatus": status},
        SetOptions(merge: true),
      );
      updates++;
    }

    if (updates > 0) await batch.commit();
  }

  Future<void> _markMessagesDeliveredAndRead(
    List<QueryDocumentSnapshot> messages,
  ) async {
    if (_statusUpdateInProgress) return;
    _statusUpdateInProgress = true;
    try {
      await _updateMessageStatus(messages, status: 2);
      await Future.delayed(const Duration(milliseconds: 300));
      await _updateMessageStatus(messages, status: 3);
    } catch (e) {
      print("⚠️ تعذر تحديث حالة الرسائل (تسليم/قراءة): $e");
    } finally {
      _statusUpdateInProgress = false;
    }
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
        border: Border(left: BorderSide(color: Colors.indigo, width: 4)),
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
            onPressed: () => setState(() {
              _replyText = null;
              _replySender = null;
              _replyMessageId = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _quotedMessage(Map<String, dynamic> data) {
    final quoted = data["replyText"]?.toString();
    if (quoted == null || quoted.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _scrollToRepliedMessage(data["replyToId"]?.toString()),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.12),
          border: const Border(left: BorderSide(color: Colors.white70, width: 3)),
        ),
        child: Text(
          "${data["replySender"] ?? "مستخدم"}: $quoted",
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ),
    );
  }

  /// تشيك حالة الرسالة متل الواتساب: ساعة (⏱) لحد ما توصل السيرفر (لسا
  /// عم تترسل - متلاً بدون نت)، تشيك وحدة أول ما توصل، تشيكين رمادي لما
  /// توصل لجهاز المستلم، وتشيكين أزرق لما يقراها. hasPendingWrites من
  /// Firestore بيخبرنا إذا الكتابة لسا محلية بس وما وصلت السيرفر فعلياً.
  Widget _messageStatus(Map<String, dynamic> data, QueryDocumentSnapshot message) {
    // التشيك عم يترسم تحت/برا الفقاعة الملوّنة، على خلفية الشات البيضاء -
    // فلازم ألوان تبيّن عليها (رمادي/أزرق)، مش أبيض شفاف يختفي فيها.
    if (message.metadata.hasPendingWrites) {
      return Icon(Icons.access_time, size: 13, color: Colors.grey.shade500);
    }
    final status = (data["status"] as num?)?.toInt() ?? 1;
    // Icons.done_all رمز واحد مصمم أصلاً بنفس تقارب تشيكات الواتساب -
    // مش تشيكتين Icons.done جنب بعض (بيصير بينهم مسافة افتراضية واضحة).
    if (status <= 1) {
      return Icon(Icons.done, size: 15, color: Colors.grey.shade500);
    }
    return Icon(
      Icons.done_all,
      size: 16,
      color: status >= 3 ? Colors.blue : Colors.grey.shade500,
    );
  }

  String getChatId() {
    List<String> users = [signedInUser.email!, widget.userEmail];

    users.sort();

    return users.join("_");
  }
Future<void> createCall({required bool isVideo}) async {

  final callDoc =
      FirebaseFirestore.instance.collection("calls").doc();


  await callDoc.set({

    "caller": signedInUser.email,

    "callerName": signedInUser.displayName ?? "User",

    "receiver": widget.userEmail,

    "receiverName": widget.userName,

    "status": "ringing",

    "isVideo": isVideo,

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
        isVideoCall: isVideo,
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
    NotificationService.currentOpenChatKey = widget.userEmail;

    _otherUserSub = _firestore
        .collection("users")
        .where("email", isEqualTo: widget.userEmail)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (!mounted || snap.docs.isEmpty) return;
      final data = snap.docs.first.data();
      final blocked = List<String>.from(data["blockedUsers"] ?? const []);
      setState(() {
        _amIBlockedByThem = blocked.contains(signedInUser.email);
        _otherUserUid = snap.docs.first.id;
      });
    });

    _chatMetaSub = _firestore
        .collection("private_chats")
        .doc(getChatId())
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      final participants = [signedInUser.email!, widget.userEmail]..sort();
      final myIndex = participants.indexOf(signedInUser.email!);
      setState(() {
        _myClearedAt = data?["clearedAt$myIndex"] as Timestamp?;
        _deletedForEveryoneAt = data?["deletedForEveryoneAt"] as Timestamp?;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    if (NotificationService.currentOpenChatKey == widget.userEmail) {
      NotificationService.currentOpenChatKey = null;
    }
    _otherUserSub?.cancel();
    _chatMetaSub?.cancel();
    super.dispose();
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

  String _formatLastSeen(Timestamp? timestamp) {
    if (timestamp == null) return "غير متصل";
    final difference = DateTime.now().difference(timestamp.toDate());
    if (difference.inMinutes < 1) return "آخر ظهور الآن";
    if (difference.inMinutes < 60) {
      return "آخر ظهور منذ ${difference.inMinutes} د";
    }
    if (difference.inHours < 24) return "آخر ظهور منذ ${difference.inHours} س";
    return "آخر ظهور ${timestamp.toDate().day}/${timestamp.toDate().month}";
  }

  void _showProfilePhoto(String photoUrl) {
    if (photoUrl.isEmpty) return;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 3,
          child: SizedBox(
            width: 240,
            height: 240,
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: photoUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// يفتح حالة هالشخص إذا عندو وحدة نشطة (آخر 24 ساعة)، وإلا بيعرض
  /// رسالة إنه ما عندو حالة حالياً. بنستخدم نفس ستريم الحالات النشطة
  /// (StatusService.activeStatuses) وبنفلتر محلياً بدل استعلام مركّب
  /// جديد بيحتاج index إضافي بالـ Firestore.
  Future<void> _viewUserStatus() async {
    final uid = _otherUserUid;
    if (uid == null) return;

    final snapshot = await StatusService.activeStatuses().first;
    final userStatuses = snapshot.docs
        .where((doc) => doc.data()["uid"] == uid)
        .toList()
      ..sort((a, b) {
        final ta = a.data()["createdAt"] as Timestamp?;
        final tb = b.data()["createdAt"] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return -1;
        if (tb == null) return 1;
        return ta.compareTo(tb);
      });

    if (userStatuses.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ما عندو حالة نشطة حالياً")),
        );
      }
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatusViewerScreen(
          uid: uid,
          name: widget.userName,
          photoUrl: userStatuses.first.data()["photoUrl"] as String?,
          statuses: userStatuses,
        ),
      ),
    );
  }

  void sendMessage() async {
    final text = messageController.text.trim();

    if (text.isEmpty) return;

    // 👇 فضي الحقل ونظف الرد فوراً حتى تحس الواجهة إنها استجابت لحظة
    // الإرسال، بدل ما تنتظر رد Firestore
    final replyText = _replyText;
    final replySender = _replySender;
    final replyMessageId = _replyMessageId;
    messageController.clear();
    setState(() {
      _replyText = null;
      _replySender = null;
      _replyMessageId = null;
    });
    await Future.delayed(const Duration(milliseconds: 50));
    _scrollToBottom();

    await _sendChatUpdate(lastMessage: text, messageData: {
      "text": text,
      if (replyText != null) "replyText": replyText,
      if (replySender != null) "replySender": replySender,
      if (replyMessageId != null) "replyToId": replyMessageId,
    });
  }

  Future<void> _sendAudioMessage(String audioUrl, int durationSeconds) async {
    await _sendChatUpdate(lastMessage: "🎤 رسالة صوتية", messageData: {
      "audioUrl": audioUrl,
      "type": "audio",
      "duration": durationSeconds,
    });
  }

  Future<void> _sendImageMessage(String imageUrl) async {
    await _sendChatUpdate(lastMessage: "📷 صورة", messageData: {
      "imageUrl": imageUrl,
      "type": "image",
    });
  }

  Future<void> _sendVideoMessage(String videoUrl) async {
    await _sendChatUpdate(lastMessage: "🎥 فيديو", messageData: {
      "videoUrl": videoUrl,
      "type": "video",
    });
  }

  Future<void> _sendChatUpdate({
    required String lastMessage,
    required Map<String, dynamic> messageData,
  }) async {
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
      ...messageData,
      "sender": myEmail,
      "receiver": widget.userEmail,
      "name": myName,
      "status": 1,
      "timestamp": FieldValue.serverTimestamp(),
      // createdAt متوفرة فوراً محلياً (مش زي serverTimestamp يلي بتضل null
      // لحد ما يرد السيرفر)، فبنرتب الرسائل عليها حتى ما الرسالة يلي
      // بعتها هلق تطلع فوق الصفحة لحظة وبعدين تنزل لتحت لما الوقت يوصل.
      "createdAt": DateTime.now().millisecondsSinceEpoch,
    });
    NotificationService.notifyForNewMessage(
      senderEmail: myEmail,
      senderName: myName,
      type: messageData["type"] as String? ?? "text",
      text: messageData["text"] as String?,
      receiverEmail: widget.userEmail,
    );

    await chatDoc.set({
      "participants": participants,
      "participantNames": names,
      "lastMessage": lastMessage,
      "lastMessageTime": FieldValue.serverTimestamp(),
      "lastSenderEmail": myEmail,
      "lastMessageStatus": 1,
      "unreadCount$otherIndex": FieldValue.increment(1),
      "unreadCount$myIndex": 0,
    }, SetOptions(merge: true));

    await Future.delayed(const Duration(milliseconds: 200));
    _scrollToBottom();
  }

  Future<void> _toggleBlock() async {
    await ChatMuteService.instance.toggleBlock(widget.userEmail);
    if (mounted) setState(() {});
  }

  Future<void> _deleteForMe() async {
    final participants = [signedInUser.email!, widget.userEmail]..sort();
    final myIndex = participants.indexOf(signedInUser.email!);
    await _firestore.collection("private_chats").doc(getChatId()).set({
      "clearedAt$myIndex": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteForEveryone() async {
    await _firestore.collection("private_chats").doc(getChatId()).set({
      "deletedForEveryoneAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) Navigator.pop(context);
  }

  void _confirmDeleteForEveryone() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("حذف لدى الطرفين"),
        content: Text(
          "رح تنحذف كل الرسائل عندك وعند ${widget.userName} ولا تقدر ترجعها. متأكد؟",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteForEveryone();
            },
            child: const Text("حذف", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDeleteChatDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("حذف الدردشة"),
        content: const Text("شو بدك تحذف؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteForMe();
            },
            child: const Text("حذف لدي فقط"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _confirmDeleteForEveryone();
            },
            child: const Text("حذف لدى الطرفين", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmToggleBlock() {
    final isBlocked = ChatMuteService.instance.isBlocked(widget.userEmail);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isBlocked ? "إلغاء حظر ${widget.userName}" : "حظر ${widget.userName}"),
        content: Text(
          isBlocked
              ? "رح تقدر تبعت وتستقبل رسائل من هاد المستخدم متل العادة."
              : "ما رح تستقبل إشعارات ولا تقدر تبعت رسائل لهاد المستخدم.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _toggleBlock();
            },
            child: Text(
              isBlocked ? "إلغاء الحظر" : "حظر",
              style: TextStyle(color: isBlocked ? null : Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatId = getChatId();
    final iBlockedThem = ChatMuteService.instance.isBlocked(widget.userEmail);
    final blockedEitherWay = iBlockedThem || _amIBlockedByThem;
    final hideCutoff = _laterOf(_myClearedAt, _deletedForEveryoneAt);
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
            : Row(
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection("users")
                        .where("email", isEqualTo: widget.userEmail)
                        .limit(1)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final userData = snapshot.hasData &&
                              snapshot.data!.docs.isNotEmpty
                          ? snapshot.data!.docs.first.data()
                              as Map<String, dynamic>
                          : <String, dynamic>{};
                      final photoUrl = (userData["photoUrl"] ?? "").toString();
                      return GestureDetector(
                        onTap: () => _showProfilePhoto(photoUrl),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white,
                          backgroundImage: photoUrl.isEmpty
                            ? null
                            : CachedNetworkImageProvider(photoUrl),
                          child: photoUrl.isEmpty
                            ? const Icon(Icons.person,
                              color: Colors.indigo, size: 20)
                            : null,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection("users")
                          .where("email", isEqualTo: widget.userEmail)
                          .limit(1)
                          .snapshots(),
                      builder: (context, snapshot) {
                        final userData = snapshot.hasData &&
                                snapshot.data!.docs.isNotEmpty
                            ? snapshot.data!.docs.first.data()
                                as Map<String, dynamic>
                            : <String, dynamic>{};
                        final photoUrl = (userData["photoUrl"] ?? "").toString();
                        final isOnline = userData["isOnline"] == true;
                        final lastSeen = userData["lastSeen"] as Timestamp?;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => _showProfilePhoto(photoUrl),
                              child: Text(
                                widget.userName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              isOnline ? "متصل الآن" : _formatLastSeen(lastSeen),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
        actions: [
          if (isSearching)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                setState(() {
                  isSearching = false;
                  searchController.clear();
                  searchText = "";
                });
              },
            ),
          IconButton(
  icon: const Icon(
    Icons.call,
    color: Colors.white,
  ),
  onPressed: blockedEitherWay ? null : () {
    createCall(isVideo: false);
  },
),
          IconButton(
  icon: const Icon(
    Icons.videocam,
    color: Colors.white,
  ),
  onPressed: blockedEitherWay ? null : () {
    createCall(isVideo: true);
  },
),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) async {
              if (value == 'search') setState(() => isSearching = true);
              if (value == 'status') _viewUserStatus();
              if (value == 'mute') {
                await ChatMuteService.instance.toggleMute(widget.userEmail);
                if (mounted) setState(() {});
              }
              if (value == 'block') _confirmToggleBlock();
              if (value == 'delete') _showDeleteChatDialog();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'search', child: Text('البحث عن رسائل')),
              const PopupMenuItem(value: 'status', child: Text('عرض الحالة')),
              PopupMenuItem(
                value: 'mute',
                child: Text(
                  ChatMuteService.instance.isMuted(widget.userEmail)
                      ? 'إلغاء كتم الإشعارات'
                      : 'كتم الإشعارات',
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: Text(iBlockedThem ? 'إلغاء حظر المستخدم' : 'حظر المستخدم'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('حذف الدردشة')),
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
            // 🔝 Header

            // 💬 Messages
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
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
                      .collection("private_chats")
                      .doc(chatId)
                      .collection("messages")
                      .orderBy("timestamp")
                      .limitToLast(200)
                      // includeMetadataChanges حتى نلحظ فوراً لما الرسالة
                      // توصل السيرفر فعلياً (hasPendingWrites يصير false)
                      // وتتغيّر أيقونة الساعة لتشيك مباشرة، بدون ما نستنى
                      // تغيير تاني بالمحادثة يحرّك الـ StreamBuilder.
                      .snapshots(includeMetadataChanges: true),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    // الأحدث أول (index 0) عشان القائمة reverse: true -
                    // هيك بتنرسم دايماً "ملتصقة" بآخر رسالة من غير ما
                    // نحتاج نقفز لأي مكان يدوياً بعد أول فتح أو بعد إرسال.
                    final messages = List<QueryDocumentSnapshot>.from(
                      snapshot.data!.docs,
                    )..sort((a, b) => _messageMillis(b).compareTo(_messageMillis(a)));
                    _currentMessages = messages;
                    _markMessagesDeliveredAndRead(messages);
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
                        final messageTimestamp = data["timestamp"] as Timestamp?;
                        if (hideCutoff != null &&
                            messageTimestamp != null &&
                            messageTimestamp.compareTo(hideCutoff) <= 0) {
                          return const SizedBox.shrink();
                        }
                        final deletedFor = List<String>.from(data["deletedFor"] ?? []);
                        if (deletedFor.contains(signedInUser.uid)) {
                          return const SizedBox.shrink();
                        }
                        final sender = data["sender"] ?? "";
                        final isMe = sender == signedInUser.email;
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
                              currentUserId: signedInUser.uid,
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
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (messageType == "audio" && audioUrl != null)
                                AudioMessageWidget(
                                  audioUrl: audioUrl,
                                  isMe: isMe,
                                  senderName: name,
                                )
                              else if (messageType == "image" &&
                                  imageUrl != null)
                                ImageMessageWidget(
                                  imageUrl: imageUrl,
                                  isMe: isMe,
                                )
                              else if (messageType == "video" &&
                                  videoUrl != null)
                                VideoMessageWidget(
                                  videoUrl: videoUrl,
                                  isMe: isMe,
                                )
                              else
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
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _quotedMessage(data),
                                        LinkifiedText(
                                          text: text,
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: isMe
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                          linkColor: isMe
                                              ? Colors.lightBlueAccent
                                              : Colors.blue,
                                          onLinkTap: _handleLinkTap,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              // تشيك حالة الرسالة (بانتظار الإرسال / وحدة /
                              // اثنين رمادي / اثنين أزرق) لأي رسالة إلي،
                              // متل الواتساب بالظبط - لكل أنواع الرسائل
                              // (نص، صوت، صورة، فيديو).
                              if (isMe)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 2,
                                    right: 8,
                                    left: 8,
                                  ),
                                  child: _messageStatus(data, message),
                                ),
                              MessageReactionsBadge(
                                data: data,
                                isMe: isMe,
                                currentUserId: signedInUser.uid,
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

            // ⌨️ Input
            Container(
              padding: const EdgeInsets.all(10),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _replyPreview(),
                  if (blockedEitherWay)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              iBlockedThem
                                  ? "لقد حظرت هذا المستخدم"
                                  : "ما فيك تبعت رسالة لهاد المستخدم",
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                          if (iBlockedThem)
                            TextButton(
                              onPressed: _toggleBlock,
                              child: const Text("إلغاء الحظر"),
                            ),
                        ],
                      ),
                    )
                  else
                    AudioComposerBar(
                      controller: messageController,
                      onSendText: sendMessage,
                      userId: signedInUser.uid,
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
