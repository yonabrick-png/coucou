#if !APPSTORE
import SwiftUI

// MARK: - Weather tab (the big view, GitHub build only)

/// Weather with room to breathe, in the spirit of Apple's Weather: a sky tinted by the
/// conditions, a big thin temperature next to a glowing icon, the next 12 hours as a smooth
/// curve, the best hours to run, and three days with temperature-range bars.
struct WeatherFullView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = WeatherStore.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            if let f = store.forecast {
                WeatherSky(code: f.code, isDay: f.isDay)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .allowsHitTesting(false)
            }
            Group {
                if let f = store.forecast {
                    HStack(alignment: .top, spacing: 16) {
                        now(f).frame(width: 214)
                        VStack(alignment: .leading, spacing: 8) {
                            runCard
                            WeatherHourlyCurve(hours: Array(f.hours.prefix(12)))
                                .frame(height: 74)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(glass(radius: 12))
                            days(f)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Image(systemName: "cloud.sun.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 28))
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

    private func glass(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    // MARK: Left: now

    private func now(_ f: WeatherStore.Forecast) -> some View {
        let today = f.days.first
        let tint = WeatherStore.symbolColor(f.code)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: "location.fill").font(.system(size: 8.5))
                    .foregroundColor(Color.white.opacity(0.7))
                Text(store.place.isEmpty ? String(localized: "Weather") : store.place)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Spacer(minLength: 4)
                Button { store.refresh() } label: {
                    HStack(spacing: 3) {
                        Text(f.fetched.formatted(date: .omitted, time: .shortened))
                        Image(systemName: "arrow.clockwise").font(.system(size: 7.5, weight: .bold))
                    }
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundColor(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Updated at this time · click to refresh"))
            }

            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    // Soft glow in the condition's colour
                    Circle()
                        .fill(RadialGradient(colors: [tint.opacity(0.45), .clear],
                                             center: .center, startRadius: 2, endRadius: 34))
                        .frame(width: 68, height: 68)
                    Image(systemName: WeatherStore.symbol(f.code, day: f.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 38))
                        .foregroundColor(tint)
                        .symbolEffect(.breathe.plain, options: .repeating)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: -2) {
                    Text("\(Int(f.temp.rounded()))°")
                        .font(.system(size: 48, weight: .thin, design: .rounded).monospacedDigit())
                        .foregroundColor(.white)
                    Text(WeatherStore.describe(f.code))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                }
            }

            HStack(spacing: 8) {
                Text("Feels \(Int(f.feels.rounded()))°")
                Text("H \(Int(f.high.rounded()))°")
                Text("L \(Int(f.low.rounded()))°")
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundColor(Color.white.opacity(0.65))

            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    tile("wind", "#7DD3FC", "\(Int(f.wind.rounded()))", "km/h")
                    tile("sun.max.fill", "#FBBF24", today.map { String(format: "%.0f", $0.uv) } ?? "–", "UV")
                }
                GridRow {
                    tile("drop.fill", "#60A5FA", today.map { "\($0.rain)%" } ?? "–", String(localized: "rain"))
                    tile("sunset.fill", "#FB923C",
                         (today?.sunset ?? f.sunset).map { $0.formatted(date: .omitted, time: .shortened) } ?? "–", "")
                }
            }
        }
    }

    private func tile(_ icon: String, _ tint: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: tint))
                .frame(width: 15)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(width: 104, alignment: .leading)
        .background(glass(radius: 9))
    }

    // MARK: Right: run, hours, days

    @ViewBuilder private var runCard: some View {
        let options = store.runOptions
        if let best = options.first {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color(hex: "#34D399").opacity(0.18))
                    Image(systemName: "figure.run")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#34D399"))
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(best.tomorrow ? String(localized: "Best run tomorrow") : String(localized: "Best run today"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Color(hex: "#34D399"))
                    Text(best.hour.time.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.white)
                    Text("\(Int(best.hour.feels.rounded()))° · \(best.hour.rain)% rain · \(Int(best.hour.wind.rounded())) km/h")
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundColor(Color.white.opacity(0.6))
                }
                Spacer(minLength: 4)
                if options.count > 1 {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(String(localized: "also good"))
                            .font(.system(size: 8.5))
                            .foregroundColor(Color.white.opacity(0.4))
                        ForEach(Array(options.dropFirst().enumerated()), id: \.offset) { _, pick in
                            Text("\(pick.hour.time.formatted(date: .omitted, time: .shortened)) · \(Int(pick.hour.feels.rounded()))°")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundColor(Color.white.opacity(0.75))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Color(hex: "#34D399").opacity(0.1)))
                        }
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color(hex: "#34D399").opacity(0.16), Color(hex: "#34D399").opacity(0.04)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#34D399").opacity(0.28), lineWidth: 1))
            )
            .help(String(localized: "Picked for a comfortable temperature (12–20°), little rain, little wind and gentle sun"))
        }
    }

    /// Three days with Apple-Weather-style range bars on a shared scale.
    private func days(_ f: WeatherStore.Forecast) -> some View {
        let lo = f.days.map(\.low).min() ?? 0
        let hi = f.days.map(\.high).max() ?? 1
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(f.days) { d in
                HStack(spacing: 8) {
                    Text(Self.dayName(d.date))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 62, alignment: .leading)
                    Image(systemName: WeatherStore.symbol(d.code))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 11.5))
                        .foregroundColor(WeatherStore.symbolColor(d.code))
                        .frame(width: 18)
                    Text(d.rain >= 10 ? "\(d.rain)%" : "")
                        .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                        .foregroundColor(Color(hex: "#60A5FA"))
                        .frame(width: 26, alignment: .leading)
                    Text("\(Int(d.low.rounded()))°")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(Color.white.opacity(0.5))
                        .frame(width: 24, alignment: .trailing)
                    WeatherRangeBar(low: d.low, high: d.high, scaleLow: lo, scaleHigh: hi,
                                    now: Calendar.current.isDateInToday(d.date) ? f.temp : nil)
                        .frame(height: 5)
                    Text("\(Int(d.high.rounded()))°")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                        .frame(width: 24, alignment: .leading)
                }
                .help(WeatherStore.describe(d.code))
            }
        }
    }

    private static func dayName(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "Today") }
        if cal.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

