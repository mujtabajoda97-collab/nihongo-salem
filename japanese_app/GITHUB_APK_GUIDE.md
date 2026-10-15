# بناء ملف APK تلقائياً عبر GitHub (خطوات بسيطة)

GitHub يملك حاسوباً سحابياً مثبّتاً عليه كل شيء. أنت ترفع المشروع، وهو يبني الـAPK ويعطيك رابط تحميله. لا تحتاج تثبيت Flutter ولا Android Studio.

## قبل البدء
- حساب GitHub مجاني (github.com).
- رابط خادمك بعد نشره، يبدأ بـ `https://` (مثل `https://japanese-api.onrender.com`).
- فكّ ضغط `japanese_app_complete_v1_1.zip`؛ سيظهر مجلد `japanese_app`.

## الخطوة 1: أنشئ مستودعاً خاصاً
1. افتح github.com/new
2. Repository name: `nihongo-salem`
3. اختر **Private** (خاص)، لا تضع علامة على أي خيار آخر، ثم Create repository.

## الخطوة 2: ارفع المشروع
**أ) بالطرفية (الأضمن)** — داخل مجلد `japanese_app`:
```bash
git init
git add .
git commit -m "first version"
git branch -M main
git remote add origin https://github.com/اسمك/nihongo-salem.git
git push -u origin main
```
**ب) من المتصفح:** في صفحة المستودع اختر "uploading an existing file"، ثم اسحب **محتويات** المجلد `japanese_app` (كل ما بداخله) إلى الصفحة، ثم Commit changes.
انتبه: المجلد المخفي `.github` يجب أن يُرفع أيضاً. تحقق بعد الرفع أنك ترى `.github/workflows/build_apk.yml` في المستودع؛ إن لم يظهر فاستخدم الطريقة (أ).

## الخطوة 3: اربطه بخادمك
في المستودع: **Settings ▸ Secrets and variables ▸ Actions**
1. تبويب **Variables** ▸ New repository variable
   - Name: `API_BASE_URL`
   - Value: رابط خادمك بلا شرطة في النهاية، مثل `https://japanese-api.onrender.com`
2. (إن فعّلت `APP_API_KEY` في الخادم) تبويب **Secrets** ▸ New repository secret
   - Name: `APP_API_KEY` ، Value: نفس القيمة الموجودة في الخادم.

## الخطوة 4: شغّل البناء
1. تبويب **Actions** ▸ اختر **Build Android APK** من اليسار ▸ **Run workflow** ▸ Run workflow.
   (إن ظهرت رسالة تطلب تفعيل Actions فوافق.)
2. انتظر حتى تظهر علامة ✅ خضراء (بضع دقائق، وقد تطول في أول مرة).

## الخطوة 5: حمّل الـAPK وثبّته
1. افتح التشغيل المنتهي، انزل إلى **Artifacts**، واضغط `nihongo-salem-apk` (ينزل ملف zip).
2. فك الضغط ليظهر `app-release.apk`، وأرسله لهاتفك (تيليجرام، Drive، كابل).
3. على الأندرويد افتح الملف؛ إن طلب، فعّل «السماح بالتثبيت من هذا المصدر».
4. عند أول مكالمة اسمح للتطبيق باستخدام الميكروفون.

## إن ظهر ❌ أحمر
- افتح الخطوة الحمراء وانسخ آخر 30 سطراً من الخطأ وأرسلها لي لأصلحه. هذا متوقع في أول بناء لأن الكود لم يُترجم من قبل على جهاز حقيقي.
- رسالة `Missing variable API_BASE_URL`: عدت إلى الخطوة 3، أو الرابط لا يبدأ بـ `https://`.

## ملاحظات
- هذا بناء تجريبي: الاشتراك محاكى ولا يُحصَّل أي مبلغ، والتوقيع تجريبي. لا ترفعه إلى Google Play.
- لتحديث التطبيق بعد أي تعديل: ارفع التعديل ثم أعد الخطوة 4، وثبّت الملف الجديد فوق القديم.
- مفتاح `APP_API_KEY` داخل التطبيق يمكن استخراجه من الملف، فهو يمنع العبث العابر فقط.
- الحصة المجانية الشهرية لـGitHub Actions تختلف بحسب خطتك؛ راجع Settings ▸ Billing إن قلقت.
- الصور والأصوات: ما لم تضعها في `assets/` قبل الرفع فسيعرض التطبيق بدائل. ولّد الأصوات بسكريبت الخادم وضعها في `assets/audio/` ثم ارفع التعديل.
