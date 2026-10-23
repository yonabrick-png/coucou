#if !APPSTORE
import SwiftUI

// MARK: - Focus mode: only music (GitHub build only)

/// What's playing (Apple Music first, else Spotify), as one value both views can read.
@MainActor
enum FocusNowPlaying {
    struct Track {
        let title: String
        let subtitle: String
        let artwork: NSImage?
        let isPlaying: Bool
        let brand: Color
        let info: NowPlayingInfo
        let actions: NowPlayingActions
    }

    static func current() -> Track? {
        let music = MusicController.shared
        if let title = music.trackTitle {
            let subtitle = [music.artist, music.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            let info = NowPlayingInfo(title: title, subtitle: subtitle, artwork: music.artwork,
                                      isPlaying: AppState.shared.musicPlaying, duration: music.duration,
                                      canSeek: music.duration > 0, shuffling: music.shuffling,
                                      repeating: music.repeating, volume: music.volume,
                                      brand: Color(hex: MusicController.red))
            let actions = NowPlayingActions(
                position: { music.position(at: $0) }, playPause: { music.playPause() },
                previous: { music.previousTrack() }, next: { music.nextTrack() },
                seek: { music.seek(to: $0) }, setShuffling: { music.setShuffling($0) },
                setRepeating: { music.setRepeating($0) }, setVolume: { music.setVolume($0) },
                openApp: { music.openMusic() }, openHelp: String(localized: "Open Music"))
            return Track(title: title, subtitle: subtitle, artwork: music.artwork,
                         isPlaying: AppState.shared.musicPlaying, brand: Color(hex: MusicController.red),
                         info: info, actions: actions)
        }
        let spotify = SpotifyController.shared
        if let track = spotify.track {
            let subtitle = [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · ")
            let info = NowPlayingInfo(title: track.title, subtitle: subtitle, artwork: spotify.artwork,
                                      isPlaying: spotify.isPlaying, duration: track.duration,
                                      canSeek: !track.isAd && track.duration > 0, shuffling: spotify.shuffling,
                                      repeating: spotify.repeating, volume: spotify.volume,
                                      brand: Color(hex: SpotifyController.green))
            let actions = NowPlayingActions(
                position: { spotify.position(at: $0) }, playPause: { spotify.playPause() },
                previous: { spotify.previousTrack() }, next: { spotify.nextTrack() },
                seek: { spotify.seek(to: $0) }, setShuffling: { spotify.setShuffling($0) },
                setRepeating: { spotify.setRepeating($0) }, setVolume: { spotify.setVolume($0) },
                openApp: { spotify.openSpotify() }, openHelp: String(localized: "Open Spotify"))
            return Track(title: track.title, subtitle: subtitle, artwork: spotify.artwork,
                         isPlaying: spotify.isPlaying, brand: Color(hex: SpotifyController.green),
                         info: info, actions: actions)
        }
        return nil
    }
}

/// The open notch in Focus: a small music island (like an expanded Dynamic Island) —
/// no header, no card, just the cover, the song, a thin seek bar and the controls.
struct FocusMusicView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var music = MusicController.shared
    @ObservedObject private var spotify = SpotifyController.shared

    var body: some View {
        Group {
            if let t = FocusNowPlaying.current() {
                player(t)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "headphones")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: NotchModes.Mode.focus.colorHex))
                    Text("Nothing playing")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer(minLength: 4)
                    Button(String(localized: "Open Music")) { MusicController.shared.openMusic() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: NotchModes.Mode.focus.colorHex))
                        .buttonStyle(.plain)
                    FocusModeDot()
                }
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
            }
        }
        // Clear the notch (the container already adds 8 pt on top): the player sits under it
        .padding(.top, max(0, state.notchHeight - 6))
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { MusicController.shared.refresh(); SpotifyController.shared.refresh() }
    }

    private func player(_ t: FocusNowPlaying.Track) -> some View {
        let accent = ArtworkAccent.color(for: t.artwork) ?? t.brand
        return VStack(spacing: 7) {
            // Cover · song · bars · mode
            HStack(spacing: 9) {
                NowPlayingArtwork(image: t.artwork, accent: accent)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: accent.opacity(t.isPlaying ? 0.5 : 0), radius: 7)
                    .scaleEffect(t.isPlaying ? 1 : 0.92)
                    .animation(.spring(response: 0.35, dampingFraction: 1), value: t.isPlaying)
                    .onTapGesture { t.actions.openApp() }
                    .help(t.actions.openHelp)
                VStack(alignment: .leading, spacing: 0) {
                    MarqueeText(text: t.title, font: .system(size: 12.5, weight: .semibold), color: .white)
                        .tracking(-0.1)
                    Text(t.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
                SoundBars(isPlaying: t.isPlaying, color: accent)
                    .frame(width: 14, height: 12)
                FocusModeDot()
            }

            // Slim seek bar with small times at both ends
            TimelineView(.animation(minimumInterval: 0.5, paused: !t.isPlaying)) { context in
                NowPlayingProgress(position: t.actions.position(context.date), duration: t.info.duration,
                                   accent: accent, canSeek: t.info.canSeek, onSeek: { t.actions.seek($0) })
            }

            // ⏮ ▶︎ ⏭ — plain glyphs, like the iPhone's island
            HStack(spacing: 30) {
                NowPlayingIconButton(icon: "backward.fill", size: 13, tint: Color.white.opacity(0.85),
                                     help: "Previous") { t.actions.previous() }
                Button(action: { t.actions.playPause() }) {
                    Image(systemName: t.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NowPlayingPressStyle())
                .help(t.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
                NowPlayingIconButton(icon: "forward.fill", size: 13, tint: Color.white.opacity(0.85),
                                     help: "Next") { t.actions.next() }
            }
        }
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.4), value: t.artwork)
    }
}

/// A tiny mode switch for the Focus island (it has no header row).
struct FocusModeDot: View {
    @ObservedObject private var modes = NotchModes.shared

    var body: some View {
        Menu {
            ForEach(NotchModes.Mode.allCases) { m in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { modes.choose(m) }
                } label: {
                    Label("\(m.title) — \(m.summary)", systemImage: m == modes.mode ? "checkmark" : m.icon)
                }
            }
        } label: {
            Image(systemName: modes.mode.icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(Color(hex: modes.mode.colorHex).opacity(0.9))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Notch mode"))
    }
}

// MARK: - Closed notch in Focus: cover on the left (where Mochi stands), bars on the right

struct CompactFocusLeading: View {
    @ObservedObject private var music = MusicController.shared
    @ObservedObject private var spotify = SpotifyController.shared
    @ObservedObject private var app = AppState.shared

    var body: some View {
        if let t = FocusNowPlaying.current() {
            Group {
                if let art = t.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note").font(.system(size: 9, weight: .semibold))
                            .foregroundColor(t.brand)
                    }
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .scaleEffect(t.isPlaying ? 1 : 0.88)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: t.isPlaying)
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
        }
    }
}
#endif
