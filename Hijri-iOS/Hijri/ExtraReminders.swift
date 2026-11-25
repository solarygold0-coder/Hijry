import Foundation
import UserNotifications
import SwiftUI

struct SalaryTask: Identifiable, Codable {
    var id = UUID()
    var payroll: String
    var text: String
    var offsets: Set<Int> = [0]
    var minute = 540
    var tone: ReminderTone = .system
}

@MainActor
final class ExtraReminders: ObservableObject {
    @Published private(set) var salaryTasks: [SalaryTask] = []
    @Published var fasting = FastingSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(fasting) { UserDefaults.standard.set(data, forKey: "hijri.fasting") }
            refresh()
        }
    }
    @Published var message: String?
    private var scheduling: Task<Void, Never>?
    private let center = UNUserNotificationCenter.current()
    private let prefix = "hijri.extra."
    var occasions = OccasionPreferences()

    init() {
        if let data = UserDefaults.standard.data(forKey: "hijri.salaryTasks"),
           let items = try? JSONDecoder().decode([SalaryTask].self, from: data) { salaryTasks = items }
        if let data = UserDefaults.standard.data(forKey: "hijri.fasting"),
           let saved = try? JSONDecoder().decode(FastingSettings.self, from: data) { fasting = saved }
    }
    func save(_ task: SalaryTask) -> Bool {
        guard !task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, task.text.count <= 500,
              !task.offsets.isEmpty, task.offsets.allSatisfy({ (-1...1).contains($0) }), (0..<1440).contains(task.minute) else {
            message = tr("أدخل المهمة وحدد يوم التنبيه ووقته.", "Enter a task and select its reminder days and time.")
            return false
        }
        var updated = salaryTasks.filter { $0.id != task.id }
        updated.append(task)
        guard let data = try? JSONEncoder().encode(updated) else { return false }
        UserDefaults.standard.set(data, forKey: "hijri.salaryTasks")
        salaryTasks = updated
        refresh()
        return true
    }
    func delete(_ task: SalaryTask) {
        salaryTasks.removeAll { $0.id == task.id }
        if let data = try? JSONEncoder().encode(salaryTasks) { UserDefaults.standard.set(data, forKey: "hijri.salaryTasks") }
        refresh()
    }
    func authorize() async -> Bool {
        do {
            let enabled = try await center.requestAuthorization(options: [.alert, .sound])
            if !enabled { message = tr("اسمح بإشعارات هجري من إعدادات الجهاز.", "Allow Hijry notifications in Settings.") }
            return enabled
        } catch {
            message = tr("تعذّر طلب إذن الإشعارات.", "Could not request notification permission.")
            return false
        }
    }
    func refresh() {
        let previous = scheduling
        previous?.cancel()
        scheduling = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.schedule()
        }
    }
    func refreshAndWait() async {
        refresh()
        await scheduling?.value
    }

    private func schedule() async {
        let now = Date()
        let calendar = DateLabels.calendar
        let events = HijriOccasions.entries(from: now, table: UmmAlQura.bundled, preferences: occasions, upcomingOnly: false)
        var planned: [(Date, UNNotificationRequest)] = []
        for task in salaryTasks {
            for event in events where event.key == task.payroll {
                let civil = SaudiCalendar.calendar.dateComponents([.year, .month, .day], from: event.date)
                guard let localPayday = calendar.date(from: civil) else { continue }
                for offset in task.offsets.sorted() {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: localPayday),
                          let fire = calendar.date(bySettingHour: task.minute / 60, minute: task.minute % 60, second: 0, of: day), fire > now else { continue }
                    let id = prefix + "salary.\(task.id).\(Int(event.date.timeIntervalSince1970)).\(offset)"
                    planned.append((fire, request(id: id, title: event.title, body: task.text, date: fire, tone: task.tone, page: "occasions")))
                }
            }
        }
        if fasting.notifications, let table = UmmAlQura.bundled {
            for day in FastingPlan.upcoming(from: now, settings: fasting, table: table, limit: 12) {
                guard let target = calendar.date(byAdding: .day, value: fasting.dayBefore ? -1 : 0, to: day.date),
                      let fire = calendar.date(bySettingHour: fasting.minute / 60, minute: fasting.minute % 60, second: 0, of: target), fire > now else { continue }
                let title = fasting.dayBefore ? tr("تذكير بصيام الغد", "Tomorrow’s fasting reminder") : tr("تذكير بصيام اليوم", "Today’s fasting reminder")
                let body = day.types.map(\.title).joined(separator: " • ") + "\n" + DateLabels.date(day.date, hijri: true, table: table)
                planned.append((fire, request(id: prefix + "fasting.\(Int(day.date.timeIntervalSince1970))", title: title,
                                               body: body, date: fire, tone: ReminderTone(rawValue: fasting.tone) ?? .system, page: "fasting")))
            }
        }
        let pending = await center.pendingNotificationRequests()
        guard !Task.isCancelled else { return }
        let managed = pending.filter { $0.identifier.hasPrefix(prefix) }
        let capacity = max(0, min(18, 62 - (pending.count - managed.count)))
        let desired = Array(planned.sorted { $0.0 < $1.0 }.prefix(capacity).map(\.1))
        let ids = Set(desired.map(\.identifier))
        center.removePendingNotificationRequests(withIdentifiers: managed.map(\.identifier).filter { !ids.contains($0) })
        message = nil
        for item in desired {
            guard !Task.isCancelled else { return }
            do { try await LocalNotices.shared.add(item) }
            catch { message = tr("تعذّرت جدولة بعض التنبيهات. راجع أذونات الإشعارات وعدد المواعيد.", "Some reminders could not be scheduled. Check notification permission and pending appointments."); break }
        }
    }
    private func request(id: String, title: String, body: String, date: Date, tone: ReminderTone, page: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = tone.sound
        content.userInfo = ["page": page]
        var components = DateLabels.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.calendar = DateLabels.calendar
        components.timeZone = DateLabels.calendar.timeZone
        return UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }
}

