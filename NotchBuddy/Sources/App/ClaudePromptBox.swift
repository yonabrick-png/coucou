#if !APPSTORE
import SwiftUI

// MARK: - Claude prompt box (overview card, GitHub build only)
//
// ✎ on the Claude pill's card opens a one-line box: type, Return, and the prompt goes to the
// chosen Claude Code session — typed into its terminal tab when it's open, otherwise run in the
// background on the same conversation (see ClaudePromptSender).

/// The ✎ button next to ↗, shown when the Claude pill is in focus and a session is known.
struct ClaudePromptButton: View {
    @ObservedObject var state: AppState
    @ObservedObject private var sessions = ClaudeSessions.shared

    var body: some View {
        if !sessions.sessions.isEmpty {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    state.composingClaudePrompt = true
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Color(hex: "#5F646D"))
                    .frame(width: 16, height: 16)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Message Claude"))
        }
    }
}

/// Covers the left card while typing a prompt for a Claude Code session.
struct ClaudePromptBox: View {
    @ObservedObject var state: AppState
    @ObservedObject private var sessions = ClaudeSessions.shared

    @State private var text = ""
    @State private var targetId: String?
    @State private var status: String?
    @State private var statusIsError = false
    @State private var sending = false
    @FocusState private var focused: Bool

    private let claudeOrange = Color(hex: "#D97757")

    private var target: ClaudeSessions.Session? {
        sessions.session(id: targetId) ?? sessions.recent.first
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
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending || target == nil)
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
            targetId = sessions.recent.first?.id
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

    /// The project the prompt goes to; a menu when several sessions are known.
    @ViewBuilder private var sessionPicker: some View {
        let all = sessions.recent
        let label = HStack(spacing: 3) {
            Text(target.map(Self.describe) ?? String(localized: "no session"))
                .lineLimit(1).truncationMode(.tail)
            if all.count > 1 {
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
            }
        }
        .font(.system(size: 11))
        .foregroundColor(Color(hex: "#8E939C"))

        if all.count > 1 {
            Menu {
                ForEach(all) { s in
                    Button(Self.describe(s)) { targetId = s.id }
                }
            } label: { label }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        } else {
            label
        }
    }

    private static func describe(_ s: ClaudeSessions.Session) -> String {
        s.ended ? String(localized: "\(s.projectName) · ended") : s.projectName
    }

    private var placeholder: String {
        guard let target else { return String(localized: "Start Claude Code in a terminal first") }
        return String(localized: "Ask Claude in \(target.projectName)…")
    }

    private var hint: String {
        guard let target else { return "" }
        if target.ended { return String(localized: "Return runs it in the background on the same conversation") }
        return String(localized: "Return types it into the session's terminal · Esc closes")
    }

    // MARK: Actions

    private func send() {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target, !prompt.isEmpty, !sending else { return }
        sending = true
        statusIsError = false
        status = target.ended ? String(localized: "Starting…") : String(localized: "Sending…")
        Task {
            let outcome = await ClaudePromptSender.send(prompt, to: target)
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
