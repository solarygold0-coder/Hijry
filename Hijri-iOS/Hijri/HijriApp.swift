import SwiftUI
import UIKit
import UserNotifications

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let delete = UNNotificationAction(identifier: reminderDeleteAction, title: tr("حذف المنبّه", "Delete alarm"), options: [.foreground, .destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: reminderNotificationCategory, actions: [delete], intentIdentifiers: [])])
        if let shortcut = options?[.shortcutItem] as? UIApplicationShortcutItem {
            UserDefaults.standard.set(shortcut.type, forKey: "hijri.pendingPage")
            return false
        }
        return true
    }
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        UserDefaults.standard.set(shortcutItem.type, forKey: "hijri.pendingPage")
        completionHandler(true)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == reminderDeleteAction, let id = info["alarmID"] as? String {
            UserDefaults.standard.set(id, forKey: pendingAlarmDeletionKey)
        } else if let page = info["page"] as? String {
            UserDefaults.standard.set(page, forKey: "hijri.pendingPage")
        } else if info["alarmID"] != nil {
            UserDefaults.standard.set("reminders", forKey: "hijri.pendingPage")
        }
    }
}

@main
@MainActor
struct HijriApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notifications
    @StateObject private var reminders = Reminders()
    @StateObject private var occasions = OccasionStore()
    @StateObject private var weather = WeatherStore()
    @StateObject private var extras = ExtraReminders()
    init() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hijri.reference556") {
            defaults.set("lavender", forKey: "designTheme")
            defaults.set("theme", forKey: "appearance")
            defaults.set(false, forKey: "navigationTop")
            defaults.set(19.0, forKey: "numberSize")
            defaults.set(true, forKey: "hijri.reference556")
        }
    }
    var body: some Scene {
        WindowGroup {
            RootScreen(reminders: reminders, occasions: occasions)
                .environmentObject(weather).environmentObject(extras)
                .modifier(DesignRootStyle())
        }
        .backgroundTask(.appRefresh(WeatherStore.refreshIdentifier)) {
            await weather.submitBackgroundRefresh()
            await reminders.refreshAndWait()
            await occasions.refreshAndWait()
            await extras.refreshAndWait()
            let weatherAlerts = await weather.alerts
            if weatherAlerts { await weather.refresh() }
        }
    }
}

private enum AppTab: String, CaseIterable {
    case calendar, occasions, reminders, settings
    var title: String {
        switch self {
        case .calendar: return tr("التقويم", "Calendar")
        case .occasions: return tr("المناسبات", "Events")
        case .reminders: return tr("مواعيدي", "Appointments")
        case .settings: return tr("الإعدادات", "Settings")
        }
    }
    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .occasions: return "star"
        case .reminders: return "clock"
        case .settings: return "gearshape"
        }
    }
}

