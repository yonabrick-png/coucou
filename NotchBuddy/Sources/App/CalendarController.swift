#if !APPSTORE
import AppKit
import Combine
import EventKit

// MARK: - Calendar Controller

/// Today's and tomorrow's events from the Mac's calendars (iCloud, Google, Exchange… whatever
/// Calendar.app shows), read with EventKit. Singleton, @MainActor, GitHub build only.
/// Runs only while the Calendar pill is active: a store-change observer plus a one-minute tick
/// that drops finished events and keeps the pill's name on the next one.
@MainActor
final class CalendarController: ObservableObject {
    static let shared = CalendarController()
    nonisolated static let pillId = "integration_calendar"
    nonisolated static let red    = "#FF453A"

    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let colorHex: String
        let location: String
        let joinURL: URL?
    }

    enum Access: Equatable { case notAsked, granted, denied }

    /// Not yet finished, from now to the end of tomorrow, in start order.
    @Published private(set) var events: [Event] = []
    @Published private(set) var access: Access = CalendarController.currentAccess()
    /// Bumped whenever the calendars change, so the month view reads them again.
    @Published private(set) var revision = 0

    private let store = EKEventStore()
    private var tick: Timer?
    private var tokens: [Any] = []
    private var cancellables = Set<AnyCancellable>()

    private var isPillActive: Bool {
        AppState.shared.activeIntegrations.contains(Self.pillId)
    }

    /// The event that matters now: the one under way, else the next timed one.
    var next: Event? {
        let now = Date()
        return events.first { !$0.isAllDay && $0.end > now }
    }

    private init() {
        let changed = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in CalendarController.shared.reload() }
        }
        let newDay = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in CalendarController.shared.reload() }
        }
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in CalendarController.shared.reload() }
        }
        tokens = [changed, newDay, wake]

        AppState.shared.$activeIntegrations
            .sink { [weak self] integrations in
                guard let self else { return }
                if integrations.contains(Self.pillId) { self.start() } else { self.stop() }
            }
            .store(in: &cancellables)
    }

    // MARK: Access

    nonisolated private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:              return .granted
        case .notDetermined:           return .notAsked
        default:                       return .denied
        }
    }

    /// Asks macOS once; afterwards only System Settings can change it.
    func requestAccess() {
        store.requestFullAccessToEvents { granted, _ in
            Task { @MainActor in
                let c = CalendarController.shared
                c.access = granted ? .granted : .denied
                if granted { c.reload() }
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Lifecycle

    private func start() {
        access = Self.currentAccess()
        if access == .notAsked { requestAccess() }
        reload()
        guard tick == nil else { return }
        tick = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in CalendarController.shared.minuteTick() }
        }
    }

    private func stop() {
        tick?.invalidate()
        tick = nil
        events = []
    }

    private func minuteTick() {
        let now = Date()
        let live = events.filter { $0.end > now }
        if live != events { events = live }
        syncTaskName()
        offerStudyIfStarting(now: now)
        // A video call under way hides the notch (Meeting mode) until it ends
        NotchModes.shared.followCalendar(inMeeting: events.contains {
            !$0.isAllDay && $0.joinURL != nil && $0.start <= now && $0.end > now
        })
    }

    // MARK: Study events → timer

    /// Words that make an event a study session (English and Hebrew).
    nonisolated private static let studyWords = [
        "study", "studying", "homework", "revision", "revise", "exam", "test", "quiz", "learn",
        "לימוד", "ללמוד", "שיעורי בית", "מבחן", "בוחן", "חזרה",
    ]
    private var offeredStudyIds: Set<String> = []

    nonisolated static func isStudy(_ title: String) -> Bool {
        let t = title.lowercased()
        return studyWords.contains { t.contains($0) }
    }

    /// A study event that began in the last two minutes gets the timer ready, once.
    private func offerStudyIfStarting(now: Date) {
        guard let e = events.first(where: {
            !$0.isAllDay && $0.start <= now && now.timeIntervalSince($0.start) < 120
                && !offeredStudyIds.contains($0.id) && Self.isStudy($0.title)
        }) else { return }
        offeredStudyIds.insert(e.id)
        FocusTimer.shared.offerStudy(for: e.title)
    }

    // MARK: Reading

    func reload() {
        access = Self.currentAccess()
        guard isPillActive else { revision &+= 1; return }
        guard access == .granted else { events = []; syncTaskName(); return }
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        guard let endOfTomorrow = cal.date(byAdding: .day, value: 2, to: startOfToday) else { return }
        events = events(in: DateInterval(start: startOfToday, end: endOfTomorrow))
            .filter { $0.end > now }
        revision &+= 1
        syncTaskName()
    }

    /// Every event overlapping `interval` (finished ones included), in start order.
    /// Used by the month view; works whether or not the pill is active.
    func events(in interval: DateInterval) -> [Event] {
        guard Self.currentAccess() == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                Event(id: "\(e.eventIdentifier ?? UUID().uuidString)@\(e.startDate.timeIntervalSince1970)",
                      title: (e.title ?? "").isEmpty ? String(localized: "Untitled event") : e.title,
                      start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                      colorHex: Self.hex(e.calendar?.color),
                      location: e.location ?? "",
                      joinURL: Self.joinURL(url: e.url, location: e.location, notes: e.notes))
            }
    }

    /// The pill shows the next event's title, like the music pills show the track.
    private func syncTaskName() {
        guard let idx = AppState.shared.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }
        AppState.shared.tasks[idx].name = next?.title
            ?? (PillCatalog.definition(for: Self.pillId)?.name ?? "Calendar")
    }

    // MARK: Actions

    func join(_ event: Event) {
        guard let url = event.joinURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openCalendar() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    // MARK: Helpers

    /// Video-call hosts whose links get a Join button. Only https links, from the event itself.
    nonisolated private static let meetingHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "facetime.apple.com", "webex.com", "whereby.com", "meet.jit.si",
    ]

    nonisolated static func joinURL(url: URL?, location: String?, notes: String?) -> URL? {
        func isMeeting(_ u: URL) -> Bool {
            guard u.scheme == "https", let host = u.host?.lowercased() else { return false }
            return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        if let url, isMeeting(url) { return url }
        let text = [location, notes].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .first(where: isMeeting)
    }

    nonisolated private static func hex(_ color: NSColor?) -> String {
        guard let c = color?.usingColorSpace(.sRGB) else { return red }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
#endif
