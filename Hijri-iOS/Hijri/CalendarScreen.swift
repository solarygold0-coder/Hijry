import SwiftUI

struct CalendarScreen: View {
    let table: UmmAlQura
    @ObservedObject var occasions: OccasionStore
    @ObservedObject var reminders: Reminders
    var openOccasions: () -> Void
    var openReminders: () -> Void
    @State private var selected = Date()
    @State private var editing = false
    @AppStorage("designTheme") private var theme = HijriTheme.lavender
    @Environment(\.hijriPalette) private var palette

    var body: some View {
        TimelineView(.everyMinute) { context in
            DesignPage(title: "") {
                if theme.current != .lavender {
                    Text(tr("هجري", "Hijry")).font(theme.headerFont).foregroundStyle(palette.accent)
                        .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                }
                if theme.current == .emerald { upcoming(today: context.date) }
                controls
                AgeCard(table: table, selected: selected, today: context.date)
                if theme.current == .lavender {
                    HStack(alignment: .top, spacing: 8) {
                        nextOccasion(today: context.date)
                        DateComparisonCard(table: table, stacked: true)
                    }
                    nextAppointment(today: context.date)
                } else {
                    DateComparisonCard(table: table)
                    if theme.current != .emerald { upcoming(today: context.date) }
                }
            }
        }
        .onAppear { selected = bounded(selected) }
        .sheet(isPresented: $editing) { DateEditor(table: table, selected: $selected) }
    }

    @ViewBuilder private var controls: some View {
        switch theme.current {
        case .minimal:
            DesignCard {
                VStack(spacing: 4) {
                    dateSummary(hijri: true)
                    Divider()
                    dateSummary(hijri: false)
                    Divider()
                    HStack {
                        Button(tr("تاريخ اليوم", "Today")) { selected = bounded(Date()) }
                        Spacer()
                        Button(tr("إدخال تاريخ الميلاد", "Enter birth date")) { editing = true }
                    }.font(.subheadline)
                }
            }
        case .sky:
            weekStrip
            HStack(spacing: 6) {
                DesignCard { dateSummary(hijri: true) }
                DesignCard { dateSummary(hijri: false) }
            }
            Button(tr("تاريخ اليوم", "Today")) { selected = bounded(Date()) }.frame(maxWidth: .infinity)
        case .lavender:
            DesignCard(padding: 8) { wheels(metallic: true) }
        default:
            wheels(metallic: false)
        }
    }

    private func wheels(metallic: Bool) -> some View {
        VStack(spacing: 5) {
            if metallic {
                DateWheels(table: table, selected: $selected, hijri: true, metallic: true)
            } else {
                DesignCard(padding: 8) { DateWheels(table: table, selected: $selected, hijri: true) }
            }
            Button(tr("تاريخ اليوم", "Today")) { selected = bounded(Date()) }
                .buttonStyle(RaisedButtonStyle()).padding(.vertical, 3)
            if metallic {
                DateWheels(table: table, selected: $selected, hijri: false, metallic: true)
            } else {
                DesignCard(padding: 8) { DateWheels(table: table, selected: $selected, hijri: false) }
            }
        }
    }

    private func dateSummary(hijri: Bool) -> some View {
        Button { editing = true } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(hijri ? tr("الهجري", "Hijri") : tr("الميلادي", "Gregorian")).font(.caption)
                Text(DateLabels.date(selected, hijri: hijri, table: table)).font(.headline).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
    }

