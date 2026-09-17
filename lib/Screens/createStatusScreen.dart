import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:groupify_app/Services/imageService.dart';
import 'package:groupify_app/Services/videoService.dart';
import 'package:groupify_app/Services/statusService.dart';

class CreateStatusScreen extends StatefulWidget {
  const CreateStatusScreen({super.key});

  @override
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  bool _isPosting = false;

  Future<void> _pickAndPostImage(ImageSource source) async {
    final file = await ImageService().pickImage(source: source);
    if (file == null) return;
    await _post(() async {
      final url = await ImageService().uploadImageToSupabase(
        imageFile: file,
        userId: FirebaseAuth.instance.currentUser!.uid,
      );
      if (url == null) throw Exception("تعذّر رفع الصورة");
      await StatusService.createImageStatus(url);
    });
  }

  Future<void> _pickAndPostVideo(ImageSource source) async {
    final file = await VideoService().pickVideo(source: source);
    if (file == null) return;
    await _post(() async {
      final url = await VideoService().uploadVideoToSupabase(
        videoFile: file,
        userId: FirebaseAuth.instance.currentUser!.uid,
      );
      if (url == null) throw Exception("تعذّر رفع الفيديو");
      await StatusService.createVideoStatus(url);
    });
  }

  Future<void> _post(Future<void> Function() action) async {
    setState(() => _isPosting = true);
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text("الكاميرا"),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndPostImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("المعرض"),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndPostImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showVideoSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text("الكاميرا"),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndPostVideo(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text("المعرض"),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndPostVideo(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A00E0),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("حالة جديدة", style: TextStyle(color: Colors.white)),
      ),
      body: AbsorbPointer(
        absorbing: _isPosting,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _OptionCard(
                    icon: Icons.text_fields,
                    color: Colors.deepPurple,
                    title: "نص",
                    subtitle: "اكتب حالة نصية بخلفية ملوّنة",
                    onTap: () async {
                      final result = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(builder: (_) => const _TextStatusScreen()),
                      );
                      if (result == true && mounted) Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 12),
                  _OptionCard(
                    icon: Icons.photo_camera,
                    color: Colors.indigo,
                    title: "صورة",
                    subtitle: "من الكاميرا أو المعرض",
                    onTap: _showImageSourceSheet,
                  ),
                  const SizedBox(height: 12),
                  _OptionCard(
                    icon: Icons.videocam,
                    color: Colors.teal,
                    title: "فيديو",
                    subtitle: "من الكاميرا أو المعرض",
                    onTap: _showVideoSourceSheet,
                  ),
                ],
              ),
            ),
            if (_isPosting)
              Container(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: color,
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
      ),
    );
  }
}

const List<Color> _statusColors = [
  Color(0xFF4A00E0),
  Color(0xFFE0004A),
  Color(0xFF00875A),
  Color(0xFFB25000),
  Color(0xFF1F1F1F),
  Color(0xFF0057B2),
];

class _TextStatusScreen extends StatefulWidget {
  const _TextStatusScreen();

  @override
  State<_TextStatusScreen> createState() => _TextStatusScreenState();
}

class _TextStatusScreenState extends State<_TextStatusScreen> {
  final TextEditingController _controller = TextEditingController();
  Color _color = _statusColors.first;
  bool _isPosting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPosting = true);
    try {
      await StatusService.createTextStatus(
        text: text,
        backgroundColor: '#${_color.toARGB32().toRadixString(16).substring(2)}',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _color,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          _isPosting
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.check, color: Colors.white),
                  tooltip: "نشر",
                  onPressed: _post,
                ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLines: null,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      hintText: "اكتب شي...",
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _statusColors.map((c) {
                  final isSelected = c == _color;
                  return GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: isSelected ? 34 : 28,
                      height: isSelected ? 34 : 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: isSelected ? 3 : 1.5,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
