import 'package:flutter/material.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  Widget item(IconData icon, String title, String value) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: ListTile(
        leading: Icon(icon, color: Colors.deepPurple),
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("تواصل معنا"),
        centerTitle: true,
        backgroundColor: const Color(0xFF6A11CB),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            item(Icons.email, "البريد الإلكتروني", "groupify@gmail.com"),
            item(Icons.phone, "الهاتف", "+964 784 588 4502"),
            item(Icons.language, "الموقع الإلكتروني", "www.groupify.com"),
          ],
        ),
      ),
    );
  }
}