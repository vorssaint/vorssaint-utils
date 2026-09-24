// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A clipboard thumbnail that never decodes on the main thread. A cached
/// thumbnail shows at once; otherwise the row keeps the image's shape with a
/// quiet placeholder while the decode runs in the background, so typing in
/// the search field stays responsive however many screenshots the history
/// holds. Callers size and clip it like a resizable `Image`.
struct ClipboardThumbnailImage: View {
    let source: ClipboardImageStore.ThumbnailSource
    /// Width over height, when known, so the placeholder takes the same room
    /// as the image and the row does not jump when it arrives.
    var aspectRatio: CGFloat?
    var contentMode: ContentMode = .fit
    var failureText: String?

    @State private var loaded: (source: ClipboardImageStore.ThumbnailSource, image: NSImage?)?

    private var image: NSImage? {
        if let loaded, loaded.source == source { return loaded.image }
        return ClipboardImageStore.cachedThumbnail(source)
    }

    private var failed: Bool {
        guard let loaded, loaded.source == source else { return false }
        return loaded.image == nil
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed, let failureText {
                Text(failureText)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .aspectRatio(aspectRatio ?? 1, contentMode: contentMode)
                    .overlay {
                        if failed {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .task(id: source) {
            // Kept in state even on a cache hit: the cache may evict it while
            // the row is still on screen, and the row must not go blank then.
            let image = await ClipboardImageStore.loadThumbnail(source)
            guard !Task.isCancelled else { return }
            loaded = (source, image)
        }
    }
}

extension ClipboardHistoryEntry {
    /// Width over height of a copied image, for sizing its placeholder.
    var imageAspectRatio: CGFloat? {
        guard let imageWidth, let imageHeight, imageWidth > 0, imageHeight > 0 else { return nil }
        return CGFloat(imageWidth) / CGFloat(imageHeight)
    }
}

extension ClipboardImageStore {
    /// Width over height of an image file, from its header alone.
    static func imageAspectRatio(atPath path: String) -> CGFloat? {
        guard let dimensions = imageDimensions(atPath: path) else { return nil }
        return CGFloat(dimensions.width) / CGFloat(dimensions.height)
    }
}
