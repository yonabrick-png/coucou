#if !APPSTORE
import SwiftUI
import Combine

// MARK: - Notch modes (GitHub build only)

/// What the notch shows and how loud it is, like the iPhone's Focus modes:
/// - Everything: all of it.
/// - Focus: only music, Dynamic-Island style (art left, bars right; a big player when open),
///   no pills or tabs, Mochi hidden, no sounds, only the volume / brightness bar.
/// - Study: timer, music and notes; only timer and reminder sounds. Turns on by itself with a
///   study session and off when the timer is reset or the break ends.
/// - Meeting: hidden and silent (screen sharing, calls); Claude's requests go to the
///   terminal. Turns on by itself during a calendar event with a video link.
/// - Night: hidden and silent; off by itself at the first unlock after 5:00.
@MainActor
final class NotchModes: ObservableObject {
    static let shared = NotchModes()

    enum Mode: String, CaseIterable, Identifiable {
        case everything, focus, study, meeting, night
        var id: String { rawValue }

        var title: String {
            switch self {
            case .everything: return String(localized: "Everything")
            case .focus:      return String(localized: "Focus")
            case .study:      return String(localized: "Study")
            case .meeting:    return String(localized: "Meeting")
            case .night:      return String(localized: "Night")
            }
        }

        var icon: String {
            switch self {
            case .everything: return "sparkles"
            case .focus:      return "headphones"
            case .study:      return "book.fill"
            case .meeting:    return "video.fill"
            case .night:      return "moon.zzz.fill"
            }
        }

        var colorHex: String {
            switch self {
            case .everything: return "#C5C8CD"
            case .focus:      return "#F472B6"
            case .study:      return "#A78BFA"
            case .meeting:    return "#F4505E"
            case .night:      return "#818CF8"
            }
        }

        var summary: String {
            switch self {
            case .everything: return String(localized: "All of it")
            case .focus:      return String(localized: "Only music, quiet")
            case .study:      return String(localized: "Timer, music and notes")
            case .meeting:    return String(localized: "Hidden and silent")
            case .night:      return String(localized: "Hidden until morning")
            }
        }
    }

    @Published private(set) var mode: Mode {
        didSet { Self.focusActive = mode == .focus }
    }
    /// Read by `islandSize` (a plain function) to make the Focus island small.
    nonisolated(unsafe) static var focusActive = false
    /// The mode was switched on by Coucou (study session, meeting), not by you.
    @Published private(set) var automatic = false

    private var before: Mode = .everything
    private var cancellables = Set<AnyCancellable>()

    private static let modeKey = "coucou.mode"
    private static let beforeKey = "coucou.mode.before"
    private static let autoKey = "coucou.mode.auto"
    private static let nightSinceKey = "coucou.mode.nightSince"

