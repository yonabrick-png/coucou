#if !APPSTORE
import AppKit
import ApplicationServices

// MARK: - Claude Code sessions seen in the hooks

/// Where each Claude Code session lives, as its hooks describe it: the folder it started in and
/// the terminal tab it runs in. The notch prompt box uses it to reach a session.
/// Everything comes from the hooks on this Mac, never from what the user types.
@MainActor
final class ClaudeSessions: ObservableObject {
    static let shared = ClaudeSessions()

    struct Session: Identifiable, Equatable {
        /// Claude Code session id (what `--resume` takes).
        let id: String
        /// The folder the session started in: `--resume` must run there.
        var cwd: String
        var projectName: String
        /// Terminal bundle id (Terminal, iTerm…); nil for VS Code and unknown hosts.
        var hostApp: String?
        /// Controlling tty of the session ("/dev/ttys003"), empty until the hook reports it.
        var tty: String
        /// iTerm2 session unique id (the part after the colon of ITERM_SESSION_ID).
        var itermSessionId: String
        var lastSeen: Date
        /// `SessionEnd` arrived: the terminal tab no longer runs it.
        var ended: Bool
        /// The session's JSONL transcript (under ~/.claude/projects), for the chat tab.
        var transcriptPath: String = ""
        /// Between a prompt and the end of its turn.
        var isWorking: Bool = false
        var firstSeen: Date = Date()
    }

    @Published private(set) var sessions: [String: Session] = [:]
    /// Bumped on every recorded event, so the chat re-reads the transcript.
    @Published private(set) var revision = 0

    /// Sessions unheard of for this long are forgotten.
    private let maxAge: TimeInterval = 12 * 3600

    private init() {}

    func record(event: String, payload: [String: Any], hostApp: String?, projectName: String) {
        guard let id = payload["session_id"] as? String, !id.isEmpty, id != "unknown" else { return }
        var s = sessions[id] ?? Session(id: id, cwd: "", projectName: projectName, hostApp: hostApp,
                                        tty: "", itermSessionId: "", lastSeen: Date(), ended: false)
        // The first folder is the one the session was started in; later events may report a subfolder.
        if s.cwd.isEmpty, let cwd = payload["cwd"] as? String { s.cwd = cwd }
        s.projectName = projectName
        if let hostApp { s.hostApp = hostApp }
        if let tty = payload["tty"] as? String, Self.isSafeToken(tty), tty.hasPrefix("/dev/tty") { s.tty = tty }
        if let iterm = payload["iterm_session_id"] as? String,
           let uid = iterm.split(separator: ":").last.map(String.init), Self.isSafeToken(uid) {
            s.itermSessionId = uid
        }
        if let path = payload["transcript_path"] as? String, Self.isTranscriptPath(path) { s.transcriptPath = path }
        switch event {
        case "UserPromptSubmit":                    s.isWorking = true
        case "Stop", "StopFailure", "SessionEnd":   s.isWorking = false
        default: break
        }
        s.lastSeen = Date()
        s.ended = event == "SessionEnd"
        sessions[id] = s
        revision &+= 1
        prune()
    }

    /// Only Claude Code's own transcripts are ever read.
    nonisolated static func isTranscriptPath(_ path: String) -> Bool {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects").standardizedFileURL.path + "/"
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        return p.hasPrefix(root) && p.hasSuffix(".jsonl")
    }

    /// Most recently active first, live sessions before ended ones.
    var recent: [Session] {
        sessions.values.sorted { a, b in
            if a.ended != b.ended { return !a.ended }
            return a.lastSeen > b.lastSeen
        }
    }

    func session(id: String?) -> Session? {
        guard let id else { return nil }
        return sessions[id]
    }

    private func prune() {
        let now = Date()
        sessions = sessions.filter { now.timeIntervalSince($0.value.lastSeen) < maxAge }
        if sessions.count > 20 {
            let keep = Set(recent.prefix(20).map(\.id))
            sessions = sessions.filter { keep.contains($0.key) }
        }
    }