actor LocalNotices {
    static let shared = LocalNotices()
    private var tail: Task<Void, Error>?
    func add(_ request: UNNotificationRequest) async throws {
        let previous = tail
        let operation = Task {
            _ = try? await previous?.value
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard pending.count < 64 || pending.contains(where: { $0.identifier == request.identifier }) else {
                throw NSError(domain: "Hijry.Notifications", code: 64, userInfo: [NSLocalizedDescriptionKey: "Notification capacity reached"])
            }
            try await center.add(request)
        }
        tail = operation
        try await operation.value
    }
}

struct FastingScreen: View {
    @EnvironmentObject private var store: ExtraReminders
    @Environment(\.dismiss) private var dismiss
    let table: UmmAlQura
    var body: some View {
        NavigationStack {
            DesignPage(title: "") {
                DesignCard {
                    VStack(spacing: 12) {
                        Toggle(tr("تفعيل الصيام المستحب", "Enable voluntary fasting"), isOn: $store.fasting.enabled)
                        Toggle(tr("أنا حاج هذا العام", "I am performing Hajj"), isOn: $store.fasting.pilgrim)
                    }
                }
                DesignCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(FastingType.allCases) { type in
                            Toggle(type.title, isOn: Binding(get: { store.fasting.types.contains(type) }, set: { enabled in
                                if enabled { store.fasting.types.insert(type) } else { store.fasting.types.remove(type) }
                            }))
                        }
                        if store.fasting.types.contains(.shawwal), let year = table.convert(Date())?.year {
                            Text(tr("أيام شوال • اختر حتى ستة أيام", "Shawwal • select up to six days")).font(.headline)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                                ForEach(2...table.monthLength(year: year, month: 10), id: \.self) { day in
                                    Button(String(day)) {
                                        store.fasting.shawwalYear = year
                                        if store.fasting.shawwalDays.contains(day) { store.fasting.shawwalDays.remove(day) }
                                        else if store.fasting.shawwalDays.count < 6 { store.fasting.shawwalDays.insert(day) }
                                    }.buttonStyle(.bordered)
                                        .background(store.fasting.shawwalYear == year && store.fasting.shawwalDays.contains(day) ? Color.accentColor.opacity(0.2) : .clear)
                                }
                            }
                        }
                    }
                }
                DesignCard {
                    VStack(spacing: 12) {
                        Toggle(tr("إشعارات الصيام", "Fasting notifications"), isOn: Binding(get: { store.fasting.notifications }, set: { enable in
                            Task {
                                if enable { guard await store.authorize() else { return } }
                                store.fasting.notifications = enable
                            }
                        }))
                        Toggle(tr("التذكير قبلها بيوم", "Remind one day before"), isOn: $store.fasting.dayBefore)
                        DatePicker(tr("وقت التذكير", "Reminder time"), selection: minuteBinding($store.fasting.minute), displayedComponents: .hourAndMinute)
                        Picker(tr("النغمة", "Sound"), selection: $store.fasting.tone) {
                            ForEach(ReminderTone.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                    }
                }
                if let message = store.message { Text(message).font(.footnote) }
                ForEach(FastingPlan.upcoming(from: Date(), settings: store.fasting, table: table, limit: 3), id: \.date) { day in
                    DesignCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(day.types.map(\.title).joined(separator: " • ")).font(.subheadline.bold())
                            Text(DateLabels.date(day.date, hijri: true, table: table)).font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle(tr("الصيام المستحب", "Voluntary fasting"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("تم", "Done")) { dismiss() } } }
        }.modifier(DesignRootStyle())
    }
}

