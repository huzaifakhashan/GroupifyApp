import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// خدمة "الحالات" (متل تيليغرام): منشورات مؤقتة (صورة/فيديو/نص) بتختفي
/// بعد 24 ساعة. ما في حذف تلقائي مجدول (بيحتاج Cloud Functions مدفوعة) -
/// الحالات الأقدم من 24 ساعة بس بتتفلتر من العرض، وبتظل بالقاعدة (بدون
/// أي تكلفة إضافية حقيقية لحجم استخدام شخصي).
class StatusService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const Duration lifetime = Duration(hours: 24);

  static CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection("statuses");

  static Timestamp get activeCutoff =>
      Timestamp.fromDate(DateTime.now().subtract(lifetime));

  /// ستريم كل الحالات النشطة (غير منتهية) لكل المستخدمين، مرتبة تصاعدياً
  /// حسب وقت النشر (الأقدم أول) حتى تنعرض بترتيب منطقي جوا حالات كل شخص.
  static Stream<QuerySnapshot<Map<String, dynamic>>> activeStatuses() {
    return _collection
        .where("createdAt", isGreaterThan: activeCutoff)
        .orderBy("createdAt")
        .snapshots();
  }

  static Future<void> createTextStatus({
    required String text,
    required String backgroundColor,
  }) => _create({
        "type": "text",
        "text": text,
        "backgroundColor": backgroundColor,
      });

  static Future<void> createImageStatus(String imageUrl) => _create({
        "type": "image",
        "mediaUrl": imageUrl,
      });

  static Future<void> createVideoStatus(String videoUrl) => _create({
        "type": "video",
        "mediaUrl": videoUrl,
      });

  static Future<void> _create(Map<String, dynamic> fields) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw Exception("يجب تسجيل الدخول");

    await _collection.add({
      ...fields,
      "uid": me.uid,
      "name": me.displayName ?? me.email ?? "مستخدم",
      "photoUrl": me.photoURL,
      "createdAt": FieldValue.serverTimestamp(),
      "viewedBy": <String>[],
    });
  }

  /// بتسجل مشاهدتي لهاي الحالة، بس إذا ما كنت شفتها قبل (تجنب كتابة زيادة
  /// عن الحاجة، ومطابق لقاعدة الأمان يلي بتسمح بإضافة واحدة بس بكل مرة).
  static Future<void> markViewed(
    String statusId,
    List<String> currentViewedBy,
  ) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || currentViewedBy.contains(myUid)) return;
    await _collection.doc(statusId).update({
      "viewedBy": FieldValue.arrayUnion([myUid]),
    });
  }

  static Future<void> deleteStatus(String statusId) {
    return _collection.doc(statusId).delete();
  }
}