    private var weekStrip: some View {
        let calendar = DateLabels.calendar
        let index = calendar.component(.weekday, from: selected) - 1
        let start = calendar.date(byAdding: .day, value: -index, to: selected) ?? selected
        return DesignCard(padding: 4) {
            HStack(spacing: 0) {
                ForEach(0..<7) { offset in
                    let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                    Button { selected = bounded(date) } label: {
                        VStack(spacing: 4) {
                            Text(DateLabels.weekday(date, short: true)).font(.system(size: 10))
                            Text(String(calendar.component(.day, from: date))).font(.subheadline.bold())
                        }.frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(calendar.isDate(date, inSameDayAs: selected) ? palette.selected : .clear,
                                        in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func upcoming(today: Date) -> some View {
        HStack(alignment: .top, spacing: 6) {
            nextOccasion(today: today)
            nextAppointment(today: today)
        }
    }

    private func nextOccasion(today: Date) -> some View {
        let event = HijriOccasions.entries(from: today, table: table, preferences: occasions.preferences)
            .filter { !occasions.preferences.hidden.contains($0.key) }.min { $0.date < $1.date }
        return Button(action: openOccasions) {
            DesignCard(selected: theme.current == .lavender, padding: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(tr("أقرب مناسبة", "Next occasion"), systemImage: "calendar.badge.checkmark").font(.subheadline.bold())
                    Text(event.map { domain($0.title) } ?? tr("لا توجد مناسبة قادمة", "No upcoming occasion")).font(.subheadline).lineLimit(2)
                    if let event {
                        Text(DateLabels.remaining(from: today, to: event.date)).font(.caption.bold()).foregroundStyle(palette.accent)
                        Text(DateLabels.date(event.date, hijri: false, table: table, timeZone: SaudiCalendar.calendar.timeZone)).font(.caption2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
    }

    private func nextAppointment(today: Date) -> some View {
        let entry = reminders.entries.compactMap { item -> (HijriReminder, Date)? in
            if item.repeatMode == .once { return item.date > today ? (item, item.date) : nil }
            guard let next = ReminderDates.upcoming(anchor: item.date, repeatMode: item.repeatMode, after: today,
                                                   limit: 1, calendar: DateLabels.calendar, table: table, allowedWeekdays: item.allowedWeekdays).first else { return nil }
            return (item, next)
        }.min { $0.1 < $1.1 }
        return Button(action: openReminders) {
            DesignCard(padding: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(tr("أقرب موعد", "Next appointment"), systemImage: "alarm").font(.subheadline.bold())
                    Text(entry?.0.title ?? tr("لا يوجد موعد قادم", "No upcoming appointment")).font(.subheadline).lineLimit(2)
                    if let entry {
                        Text(DateLabels.remaining(from: today, to: entry.1)).font(.caption.bold()).foregroundStyle(palette.accent)
                        Text(entry.1, style: .time).font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
    }
    private func bounded(_ date: Date) -> Date { min(max(date, table.range.lowerBound), table.range.upperBound) }
}

enum DateLabels {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .autoupdatingCurrent
        return value
    }
    static let gregorianMonths = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
    static func weekday(_ date: Date, short: Bool = false, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: tr("ar_SA", "en_US"))
        formatter.timeZone = timeZone
        formatter.dateFormat = short ? "EEEEE" : "EEEE"
        return formatter.string(from: date)
    }
    static func date(_ date: Date, hijri: Bool, table: UmmAlQura, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        if hijri, let day = table.convert(date, in: timeZone) {
            return "\(day.day) \(domain(UmmAlQura.months[day.month - 1])) \(day.year)"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: tr("ar_SA", "en_US"))
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
    static func remaining(from today: Date, to target: Date) -> String {
        let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: target)).day ?? 0)
        return days == 0 ? tr("اليوم", "Today") : tr("متبقي \(days) يوم", "\(days) days left")
    }
}

struct DateWheels: View {
    let table: UmmAlQura
    @Binding var selected: Date
    var hijri: Bool
    var metallic = false
    @Environment(\.hijriPalette) private var palette
    @ScaledMetric private var wheelScale = 1.0
    private var calendar: Calendar { DateLabels.calendar }
    private var day: CivilDay {
        if hijri, let value = table.convert(selected, in: calendar.timeZone) { return value }
        let values = calendar.dateComponents([.year, .month, .day], from: selected)
        return CivilDay(year: values.year ?? 2026, month: values.month ?? 1, day: values.day ?? 1)
    }
    private var yearRange: ClosedRange<Int> {
        hijri ? UmmAlQura.years : calendar.component(.year, from: table.range.lowerBound)...calendar.component(.year, from: table.range.upperBound)
    }
    private var days: Int {
        hijri ? table.monthLength(year: day.year, month: day.month) : calendar.range(of: .day, in: .month, for: selected)?.count ?? 31
    }
    private var monthRange: ClosedRange<Int> {
        let lower = !hijri && day.year == yearRange.lowerBound ? calendar.component(.month, from: table.range.lowerBound) : 1
        let upper = !hijri && day.year == yearRange.upperBound ? calendar.component(.month, from: table.range.upperBound) : 12
        return lower...upper
    }
    private var dayRange: ClosedRange<Int> {
        let first = !hijri && day.year == yearRange.lowerBound && day.month == monthRange.lowerBound ? calendar.component(.day, from: table.range.lowerBound) : 1
        let last = !hijri && day.year == yearRange.upperBound && day.month == monthRange.upperBound ? calendar.component(.day, from: table.range.upperBound) : days
        return first...last
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hijri ? tr("الهجري", "Hijri") : tr("الميلادي", "Gregorian"))
                .font(metallic ? .headline : .subheadline.bold()).foregroundStyle(metallic ? palette.ink : palette.accent)
            GeometryReader { geometry in
                let width = max(0, geometry.size.width - (metallic ? 6 : 8))
                HStack(spacing: metallic ? 3 : 4) {
                WheelColumn(label: tr("اليوم والتاريخ", "Day and date"), value: day.day, range: dayRange, metallic: metallic,
                            text: { value in DateLabels.weekday(date(year: day.year, month: day.month, day: value)) + " \(value)" },
                            change: { update(year: day.year, month: day.month, day: $0) }).frame(width: width * 1.25 / 3.75)
                WheelColumn(label: tr("الشهر", "Month"), value: day.month, range: monthRange, metallic: metallic,
                            text: { value in "\(value) " + domain(hijri ? UmmAlQura.months[value - 1] : DateLabels.gregorianMonths[value - 1]) },
                            change: { update(year: day.year, month: $0, day: day.day) }).frame(width: width * 1.7 / 3.75)
                WheelColumn(label: tr("السنة", "Year"), value: day.year, range: yearRange, metallic: metallic,
                            text: { String($0) }, change: { update(year: $0, month: day.month, day: day.day) }).frame(width: width * 0.8 / 3.75)
            }
                }
            .frame(height: (metallic ? 76 : 72) * wheelScale)
            .padding(metallic ? 3 : 0)
            .background(metallic ? Color.black : .clear, in: RoundedRectangle(cornerRadius: 11))
        }
    }
    private func date(year: Int, month: Int, day: Int) -> Date {
        if hijri {
            return table.date(year: year, month: month, day: min(day, table.monthLength(year: year, month: month)), in: calendar.timeZone) ?? selected
        }
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)),
              let days = calendar.range(of: .day, in: .month, for: first) else { return selected }
        return calendar.date(byAdding: .day, value: min(day, days.count) - 1, to: first) ?? selected
    }
    private func update(year: Int, month: Int, day: Int) {
        selected = min(max(date(year: year, month: month, day: day), table.range.lowerBound), table.range.upperBound)
    }
}

private struct MetalDrumShape: Shape {
    var metallic: Bool
    func path(in rect: CGRect) -> Path {
        guard metallic else { return Path(rect) }
        let margin = rect.width * 0.045
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + margin, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - margin, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - margin, y: rect.maxY), control: CGPoint(x: rect.maxX + margin, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + margin, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + margin, y: rect.minY), control: CGPoint(x: rect.minX - margin, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct WheelColumn: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let metallic: Bool
    let text: (Int) -> String
    let change: (Int) -> Void
    @AppStorage("numberSize") private var numberSize = 19.0
    @Environment(\.hijriPalette) private var palette
    @ScaledMetric private var scale = 1.0
    @State private var editing = false
    var body: some View {
        VStack(spacing: 1) {
            if !metallic { Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.accent) }
            GeometryReader { geometry in
                ZStack {
                    if metallic {
                        MetalDrumShape(metallic: true).fill(LinearGradient(stops: [
                            .init(color: Color(white: 0.07), location: 0), .init(color: Color(white: 0.45), location: 0.12),
                            .init(color: Color(white: 0.77), location: 0.28), .init(color: Color(white: 0.89), location: 0.42),
                            .init(color: Color(white: 0.82), location: 0.62), .init(color: Color(white: 0.75), location: 0.78),
                            .init(color: Color(white: 0.45), location: 0.91), .init(color: Color(white: 0.07), location: 1)
                        ], startPoint: .top, endPoint: .bottom))
                        ForEach([-1, 1], id: \.self) { offset in
                            if range.contains(value + offset) {
                                Text(text(value + offset)).font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Color(white: 0.1)).lineLimit(1).minimumScaleFactor(0.55)
                                    .offset(y: CGFloat(offset) * 25 * scale)
                            }
                        }
                    } else {
                        VStack {
                            Image(systemName: "arrowtriangle.up.fill")
                            Spacer()
                            Image(systemName: "arrowtriangle.down.fill")
                        }.font(.system(size: 10)).foregroundStyle(palette.accent).padding(.vertical, 2)
                    }
                    Text(text(value)).font(.system(size: min(22, max(14, numberSize - 4)), weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.55).padding(.horizontal, 3)
                        .frame(maxWidth: .infinity).frame(height: 28 * scale)
                        .foregroundStyle(metallic ? .white : palette.ink)
                        .background(metallic ? Color(red: 0.19, green: 0.22, blue: 0.25) : palette.selected,
                                    in: RoundedRectangle(cornerRadius: metallic ? 3 : 6))
                        .overlay(RoundedRectangle(cornerRadius: metallic ? 3 : 6).stroke(metallic ? Color.white.opacity(0.3) : palette.outline, lineWidth: 1))
                        .frame(maxHeight: .infinity)
                }
                .clipShape(MetalDrumShape(metallic: metallic))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 12).onEnded { gesture in
                    let steps = Int((-gesture.translation.height / 24).rounded())
                    change(min(max(value + steps, range.lowerBound), range.upperBound))
                })
                .simultaneousGesture(SpatialTapGesture().onEnded { gesture in
                    if gesture.location.y < geometry.size.height * 0.3 { step(-1) }
                    else if gesture.location.y > geometry.size.height * 0.7 { step(1) }
                    else { editing = true }
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label).accessibilityValue(text(value))
                .accessibilityAdjustableAction { direction in
                    switch direction { case .increment: step(1); case .decrement: step(-1); @unknown default: break }
                }
                .accessibilityAction(named: Text(tr("اختيار قيمة", "Choose value"))) { editing = true }
            }.frame(height: (metallic ? 76 : 56) * scale)
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                Picker(label, selection: Binding(get: { value }, set: change)) {
                    ForEach(range, id: \.self) { Text(text($0)).tag($0) }
                }.pickerStyle(.wheel).labelsHidden()
                .navigationTitle(label).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("تم", "Done")) { editing = false } } }
            }.presentationDetents([.height(310)])
        }
    }
    private func step(_ amount: Int) { change(min(max(value + amount, range.lowerBound), range.upperBound)) }
}

