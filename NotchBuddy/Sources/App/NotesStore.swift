#if !APPSTORE
import AppKit
import Combine

// MARK: - Notes & reminders

/// Quick notes typed in the notch. Each stays 24 h (or until unpinned and a day old); a note can
/// carry a reminder time, and when it comes the notch opens on it with a sound, a haptic and
/// Mochi. Only one wake-up is ever scheduled: the next reminder. Saved in UserDefaults.
/// Singleton, @MainActor, GitHub build only.
@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()
    nonisolated static let lifetime: TimeInterval = 24 * 3600
    nonisolated static let color = "#FBBF24"
    nonisolated private static let key = "coucou.notes"

    struct Note: Identifiable, Codable, Equatable {
        let id: UUID
        var text: String
        var created: Date
        var remindAt: Date?
        var done: Bool
        var pinned: Bool
        /// The reminder already went off.
        var fired: Bool

        /// A day after it was written, or an hour after its reminder if that's later.
        var expires: Date {
            let day = created.addingTimeInterval(NotesStore.lifetime)
            guard let remindAt else { return day }
            return max(day, remindAt.addingTimeInterval(3600))
        }
    }

    /// Newest first.
    @Published private(set) var notes: [Note] = []
    /// The reminder that just went off, highlighted in the list.
    @Published var ringing: UUID?

    private var reminderTask: Task<Void, Never>?
    private var sweep: Timer?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Note].self, from: data) {
            notes = saved
        }
        prune()
        scheduleNextReminder()
        sweep = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in NotesStore.shared.prune() }
        }
    }

    var pendingReminders: Int { notes.filter { $0.remindAt != nil && !$0.fired && !$0.done }.count }

    // MARK: Changes

    func add(_ raw: String, remindAt: Date?) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        notes.insert(Note(id: UUID(), text: text, created: Date(), remindAt: remindAt,
                          done: false, pinned: false, fired: false), at: 0)
        SoundEngine.shared.play("send")
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        changed()
    }

    func toggleDone(_ note: Note) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[i].done.toggle()
        if notes[i].done {
            SoundEngine.shared.play("pop")
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            if ringing == note.id { ringing = nil }
        } else {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        changed()
    }

    func togglePin(_ note: Note) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[i].pinned.toggle()
        if !notes[i].pinned { notes[i].created = Date() }   // unpinned: a full day from now
        changed()
    }

    func remove(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        if ringing == note.id { ringing = nil }
        changed()
    }

    func clearDone() {
        notes.removeAll { $0.done && !$0.pinned }
        changed()
    }

    /// Notes past their time (unless pinned) leave.
    func prune() {
        let now = Date()
        let kept = notes.filter { $0.pinned || $0.expires > now }
        if kept != notes { notes = kept; changed() }
    }

    private func changed() {
        save()
        scheduleNextReminder()
    }

    // MARK: Reminders

    private func scheduleNextReminder() {
        reminderTask?.cancel()
        let now = Date()
        // Reminders that came due while Coucou was closed ring now
        if let due = notes.first(where: { !$0.fired && !$0.done && ($0.remindAt ?? .distantFuture) <= now }) {
            ring(due.id)
            return
        }
        guard let next = notes.filter({ !$0.fired && !$0.done && $0.remindAt != nil })
            .min(by: { $0.remindAt! < $1.remindAt! }), let at = next.remindAt else { return }
        let id = next.id
        reminderTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, at.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.ring(id)
        }
    }

    private func ring(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].fired = true
        ringing = id
        save()
        SoundEngine.shared.play("approval")
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.notes)
        scheduleNextReminder()
    }

    // MARK: Saving

    private func save() {
        if let data = try? JSONEncoder().encode(notes) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
#endif
