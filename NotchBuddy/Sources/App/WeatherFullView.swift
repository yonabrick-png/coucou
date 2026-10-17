#if !APPSTORE
import SwiftUI

// MARK: - Weather tab (the big view, GitHub build only)

/// Weather with room to breathe: now (big), the day's details, the best hours to run,
/// the next 12 hours and three days.
struct WeatherFullView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = WeatherStore.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            Group {
                if let f = store.forecast {
                    HStack(alignment: .top, spacing: 14) {
                        now(f).frame(width: 222)
                        Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                        VStack(alignment: .leading, spacing: 9) {
                            runCard
                            hourly(Array(f.hours.prefix(12)))
                            days(f.days)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Image(systemName: "cloud.sun.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 26))
                        Text(store.failed ? String(localized: "Couldn't get the forecast. Checking again soon.")
                                          : String(localized: "Getting the forecast…"))
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#8E939C"))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .padding(.bottom, 10)
        .onAppear { store.refreshIfStale() }
    }

    // MARK: Left: now

    private func now(_ f: WeatherStore.Forecast) -> some View {
        let today = f.days.first
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill").font(.system(size: 8.5))
                    .foregroundColor(Color(hex: WeatherStore.color))
                Text(store.place.isEmpty ? String(localized: "Weather") : store.place)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Spacer(minLength: 4)
                Text(String(localized: "Updated \(f.fetched.formatted(date: .omitted, time: .shortened))"))
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#5F646D"))
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Refresh now"))
            }

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: WeatherStore.symbol(f.code, day: f.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 40))
                    .foregroundColor(WeatherStore.symbolColor(f.code))
                    .frame(width: 52)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(f.temp.rounded()))°")
                        .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Text(WeatherStore.describe(f.code))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#E4E6EA"))
                }
            }
            Text("feels \(Int(f.feels.rounded()))° · H \(Int(f.high.rounded()))° L \(Int(f.low.rounded()))°")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(Color(hex: "#8E939C"))

            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    tile("wind", "#7DD3FC", "\(Int(f.wind.rounded()))", "km/h")
                    tile("sun.max.fill", "#FBBF24", today.map { String(format: "%.0f", $0.uv) } ?? "–", "UV max")
                }
                GridRow {
                    tile("drop.fill", "#60A5FA", today.map { "\($0.rain)%" } ?? "–", String(localized: "rain"))
                    tile("sunset.fill", "#FB923C",
                         (today?.sunset ?? f.sunset).map { $0.formatted(date: .omitted, time: .shortened) } ?? "–",
                         String(localized: "sunset"))
                }
            }
        }
    }

    private func tile(_ icon: String, _ tint: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 10.5))
                .foregroundColor(Color(hex: tint))
                .frame(width: 14)
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(Color(hex: "#F1F2F4"))
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(Color(hex: "#6B7079"))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .frame(width: 108, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }

    // MARK: Right: run, hours, days

    @ViewBuilder private var runCard: some View {
        let options = store.runOptions
        if let best = options.first {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "figure.run").font(.system(size: 10, weight: .semibold))
                    Text(best.tomorrow ? String(localized: "Best time to run tomorrow") : String(localized: "Best time to run today"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#34D399"))
                HStack(spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, pick in
                        runChip(pick.hour, best: i == 0)
                    }
                }
            }
            .help(String(localized: "Picked for a comfortable temperature (12–20°), little rain, little wind and gentle sun"))
        }
    }

    private func runChip(_ h: WeatherStore.Hour, best: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(h.time.formatted(date: .omitted, time: .shortened))
                .font(.system(size: best ? 13 : 11.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(Color(hex: best ? "#F5F6F8" : "#C5C8CD"))
            Text("\(Int(h.feels.rounded()))° · \(h.rain)% rain")
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundColor(Color(hex: "#8E939C"))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color(hex: "#34D399").opacity(best ? 0.16 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(hex: "#34D399").opacity(best ? 0.45 : 0), lineWidth: 1))
    }

    /// The next 12 hours: hour, icon, temperature, rain chance.
    private func hourly(_ hours: [WeatherStore.Hour]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.offset) { i, h in
                VStack(spacing: 3) {
                    Text(i == 0 ? String(localized: "Now") : h.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                        .font(.system(size: 9, weight: i == 0 ? .bold : .regular).monospacedDigit())
                        .foregroundColor(Color(hex: i == 0 ? "#F5F6F8" : "#8E939C"))
                    Image(systemName: WeatherStore.symbol(h.code, day: Self.isDay(h)))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 12))
                        .foregroundColor(WeatherStore.symbolColor(h.code))
                        .frame(height: 14)
                    Text("\(Int(h.temp.rounded()))°")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(Color(hex: "#F1F2F4"))
                    Text(h.rain > 0 ? "\(h.rain)%" : " ")
                        .font(.system(size: 8.5).monospacedDigit())
                        .foregroundColor(Color(hex: "#60A5FA"))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
    }

    /// Today, tomorrow, the day after.
    private func days(_ days: [WeatherStore.Day]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(days) { d in
                HStack(spacing: 8) {
                    Text(Self.dayName(d.date))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#E4E6EA"))
                        .frame(width: 66, alignment: .leading)
                    Image(systemName: WeatherStore.symbol(d.code))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 11))
                        .foregroundColor(WeatherStore.symbolColor(d.code))
                        .frame(width: 18)
                    Text(WeatherStore.describe(d.code))
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if d.rain > 0 {
                        Text("\(d.rain)%")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundColor(Color(hex: "#60A5FA"))
                    }
                    Text("\(Int(d.low.rounded()))° – \(Int(d.high.rounded()))°")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(Color(hex: "#F1F2F4"))
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
    }

    // MARK: Helpers

    private static func dayName(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "Today") }
        if cal.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.weekday(.wide))
    }

    private static func isDay(_ h: WeatherStore.Hour) -> Bool {
        let hour = Calendar.current.component(.hour, from: h.time)
        return hour >= 6 && hour < 19
    }
}
#endif