    private init() {
        let d = UserDefaults.standard
        mode = Mode(rawValue: d.string(forKey: Self.modeKey) ?? "") ?? .everything
        before = Mode(rawValue: d.string(forKey: Self.beforeKey) ?? "") ?? .everything
        automatic = d.bool(forKey: Self.autoKey)
        Self.focusActive = mode == .focus

        // Study comes and goes with study sessions
        FocusTimer.shared.$phase
            .combineLatest(FocusTimer.shared.$mode, FocusTimer.shared.$finishedMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] phase, timerMode, finished in
                self?.followTimer(phase: phase, timerMode: timerMode, finished: finished)
            }
            .store(in: &cancellables)
    }

    // MARK: Switching

    /// You picked a mode (menu or notch button).
    func choose(_ new: Mode) {
        if mode == .meeting && automatic && new != .meeting { meetingDismissed = true }
        set(new, automatic: false)
    }

    private func set(_ new: Mode, automatic auto: Bool) {
        guard new != mode || auto != automatic else { return }
        let old = mode
        if auto && !automatic { before = mode }   // remember where to come back to
        mode = new
        automatic = auto
        if new == .night { UserDefaults.standard.set(Date(), forKey: Self.nightSinceKey) }
        save()
        applied(from: old, to: new)
    }

    /// Back to the mode before an automatic one.
    private func restore() {
        guard automatic else { return }
        let back = before
        set(back, automatic: false)
    }

    private func applied(from old: Mode, to new: Mode) {
        let wasHidden = Self.hides(old), nowHidden = Self.hides(new)
        if nowHidden && !wasHidden {
            NotificationCenter.default.post(name: .notchModeHide, object: nil)
        }
        if !nowHidden { NotificationCenter.default.post(name: .notchModeChanged, object: nil) }
        // Leaving a quiet mode: the brief that waited can show now
        if new == .everything { DailyBrief.showIfFirstToday(after: 1.0) }
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(mode.rawValue, forKey: Self.modeKey)
        d.set(before.rawValue, forKey: Self.beforeKey)
        d.set(automatic, forKey: Self.autoKey)
    }

    // MARK: Automatic

    private func followTimer(phase: FocusTimer.Phase, timerMode: FocusTimer.Mode, finished: FocusTimer.Mode?) {
        if phase == .running && timerMode == .study && mode == .everything {
            set(.study, automatic: true)
        } else if mode == .study && automatic {
            // Off when the timer is reset, or when the break after studying is over
            if phase == .idle && finished == nil { restore() }
            if phase == .finished && finished == .rest { restore() }
        }
    }

    /// You left an automatic Meeting during the call: don't force it back until the call ends.
    private var meetingDismissed = false

    /// Called every minute by the calendar: a video call under way hides the notch.
    func followCalendar(inMeeting: Bool) {
        if !inMeeting {
            meetingDismissed = false
            if mode == .meeting && automatic { restore() }
            return
        }
        guard !meetingDismissed, [.everything, .focus, .study].contains(mode) else { return }
        set(.meeting, automatic: true)
    }

    /// The Mac was unlocked: Night ends at the first unlock after 5:00 on a later morning.
    func unlocked() {
        guard mode == .night else { return }
        let cal = Calendar.current
        let now = Date()
        guard cal.component(.hour, from: now) >= 5 else { return }
        let since = UserDefaults.standard.object(forKey: Self.nightSinceKey) as? Date ?? .distantPast
        let fiveToday = cal.date(bySettingHour: 5, minute: 0, second: 0, of: now) ?? now
        guard since < fiveToday else { return }
        set(.everything, automatic: false)
    }

    // MARK: What each mode allows

    static func hides(_ m: Mode) -> Bool { m == .meeting || m == .night }

    /// Meeting and Night: the island never shows, and Claude's requests go to the terminal.
    var hidesIsland: Bool { Self.hides(mode) }

    /// Focus: Mochi steps aside for the music.
    var hidesMochi: Bool { mode == .focus }

    /// Header tabs for this mode.
    var tabs: [IslandView] {
        switch mode {
        case .everything: return [.overview, .garmin, .weather]
        case .focus, .study: return [.overview]
        case .meeting, .night: return []
        }
    }

    /// Pills the home screen may show. Claude sessions (Claude Code, Claude Desktop, other
    /// agents) never get a pill: their permission requests and questions still open their own views.
    static let homePills: Set<String> = [
        "integration_music", "integration_spotify", "integration_calendar",
        "integration_shelf", "integration_timer", "integration_notes",
    ]

    func allowsPill(_ id: String) -> Bool {
        switch mode {
        case .everything: return Self.homePills.contains(id)
        case .study: return ["integration_timer", "integration_music", "integration_spotify", "integration_notes"].contains(id)
        case .focus, .meeting, .night: return false
        }
    }

    /// Things that may take the right side of the closed notch.
    enum Compact { case popup, timer, music, calendar }
    func allowsCompact(_ c: Compact) -> Bool {
        switch mode {
        case .everything: return true
        case .focus: return c == .popup || c == .music
        case .study: return c != .calendar
        case .meeting, .night: return false
        }
    }

    /// Pop-ups: volume/brightness are your own key presses; the rest are news.
    func allowsPopup(id: String) -> Bool {
        switch mode {
        case .everything: return true
        case .focus, .study: return id == "volume" || id == "brightness"
        case .meeting, .night: return false
        }
    }

    /// Coucou's sounds for this mode.
    func allowsSound(_ name: String) -> Bool {
        switch mode {
        case .everything: return true
        case .study: return ["pop", "close", "proud", "finish", "blip", "approval", "send"].contains(name)
        case .focus, .meeting, .night: return false
        }
    }

    var allowsBrief: Bool { mode == .everything }
}

extension Notification.Name {
    /// A mode that hides the island was chosen: fold and hide it now.
    static let notchModeHide = Notification.Name("notchBuddy.notchModeHide")
    static let notchModeChanged = Notification.Name("notchBuddy.notchModeChanged")
}

// MARK: - Mode button (notch header) and menu

/// The current mode in the notch's top bar; a menu to change it.
struct NotchModeButton: View {
    @ObservedObject private var modes = NotchModes.shared

    var body: some View {
        Menu {
            ForEach(NotchModes.Mode.allCases) { m in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { modes.choose(m) }
                } label: {
                    Label("\(m.title) — \(m.summary)", systemImage: m == modes.mode ? "checkmark" : m.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: modes.mode.icon).font(.system(size: 10, weight: .semibold))
                if modes.mode != .everything {
                    Text(modes.mode.title).font(.system(size: 10.5, weight: .semibold))
                }
            }
            .foregroundColor(Color(hex: modes.mode.colorHex))
            .padding(.horizontal, modes.mode == .everything ? 6 : 8)
            .frame(height: 20)
            .background(Capsule().fill(Color(hex: modes.mode.colorHex).opacity(modes.mode == .everything ? 0.08 : 0.18)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Notch mode: \(modes.mode.title)"))
    }
}
#endif
