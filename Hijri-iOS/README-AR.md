# هجري 5.16 لأجهزة iPhone وiPad

مشروع SwiftUI مبني من قواعد سورس أندرويد `UmmAlQuraCalendar(2).zip` لإصدار 5.16. يستهدف التطبيق والويدجت iOS وiPadOS 16 فأحدث، مع اتجاهات الشاشة الأربعة على iPad.

| سورس أندرويد | المقابل في مشروع iOS |
| --- | --- |
| `CoreCal.java` و`CalendarLogic.kt` | `UmmAlQura.swift` و`CalendarScreen.swift`. جدول أم القرى الأصلي، اختيار مترابط للتاريخين، والمدة بالهجري والميلادي. |
| `SaudiPayments.kt` و`SaudiPayroll.kt` و`SchoolHolidays.kt` و`MonthlyBills.kt` | `Occasions.swift` و`SaudiOccasionRules.swift`. الدفعات والإجازات والفواتير ورواتب الشركات، مع قواعد نهاية الأسبوع. |
| `TraditionalSeasons.kt` و`OccasionPreferences.kt` و`OccasionReminders.kt` | `SaudiOccasionRules.swift` و`OccasionViews.swift`. المنازل الـ28، والعد التنازلي، وإخفاء المناسبات وترتيبها، وتنبيهات يوم المناسبة والدفعات قبلها بيوم. |
| `Appointment.kt` و`AlarmTonePlan.kt` وشاشة الرنين في 5.16 | `ReminderDates.swift` و`Reminders.swift`. أنواع التكرار السبعة، والملاحظات، ونغمة هجري الأصلية، والإشعار الصامت، وطلب حذف الموعد من واجهة التنبيه. |
| `DesignTheme.kt` و`SettingsScreen.kt` | `Preferences.swift`. الثيمات الخمسة بنمط SwiftUI، وحجم أرقام التقويم، والمظهر، وموقع شريط التنقل. |
| وحدات الطقس والموقع | `SaudiWeather.swift`. المدينة أو الموقع عند الطلب، ودرجات الحرارة والظواهر، وتنبيه طقس الغد، وتحديث الخلفية عبر iOS. |

## سلوك نسخة Apple

- المنبّه الفردي واليومي والأسبوعي يستخدم AlarmKit في iOS وiPadOS 26 فأحدث عندما يبدأ في أول موعد مطابق وبنغمة مسموعة. حذف الموعد يفتح تأكيدًا داخل هجري. تستخدم المواعيد الصامتة والأنظمة الأقدم إشعارات محلية. يعمل التكرار الهجري والميلادي الشهري والسنوي بنوافذ مجدولة تتجدد عند فتح التطبيق، وحتى أربعة مواعيد لكل منبّه بحسب سعة التنبيهات.
- يستخدم الطقس WeatherKit. عند اختيار الموقع يطلب هجري إذن الموقع أثناء الاستخدام، ويحفظ آخر إحداثيات محليًا لتحديث طقسها. اختيار مدينة يمسح الإحداثيات المحفوظة. يحدد iOS موعد تشغيل مهمة تحديث الخلفية، ويُجدول تنبيه طقس الغد بتوقيت السعودية عند توفر توقع مسبق.
- بقيت بعض سلوكيات أندرويد خارج هذه النسخة، ومنها غفوة شاشة القفل، وقلب الجهاز لكتم الرنين، واختيار نغمات الجهاز الأخرى، وإشعارات مخاطر الطقس الفورية المستقلة عن تنبيه الغد.
- سجل المتجر يحتاج التحقق من بيانات الخصوصية وسياسة الخصوصية بحسب استخدام الموقع وWeatherKit، ولقطات iPhone وiPad من النسخة المبنية. ملف تعريف الخصوصية يصرّح عن استخدام واجهة UserDefaults.

## البناء والتصدير

1. افتح `Hijri.xcodeproj` في Xcode 27.1، وسجّل دخول فريق Apple Developer في **Xcode → Settings → Accounts**.
2. سجّل معرّفَي التطبيق والويدجت. القيمة الافتراضية `com.taqwim.ummalqura` والويدجت `com.taqwim.ummalqura.widget`. استخدم معرّف التطبيق المسجّل في App Store Connect وفعّل WeatherKit للتطبيق في **App Services** و**App Capabilities**.
3. شغّل `bash Checks/run-calendar-checks.sh` لفحص قواعد التواريخ والمواسم والدفعات والفواتير قبل الأرشفة.
4. نفّذ `./export-ipa.sh TEAM_ID BUNDLE_ID` لتصدير ملف `Hijri.ipa` الموقّع. يطبع الأمر مساره بعد فحص التوقيع والويدجت ومكوّنات الحزمة.
5. ارفع الملف الناتج عبر Transporter إلى سجل التطبيق المطابق في App Store Connect. جرّب TestFlight على iPhone 12 وiPhone 18 Pro وiPad. افحص اتجاهات الشاشة، وإطلاق المنبّه وحذفه من شاشة الرنين، والويدجت، والطقس مع إذن الموقع وبدونه.

رقم البناء الحالي `1`. عند إعادة الرفع لنفس الإصدار، ارفع رقم البناء في التطبيق والويدجت معًا. فُحصت الحزمة وملفات إعدادها محليًا، ويبقى بناء Xcode والتوقيع والتحقق على أجهزة Apple.

- [تفعيل WeatherKit](https://developer.apple.com/help/account/services/weatherkit/)
- [رفع الإصدارات إلى App Store Connect](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [مقاسات لقطات الشاشة](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
