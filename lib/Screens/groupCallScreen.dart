import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:groupify_app/Services/agoraConfig.dart';
import 'package:groupify_app/Services/groupCallLink.dart';

class GroupCallScreen extends StatefulWidget {
  final String callId;
  final bool isVideoCall;

  const GroupCallScreen({
    super.key,
    required this.callId,
    this.isVideoCall = false,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  bool isMuted = false;
  bool isSpeakerOn = true;
  bool isCameraOff = false;
  bool _left = false;

  RtcEngine? _engine;
  int? _myUid;
  final Set<int> _remoteUids = <int>{};
  String? _mediaError;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _participantsSub;
  final Map<int, String> _participantNames = {};

  DocumentReference<Map<String, dynamic>> get _callDocRef =>
      FirebaseFirestore.instance.collection("group_calls").doc(widget.callId);

  @override
  void initState() {
    super.initState();
    _setupAgora();
  }

  Future<void> _setupAgora() async {
    final DocumentSnapshot<Map<String, dynamic>> callDoc;
    try {
      callDoc = await _callDocRef.get();
    } catch (e) {
      print("❌ خطأ بجلب بيانات المكالمة: $e");
      if (mounted) {
        setState(() => _mediaError = "ما قدرت أوصل لبيانات المكالمة: $e");
      }
      return;
    }
    if (!callDoc.exists) {
      if (mounted) {
        setState(() => _mediaError = "هاي الدعوة منتهية أو غير صحيحة");
      }
      return;
    }

    final permissions = [
      Permission.microphone,
      if (widget.isVideoCall) Permission.camera,
    ];
    final statuses = await permissions.request();
    final denied = statuses.values.any((s) => !s.isGranted);
    if (denied) {
      if (mounted) {
        setState(() {
          _mediaError =
              "لازم صلاحية الميكروفون${widget.isVideoCall ? ' والكاميرا' : ''} حتى تنضم";
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
          onJoinChannelSuccess: (connection, elapsed) async {
            _myUid = connection.localUid;
            await _registerParticipant();
            if (mounted) setState(() {});
            engine!.setEnableSpeakerphone(isSpeakerOn);
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (mounted) setState(() => _remoteUids.add(remoteUid));
          },
          onUserOffline: (connection, remoteUid, reason) {
            if (mounted) setState(() => _remoteUids.remove(remoteUid));
          },
          onError: (err, msg) {
            print("❌ خطأ Agora: $err - $msg");
            if (mounted) {
              setState(() => _mediaError = "خطأ Agora: ${err.name} - $msg");
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

      _listenParticipants();

      if (!mounted) {
        await engine.leaveChannel();
        await engine.release();
      } else {
        setState(() {});
      }
    } catch (e) {
      print("❌ خطأ بإعداد المكالمة الجماعية: $e");
      await engine?.release();
      if (mounted) {
        setState(() => _mediaError = "فشل في $stage: $e");
      }
    }
  }

  Future<void> _registerParticipant() async {
    final uid = _myUid;
    final user = FirebaseAuth.instance.currentUser;
    if (uid == null || user == null) return;
    final name = user.displayName ?? user.email ?? "مستخدم";
    await _callDocRef.collection("participants").doc(uid.toString()).set({
      "name": name,
      "email": user.email,
      "joinedAt": FieldValue.serverTimestamp(),
    });
  }

  void _listenParticipants() {
    _participantsSub = _callDocRef.collection("participants").snapshots().listen(
      (snapshot) {
        final names = <int, String>{};
        for (final doc in snapshot.docs) {
          final uid = int.tryParse(doc.id);
          if (uid == null) continue;
          names[uid] = (doc.data()["name"] as String?) ?? "مستخدم";
        }
        if (mounted) setState(() => _participantNames
          ..clear()
          ..addAll(names));
      },
    );
  }

  Future<void> _leaveCall() async {
    if (_left) return;
    _left = true;

    final uid = _myUid;
    if (uid != null) {
      await _callDocRef
          .collection("participants")
          .doc(uid.toString())
          .delete()
          .catchError((_) {});
    }

    final engine = _engine;
    _engine = null;
    if (engine != null) {
      try {
        await engine.leaveChannel();
        await engine.release();
      } catch (e) {
        print("❌ خطأ بإنهاء اتصال Agora: $e");
      }
    }
    await _participantsSub?.cancel();

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _participantsSub?.cancel();
    _engine?.leaveChannel();
    _engine?.release();
    super.dispose();
  }

  String _nameFor(int uid) => _participantNames[uid] ?? "مستخدم";

  @override
  Widget build(BuildContext context) {
    final totalCount = 1 + _remoteUids.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      widget.isVideoCall ? Icons.videocam : Icons.call,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "$totalCount ${totalCount == 1 ? 'مشارك' : 'مشاركين'}",
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_1, color: Colors.white70),
                      tooltip: "ادعُ أصدقاء",
                      onPressed: () => GroupCallLink.share(
                        callId: widget.callId,
                        isVideoCall: widget.isVideoCall,
                        hostName: FirebaseAuth.instance.currentUser
                                ?.displayName ??
                            "صديقك",
                      ),
                    ),
                  ],
                ),
              ),
              if (_mediaError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _mediaError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 15),
                  ),
                ),
              Expanded(
                child: widget.isVideoCall ? _buildVideoGrid() : _buildAudioParticipants(),
              ),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoGrid() {
    final engine = _engine;
    if (engine == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }

    final tiles = <Widget>[
      _videoTile(
        child: AgoraVideoView(
          controller: VideoViewController(
            rtcEngine: engine,
            canvas: const VideoCanvas(uid: 0),
          ),
        ),
        label: "أنت",
      ),
      for (final uid in _remoteUids)
        _videoTile(
          child: AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: engine,
              canvas: VideoCanvas(uid: uid),
              connection: RtcConnection(channelId: widget.callId),
            ),
          ),
          label: _nameFor(uid),
        ),
    ];

