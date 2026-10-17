#if !APPSTORE
import SwiftUI

// MARK: - Month view (the notch's calendar tab, GitHub build only)

/// Every date of the month on the left; tap one to see what's on it on the right.
struct CalendarMonthView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var controller = CalendarController.shared

    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selected = Calendar.current.startOfDay(for: Date())
    /// Events per day (start of day) for the 6 weeks on screen.
    @State private var byDay: [Date: [CalendarController.Event]] = [:]
    @State private var dayEvents: [CalendarController.Event] = []

    private let red = Color(hex: CalendarController.red)
    private var cal: Calendar { Calendar.current }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            Group {
                switch controller.access {
                case .granted:
                    HStack(alignment: .top, spacing: 16) {
                        monthGrid.frame(width: 236)
                        Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                        dayPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                case .notAsked:
                    accessPrompt(text: String(localized: "See your whole calendar here"),
                                 button: String(localized: "Allow calendar access")) { controller.requestAccess() }
                case .denied:
                    accessPrompt(text: String(localized: "Allow Coucou to see your calendars"),
                                 button: String(localized: "Open Settings…")) { controller.openPrivacySettings() }
                }
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .padding(.bottom, 10)
        .onAppear { loadMonth(); loadDay() }
        .onChange(of: month) { _, _ in loadMonth() }
        .onChange(of: selected) { _, _ in loadDay() }
        .onChange(of: controller.revision) { _, _ in loadMonth(); loadDay() }
        .onChange(of: controller.access) { _, _ in loadMonth(); loadDay() }
    }

    // MARK: Grid

    private var monthGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Spacer(minLength: 4)
                if !cal.isDate(month, equalTo: Date(), toGranularity: .month) || !cal.isDateInToday(selected) {
                    Button(String(localized: "Today")) { goToday() }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(red.opacity(0.9))
                        .buttonStyle(.plain)
                }
                arrow("chevron.left") { shiftMonth(-1) }
                arrow("chevron.right") { shiftMonth(1) }
            }
            .frame(height: 20)

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .frame(maxWidth: .infinity)
                }
            }

            let days = gridDays
            VStack(spacing: 1) {
                ForEach(0..<6, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { d in
                            if week * 7 + d < days.count { dayCell(days[week * 7 + d]) }
                        }
                    }
                }
            }
        }
    }

    private func arrow(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color(hex: "#8E939C"))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.07))
                .clipShape(Circle())
        }
        .buttonStyle(NowPlayingPressStyle())
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let colors = Self.uniqueColors(byDay[day] ?? [])
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selected = day }
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 11.5, weight: isToday || isSelected ? .bold : .regular).monospacedDigit())
                    .foregroundColor(isToday ? .white
                                     : (inMonth ? Color(hex: "#E4E6EA") : Color(hex: "#4A4F57")))
                    .frame(width: 22, height: 18)
                    .background(Circle().fill(isToday ? red : Color.clear))
                HStack(spacing: 2) {
                    ForEach(colors, id: \.self) { hex in
                        Circle().fill(Color(hex: hex).opacity(inMonth ? 1 : 0.4)).frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(isSelected && !isToday ? Color.white.opacity(0.12) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected && isToday ? red.opacity(0.7) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Up to three calendar colours for a day's dots, in order of first appearance.
    private static func uniqueColors(_ events: [CalendarController.Event]) -> [String] {
        var seen: [String] = []
        for e in events where !seen.contains(e.colorHex) {
            seen.append(e.colorHex)
            if seen.count == 3 { break }
        }
        return seen
    }

    // MARK: Day panel

    private var dayPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1)
                if let tag = dayTag {
                    Text(tag)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(red)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(red.opacity(0.15)))
                }
                Spacer(minLength: 4)
                Button(String(localized: "Open in Calendar")) { controller.openCalendar() }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .buttonStyle(.plain)
            }
            .frame(height: 20)

            if dayEvents.isEmpty {
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 20))
                        .foregroundColor(red.opacity(0.6))
                    Text("Nothing planned")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(hex: "#8E939C"))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(dayEvents) { e in CalendarDayRow(event: e, day: selected) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var dayTag: String? {
        if cal.isDateInToday(selected) { return String(localized: "TODAY") }
        if cal.isDateInTomorrow(selected) { return String(localized: "TOMORROW") }
        if cal.isDateInYesterday(selected) { return String(localized: "YESTERDAY") }
        return nil
    }

    private func accessPrompt(text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "calendar")
                .font(.system(size: 26))
                .foregroundColor(red.opacity(0.8))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#8E939C"))
            Button(button, action: action)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(red)
                .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Data

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The 42 days on screen: from the week holding the 1st, six full weeks.
    private var gridDays: [Date] {
        let weekday = cal.component(.weekday, from: month)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -leading, to: month) ?? month
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func loadMonth() {
        let days = gridDays
        guard let first = days.first, let last = days.last,
              let end = cal.date(byAdding: .day, value: 1, to: last) else { return }
        var map: [Date: [CalendarController.Event]] = [:]
        for e in controller.events(in: DateInterval(start: first, end: end)) {
            // A multi-day event marks every day it covers (up to two months)
            var day = cal.startOfDay(for: max(e.start, first))
            var steps = 0
            while day < e.end && day < end && steps < 62 {
                map[day, default: []].append(e)
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                steps += 1
            }
        }
        byDay = map
    }

    private func loadDay() {
        guard let end = cal.date(byAdding: .day, value: 1, to: selected) else { return }
        dayEvents = controller.events(in: DateInterval(start: selected, end: end))
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return a.start < b.start
            }
    }

    private func shiftMonth(_ delta: Int) {
        guard let m = cal.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            month = m
            // Keep a date selected in the month on screen
            if !cal.isDate(selected, equalTo: m, toGranularity: .month) {
                selected = cal.isDate(Date(), equalTo: m, toGranularity: .month) ? cal.startOfDay(for: Date()) : m
            }
        }
    }

    private func goToday() {
        withAnimation(.easeOut(duration: 0.15)) {
            month = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
            selected = cal.startOfDay(for: Date())
        }
    }
}

/// One event of the picked day: time, colour bar, title, place, Join.
struct CalendarDayRow: View {
    let event: CalendarController.Event
    let day: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let over = event.end <= now
            let live = event.start <= now && !over
            HStack(alignment: .center, spacing: 8) {
                Text(timeLabel)
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundColor(live ? Color(hex: "#22C55E") : Color(hex: "#8E939C"))
                    .frame(width: 46, alignment: .leading)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(hex: event.colorHex))
                    .frame(width: 3, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1).truncationMode(.tail)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 4)
                if event.joinURL != nil && !over {
                    Button { CalendarController.shared.join(event) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "video.fill").font(.system(size: 8))
                            Text("Join").font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#0E0F11"))
                        .padding(.horizontal, 8)
                        .frame(height: 18)
                        .background(Capsule().fill(live ? Color(hex: "#22C55E") : Color(hex: "#C5C8CD")))
                    }
                    .buttonStyle(NowPlayingPressStyle())
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(live ? 0.08 : 0.04)))
            .opacity(over ? 0.5 : 1)
        }
    }

    private var timeLabel: String {
        if event.isAllDay { return String(localized: "All day") }
        if !Calendar.current.isDate(event.start, inSameDayAs: day) { return String(localized: "cont.") }
        return event.start.formatted(date: .omitted, time: .shortened)
    }

    private var detail: String {
        let range = event.isAllDay ? ""
            : event.start.formatted(date: .omitted, time: .shortened) + "–" + event.end.formatted(date: .omitted, time: .shortened)
        return [range, event.location].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
#endif
