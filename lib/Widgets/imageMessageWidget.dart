import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// عنصر عرض رسالة صورة بالمحادثة، مع إمكانية فتحها بشاشة كاملة بالضغط عليها.
/// بيستخدم CachedNetworkImage حتى ما تنزل نفس الصورة من الشبكة كل مرة
/// السكرول يمر عليها من جديد - أكبر سبب تهنيج (jank) بمحادثة فيها صور كتير.
class ImageMessageWidget extends StatelessWidget {
  final String imageUrl;
  final bool isMe;

  const ImageMessageWidget({
    super.key,
    required this.imageUrl,
    required this.isMe,
  });

  void _openFullScreen(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _openFullScreen(context),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (context, url) => Container(
              width: 180,
              height: 180,
              color: Colors.grey.shade200,
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => Container(
              width: 180,
              height: 180,
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }
}
