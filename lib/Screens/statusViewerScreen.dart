import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import 'package:groupify_app/Services/statusService.dart';

class StatusViewerScreen extends StatefulWidget {
  final String uid;
  final String name;
  final String? photoUrl;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> statuses;

  const StatusViewerScreen({
    super.key,
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.statuses,
  });

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _index = 0;
  VideoPlayerController? _videoController;

  bool get _isOwn => FirebaseAuth.instance.currentUser?.uid == widget.uid;

  Map<String, dynamic> get _currentData =>
      widget.statuses[_index].data();

  String get _currentId => widget.statuses[_index].id;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _goNext();
      });
    _loadCurrent();
  }

  @override
  void dispose() {
    _controller.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _loadCurrent() {
    _controller.stop();
    _controller.reset();
    _videoController?.dispose();
    _videoController = null;

    _markViewed();

    final data = _currentData;
    if (data["type"] == "video") {
      final url = data["mediaUrl"] as String?;
      if (url == null) {
        _controller.duration = const Duration(seconds: 5);
        _controller.forward();
        return;
      }
      final vc = VideoPlayerController.networkUrl(Uri.parse(url));
      _videoController = vc;
      vc.initialize().then((_) {
        if (!mounted || _videoController != vc) return;
        _controller.duration = vc.value.duration;
        vc.play();
        _controller.forward();
        setState(() {});
      });
    } else {
      _controller.duration = const Duration(seconds: 5);
      _controller.forward();
    }
  }

  void _markViewed() {
    final viewedBy = List<String>.from(_currentData["viewedBy"] ?? []);
    StatusService.markViewed(_currentId, viewedBy);
  }

  void _goNext() {
    if (_index < widget.statuses.length - 1) {
      setState(() => _index++);
      _loadCurrent();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  void _goPrevious() {
    if (_index > 0) {
      setState(() => _index--);
      _loadCurrent();
    }
  }

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return "";
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return "الآن";
    if (diff.inHours < 1) return "منذ ${diff.inMinutes} د";
    if (diff.inDays < 1) return "منذ ${diff.inHours} س";
    return "منذ ${diff.inDays} يوم";
  }

  Future<void> _confirmDelete() async {
    _controller.stop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("حذف الحالة"),
        content: const Text("متأكد إنك بدك تحذف هاي الحالة؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("حذف", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await StatusService.deleteStatus(_currentId);
      if (mounted) Navigator.pop(context);
    } else {
      _controller.forward();
    }
  }

  Future<void> _showViewers() async {
    _controller.stop();
    final viewedBy = List<String>.from(_currentData["viewedBy"] ?? []);

    List<Map<String, dynamic>> viewers = [];
    if (viewedBy.isNotEmpty) {
      for (var i = 0; i < viewedBy.length; i += 30) {
        final chunk = viewedBy.sublist(i, i + 30 > viewedBy.length ? viewedBy.length : i + 30);
        final snap = await FirebaseFirestore.instance
            .collection("users")
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        viewers.addAll(snap.docs.map((d) => d.data()));
      }
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: viewers.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text("ولا حدا شافها لهلق"),
              )
            : ListView(
                shrinkWrap: true,
                children: viewers
                    .map((data) => ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.indigo,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                          title: Text((data["name"] ?? "مستخدم").toString()),
                        ))
                    .toList(),
              ),
      ),
    );
    if (mounted) _controller.forward();
  }

  Widget _buildContent(String type, Map<String, dynamic> data) {
    switch (type) {
      case "image":
        final url = data["mediaUrl"] as String?;
        if (url == null) return const SizedBox.shrink();
        return Center(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (context, url) =>
                const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorWidget: (context, url, error) =>
                const Icon(Icons.broken_image, color: Colors.white54, size: 48),
          ),
        );
      case "video":
        final vc = _videoController;
        if (vc == null || !vc.value.isInitialized) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        return Center(
          child: AspectRatio(
            aspectRatio: vc.value.aspectRatio,
            child: VideoPlayer(vc),
          ),
        );
      case "text":
      default:
        final colorHex = (data["backgroundColor"] as String?) ?? "#4A00E0";
        Color color;
        try {
          color = Color(int.parse(colorHex.replaceFirst('#', '0xff')));
        } catch (_) {
          color = const Color(0xFF4A00E0);
        }
        return Container(
          color: color,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(32),
          child: Text(
            (data["text"] ?? "").toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _currentData;
    final type = (data["type"] as String?) ?? "text";
    final viewedCount = List<String>.from(data["viewedBy"] ?? []).length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => _controller.stop(),
        onLongPressEnd: (_) => _controller.forward(),
        onTapUp: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx > width / 2) {
            _goNext();
          } else {
            _goPrevious();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(child: _buildContent(type, data)),
            SafeArea(
              child: Column(
                children: [
                  Row(
                    children: List.generate(widget.statuses.length, (i) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (_, _) {
                              double value;
                              if (i < _index) {
                                value = 1;
                              } else if (i == _index) {
                                value = _controller.value;
                              } else {
                                value = 0;
                              }
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: value,
                                  minHeight: 3,
                                  backgroundColor: Colors.white24,
                                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white,
                          backgroundImage: widget.photoUrl == null
                              ? null
                              : CachedNetworkImageProvider(widget.photoUrl!),
                          child: widget.photoUrl == null
                              ? const Icon(Icons.person, color: Colors.indigo)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _timeAgo(data["createdAt"] as Timestamp?),
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        if (_isOwn)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.white),
                            onPressed: _confirmDelete,
                          ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isOwn)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: TextButton.icon(
                    onPressed: _showViewers,
                    icon: const Icon(Icons.remove_red_eye, color: Colors.white),
                    label: Text(
                      "$viewedCount مشاهدة",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
