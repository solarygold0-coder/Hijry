import SwiftUI
import UIKit
import WidgetKit

struct HijriDayEntry: TimelineEntry {
    let date: Date
    let label: String

    init(date: Date) {
        self.date = date
        if let day = UmmAlQura.bundled?.convert(date) {
            label = "\(day.day) \(UmmAlQura.months[day.month - 1]) \(day.year)"
        } else {
            label = "خارج نطاق أم القرى"
        }
    }
}

struct HijriProvider: TimelineProvider {
    func placeholder(in context: Context) -> HijriDayEntry { HijriDayEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (HijriDayEntry) -> Void) {
        completion(HijriDayEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HijriDayEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        let upcoming = (1...7).compactMap { cal.date(byAdding: .day, value: $0, to: day) }
        let entries = ([now] + upcoming).map { HijriDayEntry(date: $0) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct HijriWidgetView: View {
    let entry: HijriDayEntry
    var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("هجري", systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
            Text(entry.label).font(.headline).minimumScaleFactor(0.75)
            Text(entry.date, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .environment(\.locale, Locale(identifier: "ar_SA"))
        .environment(\.layoutDirection, .rightToLeft)
    }
    var body: some View {
        if #available(iOS 17, *) {
            content.containerBackground(.fill.tertiary, for: .widget)
        } else {
            content.padding().background(Color(uiColor: .secondarySystemBackground))
        }
    }
}

@main
struct HijriDateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HijriDateWidget", provider: HijriProvider()) { HijriWidgetView(entry: $0) }
            .configurationDisplayName("تاريخ اليوم")
            .description("يعرض تاريخ اليوم حسب تقويم أم القرى.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
