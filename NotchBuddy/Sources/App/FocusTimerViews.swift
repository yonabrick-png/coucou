#if !APPSTORE
import SwiftUI

// MARK: - Timer card (overview left card, GitHub build only)

struct FocusTimerCardView: View {
    @ObservedObject private var timer = FocusTimer.shared
    /// Apple Music playlists for the study-music picker (read when Music is open).
    @State private var playlists: [String] = []
    @State private var shortcutsReady = StudyFocus.shortcutsReady
    @State private var dnd = StudyFocus.dndEnabled
    @State private var playlist = StudyFocus.playlist
    @State private var pauseOnRest = StudyFocus.pauseMusicOnRest

    private var accent: Color { Color(hex: timer.mode.colorHex) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            FocusTimerRing(size: 74, lineWidth: 6.5, showsTime: true)
                .onTapGesture { timer.toggle() }
                .help(timer.phase == .running ? String(localized: "Pause") : String(localized: "Start"))

            VStack(alignment: .leading, spacing: 7) {
                modePicker
                statusLine
                controls
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .contextMenu { studyMenu }
        .task {
            await StudyFocus.refreshShortcuts(force: true)
            shortcutsReady = StudyFocus.shortcutsReady
            playlists = await MusicController.shared.playlistNames()
        }
    }

    // MARK: Study options (right-click)

    @ViewBuilder private var studyMenu: some View {
        Section(String(localized: "While studying")) {
            if shortcutsReady {
                Toggle(String(localized: "Turn on Do Not Disturb"), isOn: Binding(
                    get: { dnd }, set: { dnd = $0; StudyFocus.dndEnabled = $0 }))
            } else {
                Button(String(localized: "Set up Do Not Disturb… (needs 2 shortcuts)")) { StudyFocus.openShortcutsApp() }
            }
            Menu(String(localized: "Focus music: \(playlist ?? String(localized: "none"))")) {
                Button(String(localized: "No music")) { playlist = nil; StudyFocus.playlist = nil }
                if playlists.isEmpty {
                    Button(String(localized: "Open Music to pick a playlist")) { MusicController.shared.openMusic() }
                } else {
                    Divider()
                    ForEach(playlists, id: \.self) { name in
                        Button(name) { playlist = name; StudyFocus.playlist = name }
                    }
                }
            }
            Toggle(String(localized: "Pause the music on breaks"), isOn: Binding(
                get: { pauseOnRest }, set: { pauseOnRest = $0; StudyFocus.pauseMusicOnRest = $0 }))
        }
    }

    // MARK: Pieces

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(FocusTimer.Mode.allCases, id: \.self) { m in
                let on = m == timer.mode
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { timer.setMode(m) } } label: {
                    HStack(spacing: 3) {
                        Image(systemName: m.icon).font(.system(size: 8.5, weight: .semibold))
                        Text(m.title).font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(on ? Color(hex: m.colorHex).lighter(by: 0.25) : Color(hex: "#6B7079"))
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(Capsule().fill(on ? Color(hex: m.colorHex).opacity(0.22) : Color.white.opacity(0.05)))
                    .overlay(Capsule().stroke(on ? Color(hex: m.colorHex).opacity(0.5) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(NowPlayingPressStyle())
                .disabled(timer.phase == .running && !on)
                .opacity(timer.phase == .running && !on ? 0.4 : 1)
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch timer.phase {
        case .idle where timer.suggestion != nil:
            // A study event just started in the calendar
            HStack(spacing: 4) {
                Image(systemName: "calendar").font(.system(size: 9, weight: .semibold))
                Text(timer.suggestion ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
            }
            .foregroundColor(accent.lighter(by: 0.2))
        case .idle:
            HStack(spacing: 6) {
                stepButton("minus") { timer.adjust(up: false) }
                Text("\(timer.minutes(for: timer.mode)) min")
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color(hex: "#E4E6EA"))
                    .frame(minWidth: 44)
                    .contentTransition(.numericText())
                stepButton("plus") { timer.adjust(up: true) }
                studyDots
            }
        case .running:
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(endsLine)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
            }
        case .paused:
            Text("Paused")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#F5A524"))
        case .finished:
            Text(doneLine)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(accent.lighter(by: 0.2))
                .lineLimit(1)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { timer.toggle() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: timer.phase == .running ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(primaryLabel)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#0E0F11"))
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Capsule().fill(accent))
                .shadow(color: accent.opacity(0.5), radius: timer.phase == .running ? 8 : 4)
            }
            .buttonStyle(NowPlayingPressStyle())

            if timer.phase != .idle {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { timer.reset() } } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(NowPlayingPressStyle())
                .help(String(localized: "Reset"))
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy(duration: 0.2)) { action() } }) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(NowPlayingPressStyle())
    }

