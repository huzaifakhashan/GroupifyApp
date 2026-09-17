import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:groupify_app/Widgets/messageActions.dart';

const List<String> kQuickReactions = ["❤️", "😂", "😮", "😢", "👍", "🙏"];
const String _kDeleteSentinel = "__delete__";
const String _kSelectSentinel = "__select__";

/// يفتح شريط اختيار التفاعل (متل واتساب) بالقرب من الرسالة، معه أيقونتين
/// بآخر الشريط: تحديد (لبدء وضع تحديد رسائل متعددة) وحذف. اختيار إيموجي
/// بيحفظ/يشيل تفاعل المستخدم الحالي، والحذف بيفتح شيت "حذف لدي / حذف لدى
/// الجميع" لهاي الرسالة لحالها، والتحديد بينده [onSelectRequested] حتى
/// الشاشة تفعّل وضع التحديد المتعدد وتبلش فيه بهاي الرسالة.
Future<void> showReactionPicker(
  BuildContext anchorContext, {
  required DocumentReference<Object?> messageRef,
  required Map<String, dynamic> data,
  required String currentUserId,
  required bool isMe,
  required VoidCallback onSelectRequested,
}) async {
  final anchorBox = anchorContext.findRenderObject() as RenderBox;
  final overlayBox =
      Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
  final anchorRect =
      anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
          anchorBox.size;
  final left = (anchorRect.center.dx - 150)
      .clamp(8.0, overlayBox.size.width - 300.0);
  final top = anchorRect.top > 72 ? anchorRect.top - 68 : anchorRect.bottom + 8;

  final reactions = Map<String, dynamic>.from(
    (data["reactions"] as Map?) ?? const {},
  );
  final currentReaction = reactions[currentUserId] as String?;

  final selected = await showGeneralDialog<String>(
    context: anchorContext,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    barrierLabel: "reactions",
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: Material(
              color: Theme.of(dialogContext).cardColor,
              elevation: 10,
              shadowColor: Colors.black45,
              borderRadius: BorderRadius.circular(28),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final reaction in kQuickReactions)
                      InkWell(
                        onTap: () => Navigator.pop(dialogContext, reaction),
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: reaction == currentReaction
                                ? Colors.indigo.withValues(alpha: 0.15)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            reaction,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 1,
                      height: 26,
                      color: Colors.black12,
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(dialogContext, _kSelectSentinel),
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.check_circle_outline, size: 22),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(dialogContext, _kDeleteSentinel),
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.delete_outline, size: 22, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );

  if (selected == null) return;

  if (selected == _kSelectSentinel) {
    onSelectRequested();
    return;
  }

  if (selected == _kDeleteSentinel) {
    if (!anchorContext.mounted) return;
    await showDeleteMessageOptions(
      anchorContext,
      messageRef: messageRef,
      isMe: isMe,
      currentUserId: currentUserId,
    );
    return;
  }

  final update = currentReaction == selected
      ? {"reactions.$currentUserId": FieldValue.delete()}
      : {"reactions.$currentUserId": selected};
  try {
    await messageRef.update(update);
    HapticFeedback.selectionClick();
  } on FirebaseException catch (error) {
    if (!anchorContext.mounted) return;
    ScaffoldMessenger.of(anchorContext).showSnackBar(
      SnackBar(content: Text("تعذر حفظ التفاعل: ${error.code}")),
    );
  }
}

/// شارة تفاعلات الرسالة (تظهر عالقة بزاوية الفقاعة متل واتساب)، والضغط عليها
/// يفتح قائمة بالأشخاص اللي تفاعلوا وبأي إيموجي.
class MessageReactionsBadge extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  final String currentUserId;

  const MessageReactionsBadge({
    super.key,
    required this.data,
    required this.isMe,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final reactions = Map<String, dynamic>.from(
      (data["reactions"] as Map?) ?? const {},
    );
    if (reactions.isEmpty) return const SizedBox.shrink();

    final counts = <String, int>{};
    for (final reaction in reactions.values) {
      final value = reaction.toString();
      counts[value] = (counts[value] ?? 0) + 1;
    }
    final topEmojis = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final iReacted = reactions.containsKey(currentUserId);

    return Transform.translate(
      offset: const Offset(0, -12),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(right: isMe ? 14 : 0, left: isMe ? 0 : 14),
          child: GestureDetector(
            onTap: () => _showReactionDetails(context, reactions),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: iReacted ? Colors.indigo : Colors.black12,
                  width: iReacted ? 1.4 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final emoji in topEmojis.take(3))
                    Text(emoji, style: const TextStyle(fontSize: 13)),
                  if (reactions.length > 1) ...[
                    const SizedBox(width: 3),
                    Text(
                      "${reactions.length}",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showReactionDetails(
    BuildContext context,
    Map<String, dynamic> reactions,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final uids = reactions.keys.toList();
        return FutureBuilder<QuerySnapshot>(
          future: uids.isEmpty
              ? null
              : FirebaseFirestore.instance
                  .collection("users")
                  .where(FieldPath.documentId, whereIn: uids.take(10).toList())
                  .get(),
          builder: (context, snapshot) {
            final names = <String, String>{};
            if (snapshot.hasData) {
              for (final doc in snapshot.data!.docs) {
                final userData = doc.data() as Map<String, dynamic>;
                names[doc.id] =
                    (userData["name"] ?? userData["email"] ?? "مستخدم")
                        .toString();
              }
            }
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    ...reactions.entries.map(
                      (entry) => ListTile(
                        dense: true,
                        leading: Text(
                          entry.value.toString(),
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(
                          entry.key == currentUserId
                              ? "أنت"
                              : names[entry.key] ?? "مستخدم",
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
