#if !APPSTORE
import SwiftUI

// MARK: - Claude prompt box (overview card, GitHub build only)
//
// ✎ on the Claude pill's card opens a one-line box: type, Return, and the prompt goes to the
// chosen Claude Code session — typed into its terminal tab when it's open, otherwise run in the
// background on the same conversation. With no session (or "New session" picked), it starts
// `claude "<prompt>"` in a new Terminal window (see ClaudePromptSender).

/// The "Ask Claude" button next to ↗ on the Claude pill's card.
struct ClaudePromptButton: View {
    @ObservedObject var state: AppState
    @State private var hovered = false

    private let claudeOrange = Color(hex: "#D97757")

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                state.composingClaudePrompt = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 9, weight: .semibold))
                Text("Ask Claude")
                    .font(.system(size: 10, weight: .semibold))
                    .fixedSize()
            }
            .foregroundColor(hovered ? claudeOrange.lighter(by: 0.35) : claudeOrange.lighter(by: 0.15))
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(Capsule().fill(claudeOrange.opacity(hovered ? 0.30 : 0.18)))
            .overlay(Capsule().stroke(claudeOrange.opacity(hovered ? 0.6 : 0.35), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(NowPlayingPressStyle())
        .scaleEffect(hovered ? 1.04 : 1)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
        .help(String(localized: "Message Claude"))
    }
}

/// Covers the left card while typing a prompt for a Claude Code session.
struct ClaudePromptBox: View {
    @ObservedObject var state: AppState
    @ObservedObject private var sessions = ClaudeSessions.shared

    /// Where the prompt goes: a known session, or a brand-new one.
    private enum Choice: Equatable { case session(String), newSession }

    @State private var text = ""
    @State private var choice: Choice?
    @State private var status: String?
    @State private var statusIsError = false
    @State private var sending = false
    @FocusState private var focused: Bool

    private let claudeOrange = Color(hex: "#D97757")

    /// The picked session, else the most recent one; nil means "start a new session".
    private var target: ClaudeSessions.Session? {
        switch choice {
        case .newSession:          return nil
        case .session(let id):     return sessions.session(id: id) ?? sessions.recent.first
        case nil:                  return sessions.recent.first
        }
    }

    /// Folder a new session starts in: the latest project seen, else the home folder.
    private var newSessionFolder: String {
        sessions.recent.first?.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    private var newSessionName: String {
        let name = URL(fileURLWithPath: newSessionFolder).lastPathComponent
        return newSessionFolder == FileManager.default.homeDirectoryForCurrentUser.path ? "~" : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 8)
                .padding(.leading, 108)
                .padding(.trailing, 12)

            HStack(spacing: 6) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
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
            .padding(.top, 8)
            .padding(.leading, 108)
            .padding(.trailing, 12)

            Text(status ?? hint)
                .font(.system(size: 10))
                .foregroundColor(statusIsError ? Color(hex: "#F4505E") : Color(hex: "#6B7079"))
                .lineLimit(2)
                .padding(.top, 6)
                .padding(.leading, 112)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            choice = sessions.recent.first.map { .session($0.id) } ?? .newSession
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
        .onExitCommand { close() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(claudeOrange).frame(width: 7, height: 7)
            Text("Message Claude")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .fixedSize()
            sessionPicker
            Spacer(minLength: 2)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .frame(width: 16, height: 16)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Close (Esc)"))
        }
    }

    /// Where the prompt goes: each known session, plus a new one.
    private var sessionPicker: some View {
        Menu {
            ForEach(sessions.recent) { s in
                Button(Self.describe(s)) { choice = .session(s.id) }
            }
            if !sessions.recent.isEmpty { Divider() }
            Button(String(localized: "New session in \(newSessionName)")) { choice = .newSession }
        } label: {
            HStack(spacing: 3) {
                Text(target.map(Self.describe) ?? String(localized: "new session"))
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

    private var placeholder: String {
        guard let target else { return String(localized: "Start Claude in \(newSessionName)…") }
        return String(localized: "Ask Claude in \(target.projectName)…")
    }

    private var hint: String {
        guard let target else { return String(localized: "Return opens Terminal with a new Claude session") }
        if target.ended { return String(localized: "Return runs it in the background on the same conversation") }
        return String(localized: "Return types it into the session's terminal · Esc closes")
    }

    // MARK: Actions

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
                closeSoon(after: 0.9)
            case .background(let project):
                text = ""
                status = String(localized: "Running in \(project) — follow it on the Claude pill")
                SoundEngine.shared.play("approve")
                closeSoon(after: 1.8)
            case .started(let project):
                text = ""
                status = String(localized: "New Claude session in \(project) ✓")
                SoundEngine.shared.play("approve")
                closeSoon(after: 0.9)
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

    private func closeSoon(after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { close() }
    }

    private func close() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            state.composingClaudePrompt = false
        }
    }
}
#endif
