#if !APPSTORE
import SwiftUI

// MARK: - Notes tab (GitHub build only)

/// Write a note (Return), optionally with a reminder (🔔); tick it off with a satisfying check.
/// Everything leaves after a day unless pinned.
struct NotesView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = NotesStore.shared

    @State private var text = ""
    @State private var choosingReminder = false
    @State private var remindAt: Date?
    @State private var customTime = Date().addingTimeInterval(3600)
    @FocusState private var focused: Bool

    private let yellow = Color(hex: NotesStore.color)

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                header
                inputBar
                if choosingReminder { reminderChooser.transition(.move(edge: .top).combined(with: .opacity)) }
                list
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .padding(.bottom, 10)
        .onAppear {
            store.prune()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
        }
        .onExitCommand {
            if choosingReminder { withAnimation { choosingReminder = false } }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(yellow).frame(width: 7, height: 7)
            Text("Notes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
            if !store.notes.isEmpty {
                Text("\(store.notes.filter { !$0.done }.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            if store.pendingReminders > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bell.fill").font(.system(size: 8))
                    Text("\(store.pendingReminders)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                }
                .foregroundColor(yellow)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(yellow.opacity(0.15)))
            }
            Spacer(minLength: 4)
            if store.notes.contains(where: { $0.done && !$0.pinned }) {
                Button(String(localized: "Clear done")) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { store.clearDone() }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color(hex: "#8E939C"))
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 6) {
            TextField(remindAt == nil ? String(localized: "Write a note…")
                                      : String(localized: "What should I remind you?"),
                      text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit(add)

            if let remindAt {
                Button { withAnimation(.snappy) { self.remindAt = nil } } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.fill").font(.system(size: 8.5))
                        Text(Self.when(remindAt)).font(.system(size: 10.5, weight: .semibold))
                        Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                    }
                    .foregroundColor(Color(hex: "#0E0F11"))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(yellow))
                }
                .buttonStyle(NowPlayingPressStyle())
                .help(String(localized: "Remove the reminder"))
                .transition(.scale.combined(with: .opacity))
            } else {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { choosingReminder.toggle() } } label: {
                    Image(systemName: choosingReminder ? "bell.fill" : "bell")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(choosingReminder ? yellow : Color(hex: "#8E939C"))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NowPlayingPressStyle())
                .help(String(localized: "Add a reminder"))
            }

            Button(action: add) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#0B0C0E"))
            }
            .buttonStyle(SendButtonStyle())
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(yellow.opacity(focused ? 0.45 : 0), lineWidth: 1))
        .simultaneousGesture(TapGesture().onEnded { focused = true })
    }

    private var reminderChooser: some View {
        HStack(spacing: 5) {
            Text("Remind me")
                .font(.system(size: 10.5))
                .foregroundColor(Color(hex: "#8E939C"))
            ForEach([(15, "15 min"), (30, "30 min"), (60, "1 h"), (180, "3 h")], id: \.0) { mins, label in
                chip(label) { pick(Date().addingTimeInterval(TimeInterval(mins * 60))) }
            }
            Text("or at")
                .font(.system(size: 10.5))
                .foregroundColor(Color(hex: "#8E939C"))
            DatePicker("", selection: $customTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(width: 70)
                .controlSize(.small)
            chip(String(localized: "Set")) { pick(Self.nextOccurrence(of: customTime)) }
        }
    }

    private func chip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(yellow.lighter(by: 0.2))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(yellow.opacity(0.15)))
                .overlay(Capsule().stroke(yellow.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(NowPlayingPressStyle())
    }

    // MARK: List

    @ViewBuilder private var list: some View {
        if store.notes.isEmpty {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                Image(systemName: "note.text")
                    .font(.system(size: 20))
                    .foregroundColor(yellow.opacity(0.7))
                Text("Write anything. It stays here for a day.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(hex: "#8E939C"))
                Text("Tap 🔔 to be reminded at a time.")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#6B7079"))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.notes) { note in
                            NoteRow(note: note, ringing: store.ringing == note.id, accent: yellow)
                                .id(note.id)
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                        removal: .opacity.combined(with: .scale(scale: 0.9))))
                        }
                    }
                    .padding(.vertical, 2)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.notes)
                }
                .onAppear { if let r = store.ringing { proxy.scrollTo(r, anchor: .center) } }
                .onChange(of: store.ringing) { _, r in
                    if let r { withAnimation { proxy.scrollTo(r, anchor: .center) } }
                }
            }
        }
    }

    // MARK: Actions

    private func add() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.add(t, remindAt: remindAt)
        text = ""
        withAnimation(.snappy) { remindAt = nil; choosingReminder = false }
        focused = true
    }

    private func pick(_ date: Date) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            remindAt = date
            choosingReminder = false
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        focused = true
    }

    /// A picked clock time that has already passed today means tomorrow.
    private static func nextOccurrence(of time: Date) -> Date {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: time)
        let now = Date()
        guard let today = cal.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: now) else { return time }
        return today > now ? today : (cal.date(byAdding: .day, value: 1, to: today) ?? today)
    }

    /// "17:30" today, "tmrw 9:00" tomorrow.
    static func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(date) ? time : String(localized: "tmrw \(time)")
    }
}

