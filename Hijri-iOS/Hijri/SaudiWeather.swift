import BackgroundTasks
import CoreLocation
import SwiftUI
import UserNotifications
import WeatherKit

struct WeatherPlace: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let latitude: Double
    let longitude: Double

    static let cities = [
        WeatherPlace(id: "riyadh", title: "الرياض", latitude: 24.7136, longitude: 46.6753),
        WeatherPlace(id: "jeddah", title: "جدة", latitude: 21.4858, longitude: 39.1925),
        WeatherPlace(id: "abha", title: "أبها", latitude: 18.2164, longitude: 42.5053),
        WeatherPlace(id: "dammam", title: "الدمام", latitude: 26.4207, longitude: 50.0888),
        WeatherPlace(id: "medina", title: "المدينة المنورة", latitude: 24.5247, longitude: 39.5692),
        WeatherPlace(id: "mecca", title: "مكة المكرمة", latitude: 21.3891, longitude: 39.8579)
    ]
}

@MainActor
final class WeatherStore: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let refreshIdentifier = (Bundle.main.bundleIdentifier ?? "com.taqwim.ummalqura") + ".weather-refresh"
    private let defaults = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()
    private let location = CLLocationManager()
    private let forecastPrefix = "hijri.weather."
    private let weatherService = WeatherService.shared
    private var wantsLocation = false
    private var refreshTask: Task<Void, Never>?

    @Published private(set) var place = WeatherPlace.cities[0]
    @Published private(set) var forecast: [DayWeather] = []
    @Published private(set) var attribution: WeatherAttribution?
    @Published private(set) var message: String?
    @Published private(set) var locating = false
    @Published private(set) var alerts = false

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyHundredMeters
        alerts = defaults.bool(forKey: "hijri.weatherAlerts")
        let cityID = defaults.string(forKey: "weatherCity")
        if let data = defaults.data(forKey: "hijri.weatherLocation"),
           let saved = try? JSONDecoder().decode(WeatherPlace.self, from: data),
           hasLocationPermission {
            place = saved
        } else {
            place = WeatherPlace.cities.first { $0.id == cityID } ?? WeatherPlace.cities[0]
        }
    }

    private var hasLocationPermission: Bool {
        location.authorizationStatus == .authorizedWhenInUse || location.authorizationStatus == .authorizedAlways
    }

    func selectCity(_ id: String) {
        guard let city = WeatherPlace.cities.first(where: { $0.id == id }) else { return }
        defaults.set(id, forKey: "weatherCity")
        defaults.removeObject(forKey: "hijri.weatherLocation")
        wantsLocation = false
        locating = false
        changePlace(city)
    }

    func useLocation() {
        wantsLocation = true
        locating = true
        message = nil
        locationManagerDidChangeAuthorization(location)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wantsLocation else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .restricted, .denied: locationFailed("اسمح باستخدام الموقع من الإعدادات أو اختر مدينة.")
        @unknown default: locationFailed("تعذّر التحقق من إذن الموقع.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsLocation else { return }
        guard let fix = locations.last, fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= 50_000, abs(fix.timestamp.timeIntervalSinceNow) <= 600 else {
            locationFailed("تعذّر الحصول على موقع حديث. حاول مرة أخرى.")
            return
        }
        wantsLocation = false
        locating = false
        let point = WeatherPlace(id: "location", title: "موقعك المحدد",
                                 latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
        if let data = try? JSONEncoder().encode(point) { defaults.set(data, forKey: "hijri.weatherLocation") }
        changePlace(point)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if wantsLocation { locationFailed("تعذّر الحصول على الموقع.") }
    }

    private func locationFailed(_ text: String) {
        wantsLocation = false
        locating = false
        message = text
    }

    private func changePlace(_ point: WeatherPlace) {
        place = point
        forecast = []
        attribution = nil
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.removeForecastNotices()
            guard !Task.isCancelled, self.place == point else { return }
            await self.refresh()
        }
    }

    func setAlerts(_ enabled: Bool) async {
        if enabled {
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                    message = "اسمح بإشعارات هجري من الإعدادات."
                    return
                }
            } catch {
                message = "تعذّر طلب إذن الإشعارات."
                return
            }
        }
        alerts = enabled
        defaults.set(enabled, forKey: "hijri.weatherAlerts")
        if enabled {
            submitBackgroundRefresh()
            startRefresh()
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshIdentifier)
            await removeForecastNotices()
        }
    }

    func startRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
        }
    }

    func refresh() async {
        if place.id == "location" && !hasLocationPermission {
            defaults.removeObject(forKey: "hijri.weatherLocation")
            let id = defaults.string(forKey: "weatherCity")
            place = WeatherPlace.cities.first { $0.id == id } ?? WeatherPlace.cities[0]
        }
        let requestedPlace = place
        message = nil
        do {
            let position = CLLocation(latitude: requestedPlace.latitude, longitude: requestedPlace.longitude)
            let weather = try await weatherService.weather(for: position)
            let credit = try await weatherService.attribution
            guard !Task.isCancelled, requestedPlace == place else { return }
            let days = Array(weather.dailyForecast.forecast.prefix(3))
            attribution = credit
            forecast = Array(days.prefix(2))
            if alerts { await scheduleForecasts(days, for: requestedPlace) }
        } catch {
            if !Task.isCancelled && requestedPlace == place { message = "تعذّر تحديث الطقس." }
        }
    }

    func submitBackgroundRefresh() {
        guard alerts else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func removeForecastNotices() async {
        let pending = await center.pendingNotificationRequests()
        guard !Task.isCancelled else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(forecastPrefix) })
    }

    private func scheduleForecasts(_ days: [DayWeather], for requestedPlace: WeatherPlace) async {
        let existing = await center.pendingNotificationRequests()
        guard alerts, requestedPlace == place, !Task.isCancelled else { return }
        let identifiers = existing.map(\.identifier).filter { $0.hasPrefix(forecastPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        let calendar = SaudiCalendar.calendar
        let now = Date()
        let remaining = max(0, 62 - (existing.count - identifiers.count))
        for day in days.dropFirst().prefix(remaining) {
            guard alerts, requestedPlace == place, !Task.isCancelled,
                  let previousDay = calendar.date(byAdding: .day, value: -1, to: day.date),
                  let send = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previousDay),
                  send > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "طقس غدًا · " + requestedPlace.title
            let phenomenon = Self.phenomenon(day.condition)
            content.body = Self.temperatures(day) + (phenomenon.map { " · " + $0 } ?? "")
            content.sound = .default
            content.threadIdentifier = "hijri.weather"
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: send)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            let identifier = forecastPrefix + String(Int(send.timeIntervalSince1970))
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            if !alerts || requestedPlace != place || Task.isCancelled {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                return
            }
        }
    }

    static func temperatures(_ day: DayWeather) -> String {
        func degrees(_ value: Measurement<UnitTemperature>) -> String {
            "\(Int(value.converted(to: .celsius).value.rounded()))°"
        }
        return "الصغرى \(degrees(day.lowTemperature)) · الكبرى \(degrees(day.highTemperature))"
    }

    static func phenomenon(_ condition: WeatherCondition) -> String? {
        switch condition {
        case .blowingDust: return "غبار أو عاصفة رملية"
        case .drizzle, .rain, .heavyRain, .sunShowers, .freezingDrizzle, .freezingRain: return "أمطار"
        case .thunderstorms, .strongStorms, .isolatedThunderstorms, .scatteredThunderstorms: return "عواصف رعدية"
        case .snow, .heavySnow, .flurries, .sunFlurries, .blizzard, .blowingSnow, .sleet, .wintryMix: return "ثلوج"
        case .hail: return "بَرَد"
        case .foggy: return "ضباب"
        case .windy, .hurricane, .tropicalStorm: return "رياح قوية"
        case .hot: return "حرارة مرتفعة"
        case .frigid: return "برودة شديدة"
        default: return nil
        }
    }
}

