import Foundation
import AVFoundation
import SwiftUI
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
import AppIntents
#endif

let pendingAlarmDeletionKey = "hijri.pendingAlarmDeletion"

let reminderNotificationCategory = "hijri.reminder"
let reminderDeleteAction = "hijri.reminder.delete"

enum ReminderTone: String, Codable, CaseIterable, Identifiable {
    case system, classic, silent

    var id: Self { self }
    var title: String {
        switch self {
        case .system: return "نغمة النظام"
        case .classic: return "نغمة هجري"
        case .silent: return "إشعار صامت"
        }
    }
    var sound: UNNotificationSound? {
        switch self {
        case .system: return .default
        case .classic: return .named(.init(rawValue: "alarm_fallback.wav"))
        case .silent: return nil
        }
    }
}

struct HijriReminder: Identifiable, Codable {
    var id = UUID()
    let title: String
    let date: Date
    let usesSystemAlarm: Bool
    var recurrence: ReminderRepeat? = nil
    var notes: String? = nil
    var tone: ReminderTone? = nil
    var notifies: Bool? = nil
    var datedStart: Bool? = nil
    var repeatMode: ReminderRepeat { recurrence ?? .once }
    var usesDatedNotifications: Bool { datedStart == true || repeatMode.usesDatedNotifications }
}

