#if !APPSTORE
import AppKit
import Combine

// MARK: - Shelf

/// Files dropped on the notch, kept for a day (or until unpinned and a day old). Only the path
/// is kept: nothing is copied, and a file deleted meanwhile leaves the shelf on its own.
/// Singleton, @MainActor, GitHub build only. Saved in UserDefaults.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    nonisolated static let pillId = "integration_shelf"
    nonisolated static let color  = "#38BDF8"
    /// How long an unpinned file stays.
    nonisolated static let lifetime: TimeInterval = 24 * 3600
    nonisolated private static let defaultsKey = "coucou.shelf"
    nonisolated private static let maxItems = 40

    struct Item: Identifiable, Codable, Equatable {
        let id: UUID
        let path: String
        var added: Date
        var pinned: Bool

        var url: URL { URL(fileURLWithPath: path) }
        var name: String { url.lastPathComponent }
        var expires: Date { added.addingTimeInterval(ShelfStore.lifetime) }
    }

    /// Newest first.
    @Published private(set) var items: [Item] = []

    private var sweep: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        }
        prune()
        // Expired files leave even while nobody looks: one sweep every 10 minutes.
        sweep = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in ShelfStore.shared.prune() }
        }
        AppState.shared.$tasks
            .map { $0.contains { $0.id == Self.pillId } }
            .removeDuplicates()
            .sink { [weak self] loaded in if loaded { self?.syncTaskName() } }
            .store(in: &cancellables)
    }

    // MARK: Changes

    func add(_ urls: [URL]) {
        let now = Date()
        for url in urls.reversed() where url.isFileURL {
            let path = url.standardizedFileURL.path
            if let i = items.firstIndex(where: { $0.path == path }) {
                // Dropped again: back to the front, with a fresh day
                var item = items.remove(at: i)
                item.added = now
                items.insert(item, at: 0)
            } else {
                items.insert(Item(id: UUID(), path: path, added: now, pinned: false), at: 0)
            }
        }
        if items.count > Self.maxItems {
            // Drop the oldest unpinned ones first
            while items.count > Self.maxItems, let i = items.lastIndex(where: { !$0.pinned }) { items.remove(at: i) }
        }
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func togglePin(_ item: Item) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].pinned.toggle()
        if !items[i].pinned { items[i].added = Date() }   // unpinned: a full day from now
        save()
    }

    func clearUnpinned() {
        items.removeAll { !$0.pinned }
        save()
    }

    /// Removes files past their day (unless pinned) and files that no longer exist.
    func prune() {
        let now = Date()
        let fm = FileManager.default
        let kept = items.filter { ($0.pinned || $0.expires > now) && fm.fileExists(atPath: $0.path) }
        if kept != items { items = kept; save() } else { syncTaskName() }
    }

    // MARK: Actions

    func open(_ item: Item) { NSWorkspace.shared.open(item.url) }

    func reveal(_ item: Item) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    func revealAll() {
        let urls = items.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    // MARK: Saving

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        syncTaskName()
    }

    /// The pill reads "Shelf · 3" while it holds files.
    private func syncTaskName() {
        guard let idx = AppState.shared.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }
        let base = PillCatalog.definition(for: Self.pillId)?.name ?? "Shelf"
        AppState.shared.tasks[idx].name = items.isEmpty ? base : "\(base) · \(items.count)"
    }
}

// MARK: - Drop on the notch

enum ShelfDrop {
    /// Files dropped on the notch go to the shelf: Mochi gulps them, then the Shelf card opens.
    @MainActor
    static func handle(urls: [URL], state: AppState) async {
        guard let first = urls.first else { return }
        ShelfStore.shared.add(urls)
        if !state.activeIntegrations.contains(ShelfStore.pillId) {
            state.toggleIntegration(ShelfStore.pillId)   // no-op when the 4 slots are taken
        }

        // Same gulp as before, shorter: the files aren't copied anywhere.
        state.droppedFile = DroppedFile(url: first, name: urls.count == 1
                                        ? first.lastPathComponent
                                        : String(localized: "\(urls.count) files"))
        state.uploadProgress = 0
        state.fileDragOver = false
        let dur = 0.8
        UploadSequenceEngine.shared.performDrop(uploadDuration: dur)
        NotificationCenter.default.post(name: .botGulp, object: nil)
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))
        state.uploadDuration = dur
        state.uploadStartTime = Date()
        state.view = .uploading

        let preProgress = USC.T_PROG_START - USC.T_DROP
        try? await Task.sleep(for: .seconds(preProgress + dur))
        SoundEngine.shared.play("approve")
        try? await Task.sleep(for: .seconds(0.7))

        state.uploadProgress = 0
        state.uploadStartTime = nil
        UploadSequenceEngine.shared.deactivate()
        if state.activeIntegrations.contains(ShelfStore.pillId) { state.setFocus(ShelfStore.pillId) }
        state.view = .overview
    }
}
#endif
