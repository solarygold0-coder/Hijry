import SwiftUI
import UserNotifications

@MainActor
final class OccasionStore: ObservableObject {
    private static let key = "hijri.occasionPreferences"
    private let center = UNUserNotificationCenter.current()
    private let prefix = "hijri.occasion."
    private var updateTask: Task<Void, Never>?

    @Published var preferences: OccasionPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
            refresh()
        }
    }
    @Published private(set) var notificationMessage: String?

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(OccasionPreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = OccasionPreferences(western: defaults.bool(forKey: "westernSchoolCalendar"))
        }
    }

    func setNotifications(_ enable: Bool) async {
        if !enable {
            preferences.notify = false
            notificationMessage = nil
            return
        }
        do {
            if try await center.requestAuthorization(options: [.alert, .sound]) {
                preferences.notify = true
            } else {
                notificationMessage = "اسمح بإشعارات هجري من إعدادات الجهاز."
            }
        } catch {
            notificationMessage = "تعذّر طلب إذن الإشعارات."
        }
    }

    func refresh() {
        let previous = updateTask
        previous?.cancel()
        updateTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.schedule()
        }
    }

    private func schedule() async {
        let requests = await center.pendingNotificationRequests()
        guard !Task.isCancelled else { return }
        let saved = preferences
        let managed = requests.filter { $0.identifier.hasPrefix(prefix) }
        guard saved.notify else {
            center.removePendingNotificationRequests(withIdentifiers: managed.map(\.identifier))
            return
        }
        let now = Date()
        let calendar = SaudiCalendar.calendar
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 45, to: today) ?? today
        var events = HijriOccasions.entries(from: now, table: UmmAlQura.bundled, preferences: saved, upcomingOnly: false)
        events += TraditionalSeasons.timeline(from: now).filter { $0.start >= today }.map {
            HijriOccasion(key: "season", title: "بداية منزلة \($0.name) · \($0.season)", date: $0.start)
        }
        let upcoming = events.filter { $0.date <= end && !saved.muted.contains($0.key) }
        let schedule = upcoming.flatMap { event in
            (event.payment ? [0, 1] : [0]).compactMap { lead -> (Date, HijriOccasion, Int)? in
                guard let day = calendar.date(byAdding: .day, value: -lead, to: event.date),
                      let fire = calendar.date(bySettingHour: saved.hour, minute: saved.minute, second: 0, of: day),
                      fire > now else { return nil }
                return (fire, event, lead)
            }
        }.sorted { $0.0 < $1.0 }
        let remaining = max(0, 60 - (requests.count - managed.count))
        let desired = schedule.prefix(min(24, remaining))
        let desiredIDs = Set(desired.map { prefix + $0.1.id + "." + String($0.2) })
        center.removePendingNotificationRequests(withIdentifiers: managed.map(\.identifier).filter { !desiredIDs.contains($0) })
        notificationMessage = nil
        for (fire, event, lead) in desired {
            guard !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = (lead == 1 ? "غدًا: " : "اليوم: ") + event.title
            content.sound = .default
            content.threadIdentifier = "hijri.occasions"
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            let request = UNNotificationRequest(identifier: prefix + event.id + "." + String(lead),
                                                content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            do { try await center.add(request) }
            catch {
                notificationMessage = "تعذّرت جدولة بعض تنبيهات المناسبات."
                return
            }
        }
    }
}

struct OccasionsScreen: View {
    let table: UmmAlQura?
    @ObservedObject var store: OccasionStore
    @State private var settings = false
    @State private var showMansions = false

    private var entries: [HijriOccasion] {
        HijriOccasions.entries(from: Date(), table: table, preferences: store.preferences)
    }

    private var catalog: [(key: String, title: String)] {
        [("season", "الموسم والمنازل")] +
            entries.filter { event in !OccasionSchedule.allCases.contains(where: { $0.id == event.key }) }
                .map { ($0.key, $0.title) } +
            OccasionSchedule.allCases.map { ($0.id, $0.title) }
    }

