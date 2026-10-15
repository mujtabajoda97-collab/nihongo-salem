# نيهونغو مع سالم - مشروع Flutter (النسخة الكاملة v1)

## التشغيل
```bash
flutter create . --platforms=android,ios   # مرة واحدة: ينشئ android/ و ios/
sh tool/setup_platforms.sh                 # مرة واحدة: صلاحيات الميكروفون والإنترنت
flutter pub get
flutter test
# تجربة كاملة بدون حساب Google Play (اشتراك محاكى):
flutter run --dart-define=MOCK_PURCHASES=true --dart-define=API_BASE_URL=https://your-server.com
# مع RevenueCat الحقيقي:
flutter run --dart-define=API_BASE_URL=https://your-server.com \
  --dart-define=RC_API_KEY_ANDROID=goog_xxx --dart-define=RC_API_KEY_IOS=appl_xxx
```
- الحد الأدنى: Flutter 3.27 / Dart 3.6.
- بدون `API_BASE_URL`: تعمل الحلقات والخريطة والاشتراك، أما ردود المعلم والمكالمة الحية فتعرض رسالة خطأ.

## وضع المحاكاة للاشتراك (Mock Mode)
- يعمل عند `--dart-define=MOCK_PURCHASES=true`، أو تلقائياً في نسخة debug إذا لم تُعطَ مفاتيح RevenueCat.
- الشراء يستغرق ثانية تقريباً ثم يمنح Premium (30 يوماً للشهري، 365 للسنوي) ويُحفظ على الجهاز.
- تظهر لافتة صفراء في شاشة الاشتراك: «وضع المحاكاة - لن يُحصَّل أي مبلغ». وفي الإعدادات خيار «إلغاء الاشتراك التجريبي».
- الأسعار في المحاكاة (4.99$ شهري و39.99$ سنوي) **أرقام مؤقتة**؛ في الإنتاج تأتي من المتجر عبر RevenueCat.
- **لا ترفع نسخة المتجر بالعلم `MOCK_PURCHASES=true`.** نسخة release بلا مفاتيح وبلا العلم لا تبيع شيئاً (خطة مجانية فقط).
- عند ربط Google Play: أنشئ المنتجين في المتجر، ثم entitlement باسم `premium` وOffering فيه Package شهري وآخر سنوي في RevenueCat.

## عقد المكالمة الحية (mode: free_talk)
نفس النقطة `POST {API_BASE_URL}/v1/turn` مع `mode: "free_talk"`:
```
المتغيرات: PERSONA, USER_NAME, USER_PROGRESS, KNOWN_VOCAB, LOCAL_TIME, IS_FIRST_TURN
الدور الأول : is_first_turn=true  (بلا صوت)  -> تحية الشخصية + audio_url
كل دور      : multipart  payload + audio (m4a)
              الرد يجب أن يحوي user_transcript (Whisper) و audio_url (TTS) إن أمكن
النهاية     : user_message = "__END_CALL__"  -> ملخص الجلسة (conversation_completed=true)
```
- المكالمة بلا استخدام اليدين: استماع ← (توقف المتعلم 1.3 ث) ← إرسال ← تشغيل الرد ← استماع...
- الزر الأحمر ينهي المكالمة ويرسل `__END_CALL__`. زر الإيقاف المؤقت يوقف الميكروفون. الضغط على الكرة أثناء حديثك يرسل فوراً، وأثناء حديث الشخصية يتخطى كلامها.
- المجاني: 5 دقائق يومياً (تُخصم كل ثانية وتُحفظ كل 5 ثوان وعند الإنهاء)؛ آخر دقيقة بالأحمر وعند الصفر تنتهي المكالمة تلقائياً. المشترك: بلا حد ويرى المدة المنقضية.
- لا يوجد wake-lock: قد تنطفئ الشاشة في مكالمة طويلة بحسب إعدادات الجهاز.

## الصلاحيات
يضيفها `tool/setup_platforms.sh`: Android `RECORD_AUDIO` + `INTERNET`، وiOS `NSMicrophoneUsageDescription`.
إذن الميكروفون يُطلب وقت الاستخدام عبر حزمة `record` (لا حاجة لـ permission_handler).

