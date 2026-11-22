import Foundation

struct CivilDay {
    let year: Int
    let month: Int
    let day: Int
}

enum GregorianDateSpan {
    static func duration(from first: Date, to last: Date, calendar: Calendar) -> DateComponents {
        let start = calendar.startOfDay(for: min(first, last))
        let end = calendar.startOfDay(for: max(first, last))
        let a = calendar.dateComponents([.year, .month, .day], from: start)
        let b = calendar.dateComponents([.year, .month, .day], from: end)
        var months = ((b.year ?? 0) - (a.year ?? 0)) * 12 + (b.month ?? 0) - (a.month ?? 0)
        var days = (b.day ?? 0) - (a.day ?? 0)
        if months > 0 && days < 0 {
            months -= 1
            let anchor = calendar.date(byAdding: .month, value: months, to: start) ?? start
            days = calendar.dateComponents([.day], from: anchor, to: end).day ?? 0
        }
        return DateComponents(year: months / 12, month: months % 12, day: days)
    }
}

struct UmmAlQura {
    static let months = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة",
                         "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
    static let years = 1300...1600
    private let starts: [Int]

    init?(bytes: Data) {
        guard bytes.count == 4 * 3614 else { return nil }
        let words = bytes.withUnsafeBytes { buffer in
            stride(from: 0, to: bytes.count, by: 4).map { offset in
                Int(Int32(bigEndian: buffer.loadUnaligned(fromByteOffset: offset, as: Int32.self)))
            }
        }
        let months = Array(words.dropFirst())
        guard words.first == 3613,
              zip(months, months.dropFirst()).allSatisfy({ pair in (29...30).contains(pair.1 - pair.0) })
        else { return nil }
        starts = months
    }

    static let bundled: UmmAlQura? = {
        guard let url = Bundle.main.url(forResource: "ummalqura", withExtension: "bin"),
              let bytes = try? Data(contentsOf: url) else { return nil }
        return Self(bytes: bytes)
    }()

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func epochDay(_ date: Date, in zone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let local = cal.dateComponents([.year, .month, .day], from: date)
        let midnight = utc.date(from: local) ?? date
        return Int(floor(midnight.timeIntervalSince1970 / 86400))
    }

    private static func date(_ day: Int, in zone: TimeZone = .current) -> Date {
        let date = Date(timeIntervalSince1970: TimeInterval(day) * 86400)
        var parts = utc.dateComponents([.year, .month, .day], from: date)
        parts.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: parts) ?? date
    }

    var range: ClosedRange<Date> {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .autoupdatingCurrent
        let first = Self.date(starts[0], in: gregorian.timeZone)
        let last = Self.date(starts[starts.count - 1] - 1, in: gregorian.timeZone)
        let end = gregorian.dateInterval(of: .day, for: last)?.end.addingTimeInterval(-1) ?? last
        return gregorian.startOfDay(for: first)...end
    }

    func convert(_ date: Date, in zone: TimeZone = .current) -> CivilDay? {
        let day = Self.epochDay(date, in: zone)
        guard day >= starts[0], day < starts[starts.count - 1] else { return nil }
        var low = 0
        var high = starts.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if starts[mid] > day { high = mid } else { low = mid }
        }
        return CivilDay(year: Self.years.lowerBound + low / 12, month: low % 12 + 1, day: day - starts[low] + 1)
    }

    func duration(from first: Date, to last: Date, in zone: TimeZone = .current) -> DateComponents? {
        let start = min(first, last)
        let end = max(first, last)
        guard let a = convert(start, in: zone), let b = convert(end, in: zone) else { return nil }
        var months = (b.year - a.year) * 12 + b.month - a.month
        var days = b.day - a.day
        if months > 0 && days < 0 {
            months -= 1
            let index = (a.year - Self.years.lowerBound) * 12 + a.month - 1 + months
            let anchorDay = starts[index] + min(a.day, starts[index + 1] - starts[index]) - 1
            days = Self.epochDay(end, in: zone) - anchorDay
        }
        return DateComponents(year: months / 12, month: months % 12, day: days)
    }

    func monthLength(year: Int, month: Int) -> Int {
        guard Self.years.contains(year), (1...12).contains(month) else { return 0 }
        let index = (year - Self.years.lowerBound) * 12 + month - 1
        return starts[index + 1] - starts[index]
    }

    func date(year: Int, month: Int, day: Int, in zone: TimeZone = .current) -> Date? {
        guard day > 0, day <= monthLength(year: year, month: month) else { return nil }
        return Self.date(starts[(year - Self.years.lowerBound) * 12 + month - 1] + day - 1, in: zone)
    }
}
