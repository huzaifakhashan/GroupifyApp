import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Services/statusService.dart';
import 'package:groupify_app/Screens/createStatusScreen.dart';
import 'package:groupify_app/Screens/statusViewerScreen.dart';

class _UserStatuses {
  final String uid;
  final String name;
  final String? photoUrl;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> statuses;

  const _UserStatuses({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.statuses,
  });

  bool hasUnseenBy(String myUid) {
    return statuses.any((doc) {
      final viewedBy = List<String>.from(doc.data()["viewedBy"] ?? []);
      return !viewedBy.contains(myUid);
    });
  }

  Timestamp? get latestTime =>
      statuses.last.data()["createdAt"] as Timestamp?;
}

class StatusList extends StatelessWidget {
  const StatusList({super.key});

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return "";
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return "الآن";
    if (diff.inHours < 1) return "منذ ${diff.inMinutes} دقيقة";
    if (diff.inDays < 1) return "منذ ${diff.inHours} ساعة";
    return "منذ ${diff.inDays} يوم";
  }

  List<_UserStatuses> _groupByUser(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final order = <String>[];
    final map = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in docs) {
      final data = doc.data();
      final uid = (data["uid"] ?? "").toString();
      if (uid.isEmpty) continue;
      if (!map.containsKey(uid)) {
        map[uid] = [];
        order.add(uid);
      }
      map[uid]!.add(doc);
    }
    return order.map((uid) {
      final statuses = map[uid]!;
      final firstData = statuses.first.data();
      return _UserStatuses(
        uid: uid,
        name: (firstData["name"] ?? "مستخدم").toString(),
        photoUrl: firstData["photoUrl"] as String?,
        statuses: statuses,
      );
    }).toList();
  }

  void _openViewer(BuildContext context, _UserStatuses group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatusViewerScreen(
          uid: group.uid,
          name: group.name,
          photoUrl: group.photoUrl,
          statuses: group.statuses,
        ),
      ),
    );
  }

  Widget _ring({required Widget child, required bool active, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? color : Colors.grey.shade300,
          width: 2.5,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

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
        child: myUid == null
            ? const Center(child: Text("سجّل الدخول لعرض الحالات"))
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: StatusService.activeStatuses(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text("خطأ: ${snapshot.error}"));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final groups = _groupByUser(snapshot.data?.docs ?? []);
                  final myGroup = groups.where((g) => g.uid == myUid).toList();
                  final otherGroups = groups.where((g) => g.uid != myUid).toList()
                    ..sort((a, b) {
                      final aUnseen = a.hasUnseenBy(myUid) ? 0 : 1;
                      final bUnseen = b.hasUnseenBy(myUid) ? 0 : 1;
                      if (aUnseen != bUnseen) return aUnseen.compareTo(bUnseen);
                      final ta = a.latestTime;
                      final tb = b.latestTime;
                      if (ta == null && tb == null) return 0;
                      if (ta == null) return 1;
                      if (tb == null) return -1;
                      return tb.compareTo(ta);
                    });

                  return ListView(
                    padding: const EdgeInsets.only(top: 10),
                    children: [
                      ListTile(
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _ring(
                              active: myGroup.isNotEmpty,
                              color: Colors.indigo,
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.indigo,
                                backgroundImage: myGroup.isNotEmpty && myGroup.first.photoUrl != null
                                    ? CachedNetworkImageProvider(myGroup.first.photoUrl!)
                                    : null,
                                child: myGroup.isEmpty || myGroup.first.photoUrl == null
                                    ? const Icon(Icons.person, color: Colors.white)
                                    : null,
                              ),
                            ),
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const CircleAvatar(
                                  radius: 9,
                                  backgroundColor: Colors.indigo,
                                  child: Icon(Icons.add, color: Colors.white, size: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          myGroup.isEmpty ? "أضف حالة" : "حالتي",
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: myGroup.isNotEmpty
                            ? Text(_timeAgo(myGroup.first.latestTime))
                            : const Text("شارك صورة أو فيديو أو نص يختفي بعد 24 ساعة"),
                        onTap: () {
                          if (myGroup.isNotEmpty) {
                            _openViewer(context, myGroup.first);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const CreateStatusScreen()),
                            );
                          }
                        },
                        trailing: myGroup.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: Colors.indigo),
                                tooltip: "إضافة حالة",
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const CreateStatusScreen()),
                                  );
                                },
                              )
                            : null,
                      ),
                      if (otherGroups.isNotEmpty) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            "آخر التحديثات",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        ...otherGroups.map((group) {
                          final unseen = group.hasUnseenBy(myUid);
                          return ListTile(
                            leading: _ring(
                              active: unseen,
                              color: Colors.indigo,
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.indigo,
                                backgroundImage: group.photoUrl != null
                                    ? CachedNetworkImageProvider(group.photoUrl!)
                                    : null,
                                child: group.photoUrl == null
                                    ? const Icon(Icons.person, color: Colors.white)
                                    : null,
                              ),
                            ),
                            title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(_timeAgo(group.latestTime)),
                            onTap: () => _openViewer(context, group),
                          );
                        }),
                      ] else if (myGroup.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.auto_awesome_motion_outlined,
                                    color: Colors.indigo.shade200, size: 50),
                                const SizedBox(height: 10),
                                Text(
                                  "ما في حالات لهلق",
                                  style: TextStyle(color: Colors.indigo.shade300, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