@MainActor
final class Reminders: ObservableObject {
    @Published private(set) var entries: [HijriReminder] = []
    @Published var error: String?
    private let key = "hijri.reminders"
    private let center = UNUserNotificationCenter.current()
    private var preview: AVAudioPlayer?
    private var rollingTask: Task<Void, Never>?
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .autoupdatingCurrent
        return value
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([HijriReminder].self, from: data) {
            entries = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func usesDatedNotifications(date: Date, recurrence: ReminderRepeat) -> Bool {
        let minute = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        return ReminderDates.requiresDatedNotifications(anchor: minute, recurrence: recurrence,
                                                        now: Date(), calendar: calendar)
    }

    func previewBundledTone() {
        guard let url = Bundle.main.url(forResource: "alarm_fallback", withExtension: "wav") else { return }
        preview = try? AVAudioPlayer(contentsOf: url)
        preview?.play()
    }

    func add(title: String, notes: String, date selectedDate: Date, recurrence: ReminderRepeat,
             tone: ReminderTone?, notify: Bool) async -> Bool {
        let date = calendar.dateInterval(of: .minute, for: selectedDate)?.start ?? selectedDate
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !notify || recurrence != .once || date > Date() else {
            error = "أدخل اسم الموعد واختر وقتًا في المستقبل."
            return false
        }
        if !notify {
            entries.append(HijriReminder(title: name, date: date, usesSystemAlarm: false,
                                         recurrence: recurrence, notes: notes, notifies: false))
            save()
            return true
        }
        guard let tone else {
            error = "اختر نغمة الموعد أو الإشعار الصامت."
            return false
        }
        let dated = usesDatedNotifications(date: date, recurrence: recurrence)
        do {
            #if canImport(AlarmKit)
            if #available(iOS 26.0, *), !dated, tone != .silent {
                let item = HijriReminder(title: name, date: date, usesSystemAlarm: true,
                                         recurrence: recurrence, notes: notes, tone: tone, notifies: true)
                let manager = AlarmManager.shared
                guard try await manager.requestAuthorization() == .authorized else {
                    error = "اسمح لتطبيق هجري بجدولة المنبّهات من الإعدادات."
                    return false
                }
                guard recurrence != .once || date > Date() else {
                    error = "انقضى الوقت المحدد. اختر وقتًا آخر."
                    return false
                }
                let title = LocalizedStringResource(stringLiteral: name)
                let delete = AlarmButton(text: "حذف المنبّه", textColor: .red, systemImageName: "trash")
                let alert: AlarmPresentation.Alert
                if #available(iOS 26.1, *) {
                    alert = .init(title: title, secondaryButton: delete, secondaryButtonBehavior: .custom)
                } else {
                    let stop = AlarmButton(text: "إيقاف", textColor: .white, systemImageName: "stop.circle")
                    alert = .init(title: title, stopButton: stop, secondaryButton: delete, secondaryButtonBehavior: .custom)
                }
                let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                                 metadata: HijriAlarmMetadata(), tintColor: Color.teal)
                let schedule: Alarm.Schedule
                if recurrence == .once {
                    schedule = .fixed(date)
                } else {
                    let cal = calendar
                    let weekday = cal.component(.weekday, from: date)
                    let weekdays: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
                    schedule = .relative(.init(time: .init(hour: cal.component(.hour, from: date),
                                                         minute: cal.component(.minute, from: date)),
                                               repeats: .weekly(recurrence == .daily ? weekdays : [weekdays[weekday - 1]])))
                }
                let configuration = AlarmManager.AlarmConfiguration<HijriAlarmMetadata>.alarm(
                    schedule: schedule, attributes: attributes,
                    stopIntent: nil, secondaryIntent: RequestAlarmDeletionIntent(id: item.id),
                    sound: tone == .classic ? .named("alarm_fallback.wav") : .default)
                _ = try await manager.schedule(id: item.id, configuration: configuration)
                entries.append(item)
                save()
                return true
            }
            #endif
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                error = "اسمح بإشعارات هجري من الإعدادات."
                return false
            }
            let interval = date.timeIntervalSinceNow
            guard recurrence != .once || interval >= 1 else {
                error = "انقضى الوقت المحدد. اختر وقتًا آخر."
                return false
            }
            let item = HijriReminder(title: name, date: date, usesSystemAlarm: false,
                                     recurrence: recurrence, notes: notes, tone: tone, notifies: true, datedStart: dated)
            if dated {
                let count = await center.pendingNotificationRequests().count
                guard count < 62 else {
                    error = "قائمة التنبيهات ممتلئة. احذف تنبيهًا ثم أعد المحاولة."
                    return false
                }
                guard try await scheduleDated(item, limit: min(4, 62 - count)) > 0 else {
                    error = "لا يوجد تاريخ تنبيه تالٍ في نطاق التقويم."
                    return false
                }
            } else {
                let trigger: UNNotificationTrigger
                if recurrence == .once {
                    trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                } else {
                    let fields: Set<Calendar.Component> = recurrence == .daily ? [.hour, .minute] : [.weekday, .hour, .minute]
                    trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents(fields, from: date), repeats: true)
                }
                let request = UNNotificationRequest(identifier: item.id.uuidString, content: content(for: item), trigger: trigger)
                try await center.add(request)
            }
            entries.append(item)
            save()
            return true
        } catch {
            self.error = "تعذّرت جدولة الموعد. تحقّق من الأذونات والوقت المختار."
            return false
        }
    }

    private func content(for item: HijriReminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.notes.flatMap { $0.isEmpty ? nil : $0 } ?? "حان وقت موعدك."
        content.sound = (item.tone ?? .system).sound
        content.categoryIdentifier = reminderNotificationCategory
        content.userInfo["alarmID"] = item.id.uuidString
        return content
    }

    private func datedPrefix(for id: UUID) -> String { "hijri.appointment." + id.uuidString + "." }

    private func removeDatedNotices(for id: UUID) async {
        let prefix = datedPrefix(for: id)
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) })
    }

    private func scheduleDated(_ item: HijriReminder, limit: Int) async throws -> Int {
        let cal = calendar
        let dates = ReminderDates.upcoming(anchor: item.date, repeatMode: item.repeatMode, after: Date(),
                                           limit: limit, calendar: cal, table: UmmAlQura.bundled)
        let alreadyScheduled = Set(await center.pendingNotificationRequests().map(\.identifier))
        var identifiers: [String] = []
        var added: [String] = []
        do {
            for date in dates {
                try Task.checkCancellation()
                let id = datedPrefix(for: item.id) + String(Int(date.timeIntervalSince1970))
                let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                if !alreadyScheduled.contains(id) {
                    try await center.add(UNNotificationRequest(identifier: id, content: content(for: item), trigger: trigger))
                    added.append(id)
                }
                identifiers.append(id)
            }
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: added)
            throw error
        }
        return identifiers.count
    }

    func refreshDatedNotices() {
        let previous = rollingTask
        previous?.cancel()
        rollingTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            for item in self.entries where item.usesDatedNotifications && item.notifies != false {
                let requests = await self.center.pendingNotificationRequests()
                guard !Task.isCancelled else { return }
                guard self.entries.contains(where: { $0.id == item.id }) else { continue }
                let prefix = self.datedPrefix(for: item.id)
                let own = requests.filter { $0.identifier.hasPrefix(prefix) }
                let limit = min(4, max(0, 62 - requests.count + own.count))
                guard limit > own.count else { continue }
                _ = try? await self.scheduleDated(item, limit: limit)
                if !self.entries.contains(where: { $0.id == item.id }) {
                    await self.removeDatedNotices(for: item.id)
                }
            }
        }
    }

    @discardableResult
    func remove(_ item: HijriReminder) -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), item.usesSystemAlarm {
            let manager = AlarmManager.shared
            do {
                if try manager.alarms.contains(where: { $0.id == item.id }) {
                    try manager.cancel(id: item.id)
                }
            } catch {
                self.error = "تعذّر إلغاء المنبّه. حاول مرة أخرى."
                return false
            }
        }
        #endif
        center.removePendingNotificationRequests(withIdentifiers: [item.id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [item.id.uuidString])
        if item.usesDatedNotifications {
            Task { await removeDatedNotices(for: item.id) }
        }
        entries.removeAll { $0.id == item.id }
        save()
        return true
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct HijriAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
struct RequestAlarmDeletionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "حذف المنبّه" }
    static var supportedModes: IntentModes { .foreground(.immediate) }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "معرّف المنبّه")
    var alarmID: String

    init() {}

    init(id: UUID) {
        alarmID = id.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(alarmID, forKey: pendingAlarmDeletionKey)
        return .result()
    }
}
#endif
