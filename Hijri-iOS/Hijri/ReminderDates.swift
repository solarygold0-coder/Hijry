import Foundation

enum ReminderRepeat: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekly, monthly, yearly, hijriMonthly, hijriYearly

    var id: Self { self }
    var title: String {
        switch self {
        case .once: return "مرة واحدة"
        case .daily: return "يوميًا"
        case .weekly: return "أسبوعيًا"
        case .monthly: return "شهريًا ميلاديًا"
        case .yearly: return "سنويًا ميلاديًا"
        case .hijriMonthly: return "شهريًا هجريًا"
        case .hijriYearly: return "سنويًا هجريًا"
        }
    }

    var usesDatedNotifications: Bool {
        switch self {
        case .once, .daily, .weekly: return false
        case .monthly, .yearly, .hijriMonthly, .hijriYearly: return true
        }
    }
}

enum ReminderDates {
    static func upcoming(anchor: Date, repeatMode: ReminderRepeat, after: Date, limit: Int,
                         calendar: Calendar, table: UmmAlQura?) -> [Date] {
        guard limit > 0, repeatMode != .once else { return [] }
        let current = max(anchor, after)
        let time = calendar.dateComponents([.hour, .minute], from: anchor)
        if repeatMode == .daily || repeatMode == .weekly {
            let step = repeatMode == .weekly ? 7 : 1
            let start = calendar.startOfDay(for: anchor)
            let elapsed = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: current)).day ?? 0
            let first = elapsed / step
            return Array((first...(first + limit)).compactMap { index -> Date? in
                guard let day = calendar.date(byAdding: .day, value: index * step, to: start),
                      let event = eventTime(on: day, time: time, calendar: calendar), event > after else { return nil }
                return event
            }.prefix(limit))
        }
        let anchorMonth: Int
        let currentMonth: Int
        let originalDay: Int
        let hijri = repeatMode == .hijriMonthly || repeatMode == .hijriYearly
        let step = repeatMode == .yearly || repeatMode == .hijriYearly ? 12 : 1
        if hijri {
            guard let a = table?.convert(anchor, in: calendar.timeZone),
                  let b = table?.convert(current, in: calendar.timeZone) else { return [] }
            anchorMonth = a.year * 12 + a.month - 1
            currentMonth = b.year * 12 + b.month - 1
            originalDay = a.day
        } else {
            let a = calendar.dateComponents([.year, .month, .day], from: anchor)
            let b = calendar.dateComponents([.year, .month], from: current)
            guard let year = a.year, let month = a.month, let day = a.day,
                  let endYear = b.year, let endMonth = b.month else { return [] }
            anchorMonth = year * 12 + month - 1
            currentMonth = endYear * 12 + endMonth - 1
            originalDay = day
        }
        let first = (currentMonth - anchorMonth) / step
        return Array((first...(first + limit)).compactMap { index -> Date? in
            let total = anchorMonth + index * step
            let year = total / 12
            let month = total % 12 + 1
            let civilDay: Date?
            if hijri {
                guard let table else { return nil }
                let day = min(originalDay, table.monthLength(year: year, month: month))
                civilDay = table.date(year: year, month: month, day: day, in: calendar.timeZone)
            } else if let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)),
                      let days = calendar.range(of: .day, in: .month, for: firstDay) {
                civilDay = calendar.date(byAdding: .day, value: min(originalDay, days.count) - 1, to: firstDay)
            } else {
                civilDay = nil
            }
            guard let civilDay,
                  let event = eventTime(on: civilDay, time: time, calendar: calendar), event > after else { return nil }
            return event
        }.prefix(limit))
    }

    private static func eventTime(on day: Date, time: DateComponents, calendar: Calendar) -> Date? {
        guard let event = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                        second: 0, of: day, matchingPolicy: .nextTimePreservingSmallerComponents),
              calendar.isDate(event, inSameDayAs: day) else { return nil }
        return event
    }

    static func requiresDatedNotifications(anchor: Date, recurrence: ReminderRepeat,
                                            now: Date, calendar: Calendar) -> Bool {
        if recurrence.usesDatedNotifications { return true }
        guard recurrence == .daily || recurrence == .weekly, anchor > now else { return false }
        let fields: Set<Calendar.Component> = recurrence == .daily ? [.hour, .minute] : [.weekday, .hour, .minute]
        let components = calendar.dateComponents(fields, from: anchor)
        guard let first = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) else { return true }
        return first < anchor
    }
}
