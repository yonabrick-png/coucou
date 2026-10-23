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

/// The open notch in Focus: one big player across the whole island, nothing else.
struct FocusMusicView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var music = MusicController.shared
    @ObservedObject private var spotify = SpotifyController.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            if let t = FocusNowPlaying.current() {
                player(t)
            } else {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06))
                        Image(systemName: "headphones")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundColor(Color(hex: NotchModes.Mode.focus.colorHex).opacity(0.8))
                    }
                    .frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Nothing playing")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Focus mode shows only your music.")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.55))
                        Button(String(localized: "Open Music")) { MusicController.shared.openMusic() }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Color(hex: NotchModes.Mode.focus.colorHex))
                            .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 22)
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.bottom, 10)
        .onAppear { MusicController.shared.refresh(); SpotifyController.shared.refresh() }
    }

    private func player(_ t: FocusNowPlaying.Track) -> some View {
        let accent = ArtworkAccent.color(for: t.artwork) ?? t.brand
        return HStack(alignment: .center, spacing: 18) {
            // Big cover with a glow in its own colour
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent.opacity(t.isPlaying ? 0.35 : 0.12))
                    .blur(radius: 14)
                    .frame(width: 84, height: 84)
                NowPlayingArtwork(image: t.artwork, accent: accent)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .scaleEffect(t.isPlaying ? 1 : 0.94)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: t.isPlaying)
                    .onTapGesture { t.actions.openApp() }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: t.title, font: .system(size: 16, weight: .semibold), color: .white)
                        Text(t.subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    SoundBars(isPlaying: t.isPlaying, color: accent)
                        .frame(width: 20, height: 16)
                }

                TimelineView(.animation(minimumInterval: 0.5, paused: !t.isPlaying)) { context in
                    NowPlayingProgress(position: t.actions.position(context.date), duration: t.info.duration,
                                       accent: accent, canSeek: t.info.canSeek, onSeek: { t.actions.seek($0) })
                }

                HStack(spacing: 0) {
                    HStack(spacing: 16) {
                        NowPlayingIconButton(icon: "shuffle", size: 11,
                                             tint: t.info.shuffling ? accent : Color(hex: "#6B7079"),
                                             help: "Shuffle") { t.actions.setShuffling(!t.info.shuffling) }
                        NowPlayingIconButton(icon: "backward.fill", size: 15, tint: Color(hex: "#E4E6EA"),
                                             help: "Previous") { t.actions.previous() }
                        Button(action: { t.actions.playPause() }) {
                            ZStack {
                                Circle().fill(Color.white)
                                Image(systemName: t.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(hex: "#0E0F11"))
                                    .offset(x: t.isPlaying ? 0 : 1.5)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .frame(width: 32, height: 32)
                            .shadow(color: accent.opacity(0.45), radius: 8)
                        }
                        .buttonStyle(NowPlayingPressStyle())
                        NowPlayingIconButton(icon: "forward.fill", size: 15, tint: Color(hex: "#E4E6EA"),
                                             help: "Next") { t.actions.next() }
                        NowPlayingIconButton(icon: "repeat", size: 11,
                                             tint: t.info.repeating ? accent : Color(hex: "#6B7079"),
                                             help: "Repeat") { t.actions.setRepeating(!t.info.repeating) }
                    }
                    Spacer(minLength: 10)
                    NowPlayingVolume(volume: t.info.volume, accent: accent) { t.actions.setVolume($0) }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.4), value: t.artwork)
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
