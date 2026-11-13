// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CryptoKit
import LinkPresentation

/// The title and picture of a copied web page, for its card on the shelf.
/// Off unless the user turns it on: the page is
/// fetched from the web when a card that shows it is on screen. A result is
/// kept on disk, so a link is fetched once.
@MainActor
final class ClipboardLinkPreviewStore: ObservableObject {
    static let shared = ClipboardLinkPreviewStore()

    struct Preview {
        let title: String?
        let image: NSImage?
    }

    @Published private(set) var previews: [URL: Preview] = [:]
    private var queue = ClipboardLinkPreviewQueue(capacity: ClipboardLinkPreviewStore.concurrentFetches)
    /// A page that gave nothing is not asked again until the next launch.
    private var failed: Set<URL> = []
    private static let concurrentFetches = 3
    /// Wide enough for a card at twice its size, small enough to keep many.
    nonisolated private static let imageWidth: CGFloat = 520

    private init() {}

    /// Starts a fetch, or queues it while the others run, when the preview is
    /// allowed and not yet known, cached or asked for. Called from a card's
    /// task, never while a view is being built.
    func request(_ url: URL) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.clipboardLinkPreviews),
              previews[url] == nil, !queue.contains(url), !failed.contains(url)
        else { return }
        if let stored = Self.readStored(url) {
            previews[url] = stored
            return
        }
        if queue.admit(url) { fetch(url) }
    }

    private func fetch(_ url: URL) {
        let provider = LPMetadataProvider()
        provider.timeout = 12
        // The store lives as long as the app, so the answer goes to it by name.
        provider.startFetchingMetadata(for: url) { metadata, _ in
            let title = metadata?.title
            guard let imageProvider = metadata?.imageProvider ?? metadata?.iconProvider else {
                Task { @MainActor in ClipboardLinkPreviewStore.shared.finish(url, title: title, image: nil) }
                return
            }
            imageProvider.loadObject(ofClass: NSImage.self) { object, _ in
                let image = (object as? NSImage).flatMap(Self.downscaled)
                Task { @MainActor in ClipboardLinkPreviewStore.shared.finish(url, title: title, image: image) }
            }
        }
    }

    private func finish(_ url: URL, title: String?, image: NSImage?) {
        // The next waiting link takes the place whatever this one gave.
        defer { queue.finish(url).forEach(fetch) }
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (cleanTitle?.isEmpty == false) || image != nil else {
            failed.insert(url)
            return
        }
        let preview = Preview(title: cleanTitle, image: image)
        previews[url] = preview
        Self.store(preview, for: url)
    }

    // MARK: - Disk

    private static var directory: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("ClipboardLinkPreviews", isDirectory: true)
    }

    private static func key(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func readStored(_ url: URL) -> Preview? {
        guard let directory else { return nil }
        let base = directory.appendingPathComponent(key(for: url))
        let title = (try? String(contentsOf: base.appendingPathExtension("txt"), encoding: .utf8))
        let image = NSImage(contentsOf: base.appendingPathExtension("png"))
        guard title != nil || image != nil else { return nil }
        return Preview(title: title?.isEmpty == true ? nil : title, image: image)
    }

    private static func store(_ preview: Preview, for url: URL) {
        guard let directory, PrivateFileStore.createDirectory(at: directory) else { return }
        let base = directory.appendingPathComponent(key(for: url))
        try? (preview.title ?? "").write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        if let image = preview.image,
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: base.appendingPathExtension("png"), options: .atomic)
        }
    }

    nonisolated private static func downscaled(_ image: NSImage) -> NSImage {
        let size = image.size
        guard size.width > imageWidth, size.width > 0 else { return image }
        let target = NSSize(width: imageWidth, height: (size.height * imageWidth / size.width).rounded())
        let scaled = NSImage(size: target)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        scaled.unlockFocus()
        return scaled
    }

    /// Turning the setting off forgets what was fetched.
    func removeAll() {
        previews = [:]
        failed = []
        queue.dropWaiting()
        if let directory = Self.directory { try? FileManager.default.removeItem(at: directory) }
    }
}
