import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class AudioMessageWidget extends StatefulWidget {
  final String audioUrl;
  final bool isMe;
  final String senderName;

  const AudioMessageWidget({
    super.key,
    required this.audioUrl,
    required this.isMe,
    required this.senderName,
  });

  @override
  State<AudioMessageWidget> createState() => _AudioMessageWidgetState();
}

class _AudioMessageWidgetState extends State<AudioMessageWidget> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    _audioPlayer.durationStream.listen((duration) {
      if (!mounted) return;
      setState(() {
        _duration = duration ?? Duration.zero;
      });
    });

    _audioPlayer.positionStream.listen((position) {
      if (!mounted) return;
      setState(() {
        _position = position;
      });
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
      });
    });
  }

  Future<void> _playPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        // إذا لم يتم تحميل الملف مسبقاً، حمّله الآن
        if (_audioPlayer.audioSource == null) {
          final client = HttpClient();
          try {
            final request = await client.getUrl(Uri.parse(widget.audioUrl));
            final response = await request.close();
            if (response.statusCode != HttpStatus.ok &&
                response.statusCode != HttpStatus.partialContent) {
              final details = await response.transform(SystemEncoding().decoder).join();
              throw Exception(
                'فشل تنزيل الصوت (HTTP ${response.statusCode}): '
                '${details.trim()}',
              );
            }

            final bytes = await response.fold<List<int>>(
              <int>[],
              (buffer, chunk) => buffer..addAll(chunk),
            );
            final directory = await getTemporaryDirectory();
            final localFile = File(
              '${directory.path}/audio_${widget.audioUrl.hashCode}.m4a',
            );
            await localFile.writeAsBytes(bytes, flush: true);
            await _audioPlayer.setFilePath(localFile.path);
          } finally {
            client.close(force: true);
          }
        }
        await _audioPlayer.play();
      }
    } catch (e) {
      print("❌ خطأ في تشغيل الملف الصوتي: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("خطأ تشغيل الصوت: $e"),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // اسم المرسل (إذا لم تكن رسالتي)
        if (!widget.isMe)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Text(
              widget.senderName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.indigo.shade700,
              ),
            ),
          ),

        // عنصر التشغيل الصوتي
        Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isMe ? Colors.indigo : Colors.grey.shade200,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
              bottomRight: Radius.circular(widget.isMe ? 4 : 18),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // زر التشغيل/الإيقاف
                  GestureDetector(
                    onTap: _playPause,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isMe
                            ? Colors.white24
                            : Colors.indigo.shade200,
                      ),
                      child: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: widget.isMe ? Colors.white : Colors.indigo,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // شريط التقدم
                  Expanded(
                    child: Column(
                      children: [
                        // شريط المدة
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _duration.inMilliseconds > 0
                                ? (_position.inMilliseconds /
                                    _duration.inMilliseconds)
                                : 0,
                            backgroundColor: widget.isMe
                                ? Colors.white12
                                : Colors.grey.shade400,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              widget.isMe
                                  ? Colors.white
                                  : Colors.indigo.shade700,
                            ),
                            minHeight: 4,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // المدة الزمنية
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(_position),
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.isMe
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                            ),
                            Text(
                              _formatDuration(_duration),
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.isMe
                                    ? Colors.white70
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
