import SwiftUI

struct CalendarScreen: View {
    let table: UmmAlQura
    @State private var selected = Date()
    @AppStorage("numberSize") private var numberSize = 22.0
    @AppStorage("designTheme") private var theme = HijriTheme.royal
    @ScaledMetric(relativeTo: .title3) private var textScale = 1.0

    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private let gregorianMonths = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
                                   "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]

    var body: some View {
        NavigationStack {
            Form {
                Text("هجري")
                    .font(theme.headerFont)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(theme.accent)
                    .accessibilityAddTraits(.isHeader)
                if let hijri = table.convert(selected, in: gregorian.timeZone) {
                    Section("أم القرى") {
                        dateRow(hijri, months: UmmAlQura.months, years: UmmAlQura.years,
                                dayCount: table.monthLength(year: hijri.year, month: hijri.month)) {
                            updateHijri($0, $1, $2)
                        }
                    }
                }
                Section("الميلادي") {
                    let lower = gregorian.component(.year, from: table.range.lowerBound)
                    let upper = gregorian.component(.year, from: table.range.upperBound)
                    dateRow(civilDate(selected), months: gregorianMonths, years: lower...upper,
                            dayCount: gregorian.range(of: .day, in: .month, for: selected)?.count ?? 31) {
                        updateGregorian($0, $1, $2)
                    }
                }
                Section {
                    LabeledContent("اليوم") {
                        Text(selected, format: .dateTime.weekday(.wide))
                    }
                    Button("تاريخ اليوم") { selectToday() }
                }
                TimelineView(.everyMinute) { context in
                    durationCard(today: context.date)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !table.range.contains(selected) { selectToday() }
            }
        }
    }

    private func civilDate(_ date: Date) -> CivilDay {
        let values = gregorian.dateComponents([.year, .month, .day], from: date)
        return CivilDay(year: values.year ?? 1970, month: values.month ?? 1, day: values.day ?? 1)
    }

    private func dateRow(_ value: CivilDay, months: [String], years: ClosedRange<Int>, dayCount: Int,
                         update: @escaping (Int, Int, Int) -> Void) -> some View {
        let day = Binding(get: { value.day }, set: { update(value.year, value.month, $0) })
        let month = Binding(get: { value.month }, set: { update(value.year, $0, value.day) })
        let year = Binding(get: { value.year }, set: { update($0, value.month, value.day) })

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                dayPicker(day, count: dayCount)
                monthPicker(month, names: months)
                yearPicker(year, years: years)
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading) {
                dayPicker(day, count: dayCount)
                monthPicker(month, names: months)
                yearPicker(year, years: years)
            }
        }
        .font(.system(size: numberSize * textScale, weight: .semibold))
    }

    private func dayPicker(_ day: Binding<Int>, count: Int) -> some View {
        Picker("اليوم", selection: day) {
            ForEach(1...max(1, count), id: \.self) { Text(String($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityLabel("اليوم")
    }

    private func monthPicker(_ month: Binding<Int>, names: [String]) -> some View {
        Picker("الشهر", selection: month) {
            ForEach(1...12, id: \.self) { number in
                Text("\(names[number - 1]) (\(number))").tag(number)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityLabel("الشهر")
    }

    private func yearPicker(_ year: Binding<Int>, years: ClosedRange<Int>) -> some View {
        Picker("السنة", selection: year) {
            ForEach(years, id: \.self) { Text(String($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityLabel("السنة")
    }

    private func selectToday() {
        selected = min(max(Date(), table.range.lowerBound), table.range.upperBound)
    }

    private func updateHijri(_ year: Int, _ month: Int, _ day: Int) {
        let last = table.monthLength(year: year, month: month)
        if let date = table.date(year: year, month: month, day: min(day, last), in: gregorian.timeZone) {
            selected = date
        }
    }

    private func updateGregorian(_ year: Int, _ month: Int, _ day: Int) {
        guard let first = gregorian.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)),
              let days = gregorian.range(of: .day, in: .month, for: first),
              let date = gregorian.date(byAdding: .day, value: min(day, days.count) - 1, to: first)
        else { return }
        selected = min(max(date, table.range.lowerBound), table.range.upperBound)
    }

    private func durationCard(today: Date) -> some View {
        let now = gregorian.startOfDay(for: today)
        let target = gregorian.startOfDay(for: selected)
        let interval = GregorianDateSpan.duration(from: now, to: target, calendar: gregorian)
        return Section(target > now ? "الوقت المتبقي" : "المدة حتى اليوم") {
            if target == now {
                Text("تاريخ اليوم")
            } else {
                if let hijri = table.duration(from: now, to: target, in: gregorian.timeZone) {
                    durationRow("بالهجري", hijri)
                }
                durationRow("بالميلادي", interval)
            }
        }
    }

    private func durationRow(_ label: String, _ interval: DateComponents) -> some View {
        LabeledContent(label) {
            Text("\(interval.year ?? 0) سنة، \(interval.month ?? 0) شهر، \(interval.day ?? 0) يوم")
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}
