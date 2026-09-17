import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:groupify_app/Services/supabaseConfig.dart';

class ImageService {
  final _picker = ImagePicker();

  /// اختيار صورة من المعرض أو الكاميرا
  Future<File?> pickImage({required ImageSource source}) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked == null) return null;
      return File(picked.path);
    } catch (e) {
      print("❌ خطأ في اختيار الصورة: $e");
      return null;
    }
  }

  String _contentTypeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  /// رفع الصورة إلى Supabase Storage
  Future<String?> uploadImageToSupabase({
    required File imageFile,
    required String userId,
  }) async {
    try {
      if (FirebaseAuth.instance.currentUser == null || userId.isEmpty) {
        throw Exception('يجب تسجيل الدخول قبل رفع الصورة');
      }
      if (!SupabaseConfig.isConfigured) {
        throw Exception(
          'Supabase غير مهيأ. شغّل التطبيق مع SUPABASE_URL وSUPABASE_PUBLISHABLE_KEY',
        );
      }
      if (!imageFile.existsSync()) {
        throw Exception('الصورة غير موجودة: ${imageFile.path}');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = imageFile.path.split('.').last;
      final fileName = "image_${userId}_$timestamp.$extension";

      print("🔄 جاري رفع الصورة...");
      await Supabase.instance.client.storage
          .from(SupabaseConfig.mediaBucket)
          .upload(
        fileName,
        imageFile,
        fileOptions: FileOptions(
          contentType: _contentTypeFor(extension),
          upsert: false,
        ),
      );

      // getPublicUrl() بناء رابط محلي بدون طلب شبكة — راجع الملاحظة بـ
      // audioService.dart لماذا ما منستخدم createSignedUrl هون.
      final downloadUrl = Supabase.instance.client.storage
          .from(SupabaseConfig.mediaBucket)
          .getPublicUrl(fileName);

      print("✅ تم رفع الصورة بنجاح: $downloadUrl");
      return downloadUrl;
    } on StorageException catch (e) {
      print("❌ خطأ Supabase في رفع الصورة: ${e.message}");
      throw Exception('Supabase Storage: ${e.message}');
    } catch (e) {
      print("❌ خطأ في رفع الصورة: $e");
      rethrow;
    }
  }
}
