// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import AppKit

/// Carries out one `SelectionAction` against a captured selection. Actions
/// that rewrite it either hand the new text to
/// `SyntheticPasteSupport.replaceSelection(with:)` (the pasteboard-swap-and-
/// ⌘V primitive Paste Plain also uses) or, for Cut/Delete, post a synthetic
/// Delete keystroke via `SyntheticPasteSupport.deleteSelection()` — pasting
/// an empty string turned out not to reliably clear a selection in every
/// field, where a real Delete keystroke does.
enum SelectionActionRunner {
    static func run(_ action: SelectionAction, on snapshot: SelectionSnapshot) {
        switch action {
        case .copy:
            copyToPasteboard(snapshot.text)
        case .cut:
            copyToPasteboard(snapshot.text)
            SyntheticPasteSupport.deleteSelection()
        case .paste:
            guard let clipboard = NSPasteboard.general.string(forType: .string) else { return }
            SyntheticPasteSupport.replaceSelection(with: clipboard)
        case .delete:
            SyntheticPasteSupport.deleteSelection()
        }
    }

    private static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