// MARK: - Sky

/// A soft gradient behind everything, tinted by the weather and the time of day.
struct WeatherSky: View {
    let code: Int
    let isDay: Bool

    var body: some View {
        let (top, bottom) = colors
        LinearGradient(colors: [top, bottom], startPoint: .topTrailing, endPoint: .bottomLeading)
            .opacity(0.55)
            .animation(.easeInOut(duration: 0.6), value: code)
    }

    private var colors: (Color, Color) {
        if !isDay {
            switch code {
            case 95...99:  return (Color(hex: "#2E1065"), Color(hex: "#0B0C10"))
            case 51...82:  return (Color(hex: "#1E293B"), Color(hex: "#0B0C10"))
            default:       return (Color(hex: "#1E1B4B"), Color(hex: "#0B0C10"))
            }
        }
        switch code {
        case 0, 1:            return (Color(hex: "#0EA5E9"), Color(hex: "#1E3A8A"))
        case 2:               return (Color(hex: "#38BDF8"), Color(hex: "#334155"))
        case 3, 45, 48:       return (Color(hex: "#64748B"), Color(hex: "#1E293B"))
        case 51...67, 80...82: return (Color(hex: "#475569"), Color(hex: "#0F172A"))
        case 71...77, 85, 86: return (Color(hex: "#94A3B8"), Color(hex: "#334155"))
        case 95...99:         return (Color(hex: "#6D28D9"), Color(hex: "#1E1B4B"))
        default:              return (Color(hex: "#475569"), Color(hex: "#1E293B"))
        }
    }
}

// MARK: - Hourly curve

/// The next hours as a smooth temperature curve with a soft fill, the icon and temperature
/// above each point, and the rain chance as small bars along the bottom.
struct WeatherHourlyCurve: View {
    let hours: [WeatherStore.Hour]

