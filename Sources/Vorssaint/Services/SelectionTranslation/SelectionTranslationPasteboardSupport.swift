// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox

/// Pure policy used by the selection reader. The actual pasteboard work still
/// runs through GeneralPasteboardAccess; keeping the destructive restore guard
/// here makes it independently testable.
enum SelectionTranslationPasteboardSupport {
    static let copyKeyCode = CGKeyCode(kVK_ANSI_C)

    static func shouldRestore(originalChangeCount: Int,
                              copyChangeCount: Int,
                              currentChangeCount: Int) -> Bool {
        copyChangeCount != originalChangeCount && currentChangeCount == copyChangeCount
    }

}

enum SelectionTranslationConstants {
    static let quickToolHotkeyID: UInt32 = 21
}
