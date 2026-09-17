import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:groupify_app/Services/supabaseConfig.dart';

class VideoService {
  final _picker = ImagePicker();

  /// اختيار فيديو من المعرض أو تصويره بالكاميرا
  Future<File?> pickVideo({required ImageSource source}) async {
    try {
      final picked = await _picker.pickVideo(source: source);
      if (picked == null) return null;
      return File(picked.path);
    } catch (e) {
      print("❌ خطأ في اختيار الفيديو: $e");
      return null;
    }
  }

  /// رفع الفيديو إلى Supabase Storage
  Future<String?> uploadVideoToSupabase({
    required File videoFile,
    required String userId,
  }) async {
    try {
      if (FirebaseAuth.instance.currentUser == null || userId.isEmpty) {
        throw Exception('يجب تسجيل الدخول قبل رفع الفيديو');
      }
      if (!SupabaseConfig.isConfigured) {
        throw Exception(
          'Supabase غير مهيأ. شغّل التطبيق مع SUPABASE_URL وSUPABASE_PUBLISHABLE_KEY',
        );
      }
      if (!videoFile.existsSync()) {
        throw Exception('الفيديو غير موجود: ${videoFile.path}');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = videoFile.path.split('.').last;
      final fileName = "video_${userId}_$timestamp.$extension";

      print("🔄 جاري رفع الفيديو...");
      await Supabase.instance.client.storage
          .from(SupabaseConfig.mediaBucket)
          .upload(
        fileName,
        videoFile,
        fileOptions: const FileOptions(
          contentType: 'video/mp4',
          upsert: false,
        ),
      );

      // getPublicUrl() بناء رابط محلي بدون طلب شبكة — راجع الملاحظة بـ
      // audioService.dart لماذا ما منستخدم createSignedUrl هون.
      final downloadUrl = Supabase.instance.client.storage
          .from(SupabaseConfig.mediaBucket)
          .getPublicUrl(fileName);

      print("✅ تم رفع الفيديو بنجاح: $downloadUrl");
      return downloadUrl;
    } on StorageException catch (e) {
      print("❌ خطأ Supabase في رفع الفيديو: ${e.message}");
      throw Exception('Supabase Storage: ${e.message}');
    } catch (e) {
      print("❌ خطأ في رفع الفيديو: $e");
      rethrow;
    }
  }
}
