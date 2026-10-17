#if !APPSTORE
import AppKit

// MARK: - Lock / unlock sounds (GitHub build only)

/// A soft sound when the Mac locks, a happy one (and a wave from Mochi) when it unlocks.
/// Uses Coucou's own sounds, so the sound switch in Settings mutes them too.
@MainActor
final class LockSounds {
    static let shared = LockSounds()
    private var tokens: [Any] = []

    private init() {}

    func start() {
        guard tokens.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        tokens.append(center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in SoundEngine.shared.play("close") }
        })
        tokens.append(center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                // Let the lock screen fade out first, then greet
                try? await Task.sleep(for: .milliseconds(350))
                SoundEngine.shared.play("greet")
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
                // First unlock of the day: the daily brief slides out of the notch
                DailyBrief.showIfFirstToday(after: 1.0)
            }
        })
    }
}
#endif
