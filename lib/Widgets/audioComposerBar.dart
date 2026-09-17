import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:groupify_app/Services/audioService.dart';
import 'package:groupify_app/Services/imageService.dart';
import 'package:groupify_app/Services/videoService.dart';

/// شريط كتابة الرسائل + تسجيل صوتي بأسلوب واتساب (اضغط مطوّلاً للتسجيل،
/// اسحب لليسار للإلغاء) + إرفاق صور وفيديو. يُستخدم في شاشة الدردشة الجماعية
/// والخاصة.
class AudioComposerBar extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSendText;
  final String userId;
  final Future<void> Function(String audioUrl, int durationSeconds)
      onAudioRecorded;
  final Future<void> Function(String imageUrl) onImageSent;
  final Future<void> Function(String videoUrl) onVideoSent;

  const AudioComposerBar({
    super.key,
    required this.controller,
    required this.onSendText,
    required this.userId,
    required this.onAudioRecorded,
    required this.onImageSent,
    required this.onVideoSent,
  });

  @override
  State<AudioComposerBar> createState() => _AudioComposerBarState();
}

class _AudioComposerBarState extends State<AudioComposerBar> {
  final AudioService _audioService = AudioService();
  final ImageService _imageService = ImageService();
  final VideoService _videoService = VideoService();
  bool _isRecording = false;
  bool _isUploadingMedia = false;
  Duration _recordingDuration = Duration.zero;
  DateTime? _recordingStartTime;
  double _dragX = 0;
  bool _willCancelRecording = false;

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AudioComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _startAudioRecording() async {
    if (_isRecording) return;

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم رفض صلاحيات الميكروفون"),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final success = await _audioService.startRecording();
    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("فشل بدء التسجيل"),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _recordingStartTime = DateTime.now();
    setState(() {
      _isRecording = true;
      _recordingDuration = Duration.zero;
      _dragX = 0;
      _willCancelRecording = false;
    });

    while (_isRecording) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted && _isRecording && _recordingStartTime != null) {
        setState(() {
          _recordingDuration = DateTime.now().difference(_recordingStartTime!);
        });
      }
    }
  }

  Future<void> _stopAudioRecording({bool cancel = false}) async {
    if (!_isRecording) return;
    final recordedDuration = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!)
        : _recordingDuration;
    setState(() {
      _isRecording = false;
      _dragX = 0;
      _willCancelRecording = false;
    });

    final audioPath = await _audioService.stopRecording();
    if (audioPath == null) {
      if (!cancel && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("خطأ في إيقاف التسجيل"),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // إلغاء (سحب أو تسجيل قصير جداً بالخطأ)
    if (cancel || recordedDuration.inMilliseconds < 500) {
      await _audioService.deleteRecordingFile(audioPath);
      return;
    }

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("جاري رفع الملف الصوتي..."),
            backgroundColor: Colors.blue,
          ),
        );
      }

      final audioUrl = await _audioService.uploadAudioToFirebase(
        audioPath: audioPath,
        userId: widget.userId,
      );

      if (audioUrl == null) {
        throw Exception("لم يرجع Supabase رابط الملف الصوتي");
      }

      await widget.onAudioRecorded(audioUrl, recordedDuration.inSeconds);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ تم إرسال الرسالة الصوتية"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      await _audioService.deleteRecordingFile(audioPath);
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_isUploadingMedia || _isRecording) return;

    final imageFile = await _imageService.pickImage(source: source);
    if (imageFile == null) return;

    setState(() => _isUploadingMedia = true);
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("جاري رفع الصورة..."),
            backgroundColor: Colors.blue,
          ),
        );
      }

      final imageUrl = await _imageService.uploadImageToSupabase(
        imageFile: imageFile,
        userId: widget.userId,
      );

      if (imageUrl == null) {
        throw Exception("لم يرجع Supabase رابط الصورة");
      }

      await widget.onImageSent(imageUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ تم إرسال الصورة"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _pickAndSendVideo(ImageSource source) async {
    if (_isUploadingMedia || _isRecording) return;

    final videoFile = await _videoService.pickVideo(source: source);
    if (videoFile == null) return;

    setState(() => _isUploadingMedia = true);
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("جاري رفع الفيديو..."),
            backgroundColor: Colors.blue,
          ),
        );
      }

      final videoUrl = await _videoService.uploadVideoToSupabase(
        videoFile: videoFile,
        userId: widget.userId,
      );

      if (videoUrl == null) {
        throw Exception("لم يرجع Supabase رابط الفيديو");
      }

      await widget.onVideoSent(videoUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ تم إرسال الفيديو"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.indigo),
              title: const Text("صورة من المعرض"),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.indigo),
              title: const Text("التقاط صورة"),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndSendImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library, color: Colors.indigo),
              title: const Text("فيديو من المعرض"),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndSendVideo(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.indigo),
              title: const Text("تصوير فيديو"),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAndSendVideo(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 👇 مهم: زر المايك (GestureDetector) لازم يضل نفس العنصر بشجرة الواجهة
  // طول فترة التسجيل. لو استبدلناه بعنصر مختلف لما _isRecording تتغيّر
  // (متل ما كان بالسابق: شريط كامل مكانه شريط تاني)، فلاتر بيفكّك متتبّع
  // اللمس (LongPressGestureRecognizer) القديم وبيصير الرفع (release) ما
  // بينلقط، فيضل التسجيل عالق بدون طريقة لإيقافه. لهيك خلّينا نفس الزر
  // موجود دايماً وبس منغيّر شكله ولونه.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Row(
        children: [
          if (!_isRecording)
            IconButton(
              icon: _isUploadingMedia
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.attach_file, color: Colors.grey.shade700),
              onPressed: _isUploadingMedia ? null : _showAttachSheet,
            ),
          Expanded(
            child: _isRecording ? _buildRecordingInfo() : _buildTextField(),
          ),
          const SizedBox(width: 8),
          if (!_isRecording && _hasText)
            CircleAvatar(
              backgroundColor: Colors.indigo,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: widget.onSendText,
              ),
            ),
          if (!_isRecording && _hasText) const SizedBox(width: 8),
          if (_isRecording || !_hasText)
            GestureDetector(
              onLongPressStart: (_) {
                HapticFeedback.mediumImpact();
                _startAudioRecording();
              },
              onLongPressMoveUpdate: (details) {
                if (!_isRecording) return;
                setState(() {
                  _dragX = details.offsetFromOrigin.dx.clamp(-120.0, 0.0);
                  _willCancelRecording = _dragX < -80;
                });
              },
              onLongPressEnd: (_) =>
                  _stopAudioRecording(cancel: _willCancelRecording),
              onLongPressCancel: () => _stopAudioRecording(cancel: true),
              child: CircleAvatar(
                radius: 26,
                backgroundColor: _willCancelRecording
                    ? Colors.grey
                    : (_isRecording ? Colors.red : Colors.green),
                child: Icon(
                  _willCancelRecording ? Icons.delete : Icons.mic,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField() {
    return TextField(
      controller: widget.controller,
      decoration: InputDecoration(
        hintText: "اكتب رسالة...",
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildRecordingInfo() {
    final minutes = _recordingDuration.inMinutes;
    final seconds = _recordingDuration.inSeconds % 60;
    final durationText = "$minutes:${seconds.toString().padLeft(2, '0')}";

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          durationText,
          style:
              const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        Expanded(
          child: AnimatedOpacity(
            opacity: _willCancelRecording ? 0.3 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Transform.translate(
              offset: Offset(_dragX, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chevron_left,
                      color: Colors.grey.shade600, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    "اسحب للإلغاء",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
