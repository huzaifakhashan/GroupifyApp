import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:groupify_app/Services/agoraConfig.dart';

// ملف اختبار مؤقت لتأكيد إنه اتصال Agora (صوت + فيديو) شغّال فعلياً بين
// جهازين حقيقيين، بدون المرور بتسجيل الدخول أو Firestore. لازم يُحذف بعد
// التأكد من النتيجة.
void main() {
  runApp(const MaterialApp(home: AgoraTestScreen()));
}

class AgoraTestScreen extends StatefulWidget {
  const AgoraTestScreen({super.key});
  @override
  State<AgoraTestScreen> createState() => _AgoraTestScreenState();
}

class _AgoraTestScreenState extends State<AgoraTestScreen> {
  RtcEngine? _engine;
  String _log = "بدء الاتصال...";
  int? _remoteUid;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      print("TESTLOG requesting permissions...");
      await [Permission.microphone, Permission.camera].request();
      print("TESTLOG permissions done, creating engine...");
      final engine = createAgoraRtcEngine();
      print("TESTLOG initializing engine...");
      await engine.initialize(RtcEngineContext(
        appId: AgoraConfig.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      print("TESTLOG engine initialized");
      engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (c, e) {
          print("TESTLOG ✅ joined channel uid=${c.localUid}");
          setState(() => _log = "✅ انضممت للقناة، uid=${c.localUid}");
        },
        onUserJoined: (c, uid, e) {
          print("TESTLOG ✅ remote joined uid=$uid");
          setState(() {
            _remoteUid = uid;
            _log = "✅ الطرف التاني انضم! uid=$uid";
          });
        },
        onUserOffline: (c, uid, r) {
          print("TESTLOG ⚠️ remote left uid=$uid reason=$r");
          setState(() {
            _remoteUid = null;
            _log = "⚠️ الطرف التاني طلع: $uid";
          });
        },
        onError: (err, msg) {
          print("TESTLOG ❌ error: $err $msg");
          setState(() => _log = "❌ خطأ: $err $msg");
        },
        onConnectionStateChanged: (c, state, reason) {
          print("TESTLOG connection state=$state reason=$reason");
          setState(() => _log = "حالة الاتصال: $state / $reason");
        },
      ));

      print("TESTLOG enabling audio...");
      await engine.enableAudio();
      print("TESTLOG enabling video...");
      await engine.enableVideo();
      print("TESTLOG starting preview...");
      await engine.startPreview();
      print("TESTLOG joining channel...");
      await engine.joinChannel(
        token: '',
        channelId: 'groupify-test-channel',
        uid: 0,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
        ),
      );

      print("TESTLOG joinChannel call returned");
      setState(() => _engine = engine);
    } catch (e) {
      print("TESTLOG ❌ exception: $e");
      setState(() => _log = "❌ استثناء: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_log,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20)),
            const SizedBox(height: 20),
            Text("remoteUid: $_remoteUid",
                style: const TextStyle(color: Colors.greenAccent)),
            const SizedBox(height: 20),
            if (_engine != null && _remoteUid != null)
              SizedBox(
                width: 300,
                height: 300,
                child: AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: _engine!,
                    canvas: VideoCanvas(uid: _remoteUid),
                    connection:
                        const RtcConnection(channelId: 'groupify-test-channel'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
