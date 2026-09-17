import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Widgets/userMultiSelectList.dart';
import 'package:groupify_app/Services/groupUsernameService.dart';

class GroupJoinResult {
  final String groupId;
  final String groupName;

  const GroupJoinResult({required this.groupId, required this.groupName});
}

class AddMembersResult {
  final List<String> added;
  final List<String> skipped;

  const AddMembersResult({required this.added, required this.skipped});
}

class GroupJoinException implements Exception {
  final String message;
  GroupJoinException(this.message);

  @override
  String toString() => message;
}

/// وسيط للتعامل مع عضوية المجموعات مباشرة عبر Firestore (بدون Cloud
/// Functions - المشروع على خطة Spark المجانية). قواعد Firestore
/// (firestore.rules) هي يلي بتتحقق فعلياً من خاصية "منع الإضافة إلى
/// المجموعات" (blockGroupInvites) وقت الكتابة، فحتى لو تلاعب حدا
/// بالتطبيق، ما بيقدر يتخطى الحماية.
class GroupInviteService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<GroupJoinResult> joinByCode(String joinCode) async {
    final codeDoc =
        await _firestore.collection("groupInviteCodes").doc(joinCode).get();
    final groupId = codeDoc.data()?["groupId"] as String?;
    if (groupId == null) {
      throw GroupJoinException("كود المجموعة غير صحيح");
    }
    return _joinGroupId(groupId);
  }

  /// انضمام عبر معرّف المجموعة (@handle) - بيوصل حتى للمجموعات المخفية
  /// عن نتائج البحث، بالضبط متل حساب مستخدم خاص بينلاقى بمعرفه الفريد.
  static Future<GroupJoinResult> joinByUsername(String handle) async {
    final groupId = await GroupUsernameService.resolveGroupId(handle);
    if (groupId == null) {
      throw GroupJoinException("ما في مجموعة بهاد المعرف");
    }
    return _joinGroupId(groupId);
  }

  static Future<GroupJoinResult> _joinGroupId(String groupId) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw GroupJoinException("يجب تسجيل الدخول");

    final groupRef = _firestore.collection("groups").doc(groupId);
    final myName = me.displayName ?? me.email ?? "مستخدم";

    try {
      await groupRef.update({
        "memberUids": FieldValue.arrayUnion([me.uid]),
        "memberEmails": FieldValue.arrayUnion([me.email ?? ""]),
        "memberNames": FieldValue.arrayUnion([myName]),
      });
    } on FirebaseException catch (e) {
      if (e.code == "not-found") {
        throw GroupJoinException("المجموعة غير موجودة");
      }
      rethrow;
    }

    final snap = await groupRef.get();
    return GroupJoinResult(
      groupId: groupId,
      groupName: (snap.data()?["name"] as String?) ?? "مجموعة",
    );
  }

  static Future<AddMembersResult> addMembers({
    required String groupId,
    required List<SelectedUser> users,
  }) async {
    final groupRef = _firestore.collection("groups").doc(groupId);
    final added = <String>[];
    final skipped = <String>[];

    for (final user in users) {
      try {
        await groupRef.update({
          "memberUids": FieldValue.arrayUnion([user.uid]),
          "memberEmails": FieldValue.arrayUnion([user.email]),
          "memberNames": FieldValue.arrayUnion([user.name]),
        });
        added.add(user.uid);
      } on FirebaseException catch (e) {
        if (e.code == "permission-denied") {
          skipped.add(user.uid);
        } else {
          rethrow;
        }
      }
    }

    return AddMembersResult(added: added, skipped: skipped);
  }
}
