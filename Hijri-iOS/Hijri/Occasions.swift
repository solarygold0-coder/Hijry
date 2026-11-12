import Foundation

struct HijriOccasion: Identifiable {
    let key: String
    var id: String { key + "@" + String(Int(date.timeIntervalSince1970)) }
    let title: String
    let date: Date
    var end: Date? = nil
    var estimated = false
    var payment = false
}

enum HijriOccasions {
    static func entries(from now: Date, table: UmmAlQura?, preferences: OccasionPreferences, upcomingOnly: Bool = true) -> [HijriOccasion] {
        let cal = SaudiCalendar.calendar
        let western = preferences.western
        let today = cal.startOfDay(for: now)
        let noon = cal.date(byAdding: .hour, value: 12, to: today) ?? now
        let monthStart = cal.dateInterval(of: .month, for: today)!.start
        var result: [HijriOccasion] = []
        let payouts: [(String, String, Int, Int)] = [
            ("salary","رواتب موظفي الدولة",27,0), ("hafiz","حافز (إعانة البحث عن عمل)",5,0),
            ("citizen","حساب المواطن",10,0), ("pension","معاش التقاعد المدني والعسكري",1,1),
            ("insurance","معاش التأمينات الاجتماعية",1,1), ("saned","ساند",1,1),
            ("disability","التأهيل الشامل",26,2), ("security","الضمان الاجتماعي المطوّر",1,0),
            ("housing","الدعم السكني",24,2)
        ]
        let published2026 = [27,26,26,27,24,28,27,27,27,27,26,27]
        for (id, title, day, rule) in payouts {
            for offset in 0...2 {
                guard let month = cal.date(byAdding: .month, value: offset, to: monthStart) else { continue }
                let official = id == "salary" && cal.component(.year, from: month) == 2026
                let payDay = official ? published2026[cal.component(.month, from: month) - 1] : day
                guard let nominal = cal.date(byAdding: .day, value: payDay - 1, to: month) else { continue }
                let weekday = cal.component(.weekday, from: nominal)
                let delta = official ? 0 : (weekday == 6 ? (rule == 2 ? 2 : -1) : weekday == 7 ? (rule == 1 ? -2 : 1) : 0)
                guard let date = cal.date(byAdding: .day, value: delta, to: nominal), date >= today else { continue }
                result.append(.init(key: id, title: title, date: date, estimated: !official, payment: true))
                if upcomingOnly { break }
            }
        }
        if let table, let h = table.convert(noon, in: cal.timeZone) {
            let religious = [("ramadan", "أول أيام شهر رمضان", 9, 1), ("fitr", "عيد الفطر المبارك", 10, 1),
                             ("hajj-start", "بداية مناسك الحج", 12, 8), ("hajj", "يوم عرفة", 12, 9),
                             ("adha", "عيد الأضحى المبارك", 12, 10)]
            for (id, title, month, day) in religious {
                for year in h.year...min(h.year + 1, 1600) {
                    guard let date = table.date(year: year, month: month, day: day, in: cal.timeZone) else { continue }
                    let start = cal.startOfDay(for: date)
                    if start >= today {
                        result.append(.init(key: id, title: title, date: start, estimated: true))
                        break
                    }
                }
            }
        }
        for (id, title, month, day) in [("founding","يوم التأسيس",2,22),("national","اليوم الوطني السعودي",9,23)] {
            let year = cal.component(.year, from: today)
            for y in year...(year + 1) {
                if let date = cal.date(from: DateComponents(year: y, month: month, day: day)), date >= today {
                    result.append(.init(key: id, title: title, date: date))
                    break
                }
            }
        }
        let school: [(String, String, String)] = [
            ("إجازة اليوم الوطني للمدارس","2026-09-23","2026-09-26"),
            ("إجازة مدرسية إضافية الأولى","2026-10-25","2026-10-25"),
            ("إجازة الخريف للمدارس","2026-11-20","2026-11-28"),
            ("إجازة منتصف العام الدراسي","2027-01-08","2027-01-16"),
            ("إجازة يوم التأسيس للمدارس","2027-02-19","2027-02-22"),
            ("إجازة عيد الفطر للمدارس","2027-02-26","2027-03-13"),
            ("إجازة عيد الأضحى للمدارس",western ? "2027-04-30" : "2027-05-07","2027-05-22"),
            ("بداية إجازة نهاية العام الدراسي",western ? "2027-07-01" : "2027-06-24",western ? "2027-07-01" : "2027-06-24")
        ] + (western ? [] : [("إجازة مدرسية إضافية الثانية","2026-11-29","2026-11-29"),
                             ("إجازة مدرسية إضافية الثالثة","2027-01-07","2027-01-07"),
                             ("إجازة مدرسية إضافية الرابعة","2027-04-11","2027-04-11")])
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = cal.timeZone
        parser.calendar = cal
        parser.dateFormat = "yyyy-MM-dd"
        for (title, start, end) in school {
            if let date = parser.date(from: start), let last = parser.date(from: end), last >= today {
                result.append(.init(key: "school-\(start)", title: title, date: date, end: last == date ? nil : last))
            }
        }
        for schedule in OccasionSchedule.allCases {
            let dates = preferences.upcoming(for: schedule, from: today, months: -1...2)
            for date in (upcomingOnly ? Array(dates.prefix(1)) : dates) {
                result.append(.init(key: schedule.id, title: schedule.title, date: date, payment: schedule.isCompany))
            }
        }
        return result.sorted { $0.date < $1.date }
    }
}
