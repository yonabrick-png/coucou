#if !APPSTORE
import SwiftUI

// MARK: - Calendar card (overview left card, GitHub build only)

struct CalendarCardView: View {
    @ObservedObject private var controller = CalendarController.shared

    private let red = Color(hex: CalendarController.red)

    var body: some View {
        Group {
            switch controller.access {
            case .notAsked: askView
            case .denied:   deniedView
            case .granted:  agenda
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    // MARK: Agenda

    /// The card is ~98 pt tall: the next event (title, countdown, time, Join) then two more.
    @ViewBuilder private var agenda: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let upcoming = controller.events.filter { $0.end > now }
            let timed = upcoming.filter { !$0.isAllDay }
            if let next = timed.first {
                VStack(alignment: .leading, spacing: 0) {
                    nextEvent(next, now: now)
                        .padding(.top, 6)
                        .padding(.trailing, 24)   // the ↗ button sits top-right
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(upcoming.filter { $0.id != next.id }.prefix(2))) { e in
                            laterRow(e, now: now)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.leading, 108)
                .padding(.trailing, 12)
            } else {
                emptyView(allDay: upcoming.filter(\.isAllDay))
            }
        }
    }

    private func nextEvent(_ e: CalendarController.Event, now: Date) -> some View {
        let color = Color(hex: e.colorHex)
        let underway = e.start <= now
        let soon = !underway && e.start.timeIntervalSince(now) < 10 * 60
        return HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(e.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1).truncationMode(.tail)
                        .layoutPriority(1)
                    Text(Self.countdown(e, now: now))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundColor(underway ? Color(hex: "#22C55E") : (soon ? Color(hex: "#F5A524") : Color(hex: "#8E939C")))
                        .fixedSize()
                }
                HStack(spacing: 6) {
                    Text(Self.timeRange(e, now: now) + (e.location.isEmpty || e.joinURL != nil ? "" : " · \(e.location)"))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1).truncationMode(.tail)
                    if e.joinURL != nil {
                        Button { controller.join(e) } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "video.fill").font(.system(size: 8))
                                Text("Join").font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(Color(hex: "#0E0F11"))
                            .padding(.horizontal, 7)
                            .frame(height: 16)
                            .background(Capsule().fill(underway || soon ? Color(hex: "#22C55E") : Color(hex: "#C5C8CD")))
                        }
                        .buttonStyle(NowPlayingPressStyle())
                        .help(String(localized: "Join the call"))
                    }
                }
            }
        }
    }

    private func laterRow(_ e: CalendarController.Event, now: Date) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: e.colorHex)).frame(width: 5, height: 5)
            Text(Self.shortStart(e, now: now))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundColor(Color(hex: "#6B7079"))
                .frame(minWidth: 34, alignment: .leading)
            Text(e.title)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .lineLimit(1).truncationMode(.tail)
        }
    }

    private func emptyView(allDay: [CalendarController.Event]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(dot: red)
            HStack(spacing: 5) {
                Circle().fill(Color(hex: "#22C55E")).frame(width: 5, height: 5)
                Text(allDay.isEmpty
                     ? String(localized: "Nothing left today or tomorrow")
                     : String(localized: "No meetings · \(allDay[0].title)"))
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .lineLimit(1)
            }
            .padding(.leading, 108)
            .padding(.top, 2)
            Button(String(localized: "Open Calendar")) { controller.openCalendar() }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(red.opacity(0.85))
                .buttonStyle(.plain)
                .padding(.leading, 108)
                .padding(.top, 2)
        }
    }

    // MARK: Access

    private var askView: some View {
        VStack(alignment: .leading, spacing: 4) {
            header(dot: red)
            Text("See your next events here")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
                .padding(.leading, 108)
            Button(String(localized: "Allow calendar access")) { controller.requestAccess() }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(red.opacity(0.9))
                .buttonStyle(.plain)
                .padding(.leading, 108)
                .padding(.top, 2)
        }
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            header(dot: Color(hex: "#F4505E"))
            Text("Allow Coucou to see your calendars")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
                .padding(.leading, 108)
                .padding(.trailing, 12)
            Button("Open Settings…") { controller.openPrivacySettings() }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(red.opacity(0.85))
                .buttonStyle(.plain)
                .padding(.leading, 108)
                .padding(.top, 2)
        }
    }

    private func header(dot: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text("Calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
            Spacer(minLength: 2)
        }
        .padding(.top, 6)
        .padding(.leading, 108)
        .padding(.trailing, 36)
    }

    // MARK: Formatting

    /// "in 25 min", "in 2 h 10", "now · 20 min left", "tomorrow 9:00".
    static func countdown(_ e: CalendarController.Event, now: Date) -> String {
        if e.start <= now {
            let left = Int(ceil(e.end.timeIntervalSince(now) / 60))
            return String(localized: "now · \(Self.duration(left)) left")
        }
        if !Calendar.current.isDate(e.start, inSameDayAs: now) {
            return String(localized: "tomorrow")
        }
        let mins = Int(ceil(e.start.timeIntervalSince(now) / 60))
        return String(localized: "in \(Self.duration(mins))")
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(1, minutes)) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(String(format: "%02d", m))"
    }

    static func timeRange(_ e: CalendarController.Event, now: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        let day = Calendar.current.isDate(e.start, inSameDayAs: now) ? "" : String(localized: "Tomorrow ")
        return day + f.string(from: e.start) + "–" + f.string(from: e.end)
    }

    static func shortStart(_ e: CalendarController.Event, now: Date) -> String {
        if e.isAllDay { return String(localized: "all day") }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        let time = f.string(from: e.start)
        return Calendar.current.isDate(e.start, inSameDayAs: now) ? time : String(localized: "tmrw \(time)")
    }
}

// MARK: - Closed notch: countdown to the next event

/// Shown on the right of the closed notch when an event starts within 30 minutes (or is under
/// way) and no music plays. Sized for the 28 × 28 slot the mini grid uses.
struct CompactCalendarBadge: View {
    let event: CalendarController.Event

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let mins = Int(ceil(event.start.timeIntervalSince(now) / 60))
            let underway = event.start <= now
            VStack(spacing: 1) {
                Image(systemName: event.joinURL != nil ? "video.fill" : "calendar")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Color(hex: event.colorHex))
                Text(underway ? String(localized: "now") : "\(max(1, mins))m")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(underway ? Color(hex: "#22C55E") : (mins <= 10 ? Color(hex: "#F5A524") : Color(hex: "#F5F6F8")))
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: 32, height: 28)
        }
    }

    /// The event worth a badge right now, if any.
    @MainActor static func current(now: Date = Date()) -> CalendarController.Event? {
        guard AppState.shared.activeIntegrations.contains(CalendarController.pillId),
              let next = CalendarController.shared.next else { return nil }
        let startsIn = next.start.timeIntervalSince(now)
        return startsIn <= 30 * 60 ? next : nil
    }
}
#endif
