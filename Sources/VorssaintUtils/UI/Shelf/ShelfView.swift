import SwiftUI
import UniformTypeIdentifiers

/// Contents of the floating shelf panel: a header with a count and actions, and
/// a row of item tiles you can drag back out. Dropping onto the card adds more.
struct ShelfView: View {
    @EnvironmentObject private var shelf: ShelfService
    @ObservedObject private var l10n = L10n.shared
    @State private var targeted = false
    @State private var hoveredID: UUID?

    private static let dropTypes: [UTType] = [.fileURL, .image, .url, .text, .plainText]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            tiles
        }
        .padding(12)
        .frame(width: 360)
        .background(HUDBackdrop())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.white.opacity(0.12),
                              lineWidth: targeted ? 2 : 1)
        )
        .animation(.easeOut(duration: 0.15), value: targeted)
        .animation(.easeOut(duration: 0.18), value: shelf.items)
        .onDrop(of: Self.dropTypes, isTargeted: $targeted) { providers in
            shelf.accept(providers: providers)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "tray.full")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(l10n.s.shelfTitle)
                .font(.system(size: 12, weight: .semibold))
            if !shelf.items.isEmpty {
                Text("\(shelf.items.count)")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
            }
            Spacer()
            if !shelf.items.isEmpty {
                Button { shelf.clear() } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(l10n.s.shelfClearAll)
            }
            Button { shelf.hide() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tiles: some View {
        if shelf.items.isEmpty {
            emptyState
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(shelf.items) { item in
                        tile(item)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 96)
        }
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(.secondary.opacity(0.4))
            .frame(height: 96)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 18)).foregroundStyle(.secondary)
                    Text(l10n.s.shelfEmpty).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            )
    }

    private func tile(_ item: ShelfService.Item) -> some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                if item.isImage {
                    Image(nsImage: item.icon)
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    Image(nsImage: item.icon)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 52)

            Text(item.title)
                .font(.system(size: 10))
                .lineLimit(1).truncationMode(.middle)
                .frame(width: 68)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hoveredID == item.id ? Color.white.opacity(0.06) : Color.clear)
        )
        .overlay(alignment: .topTrailing) {
            if hoveredID == item.id {
                Button { shelf.removeItem(item.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .onHover { hoveredID = $0 ? item.id : (hoveredID == item.id ? nil : hoveredID) }
        .onDrag { shelf.provider(for: item) }
    }
}