private struct RootScreen: View {
    @ObservedObject var reminders: Reminders
    @ObservedObject var occasions: OccasionStore
    @EnvironmentObject private var weather: WeatherStore
    @EnvironmentObject private var extras: ExtraReminders
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.hijriPalette) private var palette
    @AppStorage("navigationTop") private var navigationTop = false
    @AppStorage("appLanguage") private var language = "ar"
    @AppStorage("english24Hour") private var english24Hour = true
    @AppStorage(pendingAlarmDeletionKey) private var pendingDeletion = ""
    @AppStorage("hijri.pendingPage") private var pendingPage = ""
    @AppStorage("hijri.permissionGuide556") private var permissionGuideSeen = false
    @State private var selected: AppTab = .calendar
    @State private var toDelete: HijriReminder?
    @State private var intro = true
    @State private var permissions = false
    @State private var fasting = false
    @State private var weatherSheet = false
    private let table = UmmAlQura.bundled
    private var locale: Locale { Locale(identifier: language == "en" ? (english24Hour ? "en_GB" : "en_US") : "ar_SA") }

    var body: some View {
        ZStack {
            TabView(selection: $selected) {
                Group {
                    if let table {
                        CalendarScreen(table: table, occasions: occasions, reminders: reminders,
                                       openOccasions: { selected = .occasions }, openReminders: { selected = .reminders })
                    } else { Text(tr("تعذّر تحميل جدول أم القرى.", "Could not load the Umm al-Qura calendar.")) }
                }.tag(AppTab.calendar)
                OccasionsScreen(table: table, store: occasions).tag(AppTab.occasions)
                ReminderScreen(reminders: reminders, toDelete: $toDelete).tag(AppTab.reminders)
                PreferencesScreen().tag(AppTab.settings)
            }.tabViewStyle(.page(indexDisplayMode: .never))
                .safeAreaInset(edge: .top, spacing: 0) { if navigationTop { navigation } }
                .safeAreaInset(edge: .bottom, spacing: 0) { if !navigationTop { navigation } }
            if intro { LaunchIntro().transition(.opacity).zIndex(2) }
        }
        .background { DesignBackground() }
        .environment(\.locale, locale)
        .environment(\.layoutDirection, language == "en" ? .leftToRight : .rightToLeft)
        .task {
            refresh()
            refreshShortcuts()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.2)) { intro = false }
            if !permissionGuideSeen { permissionGuideSeen = true; permissions = true }
            route()
        }
        .onOpenURL { url in
            if url.scheme == "hijry", let page = url.host { pendingPage = page; route() }
        }
        .onChange(of: language) { _ in refreshShortcuts(); refresh() }
        .onChange(of: pendingPage) { _ in route() }
        .onChange(of: pendingDeletion) { _ in route() }
        .onChange(of: occasions.preferences) { preferences in extras.occasions = preferences; extras.refresh() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refresh(); route() }
            if phase == .background { weather.submitBackgroundRefresh() }
        }
        .sheet(isPresented: $permissions) { PermissionsScreen() }
        .sheet(isPresented: $fasting) { if let table { FastingScreen(table: table) } }
        .sheet(isPresented: $weatherSheet) { NavigationStack { SaudiWeather(store: weather) } }
    }

    private var navigation: some View {
        let floating = palette.theme == .lavender || palette.theme == .sky
        return HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button { withAnimation(.easeInOut(duration: 0.2)) { selected = tab } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon).font(.system(size: 21, weight: selected == tab ? .semibold : .regular))
                            .frame(width: 48, height: 28)
                            .background(selected == tab && floating ? palette.selected : .clear, in: Capsule())
                        if palette.theme != .minimal || selected == tab { Text(tab.title).font(.system(size: 11, weight: selected == tab ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.8) }
                        if !floating {
                            Capsule().fill(selected == tab ? palette.accent : .clear).frame(width: 22, height: 3)
                        }
                    }
                    .foregroundStyle(selected == tab ? palette.accent : palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(selected == tab && palette.theme == .royal ? palette.selected : .clear, in: DesignShape(theme: palette.theme))
                }.buttonStyle(.plain).accessibilityAddTraits(selected == tab ? .isSelected : [])
            }
        }
        .padding(5)
        .frame(maxWidth: 760)
        .background(palette.card, in: RoundedRectangle(cornerRadius: floating ? 30 : 0))
        .shadow(color: .black.opacity(floating ? 0.2 : 0), radius: 5, y: 2)
        .padding(.horizontal, floating ? 10 : 0).padding(.vertical, floating ? 4 : 0)
        .frame(maxWidth: .infinity)
    }
    private func refresh() {
        reminders.refreshDatedNotices()
        occasions.refresh()
        extras.occasions = occasions.preferences
        extras.refresh()
        UserDefaults.standard.set(occasions.preferences.notify || !extras.salaryTasks.isEmpty ||
            (extras.fasting.enabled && extras.fasting.notifications) || reminders.entries.contains { $0.notifies != false }, forKey: "hijri.hasScheduledReminders")
        if weather.alerts { weather.startRefresh() }
    }
    private func route() {
        if !pendingDeletion.isEmpty {
            let request = pendingDeletion
            pendingDeletion = ""
            if let id = UUID(uuidString: request), let item = reminders.entries.first(where: { $0.id == id }) { selected = .reminders; toDelete = item }
        }
        guard !pendingPage.isEmpty else { return }
        let page = pendingPage
        pendingPage = ""
        if page == "fasting" { selected = .occasions; fasting = true }
        else if page == "weather" { selected = .occasions; weatherSheet = true }
        else if let tab = AppTab(rawValue: page) { selected = tab }
    }
    private func refreshShortcuts() {
        UIApplication.shared.shortcutItems = [AppTab.calendar, .occasions, .reminders].map {
            UIApplicationShortcutItem(type: $0.rawValue, localizedTitle: $0.title,
                                      localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: $0.icon), userInfo: nil)
        }
    }
}

private struct LaunchIntro: View {
    @Environment(\.hijriPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DesignBackground()
                VStack(spacing: 20) {
                    Image("WelcomeSaudi").resizable().scaledToFit()
                        .accessibilityLabel(tr("خريطة المملكة العربية السعودية بالشهادة والسيف", "Map of Saudi Arabia with the shahada and sword"))
                        .frame(maxWidth: min(420, geometry.size.width - 48), maxHeight: geometry.size.height * 0.55)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(tr("هجري وأكثر", "Hijri & More")).font(.system(size: min(48, geometry.size.width * 0.1), weight: .bold))
                        .foregroundStyle(palette.accent).multilineTextAlignment(.center)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(zoom || reduceMotion ? 1 : 0.64)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: reduceMotion ? 0 : 2)) { zoom = true } }
    }
}

