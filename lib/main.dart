import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Screens/homeScreen.dart';
import 'package:groupify_app/Screens/chatScreen.dart';
import 'package:groupify_app/Services/notificationService.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
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
          
          // اذهب إلى ChatScreen فقط إذا كان في مستخدم حقيقي مسجل دخول (مش مجهول)
          if (snapshot.hasData &&
              snapshot.data != null &&
              !snapshot.data!.isAnonymous) {
            return ChatScreen();
          }
          
          // وإلا → اذهب إلى Homescreen
          return Homescreen();
        },
      ),
    );
  }
}
