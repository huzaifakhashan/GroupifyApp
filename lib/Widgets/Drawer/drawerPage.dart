import 'package:flutter/material.dart';
import 'about_page.dart';
import 'contact_page.dart';
import 'rate_page.dart';
import 'app_info_page.dart';
import 'package:groupify_app/Screens/profileScreen.dart';
class Drawerpage extends StatelessWidget {
    final bool showLogout;

  const Drawerpage({
    super.key,
    this.showLogout = false,
  });
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            // 🔵 Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.groups, size: 40, color: Colors.indigo),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "Groupify",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "تواصل، شارك، وكن جزء من المجتمع 🚀",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // 📌 Items
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                  ),
                ),
                child: ListView(
  children: [

    _buildItem(
      context,
      Icons.person_outline,
      "الملف الشخصي",
      () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
      },
    ),

    _buildItem(
      context,
      Icons.info_outline,
      "من نحن",
      () {
        // Navigator.pop(context);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AboutPage(),
          ),
        );
      },
    ),

    _buildItem(
      context,
      Icons.support_agent,
      "تواصل معنا",
      () {
        // Navigator.pop(context);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ContactPage(),
          ),
        );
      },
    ),

    _buildItem(
      context,
      Icons.star_outline,
      "قيّم التطبيق",
      () {
        // Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RatePage(),
          ),
        );
      },
    ),

    _buildItem(
      context,
      Icons.article_outlined,
      "نبذة عن التطبيق",
      () {
        // Navigator.pop(context);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AppInfoPage(),
          ),
        );
      },
    ),

],
),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.indigo),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}