    /// Only letters, digits and `/ - _ .`: these values end up inside an AppleScript string.
    nonisolated static func isSafeToken(_ s: String) -> Bool {
        !s.isEmpty && s.count < 128 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "/-_.".contains($0)) }
    }
}

// MARK: - Sending a prompt

/// Delivers a prompt typed in the notch to a Claude Code session.
/// Live session in Terminal or iTerm2 → that exact tab comes to the front, the prompt is pasted
/// and Return is pressed (so you see it in the terminal). Ended session or closed tab → the
/// session continues in the background with `claude -p … --resume`, and the hooks show the run
/// on the Claude pill like any other turn.
@MainActor
enum ClaudePromptSender {
    enum Outcome: Equatable {
        /// Pasted into the session's terminal tab and sent.
        case typed(app: String)
        /// Continuing the session in the background.
        case background(project: String)
        /// A new session started in a Terminal window.
        case started(project: String)
        /// On the clipboard for you to paste (why is the message).
        case copied(String)
        case failed(String)
    }

    private static var running: [String: Process] = [:]

    static func send(_ raw: String, to session: ClaudeSessions.Session) async -> Outcome {
        // Claude Code would take a newline as Enter and send early: keep it on one line.
        let text = raw.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return .failed(String(localized: "Type something first")) }

