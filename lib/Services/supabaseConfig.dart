class SupabaseConfig {
    static const url = String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: 'https://ufeuazufbppebpkqhbkz.supabase.co',
    );
  static const publishableKey =
            String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
        defaultValue: 'sb_publishable_Eh_8UI30wJp8SpCxHbVo0w_Tkpgf-HZ',
    );
  static const audioBucket = 'audios';
  // نفس الـ bucket مستخدم لكل أنواع الوسائط (صوت/صور/فيديو/ملفات) —
  // مو محتاجين ننشئ bucket جديد بلوحة Supabase لكل نوع.
  static const mediaBucket = audioBucket;

  static bool get isConfigured =>
      url.isNotEmpty && publishableKey.isNotEmpty;
}