## الشاشات والتنقل (lib/app_router.dart)
```
/onboarding        مقدمة + الاسم + (اختبار المستوى | ابدأ من الحلقة 1)
/placement         10 أسئلة بلا تغذية راجعة فورية
/placement/result  النتيجة + المهارات + المراجعة + زر البدء
/                  الرئيسية: التقدم، متابعة، 4 فصول × 10 حلقات (مكتملة/مفتوحة/مقفلة)
/episode/:id       4 محطات: A مشهد، B مفردات وقواعد، C تمارين، D محادثة (محمية بقواعد الوصول)
/call              اختيار الشخصية واللهجة (مجانية: المهذب والعفوي؛ بتاج بنفسجي: الساخرة وأوساكا)
/call/live         المكالمة الصوتية الحية (تعود إلى /call إن كانت الشخصية مقفلة أو انتهت الدقائق)
/paywall           الاشتراك: المميزات + الباقتان + استعادة المشتريات
```
- التوجيه الأولي: أي مستخدم لم يكمل خطوة تحديد المستوى يُحوَّل إلى /onboarding.
- الأقفال: أيقونة التاج البنفسجية = تحتاج اشتراكاً (تفتح /paywall)، القفل الرمادي = أكمل الحلقة السابقة.
- النجوم: نجمة للإكمال + نجمة لكل إجابة صحيحة في التمارين (1 إلى 3). محطة المحادثة لا تؤثر على النجوم ويمكن تخطيها.

## عقد الخادم لمحطة المحادثة (lib/services/tutor_api.dart)
```
POST {API_BASE_URL}/v1/turn
  نص  : application/json  = TutorTurnRequest.toJson()
  صوت : multipart/form-data  payload = (نفس الـ JSON كنص)  +  audio = تسجيل m4a
200 -> JSON مسطّح: المفاتيح السبعة (correction_ar, reply_japanese, reply_romaji, reply_arabic,
       emotion_tone, has_mistake, conversation_completed)
       + اختياري: user_transcript (ما فهمه Whisper)  و audio_url (رد الصوت من TTS)
```
صندوق التصحيح: أخضر عندما `has_mistake=false`، برتقالي مع تحذير عندما `true`.

## ملفات الوسائط المطلوبة (غير موجودة بعد - الواجهة تعرض بدائل أنيقة)
قائمتها الكاملة داخل ملفات JSON: 40 خلفية مشهد، صور الشخصيات، ملفات صوت الجمل والمفردات (mp3)،
بالإضافة إلى `assets/images/characters/sensei_ken.webp` (صورة سينسي كين)، وأربع صور للشخصيات:
`persona_polite_sensei.webp` و`persona_casual_friend.webp` و`persona_tsundere.webp` و`persona_kansai.webp`.

## هيكل المجلدات
```
lib/core/        constants.dart (قواعد المنتج والإعدادات)، date_utils.dart
lib/models/      episode, placement_test, ai_turn (+ الطلبات)، user_models, enums
lib/services/    content_repository, local_storage_service, access_policy, entitlement_service,
                 audio_service, tutor_api, voice_recorder
lib/providers/   providers.dart، tutor_session.dart، live_call.dart
lib/ui/          onboarding, placement, placement_result, home, settings_sheet, theme
lib/ui/call/     persona_selector_screen, live_call_screen
lib/ui/widgets/  common, voice_orb
lib/ui/          + paywall_screen
lib/ui/episode/  episode_screen + station_scene / station_cards / station_quiz / station_voice / completion_dialog
test/            النماذج، قواعد الوصول، الـ providers، جلسة المعلم، المكالمة الحية، الاشتراك التجريبي
```

## بناء APK للتجربة على الهاتف
الطريقة الأبسط: اقرأ `GITHUB_APK_GUIDE.md` (رفع المشروع إلى GitHub ليبني الملف سحابياً).
أو على جهازك: `sh tool/build_apk.sh https://your-server.com [APP_API_KEY]` ← `build/app/outputs/flutter-apk/app-release.apk`.
بناء تجريبي: الاشتراك محاكى والتوقيع تجريبي. للنشر في Google Play يلزم توقيع حقيقي وبدون `MOCK_PURCHASES`.
