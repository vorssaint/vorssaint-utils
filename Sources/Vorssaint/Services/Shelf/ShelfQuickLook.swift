// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuickLookUI

/// Space-to-preview for Shelf tiles, the way Finder does it.
///
/// The shared QLPreviewPanel is normally driven through the responder chain,
/// but the Shelf lives in a borderless `.nonactivatingPanel` that is often up
/// while another app is frontmost, so there is no reliable first responder for
/// QuickLook to walk to. Setting the panel's data source directly is the
/// documented alternative and keeps the behavior identical.
///
/// No permissions required: QuickLook renders files the user already dropped on
/// the Shelf, and nothing here reaches outside those URLs.
final class ShelfQuickLookController: NSObject {
    static let shared = ShelfQuickLookController()

    private var urls: [URL] = []

    private override init() { super.init() }

    var isPreviewing: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    /// Opens the preview, or closes it when it is already showing, so one
    /// Space press toggles the way it does in Finder. Returns false when there
    /// was nothing previewable, leaving the key event to whoever wants it next.
    @discardableResult
    func toggle(urls candidates: [URL], anchor: URL? = nil) -> Bool {
        if isPreviewing {
            close()
            return true
        }
        // A bookmark can outlive the file it points at, and QuickLook shows a
        // blank panel for a URL that is gone rather than reporting anything.
        let existing = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return false }

        urls = existing
        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = ShelfQuickLookSupport.initialIndex(urls: existing,
                                                                          anchorURL: anchor)
        // An accessory app's panels can be up without the app being active, and
        // QuickLook needs key status to take arrow keys and Escape.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func close() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }
}

extension ShelfQuickLookController: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }
}

extension ShelfQuickLookController: QLPreviewPanelDelegate {
    /// Escape closes the preview without also clearing the Shelf selection
    /// underneath it, which is what the panel's own key handling would leave
    /// to KeyableShelfPanel.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown,
              ShelfSelectionSupport.isClearSelectionShortcut(
                  keyCode: event.keyCode,
                  hasSelectionModifiers: !event.modifierFlags
                      .intersection([.command, .option, .shift, .control]).isEmpty
              ) else { return false }
        close()
        return true
    }
}
