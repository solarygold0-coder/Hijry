import Foundation

enum SaudiCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        return calendar
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func days(from start: Date, to end: Date) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

enum OccasionSchedule: String, Codable, CaseIterable, Identifiable {
    case electricity, telecom, water, aramco, sabic

    var id: String { rawValue }
    var isCompany: Bool { self == .aramco || self == .sabic }
    var defaultDay: Int { self == .electricity || self == .water ? 28 : 0 }
    var title: String {
        switch self {
        case .electricity: return "فاتورة الكهرباء"
        case .telecom: return "فاتورة الاتصالات"
        case .water: return "فاتورة المياه"
        case .aramco: return "رواتب أرامكو"
        case .sabic: return "رواتب سابك"
        }
    }
}

enum PayrollWeekend: String, Codable, CaseIterable, Identifiable {
    case none, previous, next

    var id: Self { self }
    var title: String {
        switch self {
        case .none: return "دون تعديل"
        case .previous: return "تقديم إلى الخميس"
        case .next: return "تأخير إلى الأحد"
        }
    }

    func adjusted(_ date: Date) -> Date {
        let calendar = SaudiCalendar.calendar
        let weekday = calendar.component(.weekday, from: date)
        let offset: Int
        switch (self, weekday) {
        case (.previous, 6): offset = -1
        case (.previous, 7): offset = -2
        case (.next, 6): offset = 2
        case (.next, 7): offset = 1
        default: return date
        }
        return calendar.date(byAdding: .day, value: offset, to: date) ?? date
    }
}

struct OccasionPreferences: Codable, Equatable {
    var western = false
    var days: [OccasionSchedule: Int] = [:]
    var weekend: [OccasionSchedule: PayrollWeekend] = [:]
    var hidden: Set<String> = []
    var muted: Set<String> = []
    var order: [String] = []
    var notify = false
    var hour = 9
    var minute = 0

    func day(for schedule: OccasionSchedule) -> Int {
        days[schedule] ?? schedule.defaultDay
    }

    func upcoming(for schedule: OccasionSchedule, from today: Date, months: ClosedRange<Int>) -> [Date] {
        let day = day(for: schedule)
        let calendar = SaudiCalendar.calendar
        guard (1...31).contains(day),
              let monthStart = calendar.dateInterval(of: .month, for: today)?.start else { return [] }
        let policy = weekend[schedule] ?? .none
        return months.compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: monthStart),
                  let days = calendar.range(of: .day, in: .month, for: month),
                  let date = calendar.date(byAdding: .day, value: min(day, days.count) - 1, to: month) else { return nil }
            let adjusted = policy.adjusted(date)
            return adjusted >= today ? adjusted : nil
        }
    }
}

struct TraditionalMansion: Identifiable {
    let name: String
    let season: String
    let start: Date
    let nextStart: Date
    var id: Date { start }
    var lastDay: Date { SaudiCalendar.calendar.date(byAdding: .day, value: -1, to: nextStart) ?? start }
}

enum TraditionalSeasons {
    // The regional civil-date anwaa table from the Android project's TraditionalSeasons.kt.
    private static let anchors: [(String, String, Int, Int)] = [
        ("الشولة", "المربعانية", 1, 2),
        ("النعايم", "الشبط", 1, 15),
        ("البلدة", "الشبط", 1, 28),
        ("سعد الذابح", "العقارب", 2, 10),
        ("سعد بلع", "العقارب", 2, 23),
        ("سعد السعود", "العقارب", 3, 8),
        ("سعد الأخبية", "الحميمين", 3, 21),
        ("المقدم", "الحميمين", 4, 3),
        ("المؤخر", "الذراعين", 4, 16),
        ("الرشاء", "الذراعين", 4, 29),
        ("الشرطين", "الثريا", 5, 12),
        ("البطين", "الثريا", 5, 25),
        ("الثريا", "الثريا", 6, 7),
        ("الدبران", "التويبع", 6, 20),
        ("الهقعة", "الجوزاء", 7, 3),
        ("الهنعة", "الجوزاء", 7, 16),
        ("الذراع", "المرزم", 7, 29),
        ("النثرة", "الكليبين", 8, 11),
        ("الطرف", "سهيل", 8, 24),
        ("الجبهة", "سهيل", 9, 6),
        ("الزبرة", "سهيل", 9, 20),
        ("الصرفة", "سهيل", 10, 3),
        ("العواء", "الوسم", 10, 16),
        ("السماك", "الوسم", 10, 29),
        ("الغفر", "الوسم", 11, 11),
        ("الزبانا", "الوسم", 11, 24),
        ("الإكليل", "المربعانية", 12, 7),
        ("القلب", "المربعانية", 12, 20),
    ]

    static func timeline(from date: Date) -> [TraditionalMansion] {
        let calendar = SaudiCalendar.calendar
        let today = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: today)
        let entries = ((year - 1)...(year + 2)).flatMap { year in
            anchors.compactMap { name, season, month, day -> (String, String, Date)? in
                guard let start = SaudiCalendar.day(year, month, day) else { return nil }
                return (name, season, start)
            }
        }
        return Array(zip(entries, entries.dropFirst()).compactMap { entry, next -> TraditionalMansion? in
            guard next.2 > today else { return nil }
            return TraditionalMansion(name: entry.0, season: entry.1, start: entry.2, nextStart: next.2)
        }.prefix(28))
    }
}
