#if !APPSTORE
import SwiftUI

// MARK: - Daily brief (GitHub build only)

/// The first time the Mac is opened each day (first unlock, or Coucou starting), the notch
/// slides down with a small brief: greeting, weather, today's events, Garmin, race or best
/// run, and today's reminders. Once a day; "Show daily brief" in the menu brings it back.
@MainActor
enum DailyBrief {
    private static let lastDayKey = "coucou.brief.lastDay"

    private static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// Shows the brief if it hasn't been shown today, after `delay` seconds.
    static func showIfFirstToday(after delay: Double) {
        guard UserDefaults.standard.string(forKey: lastDayKey) != dayKey() else { return }
        // Quiet modes keep it for later: it shows when you're back in Everything
        guard NotchModes.shared.allowsBrief else { return }
        UserDefaults.standard.set(dayKey(), forKey: lastDayKey)
        show(after: delay)
    }

    /// Shows it now (menu item, or the first open of the day).
    static func show(after delay: Double = 0) {
        // Freshen what the brief reads while it waits
        WeatherStore.shared.refreshIfStale()
        GarminStore.shared.refresh()
        CalendarController.shared.reload()
        Task {
            try? await Task.sleep(for: .seconds(max(0.8, delay)))
            SoundEngine.shared.play("greet")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.brief)
        }
    }
}

// MARK: - The brief

struct DailyBriefView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var weather = WeatherStore.shared
    @ObservedObject private var garmin = GarminStore.shared
    @ObservedObject private var calendar = CalendarController.shared
    @ObservedObject private var notes = NotesStore.shared

    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: .soft)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(greeting)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.55))
                }
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
                        BriefCard(card: card)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.08 * Double(i) + 0.15),
                                       value: appeared)
                    }
                }
            }
            .padding(.leading, 104)
            .padding(.trailing, 16)
            .padding(.top, 12)
        }
        .padding(.bottom, 10)
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { state.view = .overview }
        }
    }

    // MARK: Greeting

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        let hello: String
        switch hour {
        case 5..<12:  hello = String(localized: "Good morning")
        case 12..<18: hello = String(localized: "Good afternoon")
        default:      hello = String(localized: "Good evening")
        }
        return name.isEmpty ? hello : "\(hello), \(name)"
    }

    // MARK: Cards

    private var cards: [BriefCard.Content] {
        var out: [BriefCard.Content] = []

        // Weather
        if let f = weather.forecast {
            let rain = f.days.first?.rain ?? 0
            out.append(.init(icon: WeatherStore.symbol(f.code, day: f.isDay), multicolor: true,
                             tint: "#FBBF24",
                             title: "\(Int(f.temp.rounded()))° \(WeatherStore.describe(f.code))",
                             line: "H \(Int(f.high.rounded()))° L \(Int(f.low.rounded()))°" + (rain >= 10 ? " · \(rain)% rain" : "")))
        }

        // Today's calendar
        let now = Date()
        let todays = calendar.events.filter { Calendar.current.isDateInToday($0.start) && !$0.isAllDay }
        if calendar.access == .granted {
            if let next = todays.first(where: { $0.end > now }) {
                out.append(.init(icon: "calendar", tint: "#FF453A",
                                 title: todays.count == 1 ? String(localized: "1 event today")
                                                          : String(localized: "\(todays.count) events today"),
                                 line: "\(next.start.formatted(date: .omitted, time: .shortened)) \(next.title)"))
            } else {
                out.append(.init(icon: "calendar", tint: "#FF453A",
                                 title: String(localized: "Free day"), line: String(localized: "Nothing on the calendar")))
            }
        }

        // Body (Garmin)
        if let g = garmin.snapshot, let ready = g.readiness {
            out.append(.init(icon: "heart.fill", tint: GarminStore.color,
                             colorOverride: GarminStore.readinessColor(g.readinessLevel),
                             title: String(localized: "Ready \(ready) · \(g.readinessLevel.capitalized)"),
                             line: g.sleep.map { String(localized: "Sleep \($0)") } ?? ""))
        }

        // Race countdown, else the best time to run
        if let race = garmin.snapshot?.race, let date = race.date,
           let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now),
                                                     to: Calendar.current.startOfDay(for: date)).day, days >= 0, days <= 14 {
            out.append(.init(icon: "flag.checkered", tint: "#F5A524",
                             title: days == 0 ? String(localized: "Race today!") : String(localized: "Race in \(days) days"),
                             line: "\(race.distance) m · \(race.target)"))
        } else if let run = weather.bestRun {
            out.append(.init(icon: "figure.run", tint: "#34D399",
                             title: run.tomorrow ? String(localized: "Run tomorrow") : String(localized: "Best run"),
                             line: "\(run.hour.time.formatted(date: .omitted, time: .shortened)) · \(Int(run.hour.feels.rounded()))°"))
        }

        // Reminders today
        let reminders = notes.notes.filter {
            !$0.done && ($0.remindAt.map { Calendar.current.isDateInToday($0) } ?? false)
        }
        if !reminders.isEmpty {
            out.append(.init(icon: "bell.fill", tint: "#FBBF24",
                             title: reminders.count == 1 ? String(localized: "1 reminder")
                                                         : String(localized: "\(reminders.count) reminders"),
                             line: reminders[0].text))
        }
        return Array(out.prefix(5))
    }
}

/// One small card of the brief: icon, a bold line, a quiet line.
struct BriefCard: View {
    struct Content {
        var icon: String
        var multicolor = false
        var tint: String
        var colorOverride: Color? = nil
        var title: String
        var line: String
    }

    let card: Content

    var body: some View {
        let tint = card.colorOverride ?? Color(hex: card.tint)
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if card.multicolor {
                    Image(systemName: card.icon).symbolRenderingMode(.multicolor)
                } else {
                    Image(systemName: card.icon)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(tint)
            .frame(height: 16)
            Text(card.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Text(card.line)
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.55))
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(LinearGradient(colors: [tint.opacity(0.14), Color.white.opacity(0.03)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.07), lineWidth: 1))
        )
    }
}
#endif
