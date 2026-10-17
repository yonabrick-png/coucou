#if !APPSTORE
import AppKit
import Combine

// MARK: - Focus timer

/// Study / Rest / plain Timer in the notch. Counts down to a fixed end date (no drift, survives a
/// relaunch), wakes once at the end, and celebrates: sound, haptic, Mochi, the notch peeks open.
/// Study and Rest take turns: a finished study session readies a rest, and every fourth rest is a
/// long one. Singleton, @MainActor, GitHub build only.
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()
    nonisolated static let pillId = "integration_timer"

    enum Mode: String, CaseIterable, Codable {
        case study, rest, timer

        var title: String {
            switch self {
            case .study: return String(localized: "Study")
            case .rest:  return String(localized: "Rest")
            case .timer: return String(localized: "Timer")
            }
        }
        var icon: String {
            switch self {
            case .study: return "book.fill"
            case .rest:  return "cup.and.saucer.fill"
            case .timer: return "timer"
            }
        }
        var colorHex: String {
            switch self {
            case .study: return "#A78BFA"
            case .rest:  return "#34D399"
            case .timer: return "#F5A524"
            }
        }
        var defaultMinutes: Int {
            switch self {
            case .study: return 25
            case .rest:  return 5
            case .timer: return 10
            }
        }
    }

    enum Phase: String, Codable { case idle, running, paused, finished }

    @Published private(set) var mode: Mode = .study
    @Published private(set) var phase: Phase = .idle
    /// Length of the current (or next) run, in seconds.
    @Published private(set) var duration: TimeInterval = 25 * 60
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    /// Study sessions finished today.
    @Published private(set) var studiesToday = 0
    /// What just finished (shown until the next start).
    @Published private(set) var finishedMode: Mode?

    /// The long rest comes after every fourth study session.
    nonisolated static let longRestMinutes = 15
    nonisolated private static let key = "coucou.focusTimer"

    private var finishTask: Task<Void, Never>?
    private var nameTick: Timer?

    var color: String { mode.colorHex }

    private init() {
        restore()
        syncTaskName()
    }

    // MARK: Reading

    func remaining(at date: Date = Date()) -> TimeInterval {
        switch phase {
        case .running:  return max(0, (endDate ?? date).timeIntervalSince(date))
        case .paused:   return pausedRemaining ?? duration
        case .idle:     return duration
        case .finished: return 0
        }
    }

    /// 1 when full, 0 when done: the ring drains.
    func fraction(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, remaining(at: date) / duration))
    }

    var isActive: Bool { phase == .running || phase == .paused || phase == .finished }

    /// Minutes the next run of `mode` lasts.
    func minutes(for mode: Mode) -> Int {
        if mode == .rest && studiesToday > 0 && studiesToday % 4 == 0 { return Self.longRestMinutes }
        let saved = UserDefaults.standard.integer(forKey: "\(Self.key).minutes.\(mode.rawValue)")
        return saved > 0 ? saved : mode.defaultMinutes
    }

    // MARK: Controls

    func toggle() {
        switch phase {
        case .idle, .finished: start()
        case .running:         pause()
        case .paused:          resume()
        }
    }

    func start() {
        if phase == .finished { finishedMode = nil }
        duration = TimeInterval(minutes(for: mode) * 60)
        endDate = Date().addingTimeInterval(duration)
        pausedRemaining = nil
        phase = .running
        scheduleFinish()
        feedback(sound: "pop")
        save()
    }

    func pause() {
        guard phase == .running else { return }
        pausedRemaining = remaining()
        endDate = nil
        phase = .paused
        finishTask?.cancel()
        feedback(sound: "close")
        save()
    }

    func resume() {
        guard phase == .paused, let left = pausedRemaining else { return }
        endDate = Date().addingTimeInterval(left)
        pausedRemaining = nil
        phase = .running
        scheduleFinish()
        feedback(sound: "pop")
        save()
    }

    /// Back to a full, stopped timer in the same mode.
    func reset() {
        finishTask?.cancel()
        endDate = nil
        pausedRemaining = nil
        finishedMode = nil
        phase = .idle
        duration = TimeInterval(minutes(for: mode) * 60)
        feedback(sound: "blip", haptic: .alignment)
        save()
    }

    func setMode(_ new: Mode) {
        guard new != mode || phase == .finished else { return }
        finishTask?.cancel()
        mode = new
        endDate = nil
        pausedRemaining = nil
        finishedMode = nil
        phase = .idle
        duration = TimeInterval(minutes(for: new) * 60)
        feedback(sound: "blip", haptic: .alignment)
        save()
    }

    /// −/+ on a stopped timer: 1-minute steps under 10, 5-minute steps above; 1…180 min.
    func adjust(up: Bool) {
        guard phase == .idle || phase == .finished else { return }
        let current = minutes(for: mode)
        let step = (up ? current >= 10 : current > 10) ? 5 : 1
        let next = min(180, max(1, current + (up ? step : -step)))
        UserDefaults.standard.set(next, forKey: "\(Self.key).minutes.\(mode.rawValue)")
        if phase == .finished { finishedMode = nil; phase = .idle }
        duration = TimeInterval(next * 60)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        save()
    }

    // MARK: Finishing

    private func scheduleFinish() {
        finishTask?.cancel()
        guard let end = endDate else { return }
        finishTask = Task { [weak self] in
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            self?.finish()
        }
        startNameTick()
    }

    private func finish() {
        guard phase == .running else { return }
        let done = mode
        phase = .finished
        finishedMode = done
        endDate = nil
        if done == .study { bumpStudies() }

        // The celebration
        SoundEngine.shared.play(done == .study ? "proud" : "finish")
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        NotificationCenter.default.post(name: .triggerEmote, object: done == .study ? BotEmote.proud : BotEmote.happy)
        if AppState.shared.tasks.contains(where: { $0.id == Self.pillId }) {
            AppState.shared.setFocus(Self.pillId)
        }
        NotificationCenter.default.post(name: .hookReveal, object: nil)

        // Study and Rest take turns: get the next one ready
        switch done {
        case .study: mode = .rest
        case .rest:  mode = .study
        case .timer: break
        }
        duration = TimeInterval(minutes(for: mode) * 60)
        save()
    }

    private func bumpStudies() {
        let today = Self.dayKey(Date())
        if UserDefaults.standard.string(forKey: "\(Self.key).day") != today {
            UserDefaults.standard.set(today, forKey: "\(Self.key).day")
            studiesToday = 0
        }
        studiesToday += 1
        UserDefaults.standard.set(studiesToday, forKey: "\(Self.key).studies")
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: Pill name

    /// "Study · 24m" while it runs, refreshed once a minute; "Timer" when stopped.
    private func startNameTick() {
        nameTick?.invalidate()
        syncTaskName()
        nameTick = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                let t = FocusTimer.shared
                t.syncTaskName()
                if t.phase != .running { t.nameTick?.invalidate(); t.nameTick = nil }
            }
        }
    }

    func syncTaskName() {
        guard let idx = AppState.shared.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }
        let mins = Int(ceil(remaining() / 60))
        let name: String
        switch phase {
        case .idle:     name = PillCatalog.definition(for: Self.pillId)?.name ?? "Timer"
        case .running:  name = "\(mode.title) · \(mins)m"
        case .paused:   name = String(localized: "Paused · \(mins)m")
        case .finished: name = String(localized: "\(finishedMode?.title ?? mode.title) done ✓")
        }
        if AppState.shared.tasks[idx].name != name { AppState.shared.tasks[idx].name = name }
    }

    // MARK: Feedback

    private func feedback(sound: String, haptic: NSHapticFeedbackManager.FeedbackPattern = .levelChange) {
        SoundEngine.shared.play(sound)
        NSHapticFeedbackManager.defaultPerformer.perform(haptic, performanceTime: .now)
        syncTaskName()
    }

    // MARK: Saving

    private struct Saved: Codable {
        var mode: Mode
        var phase: Phase
        var duration: TimeInterval
        var endDate: Date?
        var pausedRemaining: TimeInterval?
    }

    private func save() {
        let s = Saved(mode: mode, phase: phase == .finished ? .idle : phase,
                      duration: duration, endDate: endDate, pausedRemaining: pausedRemaining)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    private func restore() {
        let d = UserDefaults.standard
        if d.string(forKey: "\(Self.key).day") == Self.dayKey(Date()) {
            studiesToday = d.integer(forKey: "\(Self.key).studies")
        }
        guard let data = d.data(forKey: Self.key),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else {
            duration = TimeInterval(minutes(for: mode) * 60)
            return
        }
        mode = s.mode
        duration = s.duration
        switch s.phase {
        case .running:
            if let end = s.endDate, end > Date() {
                endDate = end
                phase = .running
                scheduleFinish()
            } else {
                // It ended while Coucou was closed: show it as done
                phase = .running
                endDate = Date()
                finish()
            }
        case .paused:
            pausedRemaining = s.pausedRemaining
            phase = .paused
        default:
            phase = .idle
            duration = TimeInterval(minutes(for: mode) * 60)
        }
    }
}
#endif