        if !session.ended {
            switch await focusTab(of: session) {
            case .focused(let appName):
                return await pasteAndSend(text, into: session, appName: appName)
            case .notFound:
                break   // the tab is gone: continue the session in the background
            case .unsupported(let appName):
                copyToClipboard(text)
                activate(session.hostApp)
                return .copied(String(localized: "On the clipboard: paste it in \(appName) with ⌘V"))
            case .denied(let appName):
                copyToClipboard(text)
                return .copied(String(localized: "Allow Coucou to control \(appName) (Settings → Privacy → Automation). On the clipboard for now."))
            }
        }
        return runInBackground(text, session: session)
    }

    // MARK: New session

    /// Opens a Terminal window in `folder` running `claude "<prompt>"`.
    static func startNewSession(_ raw: String, in folder: String) async -> Outcome {
        let text = raw.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return .failed(String(localized: "Type something first")) }
        var isDirectory: ObjCBool = false
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory) && isDirectory.boolValue
            ? folder : home
        let claude = claudeExecutable() ?? "claude"
        // Shell words in single quotes, then the whole command as an AppleScript string.
        let command = "cd \(shellQuote(dir)) && \(shellQuote(claude)) \(shellQuote(text))"
        let script = """
        tell application id "com.apple.Terminal"
            activate
            do script "\(appleScriptQuote(command))"
        end tell
        """
        switch await runAppleScript(script) {
        case .value:
            return .started(project: dir == home ? "~" : URL(fileURLWithPath: dir).lastPathComponent)
        case .denied:
            copyToClipboard(text)
            return .copied(String(localized: "Allow Coucou to control Terminal (Settings → Privacy → Automation). On the clipboard for now."))
        case .error:
            return .failed(String(localized: "Couldn't open Terminal"))
        }
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: Terminal tab

    private enum TabLookup {
        case focused(String), notFound, unsupported(String), denied(String)
    }

    private static func appName(_ bundleId: String?) -> String {
        switch bundleId {
        case "com.apple.Terminal":      return "Terminal"
        case "com.googlecode.iterm2":   return "iTerm"
        case nil:                       return "VS Code"
        default:
            guard let bundleId,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return "the terminal" }
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
    }

    /// Brings the session's own tab to the front. Only Terminal (matched by tty) and iTerm2
    /// (matched by session id) can be addressed one tab at a time.
    private static func focusTab(of s: ClaudeSessions.Session) async -> TabLookup {
        let name = appName(s.hostApp)
        let script: String
        switch s.hostApp {
        case "com.apple.Terminal":
            guard !s.tty.isEmpty else { return .unsupported(name) }
            script = """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(s.tty)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
                return "notfound"
            end tell
            """
        case "com.googlecode.iterm2":
            guard !s.itermSessionId.isEmpty else { return .unsupported(name) }
            script = """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with ss in sessions of t
                            if unique id of ss is "\(s.itermSessionId)" then
                                select w
                                tell t to select
                                tell ss to select
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
                return "notfound"
            end tell
            """
        default:
            return .unsupported(name)
        }
        guard let bundleId = s.hostApp,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleId })
        else { return .notFound }   // the terminal quit: the session is gone with it

        switch await runAppleScript(script) {
        case .value("ok"):  return .focused(name)
        case .value:        return .notFound
        case .denied:       return .denied(name)
        case .error:        return .unsupported(name)
        }
    }

    private static func pasteAndSend(_ text: String, into s: ClaudeSessions.Session, appName: String) async -> Outcome {
        // Never paste into whatever else happens to be in front.
        var front = false
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(80))
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == s.hostApp { front = true; break }
        }
        guard front else {
            copyToClipboard(text)
            return .copied(String(localized: "\(appName) didn't come to the front. On the clipboard: paste with ⌘V"))
        }
        try? await Task.sleep(for: .milliseconds(120))
        switch FlowPaste.insert(text) {
        case .pasted:
            try? await Task.sleep(for: .milliseconds(180))
            pressReturn()
            return .typed(app: appName)
        case .noField:
            return .copied(String(localized: "Couldn't find where to type. On the clipboard: paste with ⌘V"))
        case .noAccess:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return .copied(String(localized: "Coucou needs Accessibility to type for you. On the clipboard for now."))
        }
    }

    private static func pressReturn() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let returnKey = CGKeyCode(36)
        CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private static func copyToClipboard(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    private static func activate(_ bundleId: String?) {
        let id = bundleId ?? "com.microsoft.VSCode"
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }?.activate()
    }

    // MARK: Background run

    private static func runInBackground(_ text: String, session s: ClaudeSessions.Session) -> Outcome {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: s.cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failed(String(localized: "The session's folder is gone"))
        }
        guard running[s.id] == nil else {
            return .failed(String(localized: "Claude is still working on the last one"))
        }
        guard let claude = claudeExecutable() else {
            return .failed(String(localized: "Can't find the claude command"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = ["-p", text, "--resume", s.id]
        process.currentDirectoryURL = URL(fileURLWithPath: s.cwd)
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = [URL(fileURLWithPath: claude).deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
                       "/usr/bin", "/bin", "/usr/sbin", "/sbin", "\(home)/.local/bin", env["PATH"] ?? ""].joined(separator: ":")
        // The hooks route events by client: this keeps the run on the Claude pill, where its
        // permission requests are approved by hand like any other turn.
        env["TERM_PROGRAM"] = "vscode"
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        // Output goes to a file (a pipe could fill up and stall claude).
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/NotchBuddy/notch-prompt-last.log")
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let output = try? FileHandle(forWritingTo: logURL)
        process.standardOutput = output ?? FileHandle.nullDevice
        process.standardError = output ?? FileHandle.nullDevice
        let id = s.id
        process.terminationHandler = { _ in
            try? output?.close()
            Task { @MainActor in running[id] = nil }
        }
        do {
            try process.run()
            running[id] = process
            return .background(project: s.projectName)
        } catch {
            return .failed(String(localized: "Couldn't start claude"))
        }
    }

    /// Where `claude` usually lives; the app doesn't get the shell's PATH.
    static func claudeExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.claude/local/claude",
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: AppleScript

    private enum ScriptResult: Sendable { case value(String), denied, error }

    private static let queue = DispatchQueue(label: "fr.louisraille.coucou.claude-prompt")

    private static func runAppleScript(_ source: String) async -> ScriptResult {
        await withCheckedContinuation { cont in
            queue.async {
                guard let script = NSAppleScript(source: source) else { cont.resume(returning: .error); return }
                var errDict: NSDictionary?
                let desc = script.executeAndReturnError(&errDict)
                if let errDict {
                    let code = (errDict[NSAppleScript.errorNumber] as? Int) ?? 0
                    cont.resume(returning: code == -1743 ? .denied : .error)
                    return
                }
                cont.resume(returning: .value(desc.stringValue ?? ""))
            }
        }
    }
}
#endif
