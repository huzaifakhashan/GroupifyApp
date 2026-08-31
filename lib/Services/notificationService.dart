import 'package:firebase_messaging/firebase_messaging.dart';

// استقبال الإشعارات عندما التطبيق بالخلفية
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("✅ استقبال إشعار بالخلفية");
  print("العنوان: ${message.notification?.title}");
  print("الرسالة: ${message.notification?.body}");
}

class NotificationService {
  bool initialized = false;

  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  Future<void> init() async {
    if (initialized) return;

    initialized = true;
    print("🔔 بدء خدمة الإشعارات...");
    
    try {
      // طلب صلاحية الإشعارات
      await messaging.requestPermission();
      print("✅ تم طلب صلاحيات الإشعارات");

      // جلب FCM Token
      String? token = await messaging.getToken();
      if (token != null) {
        print("✅ FCM Token: $token");
      }

      // استماع لتحديثات التوكن
      messaging.onTokenRefresh.listen((newToken) {
        print("🔄 تم تحديث FCM Token: $newToken");
      });

      // التطبيق مفتوح في الواجهة الأمامية (Foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print("📱 إشعار في الواجهة الأمامية");
        print("العنوان: ${message.notification?.title}");
        print("الرسالة: ${message.notification?.body}");
      });

      // عند الضغط على الإشعار وفتح التطبيق
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print("👆 تم فتح الإشعار");
      });

      // إذا التطبيق كان مغلق ووصل إشعار ثم فتحه المستخدم
      RemoteMessage? initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        print("🚀 تم فتح التطبيق من إشعار");
      }

      print("✅ تم تفعيل خدمة الإشعارات بنجاح");
    } catch (e) {
      print("❌ خطأ في خدمة الإشعارات: $e");
    }
  }
}
