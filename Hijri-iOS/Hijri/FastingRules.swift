import Foundation

enum FastingType: String, Codable, CaseIterable, Identifiable {
    case monday, thursday, whiteDays, arafah, ashura, dhulHijjah, shawwal, muharram, shaban
    var id: Self { self }
    var title: String {
        switch self {
        case .monday: return tr("الاثنين", "Monday")
        case .thursday: return tr("الخميس", "Thursday")
        case .whiteDays: return tr("الأيام البيض 13 و14 و15", "White days 13, 14 and 15")
        case .arafah: return tr("عرفة لغير الحاج", "Arafah for non-pilgrims")
        case .ashura: return tr("تاسوعاء وعاشوراء", "9 and 10 Muharram")
        case .dhulHijjah: return tr("التسع الأولى من ذي الحجة", "First nine days of Dhul Hijjah")
        case .shawwal: return tr("ست من شوال • أيام تختارها", "Six of Shawwal • your selected days")
        case .muharram: return tr("الإكثار من الصيام في محرم", "More fasting in Muharram")
        case .shaban: return tr("الصيام في النصف الأول من شعبان", "First half of Shaban")
        }
    }
}

struct FastingSettings: Codable, Equatable {
    var enabled = false
    var types: Set<FastingType> = [.monday, .thursday, .whiteDays, .arafah, .ashura]
    var notifications = true
    var dayBefore = true
    var minute = 1200
    var tone = "system"
    var pilgrim = false
    var shawwalYear = 0
    var shawwalDays: Set<Int> = []
}

enum FastingPlan {
    static func reasons(date: Date, settings: FastingSettings, table: UmmAlQura, calendar: Calendar) -> [FastingType] {
        guard settings.enabled, let h = table.convert(date, in: calendar.timeZone), h.month != 9,
              !(h.month == 10 && h.day == 1), !(h.month == 12 && (10...13).contains(h.day)),
              !(settings.pilgrim && h.month == 12 && h.day == 9) else { return [] }
        return FastingType.allCases.filter { type in
            guard settings.types.contains(type) else { return false }
            switch type {
            case .monday: return calendar.component(.weekday, from: date) == 2
            case .thursday: return calendar.component(.weekday, from: date) == 5
            case .whiteDays: return (13...15).contains(h.day)
            case .arafah: return h.month == 12 && h.day == 9
            case .ashura: return h.month == 1 && (9...10).contains(h.day)
            case .dhulHijjah: return h.month == 12 && (1...9).contains(h.day)
            case .shawwal: return h.month == 10 && h.year == settings.shawwalYear && settings.shawwalDays.contains(h.day)
            case .muharram: return h.month == 1
            case .shaban: return h.month == 8 && (1...15).contains(h.day)
            }
        }
    }
    static func upcoming(from now: Date, settings: FastingSettings, table: UmmAlQura, limit: Int = 8) -> [(date: Date, types: [FastingType])] {
        guard settings.enabled, !settings.types.isEmpty, limit > 0 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        var days: [(Date, [FastingType])] = []
        for offset in 0...400 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let reasons = reasons(date: date, settings: settings, table: table, calendar: calendar)
            if !reasons.isEmpty { days.append((date, reasons)) }
            if days.count == limit { break }
        }
        return days
    }
}