struct DateEditor: View {
    let table: UmmAlQura
    @Binding var selected: Date
    @State private var hijri = true
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            DesignPage(title: "") {
                Picker(tr("التقويم", "Calendar"), selection: $hijri) {
                    Text(tr("هجري", "Hijri")).tag(true)
                    Text(tr("ميلادي", "Gregorian")).tag(false)
                }.pickerStyle(.segmented)
                DesignCard { DateWheels(table: table, selected: $selected, hijri: hijri) }
                Button(tr("تاريخ اليوم", "Today")) { selected = min(max(Date(), table.range.lowerBound), table.range.upperBound) }
                    .buttonStyle(RaisedButtonStyle()).frame(maxWidth: .infinity)
            }
            .navigationTitle(tr("اختيار التاريخ", "Choose date"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("تم", "Done")) { dismiss() } } }
        }.modifier(DesignRootStyle())
    }
}

private struct AgeCard: View {
    let table: UmmAlQura
    let selected: Date
    let today: Date
    var body: some View {
        DesignCard(padding: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selected > today ? tr("الوقت المتبقي حتى التاريخ المحدد", "Time until selected date") : tr("العمر", "Age")).font(.subheadline.bold())
                if DateLabels.calendar.isDate(selected, inSameDayAs: today) {
                    Text(tr("حدّد تاريخ ميلادك من التقويم أعلاه", "Select your birth date in the calendar above")).font(.subheadline)
                } else { DurationValues(table: table, start: selected, end: today) }
            }
        }
    }
}

