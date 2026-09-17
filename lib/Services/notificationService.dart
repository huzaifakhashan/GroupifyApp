import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:groupify_app/Services/chatMuteService.dart';

// استقبال الإشعارات عندما التطبيق بالخلفية
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("✅ استقبال إشعار بالخلفية");
  print("العنوان: ${message.notification?.title}");
  print("الرسالة: ${message.notification?.body}");
}

class NotificationService {
  bool initialized = false;

  final FirebaseMessaging messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'messages_channel',
    'رسائل جديدة',
    description: 'إشعارات الرسائل الجديدة',
    importance: Importance.high,
  );

  // نفس الـ Worker المستخدم لتوليد Agora Token (شوف cloudflare-worker/README.md).
  static const _workerBaseUrl = String.fromEnvironment(
    'PUSH_TOKEN_SERVER_URL',
    defaultValue: 'https://groupify-agora-token.huzaifa-khashan.workers.dev',
  );

  static const _appKey = String.fromEnvironment(
    'AGORA_APP_KEY',
    defaultValue: '4bcea4484a4851123c959ac4f95456b1ac73cdbacc8bd9fe',
  );

  /// المحادثة المفتوحة حالياً قدام المستخدم:
  /// "public" لو فاتح الشات العام، إيميل الطرف التاني لو فاتح شات خاص معه،
  /// و null لو مو فاتح ولا شات. بنستخدمها حتى ما نطلع إشعار منبثق
  /// لمحادثة المستخدم شايفها أصلاً على الشاشة (متل واتساب بالظبط).
  static String? currentOpenChatKey;

  Future<void> init() async {
    if (initialized) return;

    initialized = true;
    print("🔔 بدء خدمة الإشعارات...");

    try {
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // طلب صلاحية الإشعارات
      await messaging.requestPermission();
      print("✅ تم طلب صلاحيات الإشعارات");

      // جلب FCM Token
      String? token = await messaging.getToken();
      if (token != null) {
        await _saveToken(token);
        print("✅ FCM Token: $token");
      }

      // استماع لتحديثات التوكن
      messaging.onTokenRefresh.listen((newToken) {
        _saveToken(newToken);
        print("🔄 تم تحديث FCM Token: $newToken");
      });

      // التطبيق مفتوح في الواجهة الأمامية (Foreground) — نعرض إشعار
      // منبثق بأنفسنا لأنه أندرويد ما بيعرضه تلقائياً بهاي الحالة،
      // إلا إذا المستخدم فاتح أصلاً نفس المحادثة.
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print("📱 إشعار في الواجهة الأمامية");
        final notification = message.notification;
        if (notification == null) return;

        final scope = message.data['scope'];
        final sender = message.data['sender'];
        final groupId = message.data['groupId'];
        final chatKey = scope == 'public'
            ? 'public'
            : scope == 'group'
                ? 'group:$groupId'
                : sender;
        if (chatKey != null && chatKey == currentOpenChatKey) {
          return; // المستخدم شايف هالمحادثة أصلاً
        }
        if (chatKey != null && ChatMuteService.instance.isMuted(chatKey)) {
          return; // المحادثة مكتومة
        }

        _localNotifications.show(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
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

  Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
      "fcmToken": token,
    }, SetOptions(merge: true));
  }

  /// يبعث إشعار Push لمجموعة أجهزة (FCM tokens) عبر الـ Worker.
  /// ما لازم يوقف إرسال الرسالة لو فشل، فمحاط بـ try/catch بصمت.
  /// بنطبع نتيجة كل توكن (نجاح/فشل) حتى نقدر نشخّص ليش إشعار معيّن ما وصل.
  static Future<void> _sendPush({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (tokens.isEmpty) {
      print("🔕 _sendPush: ولا توكن للإرسال إله");
      return;
    }
    try {
      print("📤 _sendPush: بعتلـ ${tokens.length} توكن - العنوان: $title");
      final response = await http.post(
        Uri.parse('$_workerBaseUrl/notify'),
        headers: {
          'Content-Type': 'application/json',
          'x-app-key': _appKey,
        },
        body: jsonEncode({
          'tokens': tokens,
          'title': title,
          'body': body,
          'data': data ?? {},
        }),
      );
      print("📬 _sendPush: رد الـ Worker (${response.statusCode}): ${response.body}");
    } catch (e) {
      print("⚠️ تعذر إرسال إشعار: $e");
    }
  }

  /// يجهّز نص الإشعار حسب نوع الرسالة، يجيب توكنات المستقبلين من Firestore،
  /// ويبعث الإشعار. لو [receiverEmail] فاضي و[groupMemberUids] فاضي، الإشعار
  /// بيروح لكل المستخدمين (الشات العام) عدا المرسل نفسه. لو [groupMemberUids]
  /// معبّى، الإشعار بيروح لأعضاء المجموعة بس (عدا المرسل)، ومطلوب [groupId]
  /// معها لتحديد مفتاح الكتم الصحيح ("group:<id>").
  static Future<void> notifyForNewMessage({
    required String senderEmail,
    required String senderName,
    required String type,
    String? text,
    String? receiverEmail,
    List<String>? groupMemberUids,
    String? groupId,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final chatKey = groupMemberUids != null
          ? 'group:$groupId'
          : (receiverEmail ?? 'public');

      final List<Map<String, dynamic>> userDocs;
      if (groupMemberUids != null) {
        userDocs = [];
        for (final uid in groupMemberUids) {
          try {
            final doc = await firestore.collection('users').doc(uid).get();
            if (doc.exists) {
              userDocs.add(doc.data()!);
            } else {
              print("⚠️ notifyForNewMessage: ما لقيت users/$uid (chatKey=$chatKey)");
            }
          } catch (e) {
            print("⚠️ notifyForNewMessage: تعذر قراءة users/$uid: $e");
          }
        }
        print(
            "🔎 notifyForNewMessage[group]: groupMemberUids=${groupMemberUids.length} → userDocs=${userDocs.length}");
      } else if (receiverEmail != null) {
        final snapshot = await firestore
            .collection('users')
            .where('email', isEqualTo: receiverEmail)
            .limit(1)
            .get();
        userDocs = snapshot.docs.map((d) => d.data()).toList();
        print(
            "🔎 notifyForNewMessage[private]: receiverEmail=$receiverEmail → userDocs=${userDocs.length}");
      } else {
        final snapshot = await firestore.collection('users').get();
        userDocs = snapshot.docs.map((d) => d.data()).toList();
        print("🔎 notifyForNewMessage[public]: userDocs=${userDocs.length}");
      }

      // كل مستخدم بمعالجة try/catch لحالها، حتى مستند واحد فيه بيانات
      // مش متوقعة (متلاً blockedUsers مش List) ما يوقف إشعار باقي
      // المستلمين معه بنفس الحلقة (بيصير هيك بالمجموعات يلي فيها أكتر
      // من مستلم، عكس المحادثة الخاصة يلي دايماً مستلم واحد بس).
      final tokens = <String>{};
      for (final data in userDocs) {
        try {
          final email = data['email'] as String?;
          final token = data['fcmToken'] as String?;
          final mutedChats = data['mutedChats'] as Map<String, dynamic>?;
          final isMuted = mutedChats?[chatKey] == true;
          final blockedUsers = List<String>.from(data['blockedUsers'] ?? const []);
          final hasBlockedSender = blockedUsers.contains(senderEmail);
          if (email == senderEmail) continue;
          if (token == null || token.isEmpty) {
            print("⚠️ notifyForNewMessage: $email ما عندو fcmToken محفوظ");
            continue;
          }
          if (isMuted) {
            print("🔕 notifyForNewMessage: $email مكتوم لهاي المحادثة ($chatKey)");
            continue;
          }
          if (hasBlockedSender) {
            print("🚫 notifyForNewMessage: $email حاظر $senderEmail");
            continue;
          }
          tokens.add(token);
        } catch (e) {
          print("⚠️ notifyForNewMessage: تعذر معالجة مستلم (${data['email']}): $e");
        }
      }
      print("🎯 notifyForNewMessage: توكنات جاهزة للإرسال = ${tokens.length}");
      if (tokens.isEmpty) return;

      final body = switch (type) {
        'image' => '📷 صورة',
        'video' => '🎥 فيديو',
        'audio' => '🎤 رسالة صوتية',
        _ => (text != null && text.isNotEmpty) ? text : 'رسالة جديدة',
      };

      await _sendPush(
        tokens: tokens.toList(),
        title: groupMemberUids != null
            ? '$senderName في المجموعة'
            : 'رسالة جديدة من $senderName',
        body: body,
        data: {
          'type': type,
          'sender': senderEmail,
          'scope': groupMemberUids != null
              ? 'group'
              : (receiverEmail != null ? 'private' : 'public'),
          if (groupId != null) 'groupId': groupId,
        },
      );
    } catch (e) {
      print("⚠️ تعذر تجهيز الإشعار: $e");
    }
  }
}
