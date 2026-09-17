import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Screens/privateChatScreen.dart';

class CallsList extends StatelessWidget {
  const CallsList({super.key});

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final isToday = now.year == time.year &&
        now.month == time.month &&
        now.day == time.day;
    if (isToday) {
      final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
      final minute = time.minute.toString().padLeft(2, '0');
      final period = time.hour >= 12 ? "م" : "ص";
      return "$hour:$minute $period";
    }
    return "${time.day}/${time.month}/${time.year}";
  }

  @override
  Widget build(BuildContext context) {
    final myEmail = FirebaseAuth.instance.currentUser?.email;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
        ),
        child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: myEmail == null
            ? const Center(child: Text("سجّل الدخول لعرض المكالمات"))
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection("calls")
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text("خطأ: ${snapshot.error}"));
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final calls = (snapshot.data?.docs ?? []).where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data["caller"] == myEmail ||
                        data["receiver"] == myEmail;
                  }).toList()
                    ..sort((a, b) {
                      final aTime =
                          (a.data() as Map<String, dynamic>)["timestamp"]
                              as Timestamp?;
                      final bTime =
                          (b.data() as Map<String, dynamic>)["timestamp"]
                              as Timestamp?;
                      if (aTime == null && bTime == null) return 0;
                      if (aTime == null) return 1;
                      if (bTime == null) return -1;
                      return bTime.compareTo(aTime);
                    });

                  if (calls.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone_outlined,
                              color: Colors.indigo.shade300, size: 50),
                          const SizedBox(height: 10),
                          Text(
                            "لا يوجد مكالمات بعد",
                            style: TextStyle(
                                color: Colors.indigo.shade300, fontSize: 16),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: calls.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) {
                      final data =
                          calls[index].data() as Map<String, dynamic>;
                      final isOutgoing = data["caller"] == myEmail;
                      final otherName = isOutgoing
                          ? (data["receiverName"] ?? data["receiver"] ?? "")
                          : (data["callerName"] ?? data["caller"] ?? "");
                      final otherEmail = isOutgoing
                          ? (data["receiver"] ?? "")
                          : (data["caller"] ?? "");
                      final status = data["status"] ?? "ringing";
                      final timestamp = data["timestamp"] as Timestamp?;

                      IconData icon;
                      Color color;
                      String label;

                      switch (status) {
                        case "accepted":
                        case "ended":
                          icon = isOutgoing
                              ? Icons.call_made
                              : Icons.call_received;
                          color = Colors.green;
                          label = isOutgoing ? "مكالمة صادرة" : "مكالمة واردة";
                          break;
                        case "declined":
                          icon = Icons.call_end;
                          color = Colors.red;
                          label = isOutgoing ? "تم الرفض" : "مكالمة مرفوضة";
                          break;
                        case "missed":
                          icon = isOutgoing
                              ? Icons.call_made
                              : Icons.call_missed;
                          color = Colors.red;
                          label = isOutgoing ? "لم يتم الرد" : "مكالمة فائتة";
                          break;
                        default:
                          icon = Icons.phone_in_talk;
                          color = Colors.indigo;
                          label = "جارية الآن";
                      }

                      return ListTile(
                        leading: const CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.indigo,
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(
                          otherName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Row(
                          children: [
                            Icon(icon, size: 16, color: color),
                            const SizedBox(width: 4),
                            Text(
                              label,
                              style: TextStyle(fontSize: 12, color: color),
                            ),
                          ],
                        ),
                        trailing: timestamp != null
                            ? Text(
                                _formatTime(timestamp.toDate()),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              )
                            : null,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PrivateChatScreen(
                                userName: otherName,
                                userEmail: otherEmail,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
        ),
      ),
    );
  }
}
