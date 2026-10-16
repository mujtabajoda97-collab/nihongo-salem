# الخادم الوسيط لتطبيق «نيهونغو مع سالم»

خادم صغير (Node.js 22 + TypeScript + Fastify) يضع `POST /v1/turn` الذي ينتظره تطبيق Flutter:

```
صوت المتعلم (m4a) ──▶ Whisper (ja) ──▶ Claude (prompt الحلقة أو الشخصية) ──▶ TTS (OpenAI أو ElevenLabs) ──▶ JSON + audio_url
```

## 1) تشغيل محلي
```bash
npm install            # مرة واحدة (ينشئ package-lock.json أيضاً)
cp .env.example .env   # ثم ضع ANTHROPIC_API_KEY و OPENAI_API_KEY
npm run dev            # http://localhost:8080  (GET /health ← {"ok":true})
npm test               # 40 اختباراً بمزودين وهميين: لا تصرف أي رصيد
npm run typecheck      # فحص TypeScript
```

تجربة بالـ curl:
```bash
# مكالمة حرة: الدور الأول (التحية)
curl -s localhost:8080/v1/turn -H 'content-type: application/json' -d '{
  "session_id":"t1","mode":"free_talk","persona":"kansai","tts_provider":"openai",
  "is_first_turn":true,"variables":{"USER_NAME":"サーレム","LOCAL_TIME":"08:15"}}'

# دور بالصوت (نفس شكل ما يرسله التطبيق)
curl -s localhost:8080/v1/turn \
  -F 'payload={"session_id":"t1","mode":"free_talk","persona":"kansai","is_first_turn":false}' \
  -F 'audio=@turn.m4a'

# إنهاء المكالمة
curl -s localhost:8080/v1/turn -H 'content-type: application/json' -d '{
  "session_id":"t1","mode":"free_talk","persona":"kansai","user_message":"__END_CALL__"}'
```

## 2) العقد مع التطبيق
**الطلب**: JSON عادي للنص، أو `multipart/form-data` فيه `payload` (نفس الـ JSON كنص) و`audio` (m4a). الحقول كما يرسلها `TutorTurnRequest` و`FreeTalkTurnRequest` في التطبيق:

| الحقل | ملاحظة |
|---|---|
| `session_id` | يربط أدوار المحادثة؛ الخادم يحتفظ بالتاريخ لأن التطبيق يرسل آخر رسالة فقط |
| `mode` | `episode_tutor` (داخل الحلقة) أو `free_talk`. الاسم `lesson_roleplay` مقبول كمرادف |
| `tone` / `persona` | النبرة (حلقات) أو الشخصية (مكالمة) |
| `variables` | متغيرات ملف الـ prompt (`{{TONE}}`, `{{EPISODE_SCENARIO}}` … أو `{{PERSONA}}`, `{{KNOWN_VOCAB}}` …) |
| `tts_provider` | `openai` أو `elevenlabs` |
| `user_message` | نص المتعلم، أو `__END_CALL__` لإنهاء المكالمة |
| `is_first_turn` | في المكالمة: الخادم يفرض نص التحية الحرفي للشخصية ويولّد صوتها |

**الرد (200)**: المفاتيح السبعة `correction_ar, reply_japanese, reply_romaji, reply_arabic, emotion_tone, has_mistake, conversation_completed` + اختيارياً `user_transcript` (ما سمعه Whisper) و`audio_url`.

**ما يضمنه الخادم بنفسه** (لا يعتمد على مزاج النموذج): تحية الدور الأول حرفية، و`__END_CALL__` ينتهي دائماً بـ `conversation_completed=true`، وحقول JSON تُصحَّح إن أخطأ النموذج بنوع بسيط، ويُعاد الطلب مرة واحدة إن لم يرجع JSON صالحاً.

**حالات الخطأ**: 400/413 لطلب خاطئ، 401 لمفتاح تطبيق خاطئ، 429 تجاوز الحد، 502 عند فشل Whisper أو Claude. فشل الصوت وحده (TTS) لا يُفشل الرد: يصل النص بلا `audio_url` ويجرّب الخادم المزوّد الآخر تلقائياً إن كان مُعدّاً. إن لم يسمع Whisper شيئاً (صمت/ضجيج) يردّ الخادم برسالة «لم أسمعك» دون استدعاء Claude.

## 3) النشر (مجاني أو شبه مجاني)
المقترح: **حاوية واحدة** (الذاكرة تحمل تاريخ المحادثات والصوتيات المؤقتة، فلا تشغّل أكثر من نسخة واحدة حالياً). راجع حدود الباقات المجانية الحالية عند كل مزوّد قبل الاعتماد عليها.

**Google Cloud Run**
```bash
gcloud run deploy japanese-api --source . --region europe-west1 --allow-unauthenticated \
  --max-instances=1 --min-instances=0 --memory=512Mi --timeout=60 \
  --set-env-vars ANTHROPIC_API_KEY=...,OPENAI_API_KEY=...,APP_API_KEY=...
```
**Render / Fly.io / Railway**: أنشئ خدمة من هذا المجلد (Dockerfile موجود)، ضع المتغيرات من `.env.example` في لوحة الإعدادات. بعض الباقات المجانية «تنام» عند عدم الاستخدام فيتأخر أول طلب بضع ثوانٍ.

