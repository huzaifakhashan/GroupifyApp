import 'package:share_plus/share_plus.dart';

/// يبني ويبعث رابط الدعوة لمكالمة جماعية (groupify://call/<callId>?video=true|false).
class GroupCallLink {
  static Uri build({required String callId, required bool isVideoCall}) {
    return Uri(
      scheme: 'groupify',
      host: 'call',
      pathSegments: [callId],
      queryParameters: {'video': isVideoCall.toString()},
    );
  }

  static Future<void> share({
    required String callId,
    required bool isVideoCall,
    required String hostName,
  }) async {
    final link = build(callId: callId, isVideoCall: isVideoCall);
    final kind = isVideoCall ? "مكالمة فيديو" : "مكالمة صوتية";
    await SharePlus.instance.share(
      ShareParams(
        text: "$hostName بدعوك لـ$kind جماعية على Groupify 🎉\n"
            "اضغط الرابط للانضمام:\n$link",
      ),
    );
  }

  /// يحاول يستخرج (callId, isVideoCall) من رابط دعوة. null لو الرابط مش صالح.
  static ({String callId, bool isVideoCall})? parse(Uri uri) {
    if (uri.scheme != 'groupify' || uri.host != 'call') return null;
    if (uri.pathSegments.isEmpty) return null;
    final callId = uri.pathSegments.first;
    if (callId.isEmpty) return null;
    final isVideoCall = uri.queryParameters['video'] == 'true';
    return (callId: callId, isVideoCall: isVideoCall);
  }

  /// يحاول يستخرج (callId, isVideoCall) من نص حر ممكن يكون رابط دعوة كامل
  /// (متل اللي بيتبعت بالمشاركة، أو ملصوق ضمن رسالة فيها كلام زيادة)، أو
  /// رابط groupify:// لحاله، أو حتى الـ callId نفسه بس (fallback). null لو
  /// ما قدرنا نستخرج شي مفيد.
  static ({String callId, bool isVideoCall})? parseFromText(String text) {
    final input = text.trim();
    if (input.isEmpty) return null;

    final match = RegExp(r'groupify://call/\S+').firstMatch(input);
    if (match != null) {
      final uri = Uri.tryParse(match.group(0)!);
      if (uri != null) {
        final parsed = parse(uri);
        if (parsed != null) return parsed;
      }
    }

    final directUri = Uri.tryParse(input);
    if (directUri != null) {
      final parsed = parse(directUri);
      if (parsed != null) return parsed;
    }

    // مافي رابط صالح باللي انلصق - جرّب اعتبره الـ callId مباشرة.
    if (!input.contains(RegExp(r'\s'))) {
      return (callId: input, isVideoCall: false);
    }
    return null;
  }
}
