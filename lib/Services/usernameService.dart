import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class UsernameService {
  static final _firestore = FirebaseFirestore.instance;

  static String slugify(String input) {
    final noSpaces = input.trim().replaceAll(RegExp(r'\s+'), '_');
    return noSpaces.replaceAll(RegExp(r'[^\p{L}\p{N}_]', unicode: true), '');
  }

  /// يولّد معرّف فريد (username) مبني على الاسم، ويحجزه ذرّياً بمجموعة "usernames".
  static Future<String> generateAndReserve({
    required String uid,
    required String name,
  }) async {
    final base = slugify(name).isEmpty ? "user" : slugify(name);
    final random = Random();

    for (int attempt = 0; attempt < 8; attempt++) {
      final suffix = (1000 + random.nextInt(9000)).toString();
      final candidate = "$base$suffix";
      final reserved = await _tryReserve(candidate, uid);
      if (reserved) return candidate;
    }

    final fallback = "$base${DateTime.now().millisecondsSinceEpoch}";
    await _tryReserve(fallback, uid);
    return fallback;
  }

  static Future<bool> _tryReserve(String candidate, String uid) async {
    final ref = _firestore.collection("usernames").doc(candidate);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) {
          throw Exception("taken");
        }
        tx.set(ref, {"uid": uid});
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// يغيّر معرّف مستخدم موجود مسبقاً: يتحقق من التوفر، يحجز الجديد، ويحرر القديم.
  /// يرجع null عند النجاح، أو رسالة الخطأ عند الفشل.
  static Future<String?> changeUsername({
    required String uid,
    required String? oldUsername,
    required String newUsername,
  }) async {
    final clean = slugify(newUsername);

    if (clean.length < 3) {
      return "المعرف لازم يكون 3 أحرف على الأقل";
    }
    if (clean.length > 30) {
      return "المعرف طويل كتير";
    }
    if (clean == oldUsername) {
      return null;
    }

    final reserved = await _tryReserve(clean, uid);
    if (!reserved) {
      return "هذا المعرف مستخدم مسبقاً، جرب معرف تاني";
    }

    if (oldUsername != null && oldUsername.isNotEmpty) {
      await _firestore.collection("usernames").doc(oldUsername).delete();
    }

    await _firestore.collection("users").doc(uid).set(
      {"username": clean},
      SetOptions(merge: true),
    );

    return null;
  }
}
