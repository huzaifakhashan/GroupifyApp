import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("من نحن"),
        centerTitle: true,
        backgroundColor: const Color(0xFF6A11CB),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: const [
            CircleAvatar(
              radius: 55,
              backgroundColor: Color(0xFF6A11CB),
              child: Icon(
                Icons.groups,
                color: Colors.white,
                size: 60,
              ),
            ),
            SizedBox(height: 20),
            Text(
              "Groupify",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 20),
            Text(
              "Groupify هو تطبيق دردشة حديث يهدف إلى تسهيل التواصل بين المستخدمين وإنشاء مجموعات للمحادثة بطريقة بسيطة وسريعة وآمنة.",
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}