#if !APPSTORE
import SwiftUI

// MARK: - School (Yehonathan HQ, the homework dashboard) — GitHub build only

/// Reads `~/homework-tracker/out/hq.json`, which the HQ sync job builds from the dashboard's
/// homework, the Notion tests and projects and the timetable. No login in Coucou: the sync
/// (a short Claude Code session, `sync/run-sync.sh`) does the talking. Homework ticked off in the
/// notch shows as done straight away and is written back to the dashboard by the next sync.
@MainActor
final class SchoolStore: ObservableObject {
    static let shared = SchoolStore()

    struct Lesson: Identifiable, Equatable {
        var id: String { "\(period)-\(subject.id)" }
        let period: Int
        let subject: Subject
    }

    struct Subject: Equatable {
        let id: String
        let short: String
        let name: String
        let room: String
        let color: String
        let slots: [[Int]]   // [dayOfWeek (0 = Sunday), period]
    }

    struct Homework: Identifiable, Equatable {
        let id: String
        let title: String
        let subject: String
        let due: Date?
        let kind: String     // hw | test | project
        var done: Bool
    }

    struct Test: Identifiable, Equatable {
        var id: String { url.isEmpty ? "\(title)-\(dueText)" : url }
        let title: String
        let kind: String     // test | project
        let due: Date?
        let dueText: String
        let status: String
        let subject: String
        let url: String
    }

    @Published private(set) var subjects: [String: Subject] = [:]
    @Published private(set) var tasks: [Homework] = []
    @Published private(set) var tests: [Test] = []
    @Published private(set) var practice: [Int: String] = [:]
    @Published private(set) var updatedAt: Date?
    @Published private(set) var syncing = false
    /// The last sync ended in an error (see ~/homework-tracker/logs).
    @Published private(set) var syncFailed = false
    /// The sync can't start: ~/homework-tracker isn't trusted in Claude Code yet (one-time step).
    @Published private(set) var needsSetup = false
    @Published private(set) var missing = false

    static let dashboardURL = URL(string: "https://claude.ai/artifact/Du2SJSRzpEwLVE13gLYYoS")!

