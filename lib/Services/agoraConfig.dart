import 'dart:convert';
import 'package:http/http.dart' as http;

class AgoraConfig {
  static const appId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: '6d06e3254604434fa88824a99d034d95',
  );

  // رابط الـ Cloudflare Worker اللي بيولّد التوكن (شوف cloudflare-worker/README.md).
  static const _tokenServerUrl = String.fromEnvironment(
    'AGORA_TOKEN_SERVER_URL',
    defaultValue: 'https://groupify-agora-token.huzaifa-khashan.workers.dev',
  );

  // نفس القيمة اللي انحطت بـ "wrangler secret put APP_SHARED_KEY".
  static const _appKey = String.fromEnvironment(
    'AGORA_APP_KEY',
    defaultValue: '4bcea4484a4851123c959ac4f95456b1ac73cdbacc8bd9fe',
  );

  // مشروع Agora مفعّل عليه App Certificate إجبارياً، فلازم Token حقيقي
  // لكل مكالمة. التوليد بيصير عبر سيرفر خارجي حتى ما تنكشف الشهادة
  // جوا التطبيق.
  static Future<String> fetchToken(String channelName) async {
    final response = await http.post(
      Uri.parse(_tokenServerUrl),
      headers: {
        'Content-Type': 'application/json',
        'x-app-key': _appKey,
      },
      body: jsonEncode({'channelName': channelName}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'فشل في جلب Token من السيرفر (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['token'] as String;
  }
}
