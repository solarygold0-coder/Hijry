# بناء هجري 5.16 وتصدير ملف App Store

## البناء عبر GitLab وCodemagic

1. في GitLab أنشئ مشروعًا خاصًا واختر تهيئته بملف README. من هاتفك، ارفع إلى جذر المستودع ملف `Hijri-5.16-iPhone-iPad-Xcode.zip` كما هو، ثم استخرج من نسخة محلية منه ملف `codemagic.yaml` فقط وارفعه إلى الجذر بجانب ZIP.
2. في Codemagic اختر **Add application → GitLab**. اربط حساب GitLab واختر المستودع ونوع المشروع **iOS**، ثم اختر الفرع الذي رفعت الملفين إليه. يفك مسار البناء سورس iOS على خادم macOS.

3. شغّل **Hijri iOS and iPadOS — simulator build**. يفحص قواعد التقويم والدفعات والمواسم، ويبني التطبيق والويدجت، ثم يفتح التطبيق في محاكي iPhone 18 Pro Max ومحاكي iPad Pro.
4. أضف شهادة **Apple Distribution** وملفَي تعريف **App Store** للتطبيق والويدجت في إعدادات التوقيع في Codemagic. فعّل **WeatherKit** لمعرّف التطبيق الرئيسي قبل إصدار ملف تعريفه. المعرّف الافتراضي `com.taqwim.ummalqura` والويدجت `com.taqwim.ummalqura.widget`. إذا كان لديك معرّف مسجّل مختلف، غيّر `bundle_identifier` و`HIJRI_BUNDLE_ID` في مسار التوقيع ليتطابقا معه.
5. شغّل **Hijri iOS and iPadOS — export App Store IPA**. بعد نجاح البناء وفحص التوقيع، نزّل ملف `.ipa` من **Artifacts**.
6. ارفع ملف IPA إلى App Store Connect باستخدام Transporter على Mac أو مسار رفع سحابي مرتبط بحساب App Store Connect. مسارات البناء المرفقة تتوقف بعد تصدير الملف.

## البناء من GitHub Actions

1. من متصفح هاتفك، افتح المستودع الخاص بحسابك واختر **Add file → Upload files**. ارفع ملف `Hijri-5.16-iPhone-iPad-Xcode.zip` كما هو إلى جذر الفرع الافتراضي.
2. افتح الملف المضغوط على هاتفك واستخرج `GitHub-Actions.txt` فقط. في المستودع، اختر **Add file → Create new file** واكتب الاسم `.github/workflows/hijri-ios.yml` ثم الصق النص واحفظه في الفرع الافتراضي. افتح بعدها **Actions → Hijri iOS → Run workflow**. التشغيل الافتراضي يفك سورس iOS داخل خادم البناء، ويفحص قواعد التقويم، ويبني ويشغّل محاكيَي iPhone وiPad.
3. للتصدير بعد الاختبار، أضف متغيري `APPLE_TEAM_ID` و`HIJRI_BUNDLE_ID` في **Settings → Secrets and variables → Actions**. أضف `ASC_KEY_ID` و`ASC_ISSUER_ID` و`ASC_PRIVATE_KEY` في **Secrets**. استخدم مفتاح فريق App Store Connect المسموح له بإدارة التوقيع، وضع محتوى ملف `.p8` في السر `ASC_PRIVATE_KEY`. سجّل معرّفَي التطبيق والويدجت وفعّل WeatherKit للتطبيق.
4. شغّل المسار مرة أخرى مع اختيار `export_ipa`. بعد نجاح التصدير، نزّل `Hijri.ipa` من **Artifacts** في صفحة التشغيل.

إذا كان لديك Mac، اتبع خطوات Xcode في `Hijri-iOS/README-AR.md`. الحزمة الحالية تحتوي على المصدر وإعدادات التصدير، ولم تُبنَ أو تُوقّع بعد.

- [إعداد توقيع iOS في Codemagic](https://docs.codemagic.io/yaml-code-signing/signing-ios/)
- [رفع الإصدارات إلى App Store Connect](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
