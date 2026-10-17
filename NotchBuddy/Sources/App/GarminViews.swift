#if !APPSTORE
import SwiftUI
import Combine

// MARK: - Garmin (Yehonathan's vitals, from the Redline dashboard's nightly data)

/// Reads `~/redline/out/data.json`, which the Redline job writes every night at 21:00 from the
/// Garmin MCP. No Garmin login in Coucou: if the file is there, the card shows it.
/// Re-read when the file changes (checked when the card shows and every 15 minutes).
@MainActor
final class GarminStore: ObservableObject {
    static let shared = GarminStore()
    nonisolated static let pillId = "integration_garmin"
    nonisolated static let color  = "#22D3EE"

    struct Race: Equatable {
        let name: String
        let date: Date?
        let distance: Int
        let target: String
        let xc: Bool
    }

    struct Snapshot: Equatable {
        var readiness: Int?
        var readinessLevel: String
        var status: String
        var sleep: Int?
        var sleepSub: String
        var hrv: Int?
        var hrvLow: Int?
        var hrvHigh: Int?
        var steps: Int?
        var stepGoal: Int?
        var vo2: Double?
        var bannerTitle: String
        var bannerTone: String
        var generated: String
        var race: Race?
    }

    /// Everything else in the Redline data, for the full Garmin view.
    struct Details: Equatable {
        struct Day: Equatable, Identifiable { let id: String; let date: Date; let score: Int; let level: String }
        struct Activity: Equatable, Identifiable {
            let id: String
            let name: String
            let type: String
            let date: Date?
            let km: Double
            let minutes: Double
            let hr: Int?
            let effect: String
        }
        struct Rival: Equatable, Identifiable { let id: String; let name: String; let club: String; let best: String }
        struct Record: Equatable, Identifiable { let id: String; let event: String; let result: String; let date: String; let meet: String }

        var statusLabel: String
        var statusBand: String
        var loadRatio: Double?
        var loadStatus: String
        var loadBand: String
        var vo2Sub: String
        var hrvStatus: String
        var stress: Int?
        var bannerKicker: String
        var bannerTitle: String
        var bannerText: String
        var bannerTone: String
        var week: [Day]
        var predictions: [(String, Int)]
        var activities: [Activity]
        var raceVenue: String
        var raceEvent: String
        var raceRegistered: Bool
        var racePace: String
        var raceBasis: String
        var raceURL: URL?
        var rivals: [Rival]
        var records: [Record]

        static func == (a: Details, b: Details) -> Bool {
            a.week == b.week && a.activities == b.activities && a.bannerTitle == b.bannerTitle
                && a.records == b.records && a.rivals == b.rivals && a.stress == b.stress
        }
    }

    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var details: Details?
    @Published private(set) var missing = false
    /// Redline's fetcher is running (pulling today's numbers from Garmin).
    @Published private(set) var fetching = false
    /// When the data file was last written.
    @Published private(set) var updatedAt: Date?

    private var loadedAt: Date?
    private var lastFetch: Date?

    /// Older than this, the card asks Redline for fresh numbers (at most once an hour).
    nonisolated private static let staleAfter: TimeInterval = 3 * 3600
    private var poll: Timer?
    private var cancellables = Set<AnyCancellable>()

