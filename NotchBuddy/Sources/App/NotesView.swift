#if !APPSTORE
import SwiftUI

// MARK: - Notes card (overview left card, GitHub build only)

/// Like the Timer: a pill whose card holds everything. Type a note (Return), 🔔 to make it a
/// reminder, tick it off with a satisfying check. Everything leaves after a day unless pinned.
struct NotesCardView: View {
    @ObservedObject private var store = NotesStore.shared

    @State private var text = ""
    @State private var remindAt: Date?
    @FocusState private var focused: Bool

    private let yellow = Color(hex: NotesStore.color)

    /// Open notes first (newest on top), done ones after.
    private var ordered: [NotesStore.Note] {
        store.notes.filter { !$0.done } + store.notes.filter(\.done)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            inputBar
            if store.notes.isEmpty {
                Text("Write anything: it stays a day. 🔔 to be reminded.")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .padding(.leading, 4)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(ordered) { note in
                                CompactNoteRow(note: note, ringing: store.ringing == note.id, accent: yellow)
                                    .id(note.id)
                                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                            removal: .opacity.combined(with: .scale(scale: 0.9))))
                            }
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.notes)
                    }
                    .frame(maxHeight: 54)
                    .onAppear { if let r = store.ringing { proxy.scrollTo(r, anchor: .center) } }
                    .onChange(of: store.ringing) { _, r in
                        if let r { withAnimation { proxy.scrollTo(r, anchor: .center) } }
                    }
                }
            }
        }
        .padding(.leading, 108)
        .padding(.trailing, 30)   // the ↗ button sits top-right
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { store.prune() }
        .onReceive(NotificationCenter.default.publisher(for: .notesFocusInput)) { _ in focusInput() }
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 5) {
            TextField(remindAt == nil ? String(localized: "Note or reminder…")
                                      : String(localized: "Remind me to…"),
                      text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit(add)

            if let remindAt {
                Button { withAnimation(.snappy) { self.remindAt = nil } } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "bell.fill").font(.system(size: 7.5))
                        Text(Self.when(remindAt)).font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#0E0F11"))
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(Capsule().fill(yellow))
                }
                .buttonStyle(NowPlayingPressStyle())
                .help(String(localized: "Remove the reminder"))
                .transition(.scale.combined(with: .opacity))
            } else {
                Menu {
                    Section(String(localized: "Remind me")) {
                        Button(String(localized: "In 15 minutes")) { pick(minutes: 15) }
                        Button(String(localized: "In 30 minutes")) { pick(minutes: 30) }
                        Button(String(localized: "In 1 hour"))     { pick(minutes: 60) }
                        Button(String(localized: "In 3 hours"))    { pick(minutes: 180) }
                    }
                    Divider()
                    Button(String(localized: "Tonight at 20:00"))  { pick(Self.next(hour: 20)) }
                    Button(String(localized: "Tomorrow at 9:00"))  { pick(Self.tomorrow(hour: 9)) }
                } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(localized: "Add a reminder"))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(yellow.opacity(focused ? 0.45 : 0), lineWidth: 1))
        .simultaneousGesture(TapGesture().onEnded { focusInput() })
    }

    // MARK: Actions

    /// The notch panel doesn't take the keyboard on its own: ask for it, then focus.
    private func focusInput() {
        NotificationCenter.default.post(name: .islandWantsKeyboard, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
    }

    private func add() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { store.add(t, remindAt: remindAt) }
        text = ""
        withAnimation(.snappy) { remindAt = nil }
        focused = true
    }

    private func pick(minutes: Int) { pick(Date().addingTimeInterval(TimeInterval(minutes * 60))) }

    private func pick(_ date: Date) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { remindAt = date }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        focusInput()
    }

    /// Today at `hour`, or tomorrow if that's already past.
    private static func next(hour: Int) -> Date {
        let cal = Calendar.current
        let now = Date()
        let today = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        return today > now ? today : (cal.date(byAdding: .day, value: 1, to: today) ?? today)
    }

    private static func tomorrow(hour: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    /// "17:30" today, "tmrw 9:00" tomorrow.
    static func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(date) ? time : String(localized: "tmrw \(time)")
    }
}

extension Notification.Name {
    /// ↗ on the Notes card: put the cursor in its box.
    static let notesFocusInput = Notification.Name("notchBuddy.notesFocusInput")
}

// MARK: - Row

struct CompactNoteRow: View {
    let note: NotesStore.Note
    let ringing: Bool
    let accent: Color
    @State private var hovered = false
    @State private var glow = false

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            CheckCircle(done: note.done, accent: accent) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { NotesStore.shared.toggleDone(note) }
            }
            Text(note.text)
                .font(.system(size: 11.5))
                .foregroundColor(note.done ? Color(hex: "#6B7079") : Color(hex: "#F1F2F4"))
                .strikethrough(note.done, color: Color(hex: "#6B7079"))
                .lineLimit(1).truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if hovered {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { NotesStore.shared.remove(note) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else if let at = note.remindAt, !note.done {
                HStack(spacing: 2) {
                    Image(systemName: note.fired ? "bell.badge.fill" : "bell.fill").font(.system(size: 7.5))
                    Text(NotesCardView.when(at)).font(.system(size: 9.5, weight: .medium).monospacedDigit())
                }
                .foregroundColor(note.fired ? accent : Color(hex: "#8E939C"))
            } else if note.pinned {
                Image(systemName: "pin.fill").font(.system(size: 7.5)).foregroundColor(Color(hex: "#6B7079"))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(ringing ? accent.opacity(glow ? 0.24 : 0.12) : Color.white.opacity(hovered ? 0.06 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(ringing ? accent.opacity(0.6) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
        .onAppear { if ringing { startGlow() } }
        .onChange(of: ringing) { _, r in if r { startGlow() } else { glow = false } }
        .help(helpText)
        .contextMenu {
            Button(String(localized: "Ask Claude")) { ClaudeChatDraft.open(with: note.text) }
            Divider()
            Button(note.done ? String(localized: "Mark as not done") : String(localized: "Mark as done")) {
                NotesStore.shared.toggleDone(note)
            }
            Button(note.pinned ? String(localized: "Unpin") : String(localized: "Pin (keep it)")) {
                NotesStore.shared.togglePin(note)
            }
            Button(String(localized: "Copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(note.text, forType: .string)
            }
            Divider()
            Button(String(localized: "Delete")) { NotesStore.shared.remove(note) }
        }
    }

    private var helpText: String {
        if note.pinned { return String(localized: "\(note.text) · pinned") }
        let hours = max(1, Int(ceil(note.expires.timeIntervalSinceNow / 3600)))
        return String(localized: "\(note.text) · leaves in \(hours) h")
    }

    private func startGlow() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { glow = true }
    }
}

/// The tick: a ring that fills and pops a checkmark, with a little overshoot.
struct CheckCircle: View {
    let done: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(done ? accent : Color(hex: hovered ? "#8E939C" : "#5F646D"), lineWidth: 1.5)
                Circle()
                    .fill(accent)
                    .scaleEffect(done ? 1 : 0.001)
                Image(systemName: "checkmark")
                    .font(.system(size: 7.5, weight: .heavy))
                    .foregroundColor(Color(hex: "#0E0F11"))
                    .scaleEffect(done ? 1 : 0.2)
                    .opacity(done ? 1 : 0)
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
        }
        .buttonStyle(NowPlayingPressStyle())
        .onHover { h in hovered = h }
    }
}
#endif