// MARK: - Row

struct NoteRow: View {
    let note: NotesStore.Note
    let ringing: Bool
    let accent: Color
    @State private var hovered = false
    @State private var glow = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            CheckCircle(done: note.done, accent: accent) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { NotesStore.shared.toggleDone(note) }
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.text)
                    .font(.system(size: 12.5))
                    .foregroundColor(note.done ? Color(hex: "#6B7079") : Color(hex: "#F1F2F4"))
                    .strikethrough(note.done, color: Color(hex: "#6B7079"))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    meta(now: context.date)
                }
            }
            Spacer(minLength: 4)
            if hovered {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { NotesStore.shared.remove(note) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(ringing ? accent.opacity(glow ? 0.22 : 0.12) : Color.white.opacity(hovered ? 0.07 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(ringing ? accent.opacity(0.6) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
        .onAppear { if ringing { startGlow() } }
        .onChange(of: ringing) { _, r in if r { startGlow() } else { glow = false } }
        .contextMenu {
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

    private func startGlow() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { glow = true }
    }

    @ViewBuilder private func meta(now: Date) -> some View {
        HStack(spacing: 6) {
            if let at = note.remindAt {
                HStack(spacing: 3) {
                    Image(systemName: note.fired ? "bell.badge.fill" : "bell.fill").font(.system(size: 8))
                    Text(reminderText(at, now: now)).font(.system(size: 10, weight: .medium).monospacedDigit())
                }
                .foregroundColor(note.fired && !note.done ? accent : Color(hex: "#8E939C"))
            }
            Text(note.pinned ? String(localized: "pinned") : leftText(now: now))
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#4A4F57"))
        }
    }

    private func reminderText(_ at: Date, now: Date) -> String {
        let time = NotesView.when(at)
        if note.fired || at <= now { return time }
        let mins = Int(ceil(at.timeIntervalSince(now) / 60))
        return mins < 60 ? String(localized: "\(time) · in \(mins)m")
                         : String(localized: "\(time) · in \(mins / 60)h \(mins % 60)m")
    }

    private func leftText(now: Date) -> String {
        let hours = Int(ceil(note.expires.timeIntervalSince(now) / 3600))
        return hours <= 1 ? String(localized: "leaves within the hour") : String(localized: "\(hours)h left")
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
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(Color(hex: "#0E0F11"))
                    .scaleEffect(done ? 1 : 0.2)
                    .opacity(done ? 1 : 0)
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle())
        }
        .buttonStyle(NowPlayingPressStyle())
        .onHover { h in hovered = h }
    }
}
#endif
