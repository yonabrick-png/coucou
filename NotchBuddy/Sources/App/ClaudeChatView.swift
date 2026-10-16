#if !APPSTORE
import SwiftUI

// MARK: - Claude chat (the notch's chat tab, GitHub build only)
//
// The chat tab talks to Claude Code instead of a chat API: it shows the chosen session's
// conversation, read from its own transcript, and sends the next prompt through
// ClaudePromptSender (typed into the session's terminal tab, run in the background when the
// session has ended, or a new session in Terminal).

/// One line of the conversation as the chat shows it.
struct ClaudeChatLine: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case user, assistant, tools }
    let id: String
    let kind: Kind
    var text: String
}

enum ClaudeTranscript {
    /// Reads the tail of a transcript (the last ~1 MB) into chat lines: your prompts, Claude's
    /// text, and one grey line per run of tool calls. Thinking, meta and subagent lines are skipped.
    static func read(path: String, limit: Int = 60) -> [ClaudeChatLine] {
        guard ClaudeSessions.isTranscriptPath(path),
              let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 1_000_000
        let start = size > window ? size - window : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return [] }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }   // cut mid-line

        var out: [ClaudeChatLine] = []
        for raw in lines {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(raw)) as? [String: Any] else { continue }
            let type = obj["type"] as? String ?? ""
            guard type == "user" || type == "assistant" else { continue }
            if obj["isSidechain"] as? Bool == true || obj["isMeta"] as? Bool == true
                || obj["isCompactSummary"] as? Bool == true { continue }
            guard let message = obj["message"] as? [String: Any] else { continue }
            let uuid = obj["uuid"] as? String ?? UUID().uuidString

            var texts: [String] = []
            var tools: [String] = []
            if let s = message["content"] as? String {
                texts.append(s)
            } else if let blocks = message["content"] as? [[String: Any]] {
                for b in blocks {
                    switch b["type"] as? String {
                    case "text":     if let t = b["text"] as? String { texts.append(t) }
                    case "tool_use": tools.append(b["name"] as? String ?? "Tool")
                    default:         break   // thinking, tool_result, images
                    }
                }
            }
            // Slash commands, hook output and other markup Claude Code writes as "user" text
            let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let isMarkup = text.hasPrefix("<") || text.hasPrefix("Caveat:")

            if type == "user" {
                if !text.isEmpty && !isMarkup { out.append(ClaudeChatLine(id: uuid, kind: .user, text: text)) }
            } else {
                if !text.isEmpty {
                    // One reply can arrive as several lines: glue consecutive text together
                    if let last = out.last, last.kind == .assistant {
                        out[out.count - 1].text += "\n\n" + text
                    } else {
                        out.append(ClaudeChatLine(id: uuid, kind: .assistant, text: text))
                    }
                }
                if !tools.isEmpty {
                    if let last = out.last, last.kind == .tools {
                        out[out.count - 1].text += " · " + tools.joined(separator: " · ")
                    } else {
                        out.append(ClaudeChatLine(id: uuid + "-tools", kind: .tools, text: tools.joined(separator: " · ")))
                    }
                }
            }
        }
        return Array(out.suffix(limit))
    }
}

