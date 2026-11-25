import SwiftUI
import UIKit
import UserNotifications

struct PreferencesScreen: View {
    @AppStorage("appearance") private var appearance = HijriAppearance.theme
    @AppStorage("designTheme") private var theme = HijriTheme.lavender
    @AppStorage("numberSize") private var numberSize = 19.0
    @AppStorage("navigationTop") private var navigationTop = false
    @AppStorage("appLanguage") private var language = "ar"
    @AppStorage("english24Hour") private var english24Hour = true
    @EnvironmentObject private var weather: WeatherStore
    @EnvironmentObject private var extras: ExtraReminders
    @State private var permissions = false
    @State private var fasting = false
    @State private var weatherSettings = false
    @Environment(\.hijriPalette) private var palette
    var body: some View {
        DesignPage(title: tr("الإعدادات", "Settings")) {
            DesignCard {
                Picker(tr("لغة التطبيق", "Language"), selection: $language) {
                    Text("العربية").tag("ar")
                    Text("English").tag("en")
                }.pickerStyle(.segmented)
            }
            Button { permissions = true } label: { Label(tr("مراجعة أذونات التطبيق", "Review app permissions"), systemImage: "checkmark.shield") }
                .buttonStyle(.bordered).frame(maxWidth: .infinity)
            DesignCard {
                VStack(alignment: .leading, spacing: 12) {
                    Button { weatherSettings = true } label: { Label(tr("إعدادات الطقس", "Weather settings"), systemImage: "cloud.sun") }
                    Button { fasting = true } label: { Label(tr("الصيام المستحب", "Voluntary fasting"), systemImage: "moon") }
                    Toggle(tr("التنقل أعلى الشاشة", "Navigation at the top"), isOn: $navigationTop)
                    if language == "en" { Toggle("24-hour time", isOn: $english24Hour) }
                }
            }
            Text(tr("تصميم التطبيق", "App design")).font(.headline)
            ForEach(HijriTheme.allCases) { option in
                Button { theme = option } label: {
                    HStack(spacing: 12) {
                        ThemeThumbnail(theme: option).frame(width: 82, height: 96)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(option.title).font(.headline)
                            Text(option.subtitle).font(.caption).multilineTextAlignment(.leading)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: theme.current == option ? "checkmark.circle.fill" : "circle").foregroundStyle(palette.accent)
                    }.padding(10)
                    .background(palette.card, in: DesignShape(theme: palette.theme))
                    .overlay(DesignShape(theme: palette.theme).strokeBorder(theme.current == option ? palette.accent : palette.outline, lineWidth: theme.current == option ? 2 : 1))
                }.buttonStyle(.plain).accessibilityValue(theme.current == option ? tr("محدد", "Selected") : "")
            }
            DesignCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("مظهر التطبيق", "Appearance")).font(.headline)
                    Picker(tr("المظهر", "Appearance"), selection: $appearance) {
                        ForEach(HijriAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    Text(tr("حجم الأرقام", "Number size")).font(.headline)
                    Slider(value: $numberSize, in: 18...26, step: 1)
                    HStack {
                        Text("\(Int(numberSize))").font(.system(size: numberSize, weight: .bold))
                        Spacer()
                        Button(tr("الحجم الافتراضي", "Default size")) { numberSize = 19 }
                    }
                }
            }
            DesignCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("الويدجت", "Widget")).font(.headline)
                    Text(tr("اضغط مطولًا على الشاشة الرئيسية، اختر إضافة أداة ثم «هجري». لشاشة القفل افتح تخصيص الشاشة واختر ويدجت هجري.", "Touch and hold the Home Screen, add a widget, and choose Hijry. For the Lock Screen, open customization and choose the Hijry widget."))
                        .font(.subheadline)
                }
            }
        }
        .sheet(isPresented: $permissions) { PermissionsScreen() }
        .sheet(isPresented: $fasting) { if let table = UmmAlQura.bundled { FastingScreen(table: table) } }
        .sheet(isPresented: $weatherSettings) { NavigationStack { SaudiWeather(store: weather) } }
    }
}

private struct ThemeThumbnail: View {
    let theme: HijriTheme
    var body: some View {
        let palette = ThemePalette(theme: theme, dark: theme.prefersDark)
        VStack(spacing: 5) {
            if theme == .emerald { previewCards(palette) }
            if theme == .sky { HStack(spacing: 3) { ForEach(0..<7) { _ in Circle().fill(palette.accent).frame(width: 5, height: 5) } } }
            if theme == .lavender {
                VStack(spacing: 4) { drum(palette); Capsule().fill(palette.accent).frame(width: 20, height: 4); drum(palette) }
                    .padding(5).background(palette.card, in: RoundedRectangle(cornerRadius: 8))
            } else {
                drum(palette)
                Capsule().fill(palette.accent).frame(width: 20, height: 4)
                drum(palette)
            }
            if theme != .emerald { previewCards(palette) }
        }.padding(7).background(palette.background, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
    private func drum(_ palette: ThemePalette) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 2).fill(theme == .lavender ? Color.gray : palette.selected).frame(height: theme == .minimal ? 7 : 14) }
        }
    }
    private func previewCards(_ palette: ThemePalette) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<2) { _ in DesignShape(theme: theme).fill(palette.card).frame(height: 16).overlay(DesignShape(theme: theme).stroke(palette.accent.opacity(0.6), lineWidth: 0.6)) }
        }
    }
}

struct PermissionsScreen: View {
    @EnvironmentObject private var weather: WeatherStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    var body: some View {
        NavigationStack {
            DesignPage(title: "") {
                DesignCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(tr("الإشعارات", "Notifications"), systemImage: "bell.badge").font(.headline)
                        Text(notificationStatus == .authorized || notificationStatus == .provisional ? tr("مسموح", "Allowed") : tr("تسمح بوصول تنبيهات المواعيد والمناسبات والصيام.", "Allow reminders for appointments, events, and fasting.")).font(.subheadline)
                        Button(tr("السماح بالإشعارات", "Allow notifications")) {
                            Task {
                                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                                notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                            }
                        }.buttonStyle(.bordered)
                    }
                }
                DesignCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(tr("الموقع أثناء الاستخدام", "Location while using the app"), systemImage: "location").font(.headline)
                        Text(tr("لعرض طقس منطقتك. يمكنك أيضًا اختيار مدينة يدويًا.", "Show local weather, or choose a city manually.")).font(.subheadline)
                        Button(tr("استخدم موقعي", "Use my location")) { weather.useLocation() }.buttonStyle(.bordered)
                        if let message = weather.message { Text(message).font(.footnote) }
                    }
                }
                DesignCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(tr("المنبّهات", "Alarms"), systemImage: "alarm").font(.headline)
                        Text(tr("على iOS وiPadOS 26 أو أحدث، يطلب إذن المنبّه عند حفظ أول موعد بصوت. على الأنظمة الأقدم تُستخدم الإشعارات المحلية.", "On iOS and iPadOS 26 or later, alarm permission is requested when saving your first audible alarm. Earlier systems use local notifications.")).font(.subheadline)
                        Button(tr("إعدادات هجري في الجهاز", "Hijry system settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }
            }
            .navigationTitle(tr("أذونات التطبيق", "App permissions")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("متابعة", "Continue")) { dismiss() } } }
            .task { notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        }.modifier(DesignRootStyle())
    }
}