بعد النشر: ضع الرابط في التطبيق `--dart-define=API_BASE_URL=https://...`. اضبط `PUBLIC_BASE_URL` إن جاء `audio_url` بعنوان خاطئ.

## 4) أقفل نقطة النهاية (مهم)
بدون قفل، أي شخص يعرف الرابط يصرف رصيدك. اضبط `APP_API_KEY` على الخادم، ثم في Flutter أضف الترويسة (تعديل صغير في `lib/services/tutor_api.dart` و`lib/core/constants.dart`):
```dart
// constants.dart  (داخل AppConfig)
static const String appApiKey = String.fromEnvironment('APP_API_KEY');
// tutor_api.dart  (داخل BaseOptions في DioTutorApi)
headers: {if (AppConfig.appApiKey.isNotEmpty) 'x-app-key': AppConfig.appApiKey},
```
```bash
flutter run --dart-define=API_BASE_URL=https://... --dart-define=APP_API_KEY=...
```
تنبيه صريح: مفتاح داخل التطبيق يمكن استخراجه من الملف المثبّت؛ هو يمنع العبث العابر لا المهاجم المصمم. الحد لكل IP (`RATE_LIMIT_PER_MINUTE`) يكمّله. وحصة الـ5 دقائق المجانية يطبقها التطبيق محلياً فقط؛ للحماية الكاملة اربطها لاحقاً بحساب مستخدم على الخادم.

## 5) توليد صوتيات الحلقات الثابتة
`generate_episodes_media.js` يقرأ ملفات `episode_XX.json` ويولّد كل ملف صوتي مذكور فيها: **573 سطراً + 320 كلمة = 893 ملفاً** (حوالي 14,700 حرف)، ويحفظها بالأسماء التي تنتظرها الحلقات (`ep01_line_01.mp3`, `ep01_v_01.mp3` …).
ضع مجلد الخادم بجانب مجلد التطبيق (`japanese_app/` و`japanese_app_backend/`) أو مرّر المسارات:
```bash
node --env-file=.env generate_episodes_media.js --dry-run          # عدّ فقط، بلا صرف
node --env-file=.env generate_episodes_media.js --episodes 1-2     # جرّب حلقتين أولاً واسمع الأصوات
node --env-file=.env generate_episodes_media.js                    # الكل (يتخطى الموجود، فيمكن استئنافه)
# خيارات: --provider elevenlabs  --only lines|vocab  --force  --concurrency 3  --episodes-dir ..  --out-dir ..  --voices voices.json
```
- الأصوات: يختار صوتاً للمتعلم (サーレム) ثم أصواتاً ذكورية/أنثوية للبقية بحسب الاسم والوصف العربي، ثابتة بين التشغيلات. للتعديل: `voices.json` مثل `{"ユキ":"nova","店員|موظفة المتجر":"coral"}`.
- الكلمات تُنطق من الكانا (لتجنب قراءة خاطئة للكانجي).
- يعيد المحاولة عند 429 وأخطاء الخادم، ويكتب الفاشل في `media_failures.json`؛ أعد نفس الأمر فيُكمل الناقص فقط.
- مع ElevenLabs: عيّن `ELEVENLABS_VOICES_MALE` و`ELEVENLABS_VOICES_FEMALE` (معرّفات مفصولة بفواصل).
- استمع لعيّنة قبل توليد الكل: التقييم النهائي للنطق بأذن بشرية.

## 6) ملاحظات تشغيل
- **الكلفة**: النموذج الافتراضي `claude-haiku-5-5` (غيّره بـ `ANTHROPIC_MODEL`؛ `claude-sonnet-5-5` أدق في التصحيح وأغلى). ملف الـ prompt الطويل يُرسل مع `cache_control` ليُخزَّن مؤقتاً داخل الجلسة. تحية الشخصية تُولَّد مرة وتُعاد من الذاكرة.
- **التأخير**: كل دور صوتي = Whisper + Claude + TTS بالتتابع (عادة بضع ثوانٍ). مهلة Dio في التطبيق 45 ثانية؛ مهل الخادم لكل مزوّد قابلة للضبط (`STT_TIMEOUT_MS`, `LLM_TIMEOUT_MS`, `TTS_TIMEOUT_MS`).
- **الذاكرة**: التاريخ والصوتيات المؤقتة في ذاكرة العملية؛ إعادة تشغيل الخادم تنهي المحادثات الجارية (يكمل التطبيق بلا تاريخ). للتوسع لاحقاً: Redis + تخزين كائنات.
- **الخصوصية**: لا تُسجَّل نصوص المتعلم ولا تسجيلاته في السجلات، ولا تُحفظ التسجيلات (تذهب إلى Whisper مباشرة).

## 7) هيكل المجلد
```
src/index.ts, app.ts       التشغيل وطبقة HTTP (قفل، حد معدل، multipart)
src/turn.ts                التحقق من الطلب + خط الأنابيب (STT → LLM → TTS)
src/providers/             stt.ts (Whisper) · llm.ts (Claude) · tts.ts (OpenAI/ElevenLabs)
src/personas.ts            التحيات الحرفية، تعليمات النبرة للصوت، إعدادات ElevenLabs
src/sessions.ts, audioStore.ts, prompts.ts, config.ts, http.ts
prompts/                   ai_tutor_system_prompt.txt · free_talk_personas_prompt.txt
test/                      اختبارات بمزودين وهميين
generate_episodes_media.js سكريبت الصوتيات الثابتة
Dockerfile, .env.example
```
