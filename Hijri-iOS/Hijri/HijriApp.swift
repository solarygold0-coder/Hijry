import SwiftUI
import UIKit
import UserNotifications

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let delete = UNNotificationAction(identifier: reminderDeleteAction, title: "حذف المنبّه",
                                          options: [.foreground, .destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: reminderNotificationCategory,
                                                                 actions: [delete], intentIdentifiers: [])])
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == reminderDeleteAction,
              let id = response.notification.request.content.userInfo["alarmID"] as? String else { return }
        UserDefaults.standard.set(id, forKey: pendingAlarmDeletionKey)
    }
}

@main
@MainActor
struct HijriApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notifications
    @StateObject private var reminders = Reminders()
    @StateObject private var occasions = OccasionStore()
    @StateObject private var weather = WeatherStore()
    @AppStorage("appearance") private var appearance = HijriAppearance.system
    @AppStorage("designTheme") private var theme = HijriTheme.royal
    @AppStorage("navigationTop") private var navigationTop = true
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(pendingAlarmDeletionKey) private var pendingDeletion = ""
    @State private var selectedTab: Tab = .calendar
    @State private var reminderToDelete: HijriReminder?
    private let table = UmmAlQura.bundled

    private enum Tab: CaseIterable {
        case calendar, occasions, weather, reminders, settings

        var title: String {
            switch self {
            case .calendar: return "التقويم"
            case .occasions: return "المناسبات"
            case .weather: return "الطقس"
            case .reminders: return "المواعيد"
            case .settings: return "الإعدادات"
            }
        }

        var icon: String {
            switch self {
            case .calendar: return "calendar"
            case .occasions: return "calendar.badge.clock"
            case .weather: return "cloud.sun"
            case .reminders: return "alarm"
            case .settings: return "gearshape"
            }
        }
    }

    @ViewBuilder private func screen(for tab: Tab) -> some View {
        switch tab {
        case .calendar:
            if let table { CalendarScreen(table: table) }
            else { Text("تعذّر تحميل جدول أم القرى.") }
        case .occasions:
            OccasionsScreen(table: table, store: occasions)
        case .weather:
            SaudiWeather(store: weather)
        case .reminders:
            ReminderScreen(reminders: reminders, toDelete: $reminderToDelete)
        case .settings:
            PreferencesScreen()
        }
    }

    private func presentAlarmDeletion(_ request: String) {
        guard !request.isEmpty else { return }
        pendingDeletion = ""
        guard let id = UUID(uuidString: request),
              let item = reminders.entries.first(where: { $0.id == id }) else { return }
        selectedTab = .reminders
        reminderToDelete = item
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    screen(for: tab)
                        .toolbar(navigationTop ? .hidden : .visible, for: .tabBar)
                        .tabItem { Label(tab.title, systemImage: tab.icon) }
                        .tag(tab)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if navigationTop {
                    Picker("الصفحة", selection: $selectedTab) {
                        ForEach(Tab.allCases, id: \.self) { tab in
                            Image(systemName: tab.icon).accessibilityLabel(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.regularMaterial)
                }
            }
            .onAppear {
                presentAlarmDeletion(pendingDeletion)
                reminders.refreshDatedNotices()
                occasions.refresh()
                if weather.alerts { weather.startRefresh() }
            }
            .onChange(of: pendingDeletion, perform: presentAlarmDeletion)
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    reminders.refreshDatedNotices()
                    occasions.refresh()
                    if weather.alerts { weather.startRefresh() }
                } else if phase == .background {
                    weather.submitBackgroundRefresh()
                }
            }
            .tint(theme.accent)
            .preferredColorScheme(appearance.colorScheme)
            .environment(\.locale, Locale(identifier: "ar_SA"))
            .environment(\.layoutDirection, .rightToLeft)
        }
        .backgroundTask(.appRefresh(WeatherStore.refreshIdentifier)) {
            await weather.submitBackgroundRefresh()
            await weather.refresh()
        }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("إضافة موعد") {
                    TextField("اسم الموعد", text: $title)
                    TextField("ملاحظات", text: $notes, axis: .vertical)
                    DatePicker("الوقت", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.calendar, Calendar(identifier: .gregorian))
                    Picker("التكرار", selection: $recurrence) {
                        ForEach(ReminderRepeat.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("التنبيه عند الموعد", isOn: $notify)
                    if notify {
                        Picker("نغمة الموعد", selection: $toneID) {
                            Text("اختر نغمة").tag("")
                            ForEach(ReminderTone.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        if toneID == ReminderTone.classic.rawValue {
                            Button("استمع إلى نغمة هجري") { reminders.previewBundledTone() }
                        }
                        if reminders.usesDatedNotifications(date: date, recurrence: recurrence) {
                            Text("تُجدول المواعيد التالية كإشعارات محلية وتتجدد عند فتح هجري.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if recurrence != .once {
                            Text("يبدأ التكرار عند أقرب وقت مطابق.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Button(busy ? "جارٍ الحفظ…" : "حفظ الموعد") {
                        busy = true
                        Task {
                            if await reminders.add(title: title, notes: notes, date: date, recurrence: recurrence,
                                                   tone: ReminderTone(rawValue: toneID), notify: notify) {
                                title = ""
                                notes = ""
                            }
                            busy = false
                        }
                    }
                    .disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if notify, toneID == ReminderTone.silent.rawValue {
                        Text("يصل الموعد كإشعار صامت. يتحكم الجهاز في الاهتزاز.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if #unavailable(iOS 26.0) {
                        Text("يصل الموعد كإشعار محلي على هذا الإصدار من iOS.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("المواعيد المحفوظة") {
                    if reminders.entries.isEmpty {
                        Text("لا توجد مواعيد.").foregroundStyle(.secondary)
                    }
                    ForEach(reminders.entries.sorted { $0.date < $1.date }) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline)
                            if let notes = item.notes, !notes.isEmpty {
                                Text(notes).foregroundStyle(.secondary)
                            }
                            Text(item.repeatMode == .once ? item.date.formatted(date: .abbreviated, time: .shortened) : item.date.formatted(date: .omitted, time: .shortened) + " · " + item.repeatMode.title).foregroundStyle(.secondary)
                            if item.notifies == false { Text("دون تنبيه").font(.caption) }
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            Button("حذف", role: .destructive) { toDelete = item }
                        }
                    }
                }
            }
            .navigationTitle("المواعيد")
            .confirmationDialog("حذف الموعد؟", isPresented: Binding(
                get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                titleVisibility: .visible, presenting: toDelete) { item in
                    Button("حذف «\(item.title)»", role: .destructive) { reminders.remove(item); toDelete = nil }
                    Button("إلغاء", role: .cancel) { toDelete = nil }
                }
            .alert("المواعيد", isPresented: Binding(
                get: { reminders.error != nil }, set: { if !$0 { reminders.error = nil } })) {
                    Button("حسنًا") { reminders.error = nil }
                } message: { Text(reminders.error ?? "") }
        }
    }
}
