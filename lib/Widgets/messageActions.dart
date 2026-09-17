import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// شيت "حذف لدي" / "حذف لدى الجميع" لرسالة وحدة - يظهر بالضغطة المطوّلة
/// على أي رسالة. "حذف لدى الجميع" بيمسح المستند فعلياً (مسموح للمرسل بس
/// حسب قواعد Firestore)، و"حذف لدي" بيخفيها عني بس (إضافة uid تبعي لحقل
/// deletedFor)، من دون ما تنحذف عند الطرف التاني.
Future<void> showDeleteMessageOptions(
  BuildContext context, {
  required DocumentReference<Object?> messageRef,
  required bool isMe,
  required String currentUserId,
}) async {
  await showModalBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text("حذف لدي"),
            onTap: () async {
              Navigator.pop(sheetContext);
              await messageRef.update({
                "deletedFor": FieldValue.arrayUnion([currentUserId]),
              });
            },
          ),
          if (isMe)
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text(
                "حذف لدى الجميع",
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (!context.mounted) return;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text("حذف لدى الجميع"),
                    content: const Text(
                      "رح تنحذف هاي الرسالة عند كل الأطراف ولا تقدر ترجعها. متأكد؟",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text("إلغاء"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text("حذف", style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await messageRef.delete();
                }
              },
            ),
        ],
      ),
    ),
  );
}
