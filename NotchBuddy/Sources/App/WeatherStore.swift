#if !APPSTORE
import SwiftUI
import CoreLocation
import Combine

// MARK: - Weather + best time to run (GitHub build only)

/// Weather from Open-Meteo (free, no account), for the Mac's location (asked once; Tel Aviv
/// if declined). Scores each daylight hour for running — comfortable temperature, little rain,
/// little wind, not too much sun — and shows the best one. Refreshes every 30 min while the
/// pill is active.
@MainActor
final class WeatherStore: NSObject, ObservableObject {
    static let shared = WeatherStore()
    nonisolated static let pillId = "integration_weather"
    nonisolated static let color  = "#60A5FA"

    struct Hour: Identifiable, Equatable {
        var id: Date { time }
        let time: Date
        let temp: Double
        let feels: Double
        let rain: Int        // precipitation probability %
        let wind: Double     // km/h
        let uv: Double
        let code: Int
    }

    struct Day: Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let code: Int
        let high: Double
        let low: Double
        let rain: Int            // max precipitation probability %
        let uv: Double
        let wind: Double
        let sunrise: Date?
        let sunset: Date?
    }

    struct Forecast: Equatable {
        let temp: Double
        let feels: Double
        let code: Int
        let isDay: Bool
        let wind: Double
        let high: Double
        let low: Double
        let sunset: Date?
        let hours: [Hour]          // from this hour on, ~60 h
        let days: [Day]            // today, tomorrow, the day after
        let fetched: Date
    }

    @Published private(set) var forecast: Forecast?
    @Published private(set) var place = ""
    @Published private(set) var failed = false

    private let locator = CLLocationManager()
    private var coordinate: CLLocationCoordinate2D?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    nonisolated private static let fallback = CLLocationCoordinate2D(latitude: 32.0853, longitude: 34.7818)   // Tel Aviv
    nonisolated private static let latKey = "coucou.weather.lat"
    nonisolated private static let lonKey = "coucou.weather.lon"
    nonisolated private static let placeKey = "coucou.weather.place"

    private override init() {
        super.init()
        locator.delegate = self
        locator.desiredAccuracy = kCLLocationAccuracyKilometer
        // The ☁️ tab needs no pill: keep the forecast fresh (one small request every 30 min)
        start()
        AppState.shared.$tasks
            .map { $0.contains { $0.id == Self.pillId } }
            .removeDuplicates()
            .sink { [weak self] loaded in if loaded { self?.syncTaskName() } }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    private func start() {
        refresh()   // straight away with the last known place (or Tel Aviv)
        locate()    // and a precise place when macOS gives one
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            Task { @MainActor in WeatherStore.shared.refresh() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Fresh numbers if the last ones are more than 15 minutes old.
    func refreshIfStale() {
        if let f = forecast, Date().timeIntervalSince(f.fetched) < 900 { return }
        refresh()
    }

    private func locate() {
        switch locator.authorizationStatus {
        case .notDetermined:
            locator.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locator.requestLocation()
        default:
            useFallback()
        }
    }

    private func useFallback() {
        if coordinate == nil {
            coordinate = Self.fallback
            place = "Tel Aviv"
        }
        refresh()
    }

    func refresh() {
        // Never wait on the location: the last place we knew, else Tel Aviv, right away.
        // A real fix (if macOS gives one) refines it in the location callback.
        if coordinate == nil {
            let d = UserDefaults.standard
            if d.object(forKey: Self.latKey) != nil {
                coordinate = CLLocationCoordinate2D(latitude: d.double(forKey: Self.latKey),
                                                    longitude: d.double(forKey: Self.lonKey))
                place = d.string(forKey: Self.placeKey) ?? ""
            } else {
                coordinate = Self.fallback
                place = "Tel Aviv"
            }
        }
        guard let c = coordinate else { return }
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", c.latitude)),
            .init(name: "longitude", value: String(format: "%.3f", c.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day"),
            .init(name: "hourly", value: "temperature_2m,apparent_temperature,precipitation_probability,weather_code,wind_speed_10m,uv_index"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,uv_index_max,wind_speed_10m_max"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "3"),
        ]
        guard let url = comps.url else { return }
        Task {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parsed = Self.parse(json) else {
                failed = true
                return
            }
            failed = false
            forecast = parsed
            syncTaskName()
        }
    }

    // MARK: Parsing

    private static func parse(_ j: [String: Any]) -> Forecast? {
        guard let cur = j["current"] as? [String: Any],
              let hourly = j["hourly"] as? [String: Any],
              let times = hourly["time"] as? [String] else { return nil }
        let offset = j["utc_offset_seconds"] as? Int ?? TimeZone.current.secondsFromGMT()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: offset)

        func d(_ key: String, _ i: Int) -> Double { ((hourly[key] as? [Any])?[i] as? NSNumber)?.doubleValue ?? 0 }
        let now = Date()
        let startOfHour = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        var hours: [Hour] = []
        for (i, t) in times.enumerated() {
            guard let time = f.date(from: t), time >= startOfHour else { continue }
            hours.append(Hour(time: time, temp: d("temperature_2m", i), feels: d("apparent_temperature", i),
                              rain: Int(d("precipitation_probability", i)), wind: d("wind_speed_10m", i),
                              uv: d("uv_index", i), code: Int(d("weather_code", i))))
        }

        let daily = j["daily"] as? [String: Any] ?? [:]
        let high = ((daily["temperature_2m_max"] as? [Any])?.first as? NSNumber)?.doubleValue ?? 0
        let low = ((daily["temperature_2m_min"] as? [Any])?.first as? NSNumber)?.doubleValue ?? 0
        let sunsets = (daily["sunset"] as? [String] ?? []).compactMap { f.date(from: $0) }
        let sunrises = (daily["sunrise"] as? [String] ?? []).compactMap { f.date(from: $0) }

        let dayFormat = DateFormatter()
        dayFormat.dateFormat = "yyyy-MM-dd"
        dayFormat.timeZone = TimeZone(secondsFromGMT: offset)
        func dv(_ key: String, _ i: Int) -> Double { ((daily[key] as? [Any])?[i] as? NSNumber)?.doubleValue ?? 0 }
        let days: [Day] = (daily["time"] as? [String] ?? []).enumerated().compactMap { i, t in
            guard let date = dayFormat.date(from: t) else { return nil }
            return Day(date: date, code: Int(dv("weather_code", i)),
                       high: dv("temperature_2m_max", i), low: dv("temperature_2m_min", i),
                       rain: Int(dv("precipitation_probability_max", i)), uv: dv("uv_index_max", i),
                       wind: dv("wind_speed_10m_max", i),
                       sunrise: i < sunrises.count ? sunrises[i] : nil,
                       sunset: i < sunsets.count ? sunsets[i] : nil)
        }

        return Forecast(
            temp: (cur["temperature_2m"] as? NSNumber)?.doubleValue ?? 0,
            feels: (cur["apparent_temperature"] as? NSNumber)?.doubleValue ?? 0,
            code: (cur["weather_code"] as? NSNumber)?.intValue ?? 0,
            isDay: ((cur["is_day"] as? NSNumber)?.intValue ?? 1) == 1,
            wind: (cur["wind_speed_10m"] as? NSNumber)?.doubleValue ?? 0,
            high: high, low: low,
            sunset: sunsets.first,
            hours: hours,
            days: days,
            fetched: now)
    }

    // MARK: Best time to run

    struct RunPick: Equatable { let hour: Hour; let tomorrow: Bool }

    /// The best daylight hour left today (from the next full hour to sunset), else tomorrow's.
    var bestRun: RunPick? { runOptions.first }

    /// The three best daylight hours, best first: today's remaining ones, or tomorrow's once
    /// today's daylight is over.
    var runOptions: [RunPick] {
        guard let f = forecast else { return [] }
        let cal = Calendar.current
        let now = Date()
        func daylight(_ h: Hour, sunset: Date?) -> Bool {
            let hour = cal.component(.hour, from: h.time)
            if let sunset, h.time >= sunset { return false }
            return hour >= 6 && hour <= 19
        }
        let todaySunset = f.days.first?.sunset ?? f.sunset
        let today = f.hours.filter { $0.time > now && cal.isDateInToday($0.time) && daylight($0, sunset: todaySunset) }
        let pool: [Hour]
        let tomorrow: Bool
        if today.isEmpty {
            let sunset = f.days.dropFirst().first?.sunset
            pool = f.hours.filter { cal.isDateInTomorrow($0.time) && daylight($0, sunset: sunset) }
            tomorrow = true
        } else {
            pool = today
            tomorrow = false
        }
        return pool.sorted { Self.score($0) > Self.score($1) }.prefix(3).map { RunPick(hour: $0, tomorrow: tomorrow) }
    }

    /// Higher is better: feels-like near 12–20 °C, dry, calm, gentle sun.
    static func score(_ h: Hour) -> Double {
        var s = 100.0
        if h.feels < 12 { s -= (12 - h.feels) * 3 }
        if h.feels > 20 { s -= (h.feels - 20) * 4 }
        s -= Double(h.rain) * 0.9
        s -= max(0, h.wind - 15) * 1.5
        s -= max(0, h.uv - 5) * 5
        return s
    }

    // MARK: Pill

    /// The pill reads "22° Clear".
    private func syncTaskName() {
        guard let idx = AppState.shared.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }
        let base = PillCatalog.definition(for: Self.pillId)?.name ?? "Weather"
        let name = forecast.map { "\(Int($0.temp.rounded()))° \(Self.describe($0.code))" } ?? base
        if AppState.shared.tasks[idx].name != name { AppState.shared.tasks[idx].name = name }
    }

    // MARK: WMO weather codes

    static func symbol(_ code: Int, day: Bool = true) -> String {
        switch code {
        case 0:          return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2:       return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:          return "cloud.fill"
        case 45, 48:     return "cloud.fog.fill"
        case 51...57:    return "cloud.drizzle.fill"
        case 61, 63, 66: return "cloud.rain.fill"
        case 65, 67:     return "cloud.heavyrain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 80, 81:     return day ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 82:         return "cloud.heavyrain.fill"
        case 95...99:    return "cloud.bolt.rain.fill"
        default:         return "cloud.fill"
        }
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0:          return String(localized: "Clear")
        case 1:          return String(localized: "Mostly clear")
        case 2:          return String(localized: "Partly cloudy")
        case 3:          return String(localized: "Cloudy")
        case 45, 48:     return String(localized: "Fog")
        case 51...57:    return String(localized: "Drizzle")
        case 61...67:    return String(localized: "Rain")
        case 71...77:    return String(localized: "Snow")
        case 80...82:    return String(localized: "Showers")
        case 85, 86:     return String(localized: "Snow showers")
        case 95...99:    return String(localized: "Thunderstorm")
        default:         return String(localized: "Cloudy")
        }
    }

    static func symbolColor(_ code: Int) -> Color {
        switch code {
        case 0, 1:       return Color(hex: "#FBBF24")
        case 2, 3, 45, 48: return Color(hex: "#C5C8CD")
        case 95...99:    return Color(hex: "#A78BFA")
        case 71...77, 85, 86: return Color(hex: "#E0F2FE")
        default:         return Color(hex: "#60A5FA")
        }
    }
}

// MARK: - Location

extension WeatherStore: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            let s = WeatherStore.shared
            switch status {
            case .authorizedAlways, .authorizedWhenInUse: s.locator.requestLocation()
            case .notDetermined: break
            default: s.useFallback()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coordinate = loc.coordinate
        Task { @MainActor in
            let s = WeatherStore.shared
            s.coordinate = coordinate
            UserDefaults.standard.set(coordinate.latitude, forKey: WeatherStore.latKey)
            UserDefaults.standard.set(coordinate.longitude, forKey: WeatherStore.lonKey)
            s.refresh()
            if let mark = try? await CLGeocoder().reverseGeocodeLocation(loc).first {
                s.place = mark.locality ?? mark.name ?? ""
                UserDefaults.standard.set(s.place, forKey: WeatherStore.placeKey)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in WeatherStore.shared.useFallback() }
    }
}

// MARK: - Card

struct WeatherCardView: View {
    @ObservedObject private var store = WeatherStore.shared

    var body: some View {
        Group {
            if let f = store.forecast {
                content(f)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weather")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Text(store.failed ? String(localized: "Couldn't get the forecast. Checking again soon.")
                                      : String(localized: "Getting the forecast…"))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                .padding(.top, 10)
                .padding(.leading, 108)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { store.refreshIfStale() }
    }

    private func content(_ f: WeatherStore.Forecast) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: WeatherStore.symbol(f.code, day: f.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 24))
                    .foregroundColor(WeatherStore.symbolColor(f.code))
                    .frame(width: 30)
                Text("\(Int(f.temp.rounded()))°")
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(Color(hex: "#F5F6F8"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(WeatherStore.describe(f.code) + (store.place.isEmpty ? "" : " · \(store.place)"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#E4E6EA"))
                        .lineLimit(1)
                    Text("feels \(Int(f.feels.rounded()))° · H \(Int(f.high.rounded()))° L \(Int(f.low.rounded()))°")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)
                }
            }
            rainBars(Array(f.hours.prefix(10)))
            runLine
        }
        .padding(.top, 6)
        .padding(.leading, 108)
        .padding(.trailing, 30)   // the ↗ button sits top-right
    }

    /// Rain chance for the next 10 hours, one bar each.
    private func rainBars(_ hours: [WeatherStore.Hour]) -> some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(hours) { h in
                VStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "#60A5FA").opacity(h.rain > 0 ? 0.35 + Double(h.rain) / 160 : 0.15))
                        .frame(width: 13, height: max(2, CGFloat(h.rain) / 100 * 14))
                    Text(h.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                        .font(.system(size: 7).monospacedDigit())
                        .foregroundColor(Color(hex: "#5F646D"))
                }
                .help("\(h.time.formatted(date: .omitted, time: .shortened)) · \(Int(h.temp.rounded()))° · \(h.rain)% rain")
            }
        }
        .frame(height: 24, alignment: .bottom)
    }

    @ViewBuilder private var runLine: some View {
        if let pick = store.bestRun {
            let h = pick.hour
            HStack(spacing: 4) {
                Image(systemName: "figure.run").font(.system(size: 9, weight: .semibold))
                Text(pick.tomorrow ? String(localized: "Best run tomorrow") : String(localized: "Best run"))
                    .font(.system(size: 10.5, weight: .semibold))
                Text("\(h.time.formatted(date: .omitted, time: .shortened)) · \(Int(h.feels.rounded()))° · \(h.rain)% rain")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundColor(Color(hex: "#C5C8CD"))
            }
            .foregroundColor(Color(hex: "#34D399"))
            .lineLimit(1)
            .help(String(localized: "Picked for a comfortable temperature, little rain, little wind and gentle sun"))
        }
    }
}
#endif