private struct DateComparisonCard: View {
    let table: UmmAlQura
    var stacked = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var editing: Int?
    var body: some View {
        DesignCard(padding: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("الفرق بين تاريخين", "Between two dates")).font(.subheadline.bold())
                Text(tr("إجمالي الأيام: ", "Total days: ") + String(abs(DateLabels.calendar.dateComponents([.day], from: DateLabels.calendar.startOfDay(for: start), to: DateLabels.calendar.startOfDay(for: end)).day ?? 0))).font(.caption)
                if stacked { dateButton(endDate: false); dateButton(endDate: true) }
                else { HStack { dateButton(endDate: false); dateButton(endDate: true) } }
                DurationValues(table: table, start: start, end: end)
            }
        }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            DateEditor(table: table, selected: Binding(get: { editing == 1 ? end : start }, set: { if editing == 1 { end = $0 } else { start = $0 } }))
        }
    }
    private func dateButton(endDate: Bool) -> some View {
        Button { editing = endDate ? 1 : 0 } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(endDate ? tr("إلى", "To") : tr("من", "From"))
                Text(endDate ? end : start, format: .dateTime.day().month().year())
            }.font(.caption).frame(maxWidth: .infinity).padding(.vertical, 6)
        }.buttonStyle(.bordered)
    }
}

private struct DurationValues: View {
    let table: UmmAlQura
    let start: Date
    let end: Date
    @Environment(\.hijriPalette) private var palette
    var body: some View {
        let calendar = DateLabels.calendar
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        VStack(alignment: .leading, spacing: 3) {
            if let value = table.duration(from: first, to: last, in: calendar.timeZone) {
                Text(tr("بالهجري: ", "Hijri: ") + description(value)).foregroundStyle(palette.accent)
            }
            Text(tr("بالميلادي: ", "Gregorian: ") + description(GregorianDateSpan.duration(from: first, to: last, calendar: calendar)))
        }.font(.caption).monospacedDigit().fixedSize(horizontal: false, vertical: true)
    }
    private func description(_ value: DateComponents) -> String {
        tr("\(value.year ?? 0) سنة، \(value.month ?? 0) شهر، \(value.day ?? 0) يوم", "\(value.year ?? 0) yr, \(value.month ?? 0) mo, \(value.day ?? 0) d")
    }
}