struct SaudiWeather: View {
    @ObservedObject var store: WeatherStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var asking = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("الموقع", selection: Binding(get: { store.place.id }, set: { store.selectCity($0) })) {
                    ForEach(WeatherPlace.cities) { Text($0.title).tag($0.id) }
                    if store.place.id == "location" { Text(store.place.title).tag("location") }
                }
                Button(store.locating ? "جارٍ تحديد الموقع…" : "استخدم موقعي") { store.useLocation() }
                    .disabled(store.locating)
                if let message = store.message {
                    Text(message).foregroundStyle(.secondary)
                    Button("إعادة المحاولة") { store.startRefresh() }
                } else if store.forecast.isEmpty {
                    ProgressView("جارٍ تحديث الطقس…")
                }
                ForEach(Array(store.forecast.enumerated()), id: \.offset) { index, day in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(index == 0 ? "اليوم" : "غدًا").font(.headline)
                        Text(WeatherStore.temperatures(day))
                        if let phenomenon = WeatherStore.phenomenon(day.condition) {
                            Label(phenomenon, systemImage: day.symbolName).foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle("تنبيه طقس الغد", isOn: Binding(get: { store.alerts }, set: { enabled in
                    asking = true
                    Task {
                        await store.setAlerts(enabled)
                        asking = false
                    }
                }))
                .disabled(asking)
                if let attribution = store.attribution {
                    Link(destination: attribution.legalPageURL) {
                        AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkLightURL : attribution.combinedMarkDarkURL) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Text("Apple Weather")
                        }
                        .frame(maxWidth: 150, minHeight: 24, maxHeight: 36)
                    }
                }
            }
            .navigationTitle("الطقس")
            .onAppear { if store.forecast.isEmpty { store.startRefresh() } }
        }
    }
}
