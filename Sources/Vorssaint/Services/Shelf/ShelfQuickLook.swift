// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Quartz

/// Feeds the shared Quick Look panel with the Shelf's files. A Shelf panel
/// takes control of the Quick Look panel through the responder chain and hands
/// it this source; the files are fixed when Space is pressed, so the preview
/// does not change under the user while the shelf redraws.
final class ShelfQuickLookSource: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = ShelfQuickLookSource()

    private var urls: [URL] = []
    private var initialIndex = 0

    var isPreviewing: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    /// Opens the preview on the Shelf's selection, or on everything when
    /// nothing is selected, or closes a preview that is already up. Notes and
    /// links have no file to preview, so they are left out of it.
    func toggle() {
        if isPreviewing {
            QLPreviewPanel.shared().orderOut(nil)
            return
        }
        // Files that are gone already say so through the Shelf's own notice,
        // so only a shelf without files beeps.
        let holdsFiles = ShelfService.shared.hasFilesForActions
        let preview = ShelfService.shared.quickLookPreview()
        guard !preview.urls.isEmpty else {
            if !holdsFiles { NSSound.beep() }
            return
        }
        urls = preview.urls
        initialIndex = preview.index
        // Vorssaint is rarely the active app while its Shelf is up; without
        // activating it, the preview would open behind the app in front and
        // its arrow keys would go to that app.
        NSApp.activate(ignoringOtherApps: true)
        QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
    }

    func begin(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = initialIndex
    }

    func end(_ panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }

    /// Space closes the preview again from inside it, as in Finder.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        guard ShelfQuickLookSupport.isToggleShortcut(keyCode: event.keyCode,
                                                     hasModifiers: !modifiers.isEmpty,
                                                     isRepeat: event.isARepeat) else { return false }
        panel.orderOut(nil)
        return true
    }
}
