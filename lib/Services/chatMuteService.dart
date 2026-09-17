import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// يحتفظ بنسخة محلية (Cache) من تفضيلات المستخدم الحالي المرتبطة
/// بمحادثاته: المحادثات/المجموعات المكتومة، والمستخدمين المحظورين. هيك
/// نقدر نتحقق منها فوراً بدون قراءة إضافية من Firestore في كل مرة (نفس
/// الحقول بنستخدمها أيضاً بالسيرفر Worker عبر NotificationService لفلترة
/// التوكنات وقت الإرسال).
///
/// مفاتيح المحادثة (chatKey): "public" للمجموعة العامة، إيميل الطرف
/// التاني للمحادثات الخاصة، و "group:<groupId>" لمجموعات المستخدم.
/// الحظر مرتبط بالإيميل مباشرة (نفس مفتاح المحادثة الخاصة).
class ChatMuteService {
  ChatMuteService._();

  static final ChatMuteService instance = ChatMuteService._();
  final _firestore = FirebaseFirestore.instance;

  String? _uid;
  Map<String, dynamic> _mutedChats = const {};
  Set<String> _blockedEmails = const {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  Future<void> startFor(User? user) async {
    if (user == null || user.isAnonymous) {
      await stop();
      return;
    }
    if (_uid == user.uid) return;

    await stop();
    _uid = user.uid;
    _sub = _firestore
        .collection("users")
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      _mutedChats = (data?["mutedChats"] as Map<String, dynamic>?) ?? const {};
      _blockedEmails = Set<String>.from(data?["blockedUsers"] ?? const []);
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _uid = null;
    _mutedChats = const {};
    _blockedEmails = const {};
  }

  bool isMuted(String chatKey) => _mutedChats[chatKey] == true;

  Future<void> toggleMute(String chatKey) async {
    final uid = _uid;
    if (uid == null) return;
    final next = !isMuted(chatKey);
    await _firestore.collection("users").doc(uid).set({
      "mutedChats": {chatKey: next},
    }, SetOptions(merge: true));
  }

  bool isBlocked(String email) => _blockedEmails.contains(email);

  Future<void> toggleBlock(String email) async {
    final uid = _uid;
    if (uid == null) return;
    await _firestore.collection("users").doc(uid).update({
      "blockedUsers": isBlocked(email)
          ? FieldValue.arrayRemove([email])
          : FieldValue.arrayUnion([email]),
    });
  }
}
