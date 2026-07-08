import 'package:flutter/material.dart';

class AppInfoPage extends StatelessWidget {
  const AppInfoPage({super.key});

  Widget feature(String text) {
    return ListTile(
      leading: const Icon(
        Icons.check_circle,
        color: Colors.green,
      ),
      title: Text(text),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("نبذة عن التطبيق"),
        centerTitle: true,
        backgroundColor: const Color(0xFF6A11CB),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          const Text(
            "مميزات Groupify",
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          feature("دردشة فورية وسريعة"),

          feature("إنشاء مجموعات بسهولة"),

          feature("واجهة حديثة وسهلة الاستخدام"),

          feature("إرسال الصور والملفات"),

          feature("حماية وخصوصية عالية"),

          feature("دعم الوضع الليلي"),

          feature("إشعارات لحظية"),

        ],
      ),
    );
  }
}