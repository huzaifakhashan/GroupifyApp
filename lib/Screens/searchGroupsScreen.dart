import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:groupify_app/Screens/groupChatScreen.dart';

class SearchGroupsScreen extends StatefulWidget {
  const SearchGroupsScreen({super.key});

  @override
  State<SearchGroupsScreen> createState() => _SearchGroupsScreenState();
}

enum _SortOption {
  newest("الأحدث إنشاءً"),
  oldest("الأقدم إنشاءً"),
  mostMembers("الأكثر أعضاء"),
  fewestMembers("الأقل أعضاء");

  final String label;
  const _SortOption(this.label);
}

class _SearchGroupsScreenState extends State<SearchGroupsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = "";
  _SortOption _sortOption = _SortOption.newest;

  Future<void> _joinGroup(BuildContext context, String groupId, String name) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("الانضمام للمجموعة"),
        content: Text("بدك تنضم لمجموعة \"$name\"؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("إلغاء"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("انضمام"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection("groups").doc(groupId).update({
        "memberUids": FieldValue.arrayUnion([myUid]),
        "memberEmails": FieldValue.arrayUnion([FirebaseAuth.instance.currentUser?.email ?? ""]),
        "memberNames": FieldValue.arrayUnion([
          FirebaseAuth.instance.currentUser?.displayName ??
              FirebaseAuth.instance.currentUser?.email ??
              "مستخدم",
        ]),
      });
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(groupId: groupId, groupName: name),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A00E0),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "ابحث عن اسم مجموعة...",
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
          onChanged: (value) {
            setState(() => _query = value.trim().toLowerCase());
          },
        ),
      ),
      body: Container(
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    Icon(Icons.sort, size: 18, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    const Text("ترتيب حسب:", style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    DropdownButton<_SortOption>(
                      value: _sortOption,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                      items: _SortOption.values
                          .map((option) => DropdownMenuItem(
                                value: option,
                                child: Text(option.label),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _sortOption = value);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildResults(myUid)),
            ],
          ),
        ),
      ),
    );
  }

  int _compareGroups(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
    final dataA = a.data() as Map<String, dynamic>;
    final dataB = b.data() as Map<String, dynamic>;

    switch (_sortOption) {
      case _SortOption.mostMembers:
        final countA = List<String>.from(dataA["memberUids"] ?? []).length;
        final countB = List<String>.from(dataB["memberUids"] ?? []).length;
        return countB.compareTo(countA);
      case _SortOption.fewestMembers:
        final countA = List<String>.from(dataA["memberUids"] ?? []).length;
        final countB = List<String>.from(dataB["memberUids"] ?? []).length;
        return countA.compareTo(countB);
      case _SortOption.oldest:
        final tA = dataA["createdAt"] as Timestamp?;
        final tB = dataB["createdAt"] as Timestamp?;
        if (tA == null && tB == null) return 0;
        if (tA == null) return 1;
        if (tB == null) return -1;
        return tA.compareTo(tB);
      case _SortOption.newest:
        final tA = dataA["createdAt"] as Timestamp?;
        final tB = dataB["createdAt"] as Timestamp?;
        if (tA == null && tB == null) return 0;
        if (tA == null) return 1;
        if (tB == null) return -1;
        return tB.compareTo(tA);
    }
  }

  // لازم where("isPrivate", isEqualTo: false) هون، مش استعلام مفتوح على كل
  // المجموعة: Firestore بيرفض أي استعلام غير مقيّد إذا قاعدة القراءة
  // بتعتمد على بيانات المستند (هون isPrivate)، لأنه ما بيقدر يثبت مسبقاً
  // إن كل نتيجة محتملة بتحقق الشرط. الشرط الفرعي isPrivate == false بيثبت
  // تلقائياً شرط الصلاحية (isPrivate != true) فبيسمح الاستعلام.
  Widget _buildResults(String? myUid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("groups")
          .where("isPrivate", isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("خطأ: ${snapshot.error}"));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final groups = (snapshot.data?.docs ?? []).where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = (data["name"] ?? "").toString().toLowerCase();
          if (_query.isEmpty) return true;
          return name.contains(_query);
        }).toList()
          ..sort(_compareGroups);

        if (groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.group_off_outlined,
                    color: Colors.indigo.shade300, size: 50),
                const SizedBox(height: 10),
                Text(
                  _query.isEmpty
                      ? "لا يوجد مجموعات"
                      : "ما في نتائج لـ \"$_query\"",
                  style: TextStyle(color: Colors.indigo.shade300, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: groups.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) {
            final doc = groups[index];
            final data = doc.data() as Map<String, dynamic>;
            final name = (data["name"] ?? "مجموعة").toString();
            final photoUrl = data["photoUrl"] as String?;
            final memberUids = List<String>.from(data["memberUids"] ?? []);
            final memberCount = memberUids.length;
            final isMember = myUid != null && memberUids.contains(myUid);

            return ListTile(
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: Colors.indigo,
                backgroundImage: photoUrl == null ? null : CachedNetworkImageProvider(photoUrl),
                child: photoUrl == null ? const Icon(Icons.groups, color: Colors.white) : null,
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (isMember) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "عضو",
                        style: TextStyle(fontSize: 10, color: Colors.indigo.shade700),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                "$memberCount ${memberCount == 1 ? 'عضو' : 'أعضاء'}",
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                if (isMember) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupChatScreen(groupId: doc.id, groupName: name),
                    ),
                  );
                } else {
                  _joinGroup(context, doc.id, name);
                }
              },
            );
          },
        );
      },
    );
  }
}
