#if !APPSTORE
import Foundation
import AppKit
import Combine

// MARK: - Music Controller

/// Observes Apple Music state via distributed notifications and provides playback controls.
/// Singleton, @MainActor, GitHub build only.
/// Like Spotify, nothing runs on a timer: state arrives with Music's notification and the
/// card extrapolates the position from the last anchor.
@MainActor
final class MusicController: ObservableObject {
    static let shared = MusicController()
    nonisolated static let pillId   = "integration_music"
    nonisolated static let bundleId = "com.apple.Music"
    nonisolated static let red      = "#FA2D48"

    @Published var trackTitle: String?
    @Published var artist: String?
    @Published var album: String?

    /// Track length in seconds (0 when unknown, e.g. a radio stream).
    @Published private(set) var duration: Double = 0
    /// Position (seconds) at `positionDate`; while playing, the real position runs on from there.
    @Published private(set) var positionAnchor: Double = 0
    @Published private(set) var positionDate = Date()
    @Published private(set) var shuffling = false
    @Published private(set) var repeating = false
    @Published private(set) var volume: Int = 50
    @Published private(set) var artwork: NSImage?

    nonisolated private static let grantedKey = "coucou.musicAutomationGranted"

    private var notifTokens: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "fr.louisraille.coucou.music")

    /// Identifies the loaded track (raw name, artist and album) for the artwork cache.
    private var trackKey: String?
    private var artworkCache: [String: NSImage] = [:]
    private var artworkCacheOrder: [String] = []
    private var artworkLoadingKey: String?
    private var pendingVolume: Int?
    private var volumeTask: Task<Void, Never>?

    private var isPillActive: Bool {
        AppState.shared.activeIntegrations.contains(Self.pillId)
    }

    private var automationGranted: Bool {
        UserDefaults.standard.bool(forKey: Self.grantedKey)
    }

    var isPlaying: Bool { AppState.shared.musicPlaying }

    /// Where playback is now, extrapolated from the last anchor.
    func position(at date: Date) -> Double {
        let elapsed = isPlaying ? date.timeIntervalSince(positionDate) : 0
        let p = positionAnchor + max(0, elapsed)
        return duration > 0 ? min(p, duration) : p
    }

    private init() {
        // playerInfo fires whenever Music state changes (play/pause/track change).
        // Extract Sendable values before crossing into @MainActor.
        let tok1 = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let info        = notif.userInfo
            let playerState = info?["Player State"] as? String
            let name        = info?["Name"]          as? String
            let artist      = info?["Artist"]        as? String
            let album       = info?["Album"]         as? String
            let totalTimeMs = (info?["Total Time"]   as? NSNumber)?.doubleValue
            Task { @MainActor [weak self] in
                self?.handlePlayerInfo(playerState: playerState, name: name, artist: artist,
                                       album: album, totalTimeMs: totalTimeMs)
            }
        }
        notifTokens.append(tok1)

        // Track Music launch — read current state only if granted and pill active
        let tok2 = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let bundleId = (notif.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            guard bundleId == MusicController.bundleId else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isPillActive, self.automationGranted else { return }
                self.refresh()
            }
        }
        notifTokens.append(tok2)

        // Clear state when Music quits
        let tok3 = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let bundleId = (notif.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            guard bundleId == MusicController.bundleId else { return }
            Task { @MainActor [weak self] in self?.clearState() }
        }
        notifTokens.append(tok3)

        // Observe activeIntegrations — pill activated → initial read; deactivated → clear
        AppState.shared.$activeIntegrations
            .sink { [weak self] integrations in
                guard let self else { return }
                if integrations.contains(Self.pillId) {
                    if self.isMusicRunning(), self.automationGranted {
                        self.refresh()
                    }
                } else {
                    self.clearState()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Private helpers

    private func isMusicRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Self.bundleId }
    }

    // MARK: - Metadata cleaners

    private static func shortTitle(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        var s = raw
        // Cut at first " - "
        if let r = s.range(of: " - ") {
            s = String(s[..<r.lowerBound])
        }
        // Strip trailing (...) or [...] groups repeatedly
        var changed = true
        while changed {
            changed = false
            let t = s.trimmingCharacters(in: .whitespaces)
            guard let last = t.last, (last == ")" || last == "]") else { break }
            let open: Character = last == ")" ? "(" : "["
            if let idx = t.lastIndex(of: open) {
                let candidate = String(t[..<idx]).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty { s = candidate; changed = true }
            } else { break }
        }
        let result = s.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? raw : result
    }

    private static func shortArtist(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        let lower = raw.lowercased()
        for tag in [" feat.", " ft."] {
            if let r = lower.range(of: tag) {
                let result = String(raw[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                return result.isEmpty ? raw : result
            }
        }
        return raw
    }

    // MARK: - State

    private func handlePlayerInfo(playerState: String?, name: String?, artist inputArtist: String?,
                                  album inputAlbum: String?, totalTimeMs: Double?) {
        guard isPillActive else { return }

        applyTrack(name: name ?? "", artist: inputArtist ?? "", album: inputAlbum ?? "")
        if let totalTimeMs, totalTimeMs > 0 { duration = totalTimeMs / 1000 }
        setPlaying(playerState == "Playing")

        // The notification carries no position, shuffle, repeat, volume or artwork:
        // read them when we may (never triggers the Automation prompt by itself).
        if automationGranted { refresh() }
    }

    /// Stores the cleaned metadata; a different track resets the artwork.
    private func applyTrack(name: String, artist rawArtist: String, album rawAlbum: String) {
        trackTitle = name.isEmpty ? nil : Self.shortTitle(name)
        artist     = rawArtist.isEmpty ? nil : Self.shortArtist(rawArtist)
        album      = rawAlbum.isEmpty ? nil : rawAlbum

        let key = name.isEmpty ? nil : "\(name)|\(rawArtist)|\(rawAlbum)"
        if key != trackKey {
            trackKey = key
            artwork = key.flatMap { artworkCache[$0] }
        }
        syncTaskName()
    }

    private func setPlaying(_ playing: Bool) {
        let wasPlaying = AppState.shared.musicPlaying
        if playing != wasPlaying {
            // Freeze or restart the clock at the current position
            anchor(position(at: Date()))
        }
        AppState.shared.musicPlaying = playing
        // Reveal only on transition from not-playing → playing
        if playing && !wasPlaying {
            NotificationCenter.default.post(name: .musicReveal, object: nil)
        }
    }

    private func anchor(_ position: Double) {
        positionAnchor = max(0, position)
        positionDate = Date()
    }

    private func clearState() {
        trackTitle = nil; artist = nil; album = nil
        trackKey = nil
        artwork = nil
        duration = 0
        anchor(0)
        AppState.shared.musicPlaying = false
        syncTaskName()
    }

    private func syncTaskName() {
        guard let idx = AppState.shared.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }
        let title = trackTitle ?? ""
        AppState.shared.tasks[idx].name = title.isEmpty
            ? (PillCatalog.definition(for: Self.pillId)?.name ?? "Apple Music")
            : title
    }

    // MARK: - Reading Music

    /// Reads track, position, duration, shuffle, repeat and volume, then the artwork if missing.
    /// Never launches Music. The first call is what makes macOS ask for Automation.
    func refresh() {
        guard isPillActive, isMusicRunning() else { return }
        Task {
            let result = await runAppleScript("""
                tell application id "com.apple.Music"
                    set ps to player state as string
                    if ps is "stopped" then return {ps}
                    try
                        set tr to current track
                        set n to name of tr
                    on error
                        return {"stopped"}
                    end try
                    set ar to ""
                    set al to ""
                    set du to 0
                    set pp to 0
                    set sh to false
                    set rp to "off"
                    try
                        set ar to artist of tr
                    end try
                    try
                        set al to album of tr
                    end try
                    try
                        set du to duration of tr
                    end try
                    try
                        set pp to player position
                    end try
                    try
                        set sh to shuffle enabled
                    end try
                    try
                        set rp to song repeat as string
                    end try
                    return {ps, n, ar, al, du, pp, sh, rp, sound volume}
                end tell
            """)
            guard case .success(let v) = result, let ps = v.first?.text else { return }
            guard isPillActive else { return }
            if ps == "stopped" || v.count < 9 {
                applyTrack(name: "", artist: "", album: "")
                setPlaying(false)
                return
            }
            applyTrack(name: v[1].text, artist: v[2].text, album: v[3].text)
            duration = max(0, v[4].number)
            anchor(v[5].number)
            setPlaying(ps == "playing")
            shuffling = v[6].flag
            repeating = v[7].text != "off" && !v[7].text.isEmpty
            if pendingVolume == nil { volume = Int(v[8].number.rounded()) }
            if artwork == nil, let key = trackKey { loadArtwork(key: key) }
        }
    }

    // MARK: - Artwork

    /// Library tracks carry their cover; streamed catalog tracks often don't, so fall back to
    /// Apple's public iTunes Search API (artist + album only, no account).
    private func loadArtwork(key: String) {
        if let cached = artworkCache[key] { artwork = cached; return }
        guard artworkLoadingKey != key else { return }
        artworkLoadingKey = key
        let searchArtist = artist ?? ""
        let searchAlbum  = album ?? trackTitle ?? ""
        Task {
            defer { if artworkLoadingKey == key { artworkLoadingKey = nil } }
            var image: NSImage?
            if let data = await readArtworkData() { image = NSImage(data: data) }
            if image == nil, !searchArtist.isEmpty || !searchAlbum.isEmpty,
               let url = await Self.catalogArtworkURL(artist: searchArtist, album: searchAlbum),
               let (data, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                image = NSImage(data: data)
            }
            guard let image else { return }
            cacheArtwork(image, for: key)
            if trackKey == key { artwork = image }
        }
    }

    private func cacheArtwork(_ image: NSImage, for key: String) {
        artworkCache[key] = image
        artworkCacheOrder.removeAll { $0 == key }
        artworkCacheOrder.append(key)
        while artworkCacheOrder.count > 12 {
            artworkCache[artworkCacheOrder.removeFirst()] = nil
        }
    }

    /// Raw bytes of the current track's first artwork (JPEG or PNG), nil when it has none.
    private func readArtworkData() async -> Data? {
        await withCheckedContinuation { cont in
            queue.async {
                let source = #"tell application id "com.apple.Music" to get raw data of artwork 1 of current track"#
                guard let script = NSAppleScript(source: source) else { cont.resume(returning: nil); return }
                var errDict: NSDictionary?
                let desc = script.executeAndReturnError(&errDict)
                guard errDict == nil else { cont.resume(returning: nil); return }
                let data = desc.data
                cont.resume(returning: data.isEmpty ? nil : data)
            }
        }
    }

    /// Cover URL from the iTunes catalog, upscaled to 300 px; only Apple's image CDN is accepted.
    nonisolated private static func catalogArtworkURL(artist: String, album: String) async -> URL? {
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(album)".trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = comps.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let small = first["artworkUrl100"] as? String,
              let art = safeWebURL(small.replacingOccurrences(of: "100x100bb", with: "300x300bb")),
              art.scheme == "https",
              let host = art.host?.lowercased(), host.hasSuffix(".mzstatic.com")
        else { return nil }
        return art
    }

    // MARK: - Playback controls

    func getVolume() async -> Int? {
        guard isMusicRunning() else { return nil }
        let result = await runAppleScript(#"tell application id "com.apple.Music" to return sound volume"#)
        if case .success(let vals) = result, let str = vals.first?.text, let v = Int(str) { return v }
        return nil
    }

    func playPause() {
        guard isMusicRunning() else { return }
        setPlaying(!isPlaying)   // optimistic; Music's notification confirms
        Task { await runAppleScript(#"tell application id "com.apple.Music" to playpause"#) }
    }

    func play() {
        guard isMusicRunning() else { return }
        Task { await runAppleScript(#"tell application id "com.apple.Music" to play"#) }
    }

    func pause() {
        guard isMusicRunning() else { return }
        Task { await runAppleScript(#"tell application id "com.apple.Music" to pause"#) }
    }

    /// Coalesced: a slider drag sends at most one Apple Event every 120 ms.
    func setVolume(_ pct: Int) {
        let v = max(0, min(100, pct))
        volume = v
        pendingVolume = v
        guard volumeTask == nil else { return }
        volumeTask = Task {
            while let v = pendingVolume {
                pendingVolume = nil
                await runAppleScript(#"tell application id "com.apple.Music" to set sound volume to \#(v)"#)
                try? await Task.sleep(for: .milliseconds(120))
            }
            volumeTask = nil
        }
    }

    func nextTrack() {
        guard isMusicRunning() else { return }
        Task { await runAppleScript(#"tell application id "com.apple.Music" to next track"#) }
    }

    func previousTrack() {
        guard isMusicRunning() else { return }
        Task { await runAppleScript(#"tell application id "com.apple.Music" to back track"#) }
    }

    func seek(to seconds: Double) {
        guard isMusicRunning(), duration > 0 else { return }
        let target = min(max(0, seconds), max(0, duration - 1))
        anchor(target)
        Task { await runAppleScript(#"tell application id "com.apple.Music" to set player position to \#(Int(target.rounded()))"#) }
    }

    func setShuffling(_ on: Bool) {
        guard isMusicRunning() else { return }
        shuffling = on
        Task { await runAppleScript(#"tell application id "com.apple.Music" to set shuffle enabled to \#(on)"#) }
    }

    func setRepeating(_ on: Bool) {
        guard isMusicRunning() else { return }
        repeating = on
        let mode = on ? "all" : "off"
        Task { await runAppleScript(#"tell application id "com.apple.Music" to set song repeat to \#(mode)"#) }
    }

    func adjustVolume(by delta: Int) {
        setVolume(volume + delta)
    }

    func playArtist(_ name: String) async -> Bool {
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let result = await runAppleScript("""
            tell application id "com.apple.Music"
                try
                    set tr to (first track of library playlist 1 whose artist contains "\(escaped)")
                    play tr
                    return "ok"
                on error
                    return "notfound"
                end try
            end tell
        """)
        if case .success(let vals) = result, vals.first?.text == "ok" { return true }
        return false
    }

    func playSearch(_ query: String) async -> Bool {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let result = await runAppleScript("""
            tell application id "com.apple.Music"
                try
                    set tr to (first track of library playlist 1 whose name contains "\(escaped)" or artist contains "\(escaped)")
                    play tr
                    return "ok"
                on error
                    return "notfound"
                end try
            end tell
        """)
        if case .success(let vals) = result, vals.first?.text == "ok" { return true }
        return false
    }

    func playPlaylist(_ name: String) async -> Bool {
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let result = await runAppleScript(#"tell application id "com.apple.Music" to play playlist "\#(escaped)""#)
        if case .success(_) = result { return true }
        return false
    }

    func openMusic() {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == Self.bundleId }) {
            app.activate(options: .activateIgnoringOtherApps)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - AppleScript runner

    /// One item of an AppleScript result, read three ways so callers pick the one they expect.
    struct ScriptValue: Sendable {
        let text: String
        let number: Double
        let flag: Bool
    }

    enum ScriptResult: Sendable { case success([ScriptValue]), denied, error }

    @discardableResult
    private func runAppleScript(_ source: String) async -> ScriptResult {
        let grantedKey = Self.grantedKey
        let result: ScriptResult = await withCheckedContinuation { cont in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    cont.resume(returning: .error); return
                }
                var errDict: NSDictionary?
                let desc = script.executeAndReturnError(&errDict)
                if let errDict {
                    let code = (errDict[NSAppleScript.errorNumber] as? Int) ?? 0
                    cont.resume(returning: code == -1743 ? .denied : .error)
                    return
                }
                // Extract values on this queue (NSAppleEventDescriptor isn't Sendable)
                func value(_ d: NSAppleEventDescriptor?) -> ScriptValue {
                    ScriptValue(text: d?.stringValue ?? "", number: d?.doubleValue ?? 0, flag: d?.booleanValue ?? false)
                }
                let count = desc.numberOfItems
                let values = count > 0 ? (1...count).map { value(desc.atIndex($0)) } : [value(desc)]
                cont.resume(returning: .success(values))
            }
        }
        switch result {
        case .success:
            UserDefaults.standard.set(true, forKey: grantedKey)
            AppState.shared.musicAutomationDenied = false
        case .denied:
            UserDefaults.standard.set(false, forKey: grantedKey)
            AppState.shared.musicAutomationDenied = true
        case .error:
            break
        }
        return result
    }
}
#endif