    nonisolated static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("redline/out/data.json")
    }

    private init() {
        refresh()
        poll = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { _ in
            Task { @MainActor in
                let s = GarminStore.shared
                s.refresh()
                // Keep the pill current through the day: a fetch when the data is 3 h old
                if AppState.shared.activeIntegrations.contains(GarminStore.pillId) { s.fetchIfStale() }
            }
        }
        AppState.shared.$tasks
            .map { $0.contains { $0.id == Self.pillId } }
            .removeDuplicates()
            .sink { [weak self] loaded in if loaded { self?.syncTaskName() } }
            .store(in: &cancellables)
    }

    /// Reads the file again only if it changed since the last read.
    func refresh() {
        let url = Self.fileURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else {
            missing = true; snapshot = nil; syncTaskName(); return
        }
        missing = false
        updatedAt = modified
        if let loadedAt, modified <= loadedAt, snapshot != nil { return }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        snapshot = Self.parse(json)
        details = Self.parseDetails(json)
        loadedAt = modified
        syncTaskName()
    }

    // MARK: Fresh numbers

    /// Runs Redline's `build.py` (Garmin + race data, no publishing) when the data is older than
    /// 3 hours, or right away with `force`. Never more than once an hour on its own.
    func fetchIfStale(force: Bool = false) {
        guard !fetching else { return }
        let age = updatedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if !force {
            guard age > Self.staleAfter else { return }
            if let lastFetch, Date().timeIntervalSince(lastFetch) < 3600 { return }
        }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("redline")
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("build.py").path) else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["build.py"]
        p.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["HOME"] = home
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { _ in
            Task { @MainActor in
                let s = GarminStore.shared
                s.fetching = false
                s.refresh()
            }
        }
        do {
            try p.run()
            fetching = true
            lastFetch = Date()
        } catch {
            fetching = false
        }
    }

    private static func latest<T>(_ dict: Any?) -> T? {
        guard let d = dict as? [String: Any], let key = d.keys.max() else { return nil }
        return d[key] as? T
    }

    private static func parse(_ j: [String: Any]) -> Snapshot {
        let today = j["today"] as? [String: Any] ?? [:]
        let readiness = today["readiness"] as? [String: Any]
        let sleep = today["sleep"] as? [String: Any]
        let hrv = today["hrv"] as? [String: Any]
        let vo2 = today["vo2"] as? [String: Any]
        let status = today["status"] as? [String: Any]
        let banner = j["banner"] as? [String: Any] ?? [:]
        let baseline = j["hrvBaseline"] as? [String: Any] ?? [:]

        var race: Race?
        if let r = j["nextRace"] as? [String: Any], let name = r["name"] as? String {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            race = Race(name: name,
                        date: (r["date"] as? String).flatMap { f.date(from: $0) },
                        distance: r["distance"] as? Int ?? 0,
                        target: (r["target"] as? [String: Any])?["headline"] as? String ?? "",
                        xc: r["xc"] as? Bool ?? false)
        }

        return Snapshot(
            readiness: readiness?["score"] as? Int,
            readinessLevel: readiness?["level"] as? String ?? "",
            status: status?["label"] as? String ?? "",
            sleep: sleep?["score"] as? Int,
            sleepSub: sleep?["sub"] as? String ?? "",
            hrv: hrv?["value"] as? Int,
            hrvLow: baseline["low"] as? Int,
            hrvHigh: baseline["high"] as? Int,
            steps: latest(j["steps"]),
            stepGoal: j["stepGoal"] as? Int,
            vo2: vo2?["value"] as? Double,
            bannerTitle: banner["title"] as? String ?? "",
            bannerTone: banner["tone"] as? String ?? "",
            generated: j["generated"] as? String ?? "",
            race: race)
    }

    private static func parseDetails(_ j: [String: Any]) -> Details {
        let today = j["today"] as? [String: Any] ?? [:]
        let status = today["status"] as? [String: Any] ?? [:]
        let acwr = today["acwr"] as? [String: Any] ?? [:]
        let banner = j["banner"] as? [String: Any] ?? [:]
        let race = j["nextRace"] as? [String: Any] ?? [:]
        let target = race["target"] as? [String: Any] ?? [:]
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let readiness = j["readiness"] as? [String: [String: Any]] ?? [:]
        let week = readiness.keys.sorted().suffix(7).compactMap { key -> Details.Day? in
            guard let date = day.date(from: key), let score = readiness[key]?["score"] as? Int else { return nil }
            return Details.Day(id: key, date: date, score: score, level: readiness[key]?["level"] as? String ?? "")
        }

        let paras = (banner["paras"] as? [String] ?? []).map(stripTags)

        let activities = (j["activities"] as? [[String: Any]] ?? []).enumerated().map { i, a in
            let detail = a["detail"] as? [String: Any] ?? [:]
            return Details.Activity(
                id: "\(i)-\(a["date"] as? String ?? "")",
                name: a["name"] as? String ?? "Activity",
                type: a["type"] as? String ?? "",
                date: (a["date"] as? String).flatMap { stamp.date(from: $0) },
                km: a["km"] as? Double ?? 0,
                minutes: a["min"] as? Double ?? 0,
                hr: a["hr"] as? Int,
                effect: detail["teLabel"] as? String ?? "")
        }

        let rivals = (race["rivals"] as? [[String: Any]] ?? []).enumerated().map { i, r in
            Details.Rival(id: "\(i)", name: r["name"] as? String ?? "",
                          club: r["club"] as? String ?? "",
                          best: (r["best"] as? [String: Any])?["result"] as? String ?? "")
        }

        let records = (j["pbs"] as? [[String: Any]] ?? []).enumerated().map { i, p in
            Details.Record(id: "\(i)", event: p["event"] as? String ?? "", result: p["result"] as? String ?? "",
                           date: p["date"] as? String ?? "", meet: p["meet"] as? String ?? "")
        }

        let predictions = (j["races"] as? [[String: Any]] ?? []).compactMap { r -> (String, Int)? in
            guard let d = r["d"] as? String, let t = r["t"] as? Int else { return nil }
            return (d, t)
        }

        return Details(
            statusLabel: status["label"] as? String ?? "",
            statusBand: status["band"] as? String ?? "",
            loadRatio: acwr["ratio"] as? Double,
            loadStatus: acwr["status"] as? String ?? "",
            loadBand: acwr["band"] as? String ?? "",
            vo2Sub: (today["vo2"] as? [String: Any])?["sub"] as? String ?? "",
            hrvStatus: (today["hrv"] as? [String: Any])?["status"] as? String ?? "",
            stress: latest(j["stress"]),
            bannerKicker: banner["kicker"] as? String ?? "",
            bannerTitle: banner["title"] as? String ?? "",
            bannerText: paras.first ?? "",
            bannerTone: banner["tone"] as? String ?? "",
            week: week,
            predictions: predictions,
            activities: activities,
            raceVenue: race["venue"] as? String ?? "",
            raceEvent: race["event"] as? String ?? "",
            raceRegistered: race["registered"] as? Bool ?? false,
            racePace: target["pace"] as? String ?? "",
            raceBasis: target["basis"] as? String ?? "",
            raceURL: (race["url"] as? String).flatMap(safeWebURL),
            rivals: rivals,
            records: records)
    }

    /// Redline's banner paragraphs carry a little HTML (<strong>): plain text here.
    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// The pill reads "Ready 25" (or "Garmin" with no data).
    private func syncTaskName() {
        guard let idx = AppState.shared.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }
        let base = PillCatalog.definition(for: Self.pillId)?.name ?? "Garmin"
        let name = snapshot?.readiness.map { String(localized: "Ready \($0)") } ?? base
        if AppState.shared.tasks[idx].name != name { AppState.shared.tasks[idx].name = name }
    }

    /// Readiness colours, like Garmin's: green, amber, orange, red.
    static func readinessColor(_ level: String) -> Color {
        switch level.uppercased() {
        case "PRIME", "HIGH": return Color(hex: "#22C55E")
        case "MODERATE":      return Color(hex: "#F5A524")
        case "LOW":           return Color(hex: "#FB923C")
        case "POOR":          return Color(hex: "#F4505E")
        default:              return Color(hex: color)
        }
    }

    func openDashboard() {
        if let url = URL(string: "https://claude.ai/artifact/XeU4SG8kYmMYSeNmB6k8nn") { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Card

struct GarminCardView: View {
    @ObservedObject private var store = GarminStore.shared

    var body: some View {
        Group {
            if let s = store.snapshot {
                content(s)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Garmin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Text("No Redline data yet: it appears after the nightly 21:00 refresh.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
                .padding(.leading, 108)
                .padding(.trailing, 30)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            store.refresh()
            store.fetchIfStale()
        }
    }

    /// "Updated today 10:42" with a ↻ to fetch now (spins while fetching).
    private var updatedLine: some View {
        HStack(spacing: 4) {
            Text(Self.updatedText(store.updatedAt, fetching: store.fetching))
                .font(.system(size: 9))
                .foregroundColor(Color(hex: "#5F646D"))
            Button { store.fetchIfStale(force: true) } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(hex: store.fetching ? "#22D3EE" : "#6B7079"))
                    .rotationEffect(.degrees(store.fetching ? 360 : 0))
                    .animation(store.fetching ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: store.fetching)
            }
            .buttonStyle(.plain)
            .disabled(store.fetching)
            .help(String(localized: "Get today's numbers from Garmin now"))
        }
    }

    static func updatedText(_ date: Date?, fetching: Bool) -> String {
        if fetching { return String(localized: "Updating from Garmin…") }
        guard let date else { return "" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return String(localized: "Updated today \(time)") }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Updated yesterday \(time)") }
        return String(localized: "Updated \(date.formatted(date: .abbreviated, time: .shortened))")
    }

    private func content(_ s: GarminStore.Snapshot) -> some View {
        let color = GarminStore.readinessColor(s.readinessLevel)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                // Readiness ring
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: CGFloat(s.readiness ?? 0) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: color.opacity(0.5), radius: 4)
                    VStack(spacing: 0) {
                        Text(s.readiness.map(String.init) ?? "–")
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(Color(hex: "#F5F6F8"))
                        Text(s.readinessLevel.capitalized)
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(color)
                    }
                }
                .frame(width: 50, height: 50)
                .help(s.bannerTitle.isEmpty ? String(localized: "Training readiness") : s.bannerTitle)

                // Four numbers
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        stat("moon.zzz.fill", s.sleep.map(String.init) ?? "–", String(localized: "sleep"),
                             tint: Color(hex: "#818CF8"), help: s.sleepSub)
                        stat("heart.fill", s.hrv.map(String.init) ?? "–", String(localized: "HRV"),
                             tint: hrvColor(s), help: hrvHelp(s))
                    }
                    GridRow {
                        stat("figure.walk", s.steps.map { Self.compact($0) } ?? "–", String(localized: "steps"),
                             tint: Color(hex: "#34D399"),
                             help: s.stepGoal.map { String(localized: "Goal \($0)") } ?? "")
                        stat("lungs.fill", s.vo2.map { String(format: "%.1f", $0) } ?? "–", "VO₂",
                             tint: Color(hex: "#22D3EE"), help: s.status)
                    }
                }
            }
            if let race = s.race { raceLine(race) }
            updatedLine
        }
        .padding(.top, 8)
        .padding(.leading, 108)
        .padding(.trailing, 30)   // the ↗ button sits top-right
    }

    private func stat(_ icon: String, _ value: String, _ label: String, tint: Color, help: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8.5)).foregroundColor(tint)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(Color(hex: "#F1F2F4"))
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(Color(hex: "#6B7079"))
        }
        .help(help)
    }

    private func raceLine(_ r: GarminStore.Race) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.checkered").font(.system(size: 8.5)).foregroundColor(Color(hex: "#F5A524"))
            Text(Self.raceWhen(r.date))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "#F5A524"))
            Text("\(r.distance) m · \(r.target)")
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(Color(hex: "#C5C8CD"))
                .lineLimit(1)
        }
        .help(r.name)
    }

    private func hrvColor(_ s: GarminStore.Snapshot) -> Color {
        guard let v = s.hrv, let low = s.hrvLow else { return Color(hex: "#F472B6") }
        return v < low ? Color(hex: "#FB923C") : Color(hex: "#F472B6")
    }

    private func hrvHelp(_ s: GarminStore.Snapshot) -> String {
        guard let low = s.hrvLow, let high = s.hrvHigh else { return "HRV" }
        return String(localized: "HRV · baseline \(low)–\(high)")
    }

    static func compact(_ n: Int) -> String {
        n >= 10_000 ? String(format: "%.1fk", Double(n) / 1000) : n.formatted()
    }

    static func raceWhen(_ date: Date?) -> String {
        guard let date else { return String(localized: "Next race") }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0: return String(localized: "Race done")
        case 0:    return String(localized: "Race today!")
        case 1:    return String(localized: "Race tomorrow")
        default:   return String(localized: "Race in \(days) days")
        }
    }
}
#endif
