#if !APPSTORE
import SwiftUI
import AppKit
import CoreImage

// MARK: - Shared player (Apple Music and Spotify cards, GitHub build only)
//
// Both cards hand the same player what to show and what each button does, so Apple Music
// and Spotify look and behave alike: big artwork, scrolling title, live bars, a seek bar
// and a controls row, tinted with a colour taken from the cover.

/// What the player shows, read from either controller.
struct NowPlayingInfo {
    var title: String
    var subtitle: String
    var artwork: NSImage?
    var isPlaying: Bool
    var duration: Double
    var canSeek: Bool
    var shuffling: Bool
    var repeating: Bool
    var volume: Int
    /// The service colour, used until (or when) the cover gives none.
    var brand: Color
}

/// What each control does.
struct NowPlayingActions {
    var position: @MainActor (Date) -> Double
    var playPause: @MainActor () -> Void
    var previous: @MainActor () -> Void
    var next: @MainActor () -> Void
    var seek: @MainActor (Double) -> Void
    var setShuffling: @MainActor (Bool) -> Void
    var setRepeating: @MainActor (Bool) -> Void
    var setVolume: @MainActor (Int) -> Void
    var openApp: @MainActor () -> Void
    var openHelp: String
}

// The card is 98 pt tall and starts 108 pt in (Mochi stands on the left):
// artwork row 44, seek bar 10, controls 24.
struct NowPlayingPlayer: View {
    let info: NowPlayingInfo
    let actions: NowPlayingActions

    private var accent: Color { ArtworkAccent.color(for: info.artwork) ?? info.brand }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                NowPlayingArtwork(image: info.artwork, accent: accent)
                    .frame(width: 44, height: 44)
                    .shadow(color: accent.opacity(info.isPlaying ? 0.45 : 0), radius: 8)
                    .scaleEffect(info.isPlaying ? 1 : 0.94)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: info.isPlaying)
                    .onTapGesture { actions.openApp() }
                    .help(actions.openHelp)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        MarqueeText(text: info.title,
                                    font: .system(size: 12.5, weight: .semibold),
                                    color: Color(hex: "#F5F6F8"))
                        SoundBars(isPlaying: info.isPlaying, color: accent)
                            .frame(width: 14, height: 11)
                    }
                    if !info.subtitle.isEmpty {
                        Text(info.subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 24)   // the ↗ button sits top-right
            .padding(.top, 4)

            // Position runs on its own clock only while playing and on screen
            TimelineView(.animation(minimumInterval: 0.5, paused: !info.isPlaying)) { context in
                NowPlayingProgress(
                    position: actions.position(context.date),
                    duration: info.duration,
                    accent: accent,
                    canSeek: info.canSeek,
                    onSeek: { actions.seek($0) }
                )
            }
            .padding(.top, 6)

            controls
                .padding(.top, 4)
        }
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .animation(.easeInOut(duration: 0.4), value: info.artwork)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                NowPlayingIconButton(icon: "shuffle", size: 10,
                                     tint: info.shuffling ? accent : Color(hex: "#6B7079"),
                                     help: info.shuffling ? "Shuffle on" : "Shuffle off") {
                    actions.setShuffling(!info.shuffling)
                }
                NowPlayingIconButton(icon: "backward.fill", size: 12, tint: Color(hex: "#C5C8CD"), help: "Previous") {
                    actions.previous()
                }
                Button(action: { actions.playPause() }) {
                    ZStack {
                        Circle().fill(Color(hex: "#F5F6F8"))
                        Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#0E0F11"))
                            .offset(x: info.isPlaying ? 0 : 1)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: 24, height: 24)
                    .shadow(color: accent.opacity(0.35), radius: 6)
                }
                .buttonStyle(NowPlayingPressStyle())
                .help(info.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
                NowPlayingIconButton(icon: "forward.fill", size: 12, tint: Color(hex: "#C5C8CD"), help: "Next") {
                    actions.next()
                }
                NowPlayingIconButton(icon: "repeat", size: 10,
                                     tint: info.repeating ? accent : Color(hex: "#6B7079"),
                                     help: info.repeating ? "Repeat on" : "Repeat off") {
                    actions.setRepeating(!info.repeating)
                }
            }
            Spacer(minLength: 6)
            NowPlayingVolume(volume: info.volume, accent: accent) { actions.setVolume($0) }
        }
    }
}

// MARK: - Closed notch: cover + bars (right side, in place of the mini grid)

/// Shown on the right of the closed notch while Apple Music or Spotify plays.
/// Sized for the 28 × 28 slot the mini grid uses.
struct CompactNowPlaying: View {
    let artwork: NSImage?
    let isPlaying: Bool
    let brand: Color

    var body: some View {
        let accent = ArtworkAccent.color(for: artwork) ?? brand
        HStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08))
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(accent)
                }
            }
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            SoundBars(isPlaying: isPlaying, color: accent, barCount: 3)
                .frame(width: 10, height: 12)
        }
        .frame(width: 32, height: 28)
    }
}

/// Picks what the right side of the closed notch shows: the playing service, else the mini grid.
struct CompactTrailing: View {
    @ObservedObject var state: AppState
    @ObservedObject private var music = MusicController.shared
    @ObservedObject private var spotify = SpotifyController.shared
    @ObservedObject private var calendar = CalendarController.shared
    @ObservedObject private var timer = FocusTimer.shared

