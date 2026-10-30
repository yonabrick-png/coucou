#if !APPSTORE
import SwiftUI

// MARK: - School tab (Yehonathan HQ in the notch, GitHub build only)

/// The homework dashboard in the notch, in its navy glass look: the next school day's lessons,
/// homework to tick off (late, today, tomorrow, this week) and the coming tests and projects.
struct SchoolFullView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = SchoolStore.shared
    /// Ticked in this visit: stays on screen, struck through, until the tab closes.
    @State private var ticked: Set<String> = []
    @Environment(\.islandViewActive) private var viewActive

    // HQ palette (the dashboard's tokens)
    static let card  = Color(hex: "#121B32")
    static let sep   = Color(hex: "#B4C8FF").opacity(0.09)
    static let fg    = Color(hex: "#E9EEF8")
    static let muted = Color(hex: "#9DABC6")
    static let dim   = Color(hex: "#68748F")
    static let honey = Color(hex: "#E8B95C")
    static let sage  = Color(hex: "#A6C98C")
    static let coral = Color(hex: "#E8A08A")

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                topBar
                if store.missing {
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Image(systemName: "graduationcap.fill").font(.system(size: 22)).foregroundColor(Self.honey)
                        Text("No HQ data yet")
                            .font(.system(size: 12)).foregroundColor(Self.muted)
                        Button(String(localized: "Sync now")) { store.sync(force: true) }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Self.honey)
                            .buttonStyle(.plain)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        lessonsCard.frame(width: 148)
                        homeworkCard.frame(maxWidth: .infinity)
                        testsCard.frame(width: 150)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            // Clear Mochi and the badge beside him
            .padding(.leading, 112)
            .padding(.trailing, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .padding(.bottom, 10)
        .onAppear {
            store.refresh()
            store.sync()
        }
        .onChange(of: viewActive) { _, active in
            if active { store.refresh(); store.sync() } else { ticked = [] }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 7) {
            Text("HQ")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(Self.honey)
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Self.muted)
            if let p = store.practiceToday {
                HStack(spacing: 3) {
                    Image(systemName: p == "Stairs" ? "stairs" : "figure.run").font(.system(size: 8.5, weight: .semibold))
                    Text("\(p) 17:00").font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundColor(Self.sage)
                .padding(.horizontal, 7).frame(height: 17)
                .background(Capsule().fill(Self.sage.opacity(0.14)))
                .help(String(localized: "Training tonight, 17:00–20:00"))
            }
            Spacer(minLength: 4)
            if store.needsSetup && !store.syncing {
                // The sync can't start until ~/homework-tracker is trusted once in Claude Code
                Button { store.startSetup() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.circle.fill").font(.system(size: 8.5))
                        Text("Setup needed").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(Self.coral)
                }
                .buttonStyle(.plain)
                .help(String(localized: "One-time step: click to open Terminal with the command copied. Paste it, press Return, accept the trust prompt, then type /exit and press ↻. \(updatedText)"))
            } else {
                Text(store.syncing ? String(localized: "Syncing…")
                     : store.syncFailed ? String(localized: "Sync failed") : updatedText)
                    .font(.system(size: 9))
                    .foregroundColor(store.syncFailed && !store.syncing ? Self.coral : Self.dim)
                    .help(store.syncFailed ? String(localized: "See ~/homework-tracker/logs. \(updatedText)") : "")
            }
            Button { store.sync(force: true) } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(store.syncing ? Self.honey : Self.muted)
                    .rotationEffect(.degrees(store.syncing ? 360 : 0))
                    .animation(store.syncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: store.syncing)
            }
            .buttonStyle(.plain)
            .disabled(store.syncing)
            .help(String(localized: "Sync with the dashboard and Notion now"))
            Button { store.openDashboard() } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Self.muted)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Open Yehonathan HQ"))
        }
    }

    private var updatedText: String {
        guard let d = store.updatedAt else { return "" }
        let time = d.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(d) ? String(localized: "Synced \(time)")
            : String(localized: "Synced \(d.formatted(.dateTime.weekday(.abbreviated))) \(time)")
    }

    // MARK: Cards

    private func card<Content: View>(_ title: String, trailing: String = "", @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(Self.muted)
                Spacer(minLength: 2)
                Text(trailing)
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundColor(Self.dim)
            }
            content()
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Self.sep, lineWidth: 1))
    }

    private var lessonsCard: some View {
        let day = store.lessonDay()
        let cal = Calendar.current
        let label = cal.isDateInToday(day.date) ? String(localized: "TODAY")
            : cal.isDateInTomorrow(day.date) ? String(localized: "TOMORROW")
            : day.date.formatted(.dateTime.weekday(.wide)).uppercased()
        return card(label, trailing: day.lessons.isEmpty ? "" : String(localized: "\(day.lessons.count) lessons")) {
            if day.lessons.isEmpty {
                Text("No lessons").font(.system(size: 10.5)).foregroundColor(Self.dim)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(day.lessons) { l in
                        HStack(spacing: 6) {
                            Text("\(l.period)")
                                .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundColor(Self.dim)
                                .frame(width: 9, alignment: .trailing)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color(hex: l.subject.color))
                                .frame(width: 3, height: 12)
                            Text(l.subject.short)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(Self.fg)
                                .lineLimit(1)
                                .layoutPriority(1)
                            Spacer(minLength: 2)
                            // "Computer Lab E" → "Lab E": the subject name keeps the room
                            Text(l.subject.room.replacingOccurrences(of: "Computer Lab", with: "Lab")
                                    .replacingOccurrences(of: "Physics Lab", with: "Lab"))
                                .font(.system(size: 8.5))
                                .foregroundColor(Self.dim)
                                .lineLimit(1)
                        }
                        .help("\(l.subject.name)\(l.subject.room.isEmpty ? "" : " · \(l.subject.room)")")
                    }
                }
            }
        }
    }

    // MARK: Homework

    private enum Bucket: Int, CaseIterable {
        case late, today, tomorrow, later
        var title: String {
            switch self {
            case .late:     return String(localized: "Late")
            case .today:    return String(localized: "Today")
            case .tomorrow: return String(localized: "Tomorrow")
            case .later:    return String(localized: "This week")
            }
        }
    }

    private func bucket(_ due: Date?) -> Bucket? {
        guard let due else { return .later }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: due)).day ?? 0
        switch days {
        case ..<0: return .late
        case 0:    return .today
        case 1:    return .tomorrow
        case 2...7: return .later
        default:   return nil
        }
    }

    private var homework: [(Bucket, [SchoolStore.Homework])] {
        let open = store.tasks.filter { $0.kind == "hw" && (!$0.done || ticked.contains($0.id)) }
        return Bucket.allCases.compactMap { b in
            let items = open.filter { bucket($0.due) == b }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            return items.isEmpty ? nil : (b, items)
        }
    }

    private var homeworkCard: some View {
        let groups = homework
        let left = groups.flatMap(\.1).filter { !$0.done }.count
        return card(String(localized: "HOMEWORK"), trailing: left > 0 ? "\(left)" : "") {
            if groups.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 16)).foregroundColor(Self.sage)
                    Text("All done").font(.system(size: 12, weight: .semibold)).foregroundColor(Self.fg)
                    Text("Nothing due this week").font(.system(size: 9.5)).foregroundColor(Self.dim)
                }
                .padding(.top, 4)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(groups, id: \.0) { b, items in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(b.title)
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundColor(b == .late ? Self.coral : Self.dim)
                                ForEach(items) { homeworkRow($0, late: b == .late) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func homeworkRow(_ t: SchoolStore.Homework, late: Bool) -> some View {
        let s = store.subject(t.subject)
        return HStack(spacing: 7) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    ticked.insert(t.id)
                    store.tick(t.id)
                }
            } label: {
                ZStack {
                    Circle().stroke(t.done ? Self.sage : Color(hex: s.color).opacity(0.7), lineWidth: 1.4)
                    if t.done {
                        Circle().fill(Self.sage)
                        Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy)).foregroundColor(Self.card)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 13, height: 13)
                .contentShape(Circle())
            }
            .buttonStyle(NowPlayingPressStyle())
            .disabled(t.done)
            .help(t.done ? String(localized: "Done — saved to the dashboard on the next sync") : String(localized: "Mark done"))

            VStack(alignment: .leading, spacing: 0) {
                Text(t.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(t.done ? Self.dim : Self.fg)
                    .strikethrough(t.done, color: Self.dim)
                    .lineLimit(1)
                Text(s.short)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundColor(Color(hex: s.color))
            }
            Spacer(minLength: 2)
            if let due = t.due, !t.done {
                Text(late ? String(localized: "late") : due.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(late ? Self.coral : Self.muted)
            }
        }
    }

    // MARK: Tests and projects (Notion, plus tests added on the dashboard)

    private struct Upcoming: Identifiable {
        let id: String
        let title: String
        let kind: String
        let subject: String
        let due: Date?
        let notion: SchoolStore.Test?
    }

    private var upcoming: [Upcoming] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let notion = store.tests.map { Upcoming(id: $0.id, title: $0.title, kind: $0.kind, subject: $0.subject, due: $0.due, notion: $0) }
        let local = store.tasks.filter { $0.kind != "hw" && !$0.done }
            .map { Upcoming(id: $0.id, title: $0.title, kind: $0.kind, subject: $0.subject, due: $0.due, notion: nil) }
        return (notion + local)
            .filter { ($0.due ?? .distantFuture) >= cal.date(byAdding: .day, value: -1, to: today)! }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    private var testsCard: some View {
        let items = upcoming
        return card(String(localized: "TESTS & PROJECTS")) {
            if items.isEmpty {
                Text("Nothing coming up").font(.system(size: 10.5)).foregroundColor(Self.dim)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(items) { u in testRow(u) }
                    }
                }
            }
        }
    }

    private func testRow(_ u: Upcoming) -> some View {
        let s = store.subject(u.subject)
        let cal = Calendar.current
        let days = u.due.map { cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: $0)).day ?? 0 }
        let soon = (days ?? 99) <= 2
        return HStack(alignment: .center, spacing: 7) {
            VStack(spacing: -2) {
                Text(days.map { $0 <= 0 ? (($0 == 0) ? String(localized: "now") : "–") : "\($0)" } ?? "?")
                    .font(.system(size: (days ?? 1) <= 0 ? 10 : 14, weight: .bold, design: .rounded).monospacedDigit())
                Text((days ?? 1) <= 0 ? "" : ((days == 1) ? String(localized: "day") : String(localized: "days")))
                    .font(.system(size: 7, weight: .medium))
            }
            .foregroundColor(soon ? Self.honey : Self.fg)
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(u.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Self.fg)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Text(u.kind == "project" ? String(localized: "Project") : String(localized: "Test"))
                        .foregroundColor(u.kind == "project" ? Self.honey : Self.coral)
                    Text("· \(s.short)").foregroundColor(Color(hex: s.color))
                }
                .font(.system(size: 8.5, weight: .medium))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.035)))
        .contentShape(Rectangle())
        .onTapGesture { if let n = u.notion { store.open(n) } }
        .help(u.notion.map { "\($0.status) · \(String(localized: "Open in Notion"))" } ?? "")
    }
}
#endif