    var body: some View {
        GeometryReader { geo in
            let n = max(1, hours.count)
            let w = geo.size.width
            let step = w / CGFloat(n)
            let temps = hours.map(\.temp)
            let lo = (temps.min() ?? 0) - 1
            let hi = (temps.max() ?? 1) + 1
            let top: CGFloat = 26        // room for icon + temperature
            let bottom: CGFloat = 22     // room for rain + hour
            let chartH = max(10, geo.size.height - top - bottom)
            let points: [CGPoint] = hours.enumerated().map { i, h in
                let x = step * (CGFloat(i) + 0.5)
                let y = top + chartH * (1 - CGFloat((h.temp - lo) / max(0.1, hi - lo)))
                return CGPoint(x: x, y: y)
            }

            ZStack(alignment: .topLeading) {
                // Fill under the curve
                Self.smoothPath(points, closeTo: top + chartH)
                    .fill(LinearGradient(colors: [Color(hex: "#FBBF24").opacity(0.28), Color(hex: "#FBBF24").opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                // The curve
                Self.smoothPath(points, closeTo: nil)
                    .stroke(LinearGradient(colors: [Color(hex: "#FBBF24"), Color(hex: "#FB923C")],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .shadow(color: Color(hex: "#FBBF24").opacity(0.5), radius: 3)

                ForEach(Array(hours.enumerated()), id: \.offset) { i, h in
                    let p = points[i]
                    // Dot, temperature and icon above it
                    Circle()
                        .fill(i == 0 ? Color.white : Color(hex: "#FBBF24"))
                        .frame(width: i == 0 ? 6 : 4, height: i == 0 ? 6 : 4)
                        .position(p)
                    Text("\(Int(h.temp.rounded()))°")
                        .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                        .position(x: p.x, y: p.y - 9)
                    Image(systemName: WeatherStore.symbol(h.code, day: Self.isDay(h)))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 10))
                        .foregroundColor(WeatherStore.symbolColor(h.code))
                        .position(x: p.x, y: 6)
                    // Rain chance bar + hour along the bottom
                    let rainH = CGFloat(h.rain) / 100 * 8
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: "#60A5FA").opacity(h.rain > 0 ? 0.85 : 0.15))
                        .frame(width: step * 0.42, height: max(1.5, rainH))
                        .position(x: p.x, y: geo.size.height - 13 - max(1.5, rainH) / 2)
                    Text(i == 0 ? String(localized: "Now") : h.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                        .font(.system(size: 8.5, weight: i == 0 ? .bold : .regular).monospacedDigit())
                        .foregroundColor(Color.white.opacity(i == 0 ? 0.95 : 0.5))
                        .position(x: p.x, y: geo.size.height - 4)
                }
            }
            .help(hours.map { "\($0.time.formatted(date: .omitted, time: .shortened)) \(Int($0.temp.rounded()))° \($0.rain)%" }
                       .joined(separator: " · "))
        }
    }

    /// A curve through the points (Catmull-Rom style), closed down to `closeTo` for the fill.
    static func smoothPath(_ pts: [CGPoint], closeTo baseline: CGFloat?) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for i in 1..<max(1, pts.count) where pts.count > 1 {
            let p0 = pts[max(0, i - 2)], p1 = pts[i - 1], p2 = pts[i], p3 = pts[min(pts.count - 1, i + 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        if let baseline, let last = pts.last {
            path.addLine(to: CGPoint(x: last.x, y: baseline))
            path.addLine(to: CGPoint(x: first.x, y: baseline))
            path.closeSubpath()
        }
        return path
    }

    static func isDay(_ h: WeatherStore.Hour) -> Bool {
        let hour = Calendar.current.component(.hour, from: h.time)
        return hour >= 6 && hour < 19
    }
}

// MARK: - Range bar

/// A day's low–high on the three days' shared scale, coloured cool to warm, with a dot for
/// the temperature now on today's bar.
struct WeatherRangeBar: View {
    let low: Double
    let high: Double
    let scaleLow: Double
    let scaleHigh: Double
    let now: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = max(0.1, scaleHigh - scaleLow)
            let x0 = CGFloat((low - scaleLow) / span) * w
            let x1 = CGFloat((high - scaleLow) / span) * w
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [Self.color(for: low), Self.color(for: high)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(5, x1 - x0))
                    .offset(x: x0)
                if let now {
                    let xn = min(w - 5, max(0, CGFloat((now - scaleLow) / span) * w - 2.5))
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                        .frame(width: 6, height: 6)
                        .offset(x: xn)
                }
            }
        }
    }

    /// Blue when cool, green when mild, amber then orange when warm.
    static func color(for t: Double) -> Color {
        switch t {
        case ..<10:  return Color(hex: "#60A5FA")
        case ..<16:  return Color(hex: "#38BDF8")
        case ..<21:  return Color(hex: "#34D399")
        case ..<26:  return Color(hex: "#FBBF24")
        case ..<31:  return Color(hex: "#FB923C")
        default:     return Color(hex: "#F4505E")
        }
    }
}
#endif
