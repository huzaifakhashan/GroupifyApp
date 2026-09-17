import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:groupify_app/Screens/homeScreen.dart';
import 'package:groupify_app/Screens/chatScreen.dart';
import 'package:groupify_app/Screens/groupCallScreen.dart';
import 'package:groupify_app/Services/notificationService.dart';
import 'package:groupify_app/Services/presenceService.dart';
import 'package:groupify_app/Services/supabaseConfig.dart';
import 'package:groupify_app/Services/groupCallLink.dart';
import 'package:groupify_app/Services/chatMuteService.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseAuth.instance.authStateChanges().listen(
    PresenceService.instance.startFor,
  );
  FirebaseAuth.instance.authStateChanges().listen(
    ChatMuteService.instance.startFor,
  );
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null && !user.isAnonymous) {
      NotificationService().init();
    }
  });

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  }

  // 👇 مزوّد "Debug" مؤقت للتطوير: يطبع رمز تصحيح بالسجلات لازم يُضاف يدوياً
  // بمفاتيح App Check بلوحة تحكم Firebase حتى تنجح طلبات Storage/Firestore
  // إذا كان App Check مفعّل إجبارياً على المشروع.
  await FirebaseAppCheck.instance.activate(
    // ignore: deprecated_member_use
    androidProvider: AndroidProvider.debug,
    // ignore: deprecated_member_use
    appleProvider: AppleProvider.debug,
  );

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) _handleLink(initialUri);
    } catch (_) {}

    _linkSub = _appLinks.uriLinkStream.listen(_handleLink, onError: (_) {});
  }

  void _handleLink(Uri uri) {
    final parsed = GroupCallLink.parse(uri);
    if (parsed == null) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          callId: parsed.callId,
          isVideoCall: parsed.isVideoCall,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text("جاري التحضير..."),
                  ],
                ),
              ),
            );
          }

          if (snapshot.hasData &&
              snapshot.data != null &&
              !snapshot.data!.isAnonymous) {
            return const ChatScreen();
          }

          return const Homescreen();
        },
      ),
    );
  }
}