struct ClaudeChatView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var sessions = ClaudeSessions.shared

    private enum Choice: Equatable { case session(String), newSession }

    @State private var choice: Choice?
    @State private var lines: [ClaudeChatLine] = []
    @State private var text = ""
    @State private var status: String?
    @State private var statusIsError = false
    @State private var sending = false
    /// After starting a run, jump to the session that appears in this folder.
    @State private var follow: (cwd: String, since: Date)?
    @FocusState private var focused: Bool

    private let claudeOrange = Color(hex: "#D97757")

    private var target: ClaudeSessions.Session? {
        switch choice {
        case .newSession:       return nil
        case .session(let id):  return sessions.session(id: id) ?? sessions.recent.first
        case nil:               return sessions.recent.first
        }
    }

    private var newSessionFolder: String {
        sessions.recent.first?.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    private var newSessionName: String {
        newSessionFolder == FileManager.default.homeDirectoryForCurrentUser.path
            ? "~" : URL(fileURLWithPath: newSessionFolder).lastPathComponent
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)

            VStack(alignment: .leading, spacing: 8) {
                header
                conversation
                inputBar
                Text(status ?? hint)
                    .font(.system(size: 10))
                    .foregroundColor(statusIsError ? Color(hex: "#F4505E") : Color(hex: "#6B7079"))
                    .lineLimit(1)
                    .padding(.leading, 4)
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .padding(.bottom, 10)
        .onAppear {
            if choice == nil { choice = sessions.recent.first.map { .session($0.id) } ?? .newSession }
            prefillFromDrop()
            reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
        .onChange(of: sessions.revision) { _, _ in
            followNewSession()
            reload()
        }
        .onChange(of: choice) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .islandSendMessage)) { _ in send() }
        .onReceive(NotificationCenter.default.publisher(for: .islandNewConversation)) { _ in
            choice = .newSession
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(claudeOrange).frame(width: 7, height: 7)
            Text("Claude")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
            sessionPicker
            Spacer(minLength: 4)
            if target?.isWorking == true {
                HStack(spacing: 5) {
                    TypingDotsView()
                    Text("working")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
            }
            if let target, target.hostApp != nil, !target.ended {
                Button {
                    TerminalTarget.activate(sessionBundleId: target.hostApp)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .frame(width: 16, height: 16)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Open the terminal"))
            }
        }
    }

    private var sessionPicker: some View {
        Menu {
            ForEach(sessions.recent) { s in
                Button(Self.describe(s)) { choice = .session(s.id) }
            }
            if !sessions.recent.isEmpty { Divider() }
            Button(String(localized: "New session in \(newSessionName)  ⌘K")) { choice = .newSession }
        } label: {
            HStack(spacing: 3) {
                Text(target.map(Self.describe) ?? String(localized: "new session in \(newSessionName)"))
                    .lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }
            .font(.system(size: 11))
            .foregroundColor(Color(hex: "#8E939C"))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private static func describe(_ s: ClaudeSessions.Session) -> String {
        s.ended ? String(localized: "\(s.projectName) · ended") : s.projectName
    }

    // MARK: Conversation

    @ViewBuilder private var conversation: some View {
        if lines.isEmpty {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 18))
                    .foregroundColor(claudeOrange.opacity(0.7))
                Text(emptyText)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lines) { line in
                            ClaudeChatRow(line: line).id(line.id)
                        }
                        if target?.isWorking == true {
                            HStack { TypingDotsView(); Spacer(minLength: 32) }.id("typing")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear { scrollToEnd(proxy, animated: false) }
                .onChange(of: lines) { _, _ in scrollToEnd(proxy, animated: true) }
                .onChange(of: target?.isWorking) { _, _ in scrollToEnd(proxy, animated: true) }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var emptyText: String {
        guard let target else { return String(localized: "Type below to start Claude in \(newSessionName)") }
        if target.transcriptPath.isEmpty { return String(localized: "Send a message in \(target.projectName) to see the conversation here") }
        return String(localized: "No messages yet in \(target.projectName)")
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        let id: String? = target?.isWorking == true ? "typing" : lines.last?.id
        guard let id else { return }
        if animated { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
        else { proxy.scrollTo(id, anchor: .bottom) }
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { send() }
                .disabled(sending)
            Button(action: send) {
                Image(systemName: sending ? "ellipsis" : "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#0B0C0E"))
            }
            .buttonStyle(SendButtonStyle())
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(claudeOrange.opacity(focused ? 0.45 : 0), lineWidth: 1))
        .simultaneousGesture(TapGesture().onEnded { focused = true })
    }

    private var placeholder: String {
        guard let target else { return String(localized: "Start Claude in \(newSessionName)…") }
        return String(localized: "Message Claude in \(target.projectName)…")
    }

    private var hint: String {
        guard let target else { return String(localized: "Return opens Terminal with a new Claude session") }
        if target.ended { return String(localized: "Session ended: Return continues it in the background") }
        return String(localized: "Return types it into the session's terminal · ⌘K new session")
    }

    // MARK: Actions

    private func reload() {
        guard let path = target?.transcriptPath, !path.isEmpty else { lines = []; return }
        Task {
            let read = await Task.detached(priority: .userInitiated) { ClaudeTranscript.read(path: path) }.value
            if read != lines { lines = read }
        }
    }

    /// A dropped file opens the chat with its path ready to mention.
    private func prefillFromDrop() {
        guard case .file(_, let url?)? = state.promptContext else { return }
        if text.isEmpty { text = "@\(url.path) " }
        state.promptContext = nil
    }

    private func followNewSession() {
        guard let f = follow else { return }
        if let s = sessions.recent.first(where: { $0.cwd == f.cwd && $0.firstSeen >= f.since }) {
            choice = .session(s.id)
            follow = nil
        } else if Date().timeIntervalSince(f.since) > 60 {
            follow = nil
        }
    }

    private func send() {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !sending else { return }
        sending = true
        statusIsError = false
        let target = self.target
        let folder = newSessionFolder
        status = target?.ended == false ? String(localized: "Sending…") : String(localized: "Starting…")
        Task {
            let outcome: ClaudePromptSender.Outcome
            let since = Date()
            if let target {
                outcome = await ClaudePromptSender.send(prompt, to: target)
            } else {
                outcome = await ClaudePromptSender.startNewSession(prompt, in: folder)
            }
            sending = false
            switch outcome {
            case .typed(let app):
                text = ""
                status = String(localized: "Sent to \(app) ✓")
                SoundEngine.shared.play("approve")
            case .background(let project):
                text = ""
                status = String(localized: "Running in \(project) in the background…")
                follow = (target?.cwd ?? folder, since)
                SoundEngine.shared.play("approve")
            case .started(let project):
                text = ""
                status = String(localized: "New session in \(project) ✓")
                follow = (folder, since)
                SoundEngine.shared.play("approve")
            case .copied(let why):
                statusIsError = true
                status = why
            case .failed(let why):
                statusIsError = true
                status = why
                SoundEngine.shared.play("error")
            }
        }
    }
}

// MARK: - Rows

struct ClaudeChatRow: View {
    let line: ClaudeChatLine

    var body: some View {
        switch line.kind {
        case .user:
            HStack(alignment: .top) {
                Spacer(minLength: 32)
                Text(line.text)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: "#F1F2F4"))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case .assistant:
            HStack(alignment: .top) {
                ChatMarkdownView(markdown: line.text)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer(minLength: 8)
            }
        case .tools:
            HStack(spacing: 5) {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 9))
                Text(line.text)
                    .font(.system(size: 10.5))
                    .lineLimit(1).truncationMode(.tail)
            }
            .foregroundColor(Color(hex: "#6B7079"))
            .padding(.leading, 8)
        }
    }
}
#endif