    /// Today's study sessions as dots, four to a round.
    @ViewBuilder private var studyDots: some View {
        if timer.studiesToday > 0 {
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < (timer.studiesToday - 1) % 4 + 1 ? Color(hex: FocusTimer.Mode.study.colorHex) : Color.white.opacity(0.12))
                        .frame(width: 5, height: 5)
                }
                Text("\(timer.studiesToday)")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.leading, 4)
            .help(String(localized: "\(timer.studiesToday) study sessions today"))
        }
    }

    // MARK: Text

    private var primaryLabel: String {
        switch timer.phase {
        case .running:  return String(localized: "Pause")
        case .paused:   return String(localized: "Resume")
        case .idle:     return String(localized: "Start \(timer.mode.title.lowercased())")
        case .finished: return String(localized: "Start \(timer.mode.title.lowercased())")
        }
    }

    private var endsLine: String {
        let end = Date().addingTimeInterval(timer.remaining()).formatted(date: .omitted, time: .shortened)
        switch timer.mode {
        case .study: return String(localized: "Focus · break at \(end)")
        case .rest:  return String(localized: "Breathe · back at \(end)")
        case .timer: return String(localized: "Ends at \(end)")
        }
    }

    private var doneLine: String {
        switch timer.finishedMode {
        case .study: return String(localized: "Session done! \(timer.minutes(for: .rest)) min rest?")
        case .rest:  return String(localized: "Rested. Ready to study?")
        default:     return String(localized: "Time's up!")
        }
    }
}

// MARK: - Ring

/// The glowing ring that drains as time passes; full at start, empty at the end.
/// Animates only while running and on screen.
struct FocusTimerRing: View {
    @ObservedObject private var timer = FocusTimer.shared
    let size: CGFloat
    let lineWidth: CGFloat
    var showsTime: Bool = false

    @State private var pulse = false

    var body: some View {
        let accent = Color(hex: timer.mode.colorHex)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: timer.phase != .running)) { context in
            let fraction = timer.fraction(at: context.date)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: timer.phase == .finished ? 1 : fraction)
                    .stroke(
                        AngularGradient(colors: [accent.opacity(0.55), accent, accent.lighter(by: 0.3)],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * fraction)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accent.opacity(timer.phase == .running ? 0.65 : 0.25), radius: lineWidth * 1.2)
                if showsTime {
                    VStack(spacing: 1) {
                        if timer.phase == .finished {
                            Image(systemName: "checkmark")
                                .font(.system(size: size * 0.26, weight: .bold))
                                .foregroundColor(accent)
                        } else {
                            Text(Self.clock(timer.remaining(at: context.date)))
                                .font(.system(size: size * 0.22, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundColor(Color(hex: "#F5F6F8"))
                                .contentTransition(.numericText(countsDown: true))
                        }
                        Image(systemName: timer.mode.icon)
                            .font(.system(size: size * 0.11))
                            .foregroundColor(accent.opacity(0.85))
                    }
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(pulse ? 1.06 : 1)
        }
        .onChange(of: timer.phase) { _, phase in
            if phase == .finished {
                withAnimation(.easeInOut(duration: 0.5).repeatCount(5, autoreverses: true)) { pulse = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { withAnimation { pulse = false } }
            }
        }
        .contentShape(Circle())
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(ceil(seconds))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Closed notch: mini ring + minutes

/// Right side of the closed notch while the timer runs, is paused or just finished.
struct CompactFocusTimer: View {
    @ObservedObject private var timer = FocusTimer.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: timer.phase != .running)) { context in
            let left = timer.remaining(at: context.date)
            HStack(spacing: 3) {
                FocusTimerRing(size: 14, lineWidth: 2.5)
                Text(label(left))
                    .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(timer.phase == .paused ? Color(hex: "#F5A524") : Color(hex: "#F5F6F8"))
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: 34, height: 28)
        }
    }

    private func label(_ left: TimeInterval) -> String {
        if timer.phase == .finished { return "✓" }
        if left < 60 { return "\(Int(ceil(left)))s" }
        return "\(Int(ceil(left / 60)))m"
    }
}
#endif