    nonisolated static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("homework-tracker")
    }
    private var out: URL { Self.dir.appendingPathComponent("out") }
    private var loadedAt: Date?
    private var lastSync: Date?
    private var pending: Set<String> = []
    private var tickSync: DispatchWorkItem?

    private init() {
        pending = Set(readPending())
        refresh()   // and again each time the tab opens, or a sync ends: nothing runs while hidden
    }

    // MARK: Reading

    func refresh() {
        readStatus()
        let url = out.appendingPathComponent("hq.json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else { missing = true; return }
        missing = false
        updatedAt = modified
        if let loadedAt, modified <= loadedAt { return }
        guard let data = try? Data(contentsOf: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        loadedAt = modified
        pending = Set(readPending())

        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"

        var subs: [String: Subject] = [:]
        for c in j["classes"] as? [[String: Any]] ?? [] {
            guard let id = c["id"] as? String else { continue }
            subs[id] = Subject(id: id, short: c["short"] as? String ?? id, name: c["name"] as? String ?? id,
                               room: c["room"] as? String ?? "", color: c["color"] as? String ?? "#A99B8A",
                               slots: c["slots"] as? [[Int]] ?? [])
        }
        subjects = subs
        practice = Dictionary(uniqueKeysWithValues: (j["practice"] as? [String: String] ?? [:])
            .compactMap { k, v in Int(k).map { ($0, v) } })
        tasks = (j["tasks"] as? [[String: Any]] ?? []).compactMap { t in
            guard let id = t["id"] as? String else { return nil }
            return Homework(id: id, title: t["title"] as? String ?? "", subject: t["subject"] as? String ?? "other",
                        due: (t["due"] as? String).flatMap { day.date(from: $0) }, kind: t["kind"] as? String ?? "hw",
                        done: (t["done"] as? Bool ?? false) || pending.contains(id))
        }
        tests = (j["tests"] as? [[String: Any]] ?? []).map { t in
            let due = t["due"] as? String ?? ""
            return Test(title: t["title"] as? String ?? "", kind: t["kind"] as? String ?? "test",
                        due: day.date(from: due), dueText: due, status: t["status"] as? String ?? "",
                        subject: t["subject"] as? String ?? "other", url: t["url"] as? String ?? "")
        }
    }

    private func readStatus() {
        guard let data = try? Data(contentsOf: out.appendingPathComponent("status.json")),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { syncing = false; return }
        // A "running" status older than 10 minutes is a crashed run
        let started = (j["started"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        syncing = (j["state"] as? String) == "running" && (started.map { Date().timeIntervalSince($0) < 600 } ?? false)
        syncFailed = (j["state"] as? String) == "done" && (j["ok"] as? Bool) == false
        needsSetup = syncFailed && (j["reason"] as? String) == "untrusted"
    }

    private func readPending() -> [String] {
        guard let data = try? Data(contentsOf: out.appendingPathComponent("pending.json")),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return j["done"] as? [String] ?? []
    }

    // MARK: Ticking off

    /// Marks homework done here at once; the next sync (started ~15 s later, so several ticks
    /// travel together) writes it to the dashboard.
    func tick(_ id: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }), !tasks[i].done else { return }
        tasks[i].done = true
        pending.insert(id)
        let file = out.appendingPathComponent("pending.json")
        if let data = try? JSONSerialization.data(withJSONObject: ["done": Array(pending).sorted()]) {
            try? data.write(to: file, options: .atomic)
        }
        tickSync?.cancel()
        let work = DispatchWorkItem { Task { @MainActor in SchoolStore.shared.sync(force: true) } }
        tickSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    // MARK: Syncing

    /// Runs the HQ sync (dashboard + Notion → hq.json) when the data is older than 3 hours, or
    /// right away with `force`. Never more than once every 10 minutes on its own.
    func sync(force: Bool = false) {
        readStatus()
        guard !syncing else { return }
        let age = updatedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if !force {
            guard age > 3 * 3600 else { return }
            if let lastSync, Date().timeIntervalSince(lastSync) < 600 { return }
        }
        let script = Self.dir.appendingPathComponent("sync/run-sync.sh")
        guard FileManager.default.fileExists(atPath: script.path) else { return }
        lastSync = Date()
        syncing = true
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        p.terminationHandler = { _ in
            Task { @MainActor in
                let s = SchoolStore.shared
                s.loadedAt = nil
                s.refresh()
            }
        }
        try? p.run()
    }

    func openDashboard() { NSWorkspace.shared.open(Self.dashboardURL) }

    /// The one-time trust step: copies the command and opens Terminal, where Yehonathan pastes it.
    func startSetup() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("cd ~/homework-tracker && claude", forType: .string)
        if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func open(_ test: Test) {
        if let url = URL(string: test.url), url.scheme == "https" { NSWorkspace.shared.open(url) }
    }

    // MARK: Timetable

    /// The day whose lessons to show: today until 15:00 on a school day (Sun–Fri with lessons),
    /// otherwise the next day that has lessons.
    func lessonDay(now: Date = Date()) -> (date: Date, lessons: [Lesson]) {
        let cal = Calendar.current
        for offset in 0..<8 {
            guard let date = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            if offset == 0 && cal.component(.hour, from: now) >= 15 { continue }
            let list = lessons(on: date)
            if !list.isEmpty { return (date, list) }
        }
        return (now, [])
    }

    func lessons(on date: Date) -> [Lesson] {
        let dow = Calendar.current.component(.weekday, from: date) - 1   // 0 = Sunday
        var out: [Lesson] = []
        for s in subjects.values where s.id != "other" {
            for slot in s.slots where slot.count == 2 && slot[0] == dow {
                out.append(Lesson(period: slot[1], subject: s))
            }
        }
        return out.sorted { $0.period < $1.period }
    }

    func subject(_ id: String) -> Subject {
        subjects[id] ?? Subject(id: "other", short: "Other", name: "Other", room: "", color: "#A99B8A", slots: [])
    }

    /// Practice tonight ("Practice" or "Stairs", 17:00–20:00), from the dashboard's practice days.
    var practiceToday: String? {
        practice[Calendar.current.component(.weekday, from: Date()) - 1]
    }
}
#endif
