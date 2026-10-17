#if !APPSTORE
import SwiftUI
import AppKit

// MARK: - Shelf card (overview left card, GitHub build only)

struct ShelfCardView: View {
    @ObservedObject private var shelf = ShelfStore.shared

    private let blue = Color(hex: ShelfStore.color)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

            if shelf.items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 16))
                        .foregroundColor(blue.opacity(0.7))
                    Text("Drop files on the notch to keep them here for a day")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 14)
                .padding(.leading, 108)
                .padding(.trailing, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item, accent: blue)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .padding(.top, 8)
                .padding(.leading, 106)
                .padding(.trailing, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .onAppear { shelf.prune() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(blue).frame(width: 7, height: 7)
            Text("Shelf")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
            if !shelf.items.isEmpty {
                Text("\(shelf.items.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            Spacer(minLength: 2)
            if shelf.items.contains(where: { !$0.pinned }) {
                Button(String(localized: "Clear")) { withAnimation(.easeOut(duration: 0.2)) { shelf.clearUnpinned() } }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .buttonStyle(.plain)
                    .help(String(localized: "Remove every file that isn't pinned"))
            }
        }
    }
}

/// One file: its icon and name. Drag it out anywhere, click to open, right-click for more.
struct ShelfTile: View {
    let item: ShelfStore.Item
    let accent: Color
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 34, height: 34)
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Circle().fill(accent))
                        .offset(x: 4, y: -3)
                }
            }
            Text(item.name)
                .font(.system(size: 9))
                .foregroundColor(Color(hex: hovered ? "#F5F6F8" : "#B0B5BE"))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 50, height: 22, alignment: .top)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovered ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
        .onTapGesture { ShelfStore.shared.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .help(helpText)
        .contextMenu {
            Button(String(localized: "Open")) { ShelfStore.shared.open(item) }
            Button(String(localized: "Show in Finder")) { ShelfStore.shared.reveal(item) }
            Divider()
            Button(item.pinned ? String(localized: "Unpin") : String(localized: "Pin (keep it)")) {
                ShelfStore.shared.togglePin(item)
            }
            Button(String(localized: "Remove from shelf")) { ShelfStore.shared.remove(item) }
        }
    }

    private var helpText: String {
        if item.pinned { return String(localized: "\(item.name) · pinned") }
        let hours = max(1, Int(ceil(item.expires.timeIntervalSinceNow / 3600)))
        return String(localized: "\(item.name) · leaves the shelf in \(hours) h")
    }
}
#endif
