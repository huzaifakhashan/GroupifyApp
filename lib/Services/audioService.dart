import 'package:record/record.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:groupify_app/Services/supabaseConfig.dart';
import 'dart:io';

class AudioService {
  final _record = Record();
  String? _recordingPath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  String? get recordingPath => _recordingPath;

  /// بدء التسجيل الصوتي
  Future<bool> startRecording() async {
    if (_isRecording) return false;
    try {
      // تحقق من وجود صلاحيات الميكروفون
      final hasPermission = await _record.hasPermission();
      if (!hasPermission) {
        print("❌ لا توجد صلاحيات لاستخدام الميكروفون");
        return false;
      }

      // احصل على مسار المجلد المؤقت
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordingPath = "${dir.path}/audio_$timestamp.m4a";

      // ابدأ التسجيل
      await _record.start(
        path: _recordingPath!,
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        samplingRate: 44100,
      );

      _isRecording = true;
      print("✅ بدأ التسجيل الصوتي");
      return true;
    } catch (e) {
      print("❌ خطأ في بدء التسجيل: $e");
      _isRecording = false;
      return false;
    }
  }

  /// إيقاف التسجيل الصوتي
  Future<String?> stopRecording() async {
    try {
      final path = await _record.stop();
      _isRecording = false;
      print("✅ تم إيقاف التسجيل");
      return path;
    } catch (e) {
      print("❌ خطأ في إيقاف التسجيل: $e");
      _isRecording = false;
      return null;
    }
  }

  /// رفع الملف الصوتي إلى Supabase Storage
  Future<String?> uploadAudioToFirebase({
    required String audioPath,
    required String userId,
  }) async {
    try {
      if (FirebaseAuth.instance.currentUser == null || userId.isEmpty) {
        throw Exception('يجب تسجيل الدخول قبل رفع الملف الصوتي');
      }
      if (!SupabaseConfig.isConfigured) {
        throw Exception(
          'Supabase غير مهيأ. شغّل التطبيق مع SUPABASE_URL وSUPABASE_PUBLISHABLE_KEY',
        );
      }

      final file = File(audioPath);

      if (!file.existsSync()) {
        throw Exception('الملف الصوتي غير موجود: $audioPath');
      }

      // إنشاء مسار فريد في Firebase Storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = "audio_${userId}_$timestamp.m4a";
      // رفع الملف
      print("🔄 جاري رفع الملف الصوتي...");
      await Supabase.instance.client.storage
          .from(SupabaseConfig.audioBucket)
          .upload(
        fileName,
        file,
        fileOptions: const FileOptions(
          contentType: 'audio/mp4',
          upsert: false,
        ),
      );

      // ملاحظة: createSignedUrl() بيعتمد على سياسة SELECT بجدول
      // storage.objects (RLS) عشان يلاقي الملف، وهاي السياسة مش فعّالة
      // فعلياً بمشروع Supabase (بترجع "Object not found" رغم إنه الملف
      // موجود ويمكن الوصول له مباشرة). الـ bucket أصلاً public، فمنستخدم
      // getPublicUrl() — بناء رابط محلي بدون أي طلب شبكة أو RLS.
      final downloadUrl = Supabase.instance.client.storage
          .from(SupabaseConfig.audioBucket)
          .getPublicUrl(fileName);

      print("✅ تم رفع الملف الصوتي بنجاح: $downloadUrl");
      return downloadUrl;
    } on StorageException catch (e) {
      print("❌ خطأ Supabase في رفع الملف الصوتي: ${e.message}");
      throw Exception('Supabase Storage: ${e.message}');
    } catch (e) {
      print("❌ خطأ في رفع الملف الصوتي: $e");
      rethrow;
    }
  }

  /// حذف الملف المؤقت
  Future<void> deleteRecordingFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
        print("✅ تم حذف الملف المؤقت");
      }
    } catch (e) {
      print("❌ خطأ في حذف الملف: $e");
    }
  }

  /// تنظيف الموارد
  Future<void> dispose() async {
    await _record.dispose();
  }
}
