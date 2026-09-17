import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:groupify_app/Screens/groupCallScreen.dart';
import 'package:groupify_app/Screens/privateChatScreen.dart';
import 'package:groupify_app/Services/imageService.dart';
import 'package:groupify_app/Widgets/audioMessageWidget.dart';
import 'package:groupify_app/Widgets/imageMessageWidget.dart';
import 'package:groupify_app/Widgets/videoMessageWidget.dart';
import 'package:groupify_app/Widgets/audioComposerBar.dart';
import 'package:groupify_app/Widgets/messageReactions.dart';
import 'package:groupify_app/Widgets/linkifiedText.dart';
import 'package:groupify_app/Widgets/userMultiSelectList.dart';
import 'package:groupify_app/Services/notificationService.dart';
import 'package:groupify_app/Services/groupCallLink.dart';
import 'package:groupify_app/Services/chatMuteService.dart';
import 'package:groupify_app/Services/groupInviteService.dart';
import 'package:groupify_app/Services/groupUsernameService.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController messageController = TextEditingController();
  bool isSearching = false;
  String searchText = "";
  final TextEditingController searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late User signedInUser;
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
    for (final id in ids) {
      final ref = _groupRef.collection("messages").doc(id);
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

  List<String> _memberUids = [];
  List<String> _memberEmails = [];
  List<String> _memberNames = [];
  bool _isGroupHidden = false;
  String? _groupUsername;
  String? _createdBy;
  List<String> _admins = [];
  String? _groupPhotoUrl;
  late String _groupName = widget.groupName;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _groupSub;

  bool get _isOwner => _createdBy != null && signedInUser.uid == _createdBy;
  bool get _isAdmin => _admins.contains(signedInUser.uid);
  bool get _canManageGroup => _isOwner || _isAdmin;

  String get _chatKey => "group:${widget.groupId}";

  DocumentReference<Map<String, dynamic>> get _groupRef =>
      _firestore.collection("groups").doc(widget.groupId);

  void getCurrentUser() {
    try {
      final user = _auth.currentUser;
      if (user != null) signedInUser = user;
    } catch (e) {
      print(e);
    }
  }

  @override
  void initState() {
    super.initState();
    getCurrentUser();
    NotificationService.currentOpenChatKey = _chatKey;

    _groupSub = _groupRef.snapshots().listen((snap) {
      final data = snap.data();
      if (data == null || !mounted) return;
      setState(() {
        _memberUids = List<String>.from(data["memberUids"] ?? []);
        _memberEmails = List<String>.from(data["memberEmails"] ?? []);
        _memberNames = List<String>.from(data["memberNames"] ?? []);
        _isGroupHidden = data["isPrivate"] == true;
        _groupUsername = data["groupUsername"] as String?;
        _createdBy = data["createdBy"] as String?;
        _admins = List<String>.from(data["admins"] ?? []);
        _groupPhotoUrl = data["photoUrl"] as String?;
        _groupName = (data["name"] as String?) ?? _groupName;
      });
    });

  }

  @override
  void dispose() {
    if (NotificationService.currentOpenChatKey == _chatKey) {
      NotificationService.currentOpenChatKey = null;
    }
    _groupSub?.cancel();
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

  void sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;

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

    await _sendGroupUpdate(lastMessage: text, messageData: {
      "text": text,
      if (replyText != null) "replyText": replyText,
      if (replySender != null) "replySender": replySender,
      if (replyMessageId != null) "replyToId": replyMessageId,
    });
  }

  Future<void> _sendAudioMessage(String audioUrl, int durationSeconds) async {
    await _sendGroupUpdate(lastMessage: "🎤 رسالة صوتية", messageData: {
      "audioUrl": audioUrl,
      "type": "audio",
      "duration": durationSeconds,
    });
  }

  Future<void> _sendImageMessage(String imageUrl) async {
    await _sendGroupUpdate(lastMessage: "📷 صورة", messageData: {
      "imageUrl": imageUrl,
      "type": "image",
    });
  }

  Future<void> _sendVideoMessage(String videoUrl) async {
    await _sendGroupUpdate(lastMessage: "🎥 فيديو", messageData: {
      "videoUrl": videoUrl,
      "type": "video",
    });
  }

  Future<void> _sendGroupUpdate({
    required String lastMessage,
    required Map<String, dynamic> messageData,
  }) async {
    final myEmail = signedInUser.email!;
    final myName = signedInUser.displayName ?? "User";

    await _groupRef.collection("messages").add({
      ...messageData,
      "sender": myEmail,
      "senderUid": signedInUser.uid,
      "name": myName,
      "photoUrl": signedInUser.photoURL,
      "timestamp": FieldValue.serverTimestamp(),
      // createdAt متوفرة فوراً محلياً (مش زي serverTimestamp يلي بتضل null
      // لحد ما يرد السيرفر)، فبنرتب الرسائل عليها حتى ما الرسالة يلي
      // بعتها هلق تطلع فوق الصفحة لحظة وبعدين تنزل لتحت لما الوقت يوصل.
      "createdAt": DateTime.now().millisecondsSinceEpoch,
    });

    await _groupRef.set({
      "lastMessage": lastMessage,
      "lastMessageTime": FieldValue.serverTimestamp(),
      "lastSenderName": myName,
    }, SetOptions(merge: true));

    NotificationService.notifyForNewMessage(
      senderEmail: myEmail,
      senderName: myName,
      type: messageData["type"] as String? ?? "text",
      text: messageData["text"] as String?,
      groupMemberUids: _memberUids,
      groupId: widget.groupId,
    );

    await Future.delayed(const Duration(milliseconds: 200));
    _scrollToBottom();
  }

  Future<void> _startGroupCall(bool isVideoCall) async {
    final hostName = signedInUser.displayName ?? signedInUser.email ?? "مستخدم";
    final callRef = _firestore.collection("group_calls").doc();

    await callRef.set({
      "hostEmail": signedInUser.email,
      "hostName": hostName,
      "isVideoCall": isVideoCall,
      "groupId": widget.groupId,
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

    final link = GroupCallLink.build(callId: callRef.id, isVideoCall: isVideoCall);
    final kind = isVideoCall ? "مكالمة فيديو" : "مكالمة صوتية";
    await _sendGroupUpdate(
      lastMessage: "📞 $kind جماعية",
      messageData: {
        "text": "📞 $hostName بدأ $kind جماعية بالمجموعة - اضغط للانضمام:\n$link",
      },
    );
  }

  void _showStartCallDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("مكالمة جماعية"),
        content: const Text("اختر نوع المكالمة، وكل أعضاء المجموعة رح ياخدوا رابط الانضمام."),
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
        ],
      ),
    );
  }

  void _showMembersDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("أعضاء المجموعة (${_memberUids.length})"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _memberUids.length,
            itemBuilder: (_, i) {
              final uid = _memberUids[i];
              final name = i < _memberNames.length ? _memberNames[i] : "عضو";
              final isMemberOwner = uid == _createdBy;
              final isMemberAdmin = _admins.contains(uid);
              final isSelf = uid == signedInUser.uid;
              // المالك يقدر يتصرف بأي عضو (غير حاله). المشرف يقدر يتصرف
              // بالأعضاء العاديين بس، مو بالمالك ولا بمشرف تاني.
              final canAct = _canManageGroup && !isSelf && !isMemberOwner &&
                  (_isOwner || !isMemberAdmin);

              return ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.indigo,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                title: Text(name),
                subtitle: isMemberOwner
                    ? const Text(
                        "مالك المجموعة",
                        style: TextStyle(fontSize: 11, color: Colors.indigo),
                      )
                    : isMemberAdmin
                        ? const Text(
                            "مشرف",
                            style: TextStyle(fontSize: 11, color: Colors.teal),
                          )
                        : null,
                trailing: canAct
                    ? PopupMenuButton<String>(
                        onSelected: (value) {
                          Navigator.pop(dialogContext);
                          if (value == 'toggle_admin') {
                            _toggleAdmin(uid, !isMemberAdmin);
                          } else if (value == 'remove') {
                            _confirmRemoveMember(uid, name);
                          }
                        },
                        itemBuilder: (_) => [
                          if (_isOwner)
                            PopupMenuItem(
                              value: 'toggle_admin',
                              child: Text(
                                isMemberAdmin ? 'إزالة الإشراف' : 'تعيين كمشرف',
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('إزالة من المجموعة'),
                          ),
                        ],
                      )
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("إغلاق"),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleAdmin(String uid, bool makeAdmin) async {
    final newAdmins = List<String>.from(_admins);
    if (makeAdmin) {
      if (!newAdmins.contains(uid)) newAdmins.add(uid);
    } else {
      newAdmins.remove(uid);
    }
    try {
      await _groupRef.update({"admins": newAdmins});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmRemoveMember(String uid, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("إزالة عضو"),
        content: Text("متأكد إنك بدك تشيل \"$name\" من المجموعة؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("إزالة", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _removeMember(uid);
  }

  Future<void> _removeMember(String uid) async {
    final index = _memberUids.indexOf(uid);
    if (index == -1) return;
    final email = index < _memberEmails.length ? _memberEmails[index] : "";
    final name = index < _memberNames.length ? _memberNames[index] : "";

    final updates = <String, dynamic>{
      "memberUids": FieldValue.arrayRemove([uid]),
      "memberEmails": FieldValue.arrayRemove([email]),
      "memberNames": FieldValue.arrayRemove([name]),
    };
    // نشيل uid العضو من قائمة المشرفين كمان إذا كان مشرف، حتى ما تضل
    // إشارة لمشرف مش عضو بالمجموعة أصلاً.
    if (_admins.contains(uid)) {
      updates["admins"] = _admins.where((a) => a != uid).toList();
    }

    try {
      await _groupRef.update(updates);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showEditGroupNameDialog() {
    final controller = TextEditingController(text: _groupName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("تغيير اسم المجموعة"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "اسم المجموعة",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(dialogContext);
              try {
                await _groupRef.update({"name": newName});
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text("حفظ"),
          ),
        ],
      ),
    );
  }

  Future<void> _changeGroupPhoto() async {
    final file = await ImageService().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    try {
      final url = await ImageService().uploadImageToSupabase(
        imageFile: file,
        userId: widget.groupId,
      );
      if (url == null) throw Exception("تعذّر رفع الصورة");
      await _groupRef.update({"photoUrl": url});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddMembersScreen() {
    var selected = <SelectedUser>[];
    var isAdding = false;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (screenContext) => StatefulBuilder(
          builder: (screenContext, setScreenState) {
            return Scaffold(
              appBar: AppBar(
                backgroundColor: const Color(0xFF4A00E0),
                elevation: 0,
                iconTheme: const IconThemeData(color: Colors.white),
                title:
                    const Text("إضافة أعضاء", style: TextStyle(color: Colors.white)),
                actions: [
                  isAdding
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
                          onPressed: () async {
                            if (selected.isEmpty) {
                              Navigator.pop(screenContext);
                              return;
                            }
                            setScreenState(() => isAdding = true);
                            try {
                              final result = await GroupInviteService.addMembers(
                                groupId: widget.groupId,
                                users: selected,
                              );
                              if (!screenContext.mounted) return;
                              Navigator.pop(screenContext);
                              if (result.skipped.isNotEmpty && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "${result.skipped.length} ما انضافوا لأنهم مفعّلين خاصية منع الإضافة إلى المجموعات",
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                            } catch (e) {
                              setScreenState(() => isAdding = false);
                              if (screenContext.mounted) {
                                ScaffoldMessenger.of(screenContext).showSnackBar(
                                  SnackBar(
                                    content: Text("خطأ: $e"),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                ],
              ),
              body: UserMultiSelectList(
                excludeUids: _memberUids.toSet(),
                onSelectionChanged: (s) => selected = s,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _copyJoinCode() async {
    final snap = await _groupRef.get();
    final code = (snap.data()?["joinCode"] ?? "").toString();
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تم نسخ كود الدعوة: $code")),
      );
    }
  }

  Future<void> _toggleGroupVisibility() async {
    final hide = !_isGroupHidden;
    await _groupRef.update({"isPrivate": hide});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hide
                ? "المجموعة صارت مخفية عن نتائج البحث"
                : "المجموعة صارت تظهر بنتائج البحث",
          ),
        ),
      );
    }
  }

  void _showEditGroupUsernameDialog() {
    final controller = TextEditingController(text: _groupUsername ?? "");
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("معرّف المجموعة"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: "معرف فريد (حروف وأرقام)",
                  prefixText: "@",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "أي حدا يعرف هاد المعرّف فيه يوصل للمجموعة ويعرضها، حتى لو مفعّل \"إخفاء عن نتائج البحث\". فيك تغيّرو وقت ما بدك.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              onPressed: () async {
                final newUsername = controller.text.trim();
                if (newUsername.isEmpty) return;

                final error = await GroupUsernameService.changeGroupUsername(
                  groupId: widget.groupId,
                  oldUsername: _groupUsername,
                  newUsername: newUsername,
                );

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error ?? "تم تعيين المعرف بنجاح")),
                  );
                }
              },
              child: const Text("حفظ"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _leaveGroup() async {
    final myUid = signedInUser.uid;
    final myEmail = signedInUser.email;
    final myName = signedInUser.displayName ?? signedInUser.email ?? "";
    await _groupRef.update({
      "memberUids": FieldValue.arrayRemove([myUid]),
      "memberEmails": FieldValue.arrayRemove([myEmail]),
      "memberNames": FieldValue.arrayRemove([myName]),
    });
    if (mounted) Navigator.pop(context);
  }

  void _confirmLeaveGroup() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("مغادرة المجموعة"),
        content: const Text("متأكد إنك بدك تطلع من هي المجموعة؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _leaveGroup();
            },
            child: const Text("مغادرة", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMuted = ChatMuteService.instance.isMuted(_chatKey);

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
                  setState(() => searchText = value.toLowerCase());
                },
              )
            : Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white,
                    backgroundImage: _groupPhotoUrl == null
                        ? null
                        : CachedNetworkImageProvider(_groupPhotoUrl!),
                    child: _groupPhotoUrl == null
                        ? const Icon(Icons.groups, color: Colors.indigo, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _showMembersDialog,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _groupName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _memberUids.isEmpty
                                ? " "
                                : "${_memberUids.length} ${_memberUids.length == 1 ? 'عضو' : 'أعضاء'}",
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
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
            icon: const Icon(Icons.call, color: Colors.white),
            tooltip: "مكالمة جماعية",
            onPressed: _showStartCallDialog,
          ),
          IconButton(
            icon: Icon(
              isMuted ? Icons.notifications_off : Icons.notifications_active,
              color: Colors.white,
            ),
            tooltip: isMuted ? "إلغاء كتم الإشعارات" : "كتم الإشعارات",
            onPressed: () async {
              await ChatMuteService.instance.toggleMute(_chatKey);
              if (mounted) setState(() {});
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'search') setState(() => isSearching = true);
              if (value == 'add') _showAddMembersScreen();
              if (value == 'name') _showEditGroupNameDialog();
              if (value == 'photo') _changeGroupPhoto();
              if (value == 'code') _copyJoinCode();
              if (value == 'username') _showEditGroupUsernameDialog();
              if (value == 'visibility') _toggleGroupVisibility();
              if (value == 'leave') _confirmLeaveGroup();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'search', child: Text('البحث عن رسائل')),
              // إضافة أعضاء لمالك المجموعة بس. تغيير الاسم/الصورة للمالك
              // والمشرفين. باقي الخيارات (كود الدعوة، المعرّف، الظهور
              // بالبحث، المغادرة) متاحة لأي عضو متل ما كانت.
              if (_isOwner)
                const PopupMenuItem(value: 'add', child: Text('إضافة أعضاء')),
              if (_canManageGroup)
                const PopupMenuItem(value: 'name', child: Text('تغيير اسم المجموعة')),
              if (_canManageGroup)
                const PopupMenuItem(value: 'photo', child: Text('تغيير صورة المجموعة')),
              const PopupMenuItem(value: 'code', child: Text('نسخ كود الدعوة')),
              PopupMenuItem(
                value: 'username',
                child: Text(
                  _groupUsername == null || _groupUsername!.isEmpty
                      ? 'تعيين معرّف للمجموعة'
                      : 'تغيير معرّف المجموعة (@$_groupUsername)',
                ),
              ),
              PopupMenuItem(
                value: 'visibility',
                child: Text(
                  _isGroupHidden
                      ? 'إظهار المجموعة بنتائج البحث'
                      : 'إخفاء المجموعة عن نتائج البحث',
                ),
              ),
              const PopupMenuItem(value: 'leave', child: Text('مغادرة المجموعة')),
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
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.only(
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
                  stream: _groupRef
                      .collection("messages")
                      .orderBy("timestamp")
                      .limitToLast(200)
                      .snapshots(),
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
                        final photoUrl = data["photoUrl"] as String?;
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
                        final deletedFor = List<String>.from(data["deletedFor"] ?? []);
                        if (deletedFor.contains(signedInUser.uid)) {
                          return const SizedBox.shrink();
                        }
                        final sender = data["sender"] ?? "";
                        final isMe = sender == signedInUser.email;
                        final isSelected = _selectedMessageIds.contains(message.id);
                        // القائمة reverse (index 0 = الأحدث)، فالرسالة "قبل"
                        // هاي زمنياً (الأقدم) موجودة بعدها بالقائمة (index+1).
                        final previousSender = index + 1 < messages.length
                            ? ((messages[index + 1].data()
                                    as Map<String, dynamic>)["sender"] ??
                                "")
                            : null;
                        final isFirstFromSender = previousSender != sender;

                        return KeyedSubtree(
                          key: _messageKeys.putIfAbsent(message.id, () => GlobalKey()),
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
                                  crossAxisAlignment:
                                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    if (!isMe && isFirstFromSender)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 12, bottom: 4),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircleAvatar(
                                              radius: 16,
                                              backgroundColor: Colors.indigo.shade100,
                                              backgroundImage: (photoUrl != null &&
                                                      photoUrl.isNotEmpty)
                                                  ? CachedNetworkImageProvider(photoUrl)
                                                  : null,
                                              child: (photoUrl == null || photoUrl.isEmpty)
                                                  ? Icon(Icons.person,
                                                      size: 18,
                                                      color: Colors.indigo.shade700)
                                                  : null,
                                            ),
                                            const SizedBox(width: 7),
                                            GestureDetector(
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
                                          ],
                                        ),
                                      ),
                                    if (messageType == "audio" && audioUrl != null)
                                      Padding(
                                        padding: EdgeInsets.only(left: isMe ? 0 : 38),
                                        child: AudioMessageWidget(
                                          audioUrl: audioUrl,
                                          isMe: isMe,
                                          senderName: name,
                                        ),
                                      )
                                    else if (messageType == "image" && imageUrl != null)
                                      Padding(
                                        padding: EdgeInsets.only(left: isMe ? 0 : 38),
                                        child: ImageMessageWidget(imageUrl: imageUrl, isMe: isMe),
                                      )
                                    else if (messageType == "video" && videoUrl != null)
                                      Padding(
                                        padding: EdgeInsets.only(left: isMe ? 0 : 38),
                                        child: VideoMessageWidget(videoUrl: videoUrl, isMe: isMe),
                                      )
                                    else
                                      Align(
                                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Container(
                                          constraints: const BoxConstraints(maxWidth: 280),
                                          margin: EdgeInsets.only(left: isMe ? 8 : 46, right: 8),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _highlightedMessageId == message.id
                                                ? Colors.amber.shade300
                                                : (isMe ? Colors.indigo : Colors.grey.shade200),
                                            borderRadius: BorderRadius.only(
                                              topLeft: const Radius.circular(18),
                                              topRight: const Radius.circular(18),
                                              bottomLeft: Radius.circular(isMe ? 18 : 4),
                                              bottomRight: Radius.circular(isMe ? 4 : 18),
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
                                                  color: isMe ? Colors.white : Colors.black87,
                                                ),
                                                linkColor:
                                                    isMe ? Colors.lightBlueAccent : Colors.blue,
                                                onLinkTap: _handleLinkTap,
                                              ),
                                            ],
                                          ),
                                        ),
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
            Container(
              padding: const EdgeInsets.all(10),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _replyPreview(),
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
