// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure decisions for Space → Get Info on Finder folders (issue #1424).
/// The event tap claims Space only when Finder is frontmost, the focused
/// role is not a text field, and no modifiers are held; the selection is
/// inspected off the tap thread afterwards.
enum FinderFolderInfoSupport {
    /// What to do once the Finder selection has been classified.
    enum AfterSelection: Equatable {
        /// Every selected item is a folder: open Finder's Get Info windows.
        case openGetInfo
        /// Empty selection, or any non-folder: re-post Space so Finder's
        /// Quick Look (or its empty-selection no-op) still runs.
        case forwardQuickLook
    }

    /// Whether the tap should swallow Space before reading the selection.
    static func shouldClaimSpace(isFinderFrontmost: Bool,
                                 hasModifiers: Bool,
                                 acceptsFocusedRole: Bool) -> Bool {
        isFinderFrontmost && !hasModifiers && acceptsFocusedRole
    }

    /// `directoryFlags[i]` is true when selection item `i` is a directory.
    static func action(directoryFlags: [Bool]) -> AfterSelection {
        guard !directoryFlags.isEmpty else { return .forwardQuickLook }
        if directoryFlags.allSatisfy({ $0 }) { return .openGetInfo }
        return .forwardQuickLook
    }
}
