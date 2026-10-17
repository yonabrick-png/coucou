#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - Study mode links (GitHub build only)

/// What a study session switches around it: Do Not Disturb (through two Shortcuts the user
/// makes once, since macOS has no public API for Focus) and a focus playlist in Apple Music.
/// Called by FocusTimer when a study session starts and ends.
@MainActor
enum StudyFocus {
    static let onShortcut  = "Coucou Study On"
    static let offShortcut = "Coucou Study Off"

    private static let dndKey      = "coucou.study.dnd"
    private static let playlistKey = "coucou.study.playlist"
    private static let pauseKey    = "coucou.study.pauseOnRest"

    /// Turn Do Not Disturb on while studying (needs the two shortcuts).
    static var dndEnabled: Bool {
        get { UserDefaults.standard.object(forKey: dndKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: dndKey) }
    }

    /// Apple Music playlist started with each study session; nil = no music.
    static var playlist: String? {
        get { UserDefaults.standard.string(forKey: playlistKey) }
        set { UserDefaults.standard.set(newValue, forKey: playlistKey) }
    }

    /// Pause the music when a study session ends (the break is quiet).
    static var pauseMusicOnRest: Bool {
        get { UserDefaults.standard.object(forKey: pauseKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: pauseKey) }
    }

    /// Whether the two shortcuts exist, read from `shortcuts list` (refreshed at most once a minute).
    private(set) static var shortcutsReady = false
    private static var checkedAt: Date?

    // MARK: Session

    static func studyStarted() {
        Task {
            await refreshShortcuts()
            if dndEnabled && shortcutsReady { runShortcut(onShortcut) }
        }
        if let name = playlist, !name.isEmpty {
            Task { _ = await MusicController.shared.playPlaylist(name) }
        }
    }

    /// `resting`: the session finished and a break follows (vs. reset or switched away).
    static func studyStopped(resting: Bool) {
        Task {
            await refreshShortcuts()
            if dndEnabled && shortcutsReady { runShortcut(offShortcut) }
        }
        if resting && pauseMusicOnRest && playlist != nil {
            MusicController.shared.pause()
        }
    }

    // MARK: Shortcuts

    static func refreshShortcuts(force: Bool = false) async {
        if !force, let at = checkedAt, Date().timeIntervalSince(at) < 60 { return }
        let names = await Task.detached { () -> [String] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            p.arguments = ["list"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        }.value
        shortcutsReady = names.contains(onShortcut) && names.contains(offShortcut)
        checkedAt = Date()
    }

    private static func runShortcut(_ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    static func openShortcutsApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
    }
}

// MARK: - Note → Claude

/// Text waiting for the Claude chat tab (a note sent with "Ask Claude").
@MainActor
enum ClaudeChatDraft {
    static var pending: String?

    /// Opens the chat tab with `text` in its box, ready to send.
    static func open(with text: String) {
        pending = text
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            AppState.shared.view = .prompt
        }
    }
}
#endif