    private var order: [String] {
        let available = catalog.map { $0.key }
        return store.preferences.order.filter { available.contains($0) }
            + available.filter { !store.preferences.order.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("التقويم الدراسي", selection: $store.preferences.western) {
                        Text("عموم المناطق").tag(false)
                        Text("مكة والمدينة وجدة والطائف").tag(true)
                    }
                    Button("تنبيهات الفواتير والمناسبات") { settings = true }
                }
                Section("القادمة") {
                    ForEach(order.filter { !store.preferences.hidden.contains($0) }, id: \.self) { id in
                        if id == "season" {
                            mansions
                        } else if let event = entries.first(where: { $0.key == id }) {
                            eventRow(event)
                        }
                    }
                }
            }
            .navigationTitle("المناسبات")
            .sheet(isPresented: $settings) {
                NavigationStack { OccasionPreferencesScreen(store: store, catalog: catalog) }
            }
        }
    }

    private func eventRow(_ event: HijriOccasion) -> some View {
        let today = SaudiCalendar.calendar.startOfDay(for: Date())
        let remaining = SaudiCalendar.days(from: today, to: event.date)
        return VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.headline)
            Text(format(event.date) + (event.end.map { " – " + format($0) } ?? ""))
            if remaining > 0 { Text("متبقي \(remaining) يومًا") }
            else { Text(remaining == 0 ? "اليوم" : "جارية") }
            if event.estimated { Text("موعد متوقع").font(.caption) }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 3)
    }

    @ViewBuilder private var mansions: some View {
        let today = SaudiCalendar.calendar.startOfDay(for: Date())
        let timeline = TraditionalSeasons.timeline(from: today)
        if let current = timeline.first {
            DisclosureGroup(isExpanded: $showMansions) {
                ForEach(timeline) { mansion in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mansion.name + " · " + mansion.season).font(.headline)
                        Text(format(mansion.start) + " – " + format(mansion.lastDay))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("الموسم الحالي: \(current.season)").font(.headline)
                    Text("المنزلة الحالية: \(current.name)")
                    Text("متبقي \(SaudiCalendar.days(from: today, to: current.nextStart)) يومًا")
                    if let next = timeline.dropFirst().first {
                        Text("التالية: \(next.name)").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar_SA")
        formatter.calendar = SaudiCalendar.calendar
        formatter.timeZone = SaudiCalendar.calendar.timeZone
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
}

private struct OccasionPreferencesScreen: View {
    @ObservedObject var store: OccasionStore
    let catalog: [(key: String, title: String)]
    @Environment(\.dismiss) private var dismiss
    @State private var requesting = false

    private var order: [String] {
        let keys = catalog.map { $0.key }
        return store.preferences.order.filter { keys.contains($0) }
            + keys.filter { !store.preferences.order.contains($0) }
    }

    private var notificationTime: Binding<Date> {
        let calendar = Calendar.current
        return Binding(get: {
            calendar.date(bySettingHour: store.preferences.hour, minute: store.preferences.minute,
                          second: 0, of: Date()) ?? Date()
        }, set: { date in
            let time = calendar.dateComponents([.hour, .minute], from: date)
            var prefs = store.preferences
            prefs.hour = time.hour ?? 9
            prefs.minute = time.minute ?? 0
            store.preferences = prefs
        })
    }

    var body: some View {
        Form {
            Section("التنبيهات بتوقيت السعودية") {
                Toggle("تنبيهات المناسبات", isOn: Binding(get: { store.preferences.notify }, set: { enable in
                    requesting = true
                    Task {
                        await store.setNotifications(enable)
                        requesting = false
                    }
                }))
                .disabled(requesting)
                DatePicker("وقت التنبيه", selection: notificationTime, displayedComponents: .hourAndMinute)
                if let message = store.notificationMessage { Text(message).foregroundStyle(.secondary) }
            }
            Section("الفواتير ورواتب الشركات") {
                ForEach(OccasionSchedule.allCases) { item in
                    Picker(item.title, selection: Binding(get: { store.preferences.day(for: item) },
                                                         set: { store.preferences.days[item] = $0 })) {
                        Text("إيقاف").tag(0)
                        ForEach(1...31, id: \.self) { Text(String($0)).tag($0) }
                    }
                    if item.isCompany && store.preferences.day(for: item) > 0 {
                        Picker("عطلة نهاية الأسبوع", selection: Binding(get: { store.preferences.weekend[item] ?? PayrollWeekend.none },
                                                                         set: { store.preferences.weekend[item] = $0 })) {
                            ForEach(PayrollWeekend.allCases) { Text($0.title).tag($0) }
                        }
                    }
                }
            }
            Section("الظهور والترتيب") {
                ForEach(order, id: \.self) { id in
                    let title = catalog.first(where: { $0.key == id })?.title ?? id
                    DisclosureGroup(title) {
                        Toggle("إظهار", isOn: option(\.hidden, id: id))
                        Toggle("إشعار", isOn: option(\.muted, id: id))
                    }
                }
                .onMove { source, destination in
                    var updated = order
                    updated.move(fromOffsets: source, toOffset: destination)
                    store.preferences.order = updated
                }
            }
        }
        .navigationTitle("المناسبات والفواتير")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("تم") { dismiss() } }
            ToolbarItem(placement: .primaryAction) { EditButton() }
        }
    }

    private func option(_ key: WritableKeyPath<OccasionPreferences, Set<String>>, id: String) -> Binding<Bool> {
        Binding(get: { !store.preferences[keyPath: key].contains(id) }, set: { enabled in
            if enabled { store.preferences[keyPath: key].remove(id) }
            else { store.preferences[keyPath: key].insert(id) }
        })
    }
}
