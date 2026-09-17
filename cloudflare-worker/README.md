# Agora Token Worker

سيرفر صغير ومجاني (Cloudflare Workers) وظيفته الوحيدة: يولّد Agora RTC Token لكل مكالمة، بحيث App Certificate الخاص بـ Agora ما يبقى أبداً جوا تطبيق الفلاتر.

## النشر (مرة وحدة بس)

من جوا هاد المجلد (`cloudflare-worker/`):

```bash
npm install
npx wrangler login        # بيفتح المتصفح، سجّل دخول / أنشئ حساب Cloudflare مجاني
npx wrangler secret put AGORA_APP_CERTIFICATE
# الصق قيمة Primary Certificate من Agora Console لما يطلبها

npx wrangler secret put APP_SHARED_KEY
# الصق القيمة: 4bcea4484a4851123c959ac4f95456b1ac73cdbacc8bd9fe
# (أو ولّد قيمة عشوائية جديدة بنفسك، المهم تحطها نفسها بالتطبيق)

npx wrangler deploy
```

بعد آخر أمر رح يطبعلك رابط شبيه بـ:
`https://groupify-agora-token.<your-subdomain>.workers.dev`

## بعد النشر

خذ الرابط اللي طلع وحطه بـ `lib/Services/agoraConfig.dart` بمكان
`_tokenServerUrl`، وتأكد `_appKey` مطابق لنفس القيمة اللي حطيتها بـ `APP_SHARED_KEY`.
