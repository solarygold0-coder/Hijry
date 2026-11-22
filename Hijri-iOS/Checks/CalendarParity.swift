import Foundation

@main
struct CalendarParity {
    static func main() throws {
        let calendar = SaudiCalendar.calendar
        let tableURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let table = UmmAlQura(bytes: try Data(contentsOf: tableURL))!
        func day(_ year: Int, _ month: Int, _ number: Int) -> Date {
            SaudiCalendar.day(year, month, number)!
        }

        let start = table.date(year: 1300, month: 1, day: 1, in: calendar.timeZone)!
        let first = table.convert(start, in: calendar.timeZone)!
        precondition(first.year == 1300 && first.month == 1 && first.day == 1)
        let lastDay = table.monthLength(year: 1600, month: 12)
        let end = table.date(year: 1600, month: 12, day: lastDay, in: calendar.timeZone)!
        precondition(table.convert(end, in: calendar.timeZone)?.day == lastDay)
        precondition(table.convert(calendar.date(byAdding: .day, value: 1, to: end)!, in: calendar.timeZone) == nil)

        let hijriSpanStart = table.date(year: 1448, month: 1, day: 28, in: calendar.timeZone)!
        let hijriSpanEnd = table.date(year: 1448, month: 2, day: 2, in: calendar.timeZone)!
        let span = table.duration(from: hijriSpanEnd, to: hijriSpanStart, in: calendar.timeZone)!
        precondition(span.year == 0 && span.month == 0 && span.day == table.monthLength(year: 1448, month: 1) - 26)

        let civilSpan = GregorianDateSpan.duration(from: day(2027, 1, 31), to: day(2027, 2, 28), calendar: calendar)
        precondition(civilSpan.year == 0 && civilSpan.month == 0 && civilSpan.day == 28)
        let monthly = ReminderDates.upcoming(anchor: day(2027, 1, 31), repeatMode: .monthly,
                                             after: day(2027, 1, 31), limit: 2, calendar: calendar, table: table)
        precondition(monthly == [day(2027, 2, 28), day(2027, 3, 31)])
        let leap = ReminderDates.upcoming(anchor: day(2024, 2, 29), repeatMode: .yearly,
                                          after: day(2024, 2, 29), limit: 4, calendar: calendar, table: table)
        precondition(leap == [day(2025, 2, 28), day(2026, 2, 28), day(2027, 2, 28), day(2028, 2, 29)])
        let futureStart = day(2027, 2, 9)
        let early = day(2027, 2, 1)
        precondition(ReminderDates.requiresDatedNotifications(anchor: futureStart, recurrence: .daily,
                                                               now: early, calendar: calendar))
        let daily = ReminderDates.upcoming(anchor: futureStart, repeatMode: .daily, after: early,
                                           limit: 2, calendar: calendar, table: table)
        precondition(daily == [futureStart, day(2027, 2, 10)])
        let hijriDate = table.date(year: 1448, month: 1, day: 28, in: calendar.timeZone)!
        let hijriRepeat = ReminderDates.upcoming(anchor: hijriDate, repeatMode: .hijriMonthly, after: hijriDate,
                                                 limit: 2, calendar: calendar, table: table)
        precondition(hijriRepeat.compactMap { table.convert($0, in: calendar.timeZone)?.month } == [2, 3])

        let mansions = TraditionalSeasons.timeline(from: day(2028, 2, 29))
        precondition(mansions.count == 28 && mansions.first?.name == "سعد بلع")
        precondition(mansions.first?.nextStart == day(2028, 3, 8))
        precondition(zip(mansions, mansions.dropFirst()).allSatisfy { $0.0.nextStart == $0.1.start })

        var preferences = OccasionPreferences()
        preferences.days[.telecom] = 31
        precondition(preferences.upcoming(for: .telecom, from: day(2027, 2, 1), months: 0...0) == [day(2027, 2, 28)])
        preferences.days[.aramco] = 31
        preferences.weekend[.aramco] = .next
        precondition(preferences.upcoming(for: .aramco, from: day(2026, 11, 1), months: -1...0).first == day(2026, 11, 1))

        let occasions = HijriOccasions.entries(from: day(2026, 5, 1), table: table, preferences: preferences)
        precondition(occasions.first { $0.key == "salary" }?.date == day(2026, 5, 24))
        let western = OccasionPreferences(western: true)
        let westernSchool = HijriOccasions.entries(from: day(2027, 4, 1), table: table, preferences: western)
        precondition(westernSchool.contains { $0.key == "school-2027-04-30" })
        precondition(!westernSchool.contains { $0.key == "school-2027-04-11" })
        print("Hijri Android calendar rules passed")
    }
}