    var body: some View {
        if state.activeIntegrations.contains(FocusTimer.pillId), timer.isActive {
            // A running (or paused, or just finished) timer comes first
            CompactFocusTimer()
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        } else if state.activeIntegrations.contains(MusicController.pillId),
           state.musicPlaying, music.trackTitle != nil {
            CompactNowPlaying(artwork: music.artwork, isPlaying: true,
                              brand: Color(hex: MusicController.red))
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        } else if state.activeIntegrations.contains(SpotifyController.pillId),
                  spotify.isPlaying, spotify.track != nil {
            CompactNowPlaying(artwork: spotify.artwork, isPlaying: true,
                              brand: Color(hex: SpotifyController.green))
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        } else if state.activeIntegrations.contains(CalendarController.pillId) {
            // An event within 30 minutes takes the slot; re-checked once a minute
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if let event = CompactCalendarBadge.current(now: context.date) {
                    CompactCalendarBadge(event: event)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    CompactMiniGrid(state: state)
                        .transition(.opacity)
                }
            }
        } else {
            CompactMiniGrid(state: state)
                .transition(.opacity)
        }
    }
}

// MARK: - Live bars

/// Equaliser-style bars: they dance while playing (15 fps, paused otherwise) and rest flat.
struct SoundBars: View {
    let isPlaying: Bool
    let color: Color
    var barCount: Int = 4

    private static let speeds: [Double] = [7.1, 9.3, 5.7, 8.2]
    private static let phases: [Double] = [0.0, 1.7, 3.1, 4.6]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let gap: CGFloat = 1.5
                let w = max(1, (geo.size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount))
                HStack(alignment: .center, spacing: gap) {
                    ForEach(0..<barCount, id: \.self) { i in
                        Capsule()
                            .fill(color)
                            .frame(width: w, height: max(2, geo.size.height * level(i, t)))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isPlaying)
        .accessibilityHidden(true)
    }

    private func level(_ i: Int, _ t: Double) -> CGFloat {
        guard isPlaying else { return 0.22 }
        let k = i % Self.speeds.count
        let a = abs(sin(t * Self.speeds[k] + Self.phases[k]))
        let b = abs(sin(t * Self.speeds[k] * 0.53 + Self.phases[k] * 1.9))
        return CGFloat(0.25 + 0.75 * (0.6 * a + 0.4 * b))
    }
}

// MARK: - Scrolling title

/// One line that scrolls back and forth when it doesn't fit, with soft faded edges.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var start = Date()

    private let speed: Double = 28      // points per second
    private let rest: Double = 1.8      // pause at each end

    var body: some View {
        let overflow = max(0, textWidth - boxWidth)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: overflow < 1)) { context in
            Text(text)
                .font(font)
                .foregroundColor(color)
                .lineLimit(1)
                .fixedSize()
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { textWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in textWidth = w }
                })
                .offset(x: -offset(overflow: overflow, at: context.date))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { boxWidth = g.size.width }
                .onChange(of: g.size.width) { _, w in boxWidth = w }
        })
        .clipped()
        .mask(LinearGradient(stops: fadeStops(scrolling: overflow >= 1),
                             startPoint: .leading, endPoint: .trailing))
        .onChange(of: text) { _, _ in start = Date() }
    }

    /// Faded edges only while the title scrolls.
    private func fadeStops(scrolling: Bool) -> [Gradient.Stop] {
        guard scrolling else {
            return [Gradient.Stop(color: .black, location: 0), Gradient.Stop(color: .black, location: 1)]
        }
        return [
            Gradient.Stop(color: .clear, location: 0),
            Gradient.Stop(color: .black, location: 0.06),
            Gradient.Stop(color: .black, location: 0.9),
            Gradient.Stop(color: .clear, location: 1),
        ]
    }

    /// Rest, scroll to the end, rest, scroll back — on a loop.
    private func offset(overflow: CGFloat, at date: Date) -> CGFloat {
        guard overflow >= 1 else { return 0 }
        let travel = Double(overflow) / speed
        let cycle = 2 * (rest + travel)
        let t = date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
        let p: Double
        switch t {
        case ..<rest:                  p = 0
        case ..<(rest + travel):       p = (t - rest) / travel
        case ..<(2 * rest + travel):   p = 1
        default:                       p = 1 - (t - 2 * rest - travel) / travel
        }
        let eased = p * p * (3 - 2 * p)   // smoothstep
        return overflow * CGFloat(eased)
    }
}

// MARK: - Accent from the cover

/// The cover's average colour, lifted so it reads on the black island. Cached per image.
@MainActor
enum ArtworkAccent {
    private static let cache = NSCache<NSImage, NSColor>()
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func color(for image: NSImage?) -> Color? {
        guard let image else { return nil }
        if let cached = cache.object(forKey: image) { return Color(nsColor: cached) }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: ci.extent),
        ]), let output = filter.outputImage else { return nil }

        var px = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &px, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        let average = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255,
                              blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        average.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Grey covers stay grey; coloured ones get enough saturation and light to stand out.
        let tuned = NSColor(hue: h,
                            saturation: s < 0.12 ? s : min(1, max(0.5, s * 1.2)),
                            brightness: max(0.78, b),
                            alpha: 1)
        cache.setObject(tuned, forKey: image)
        return Color(nsColor: tuned)
    }
}
#endif
