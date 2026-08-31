import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Callscreen extends StatefulWidget {
  final String callId;
  final String userName;
  final String userEmail;

  const Callscreen({
    super.key,
    required this.callId,
    required this.userName,
    required this.userEmail,
  });

  @override
  State<Callscreen> createState() => _CallscreenState();
}

class _CallscreenState extends State<Callscreen> {

  bool isMuted = false;
  bool isSpeakerOn = false;
  bool _ended = false;

  DocumentReference<Map<String, dynamic>> get _callRef =>
      FirebaseFirestore.instance.collection("calls").doc(widget.callId);

  Future<void> _endCall(String currentStatus) async {
    if (_ended) return;
    _ended = true;

    if (currentStatus == "ringing") {
      await _callRef.update({"status": "missed"});
    } else if (currentStatus == "accepted") {
      await _callRef.update({"status": "ended"});
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _callRef.snapshots(),
      builder: (context, snapshot) {
        final status = snapshot.data?.data()?["status"] ?? "ringing";

        if (status == "declined" && !_ended) {
          _ended = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }

        final statusText = status == "accepted" ? "متصل الآن" : "جاري الاتصال...";

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _endCall(status);
          },
          child: Scaffold(
            backgroundColor: Colors.black,

            body: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [

                  // معلومات الشخص
                  Column(
                    children: [

                      const SizedBox(height: 80),

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
                        statusText,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                        ),
                      ),

                    ],
                  ),


                  // أزرار التحكم
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: 40,
                    ),

                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [

                        // كتم الصوت
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.white24,
                          child: IconButton(
                            icon: Icon(
                              isMuted
                                  ? Icons.mic_off
                                  : Icons.mic,
                              color: Colors.white,
                            ),

                            onPressed: (){
                              setState(() {
                                isMuted = !isMuted;
                              });
                            },
                          ),
                        ),


                        const SizedBox(width: 25),


                        // السماعة
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

                            onPressed: (){
                              setState(() {
                                isSpeakerOn = !isSpeakerOn;
                              });
                            },
                          ),
                        ),


                        const SizedBox(width: 25),


                        // إنهاء المكالمة
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
            ),
          ),
        );
      },
    );
  }
}
