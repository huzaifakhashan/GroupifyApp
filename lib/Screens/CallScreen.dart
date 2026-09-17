import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:groupify_app/Services/agoraConfig.dart';

class Callscreen extends StatefulWidget {
  final String callId;
  final String userName;
  final String userEmail;
  final bool isVideoCall;

  const Callscreen({
    super.key,
    required this.callId,
    required this.userName,
    required this.userEmail,
    this.isVideoCall = false,
  });

  @override
  State<Callscreen> createState() => _CallscreenState();
}

class _CallscreenState extends State<Callscreen> {
  bool isMuted = false;
  bool isSpeakerOn = true;
  bool _ended = false;

  RtcEngine? _engine;
  bool _joinedChannel = false;
  int? _remoteUid;
  String? _mediaError;

  DocumentReference<Map<String, dynamic>> get _callRef =>
      FirebaseFirestore.instance.collection("calls").doc(widget.callId);

  @override
  void initState() {
    super.initState();
    _setupAgora();
  }

  Future<void> _setupAgora() async {
    final permissions = [
      Permission.microphone,
      if (widget.isVideoCall) Permission.camera,
    ];
    final statuses = await permissions.request();
    final denied = statuses.values.any((s) => !s.isGranted);
    if (denied) {
      if (mounted) {
        setState(() {
          _mediaError = "لازم صلاحية الميكروفون${widget.isVideoCall ? ' والكاميرا' : ''} حتى تتصل";
        });
      }
      return;
    }

    if (AgoraConfig.appId.trim().isEmpty) {
      if (mounted) setState(() => _mediaError = "Agora App ID غير مضبوط");
      return;
    }

    var stage = "إنشاء محرك Agora";
    RtcEngine? engine;
    try {
      engine = createAgoraRtcEngine();
      stage = "تهيئة Agora";
      await engine.initialize(
        RtcEngineContext(
          appId: AgoraConfig.appId.trim(),
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      _engine = engine;

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (mounted) setState(() => _joinedChannel = true);
            engine!.setEnableSpeakerphone(isSpeakerOn);
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (mounted) setState(() => _remoteUid = remoteUid);
          },
          onUserOffline: (connection, remoteUid, reason) {
            if (mounted) setState(() => _remoteUid = null);
          },
          onError: (err, msg) {
            print("❌ خطأ Agora: $err - $msg");
            if (mounted) {
              setState(() => _mediaError = "خطأ Agora: ${err.name} - $msg");
            }
          },
          onConnectionStateChanged: (connection, state, reason) {
            print("🔌 حالة الاتصال: $state - $reason");
            if (reason ==
                    ConnectionChangedReasonType
                        .connectionChangedInvalidToken ||
                reason ==
                    ConnectionChangedReasonType
                        .connectionChangedTokenExpired) {
              if (mounted) {
                setState(() => _mediaError = "توكن Agora غير صالح أو منتهي");
              }
            }
          },
        ),
      );

      stage = "تفعيل الصوت";
      await engine.enableAudio();

      if (widget.isVideoCall) {
        stage = "تفعيل الفيديو";
        await engine.enableVideo();
        stage = "تشغيل معاينة الكاميرا";
        await engine.startPreview();
      }

      stage = "جلب Token من السيرفر";
      final token = await AgoraConfig.fetchToken(widget.callId);

      stage = "الانضمام إلى القناة";
      await engine.joinChannel(
        token: token,
        channelId: widget.callId,
        uid: 0,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          autoSubscribeAudio: true,
          autoSubscribeVideo: widget.isVideoCall,
          publishCameraTrack: widget.isVideoCall,
          publishMicrophoneTrack: true,
        ),
      );
      if (mounted) {
        setState(() => _engine = engine);
        await _setSpeakerphone(isSpeakerOn);
      } else {
        await engine.leaveChannel();
        await engine.release();
      }
    } catch (e) {
      print("❌ خطأ بإعداد Agora: $e");
      await engine?.release();
      if (mounted) {
        setState(() {
          _mediaError = "فشل في $stage: $e";
        });
      }
    }
  }

  Future<void> _setSpeakerphone(bool enabled) async {
    try {
      await _engine?.setEnableSpeakerphone(enabled);
    } catch (e) {
      print("⚠️ تعذر تغيير مخرج الصوت: $e");
    }
  }

  Future<void> _leaveAgora() async {
    final engine = _engine;
    if (engine == null) return;
    _engine = null;
    try {
      await engine.leaveChannel();
      await engine.release();
    } catch (e) {
      print("❌ خطأ بإنهاء اتصال Agora: $e");
    }
  }

  Future<void> _endCall(String currentStatus) async {
    if (_ended) return;
    _ended = true;

    await _leaveAgora();

    if (currentStatus == "ringing") {
      await _callRef.update({"status": "missed"});
    } else if (currentStatus == "accepted") {
      await _callRef.update({"status": "ended"});
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _leaveAfterRemoteEnd() async {
    if (_ended) return;
    _ended = true;
    await _leaveAgora();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _engine?.leaveChannel();
    _engine?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _callRef.snapshots(),
      builder: (context, snapshot) {
        final status = snapshot.data?.data()?["status"] ?? "ringing";

        if ((status == "declined" || status == "ended") && !_ended) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _leaveAfterRemoteEnd();
          });
        }

        final statusText = status == "accepted"
            ? (_joinedChannel ? "متصل الآن" : "جاري الاتصال...")
            : "جاري الاتصال...";

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _endCall(status);
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Stack(
                children: [
                  if (widget.isVideoCall && _engine != null) _buildVideoLayer(),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        children: [
                          const SizedBox(height: 80),
                          if (!widget.isVideoCall || _remoteUid == null)
                            CircleAvatar(
                              radius: 65,
                              backgroundColor: Colors.white24,
                              child: const Icon(
                                Icons.person,
                                size: 80,
                                color: Colors.white,
                              ),
                            ),
                          const SizedBox(height: 25),
                          Text(
                            widget.userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.userEmail,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _mediaError ?? statusText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _mediaError != null
                                  ? Colors.redAccent
                                  : Colors.white70,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 40),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.white24,
                              child: IconButton(
                                icon: Icon(
                                  isMuted ? Icons.mic_off : Icons.mic,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  setState(() => isMuted = !isMuted);
                                  _engine?.muteLocalAudioStream(isMuted);
                                },
                              ),
                            ),
                            const SizedBox(width: 25),
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.white24,
                              child: IconButton(
                                icon: Icon(
                                  isSpeakerOn
                                      ? Icons.volume_up
                                      : Icons.volume_down,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  setState(() => isSpeakerOn = !isSpeakerOn);
                                  _setSpeakerphone(isSpeakerOn);
                                },
                              ),
                            ),
                            const SizedBox(width: 25),
                            CircleAvatar(
                              radius: 35,
                              backgroundColor: Colors.red,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.call_end,
                                  color: Colors.white,
                                  size: 30,
                                ),
                                onPressed: () => _endCall(status),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoLayer() {
    final engine = _engine!;
    return Stack(
      children: [
        if (_remoteUid != null)
          Positioned.fill(
            child: AgoraVideoView(
              controller: VideoViewController.remote(
                rtcEngine: engine,
                canvas: VideoCanvas(uid: _remoteUid),
                connection: RtcConnection(channelId: widget.callId),
              ),
            ),
          ),
        Positioned(
          top: 20,
          right: 20,
          width: 110,
          height: 150,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AgoraVideoView(
              controller: VideoViewController(
                rtcEngine: engine,
                canvas: const VideoCanvas(uid: 0),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
