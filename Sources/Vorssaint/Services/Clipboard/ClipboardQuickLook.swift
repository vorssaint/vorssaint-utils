// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Quartz

/// Quick Look for a clipboard entry: the system's own preview panel, the one
/// Finder opens on Space, so an image, a file or a long text gets a window of
/// its own instead of the pane beside the list. Files and stored images are
/// shown in place; text is written to a temporary file for the panel to read,
/// and that file is replaced on the next look and removed on quit.
final class ClipboardQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = ClipboardQuickLook()

    private var items: [URL] = []
    private var textFile: URL?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.removeTextFile()
        }
    }

    func show(_ entry: ClipboardHistoryEntry) {
        let urls: [URL]
        switch entry.kind {
        case .text:
            guard let url = writeTextFile(entry.text) else { return }
            urls = [url]
        case .files, .image:
            urls = ClipboardHistoryService.draggableFileURLs(for: entry)
        }
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        items = urls
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
              panel.isVisible else { return }
        panel.orderOut(nil)
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        items[index] as NSURL
    }

    // MARK: Text on disk

    private func writeTextFile(_ text: String) -> URL? {
        removeTextFile()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-\(UUID().uuidString).txt")
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        textFile = url
        return url
    }

    private func removeTextFile() {
        if let textFile { try? FileManager.default.removeItem(at: textFile) }
        textFile = nil
    }
}