private struct ReminderScreen: View {
    @ObservedObject var reminders: Reminders
    @Binding var toDelete: HijriReminder?
    @State private var title = ""
    @State private var notes = ""
    @State private var notify = true
    @AppStorage("hijri.reminderTone") private var toneID = ""
    @State private var date = Date().addingTimeInterval(3600)
    @State private var busy = false
    @State private var recurrence: ReminderRepeat = .once
    @State private var weekdays = Set(1...7)
    var body: some View {
        DesignPage(title: tr("مواعيدي", "Appointments")) {
            DesignCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(tr("إضافة موعد", "Add appointment")).font(.headline)
                    TextField(tr("اسم الموعد", "Appointment title"), text: $title).textFieldStyle(.roundedBorder)
                    TextField(tr("ملاحظات", "Notes"), text: $notes, axis: .vertical).textFieldStyle(.roundedBorder)
                    DatePicker(tr("الوقت", "Time"), selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.calendar, Calendar(identifier: .gregorian))
                    Picker(tr("التكرار", "Repeat"), selection: $recurrence) { ForEach(ReminderRepeat.allCases) { Text($0.title).tag($0) } }
                    if recurrence == .daily {
                        Text(tr("يوميًا ما عدا الأيام غير المحددة", "Repeat on selected weekdays")).font(.caption)
                        HStack(spacing: 3) {
                            ForEach(1...7, id: \.self) { day in
                                Button {
                                    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(Calendar.current.shortWeekdaySymbols[day - 1]).font(.system(size: 10))
                                        Image(systemName: weekdays.contains(day) ? "checkmark.circle.fill" : "xmark.circle")
                                    }.frame(maxWidth: .infinity, minHeight: 44)
                                }.buttonStyle(.plain).accessibilityValue(weekdays.contains(day) ? tr("مفعّل", "Enabled") : tr("متوقف", "Disabled"))
                            }
                        }
                    }
                    Toggle(tr("التنبيه عند الموعد", "Notify at appointment time"), isOn: $notify)
                    if notify {
                        Picker(tr("نغمة الموعد", "Alarm sound"), selection: $toneID) {
                            Text(tr("اختر نغمة", "Choose a sound")).tag("")
                            ForEach(ReminderTone.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        if toneID == ReminderTone.classic.rawValue { Button(tr("استمع إلى نغمة هجري", "Preview Hijry sound")) { reminders.previewBundledTone() } }
                    }
                    Button(busy ? tr("جارٍ الحفظ…", "Saving…") : tr("حفظ الموعد", "Save appointment")) {
                        busy = true
                        Task {
                            if await reminders.add(title: title, notes: notes, date: date, recurrence: recurrence,
                                                   tone: ReminderTone(rawValue: toneID), notify: notify,
                                                   weekdays: recurrence == .daily ? weekdays : nil) { title = ""; notes = "" }
                            busy = false
                        }
                    }.buttonStyle(RaisedButtonStyle()).frame(maxWidth: .infinity)
                        .disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (recurrence == .daily && weekdays.isEmpty))
                }
            }
            if reminders.entries.isEmpty {
                DesignCard { Text(tr("لا توجد مواعيد.", "No appointments yet.")).font(.subheadline) }
            }
            ForEach(reminders.entries.sorted { $0.date < $1.date }) { item in
                DesignCard {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).font(.headline)
                            if let notes = item.notes, !notes.isEmpty { Text(notes).font(.subheadline) }
                            Text(item.date, style: .date).font(.caption)
                            Text(item.date, style: .time).font(.subheadline.bold())
                            Text(item.repeatMode.title).font(.caption)
                            if item.notifies == false { Text(tr("دون تنبيه", "No alert")).font(.caption) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button(role: .destructive) { toDelete = item } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                            .accessibilityLabel(tr("حذف الموعد", "Delete appointment"))
                    }
                }
            }
        }
        .confirmationDialog(tr("حذف الموعد؟", "Delete appointment?"), isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible, presenting: toDelete) { item in
            Button(tr("حذف", "Delete"), role: .destructive) { if reminders.remove(item) { toDelete = nil } }
            Button(tr("إلغاء", "Cancel"), role: .cancel) { toDelete = nil }
        }
        .alert(tr("المواعيد", "Appointments"), isPresented: Binding(get: { reminders.error != nil }, set: { if !$0 { reminders.error = nil } })) {
            Button(tr("حسنًا", "OK")) { reminders.error = nil }
        } message: { Text(reminders.error ?? "") }
    }
}
