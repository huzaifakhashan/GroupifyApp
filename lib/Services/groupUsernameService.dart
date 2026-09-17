import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:groupify_app/Services/usernameService.dart';

/// معرّف نصي ثابت للمجموعة (زي @معرف)، قابل للتغيير من صاحب المجموعة،
/// بيسمح لأي حدا يعرفه إنه يوصل للمجموعة حتى لو مفعّل فيها "إخفاء عن
/// نتائج البحث" - بالضبط متل معرّف المستخدمين الفريد (UsernameService)
/// بس مربوط بمجموعة (groupId) عوض مستخدم (uid).
class GroupUsernameService {
  static final _firestore = FirebaseFirestore.instance;

  static Future<String?> resolveGroupId(String handle) async {
    final doc = await _firestore.collection("groupUsernames").doc(handle).get();
    return doc.data()?["groupId"] as String?;
  }

  static Future<bool> _tryReserve(String candidate, String groupId) async {
    final ref = _firestore.collection("groupUsernames").doc(candidate);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) {
          throw Exception("taken");
        }
        tx.set(ref, {"groupId": groupId});
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// يغيّر معرّف مجموعة (أو يعيّنه أول مرة): يتحقق من التوفر، يحجز
  /// الجديد، ويحرر القديم. يرجع null عند النجاح، أو رسالة الخطأ عند الفشل.
  static Future<String?> changeGroupUsername({
    required String groupId,
    required String? oldUsername,
    required String newUsername,
  }) async {
    final clean = UsernameService.slugify(newUsername);

    if (clean.length < 3) {
      return "المعرف لازم يكون 3 أحرف على الأقل";
    }
    if (clean.length > 30) {
      return "المعرف طويل كتير";
    }
    if (clean == oldUsername) {
      return null;
    }

    final reserved = await _tryReserve(clean, groupId);
    if (!reserved) {
      return "هذا المعرف مستخدم مسبقاً، جرب معرف تاني";
    }

    if (oldUsername != null && oldUsername.isNotEmpty) {
      await _firestore.collection("groupUsernames").doc(oldUsername).delete();
    }

    await _firestore.collection("groups").doc(groupId).set(
      {"groupUsername": clean},
      SetOptions(merge: true),
    );

    return null;
  }
}