func minuteBinding(_ minute: Binding<Int>) -> Binding<Date> {
    Binding(get: {
        DateLabels.calendar.date(bySettingHour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60, second: 0, of: Date()) ?? Date()
    }, set: { date in
        let values = DateLabels.calendar.dateComponents([.hour, .minute], from: date)
        minute.wrappedValue = (values.hour ?? 0) * 60 + (values.minute ?? 0)
    })
}

struct PayrollTasksScreen: View {
    let event: HijriOccasion
    @EnvironmentObject private var store: ExtraReminders
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var editingID: UUID?
    @State private var offsets: Set<Int> = [0]
    @State private var minute = 540
    @State private var tone = ReminderTone.system
    @State private var saving = false
    var body: some View {
        NavigationStack {
            DesignPage(title: "") {
                DesignCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(event.title).font(.headline)
                        TextField(tr("اكتب المهمة", "Task"), text: $text, axis: .vertical).textFieldStyle(.roundedBorder)
                        ForEach([-1, 0, 1], id: \.self) { day in
                            Toggle(day == -1 ? tr("قبل الراتب بيوم", "One day before payday") : day == 0 ? tr("يوم الراتب", "Payday") : tr("بعد الراتب بيوم", "One day after payday"),
                                   isOn: Binding(get: { offsets.contains(day) }, set: { if $0 { offsets.insert(day) } else { offsets.remove(day) } }))
                        }
                        DatePicker(tr("وقت المهمة", "Task time"), selection: minuteBinding($minute), displayedComponents: .hourAndMinute)
                        Picker(tr("النغمة", "Sound"), selection: $tone) { ForEach(ReminderTone.allCases) { Text($0.title).tag($0) } }
                        Text(tr("تتكرر المهمة مع هذه المناسبة كل شهر.", "Repeats with this payday every month.")).font(.caption)
                        Button(tr("حفظ المهمة", "Save task")) {
                            saving = true
                            Task {
                                if await store.authorize(), store.save(SalaryTask(id: editingID ?? UUID(), payroll: event.key, text: text, offsets: offsets, minute: minute, tone: tone)) { text = ""; editingID = nil }
                                saving = false
                            }
                        }.buttonStyle(RaisedButtonStyle()).disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || offsets.isEmpty)
                    }
                }
                if let message = store.message { Text(message).font(.footnote) }
                ForEach(store.salaryTasks.filter { $0.payroll == event.key }) { task in
                    DesignCard {
                        HStack {
                            Text(task.text).frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                editingID = task.id; text = task.text; offsets = task.offsets; minute = task.minute; tone = task.tone
                            } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                                .accessibilityLabel(tr("تعديل المهمة", "Edit task"))
                            Button(role: .destructive) { store.delete(task) } label: { Image(systemName: "trash") }
                                .accessibilityLabel(tr("حذف المهمة", "Delete task"))
                        }
                    }
                }
            }
            .navigationTitle(tr("مهام الراتب", "Salary tasks")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("تم", "Done")) { dismiss() } } }
        }.modifier(DesignRootStyle())
    }
}