    return GridView.count(
      padding: const EdgeInsets.all(8),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3 / 4,
      children: tiles,
    );
  }

  Widget _videoTile({required Widget child, required String label}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.grey.shade900, child: child),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioParticipants() {
    final uids = [_myUid, ..._remoteUids.toList()..sort()];
    return GridView.count(
      padding: const EdgeInsets.all(20),
      crossAxisCount: 3,
      mainAxisSpacing: 20,
      crossAxisSpacing: 12,
      children: uids.where((u) => u != null).map((uid) {
        final isMe = uid == _myUid;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, size: 36, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              isMe ? "أنت" : _nameFor(uid!),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _controlButton(
            icon: isMuted ? Icons.mic_off : Icons.mic,
            onPressed: () {
              setState(() => isMuted = !isMuted);
              _engine?.muteLocalAudioStream(isMuted);
            },
          ),
          const SizedBox(width: 20),
          if (widget.isVideoCall)
            _controlButton(
              icon: isCameraOff ? Icons.videocam_off : Icons.videocam,
              onPressed: () {
                setState(() => isCameraOff = !isCameraOff);
                _engine?.muteLocalVideoStream(isCameraOff);
              },
            ),
          if (widget.isVideoCall) const SizedBox(width: 20),
          _controlButton(
            icon: isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            onPressed: () {
              setState(() => isSpeakerOn = !isSpeakerOn);
              _engine?.setEnableSpeakerphone(isSpeakerOn);
            },
          ),
          const SizedBox(width: 20),
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.red,
            child: IconButton(
              icon: const Icon(Icons.call_end, color: Colors.white, size: 28),
              onPressed: _leaveCall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton({required IconData icon, required VoidCallback onPressed}) {
    return CircleAvatar(
      radius: 27,
      backgroundColor: Colors.white24,
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }
}
