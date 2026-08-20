// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

/// Falls back to a real ⌘C when Accessibility has no selected-text string to
/// offer — some apps (VS Code's editor, Mail's rich-text compose) never
/// populate `kAXSelectedTextAttribute` even though a real Copy works fine.
/// This is the same "Simulated Keystroke" strategy PopClip's own preferences
/// document as an alternative to its Accessibility-API mode.
enum ShadowCopySelectionReader {
    /// Sends ⌘C, diffs the pasteboard against its state from just before the
    /// copy, and restores it afterward — reading a selection this way never
    /// leaves a lasting trace on the clipboard or in its history.
    ///
    /// Every actual pasteboard touch runs through `GeneralPasteboardAccess`,
    /// the same serial lane Clipboard History and the URL cleaner use —
    /// touching `NSPasteboard.general` directly from here raced their
    /// background reads of its type cache and crashed the app.
    static func read(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let (snapshotBefore, beforeChangeCount) = GeneralPasteboardAccess.shared.sync {
            () -> ([NSPasteboardItem], Int) in
            (SyntheticPasteSupport.snapshot(of: pasteboard), pasteboard.changeCount)
        }
        SyntheticPasteSupport.waitForCleanModifiers {
            postCmdC {
                // Give the target app a beat to actually write to the
                // pasteboard before checking whether anything changed.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    let outcome: (text: String?, restoredChangeCount: Int)? = GeneralPasteboardAccess.shared.sync {
                        guard pasteboard.changeCount != beforeChangeCount else { return nil }
                        let copied = pasteboard.string(forType: .string)
                        pasteboard.clearContents()
                        if !snapshotBefore.isEmpty {
                            pasteboard.writeObjects(snapshotBefore)
                        }
                        return (copied, pasteboard.changeCount)
                    }
                    if let outcome {
                        ClipboardHistoryService.shared.ignoreNextChange(upTo: outcome.restoredChangeCount)
                    }
                    completion(outcome?.text)
                }
            }
        }
    }

    /// Posts the raw ⌘C key-down/key-up pair — mirrors
    /// `SyntheticPasteSupport.postCmdV` exactly, including not setting a
    /// unicode string on the event (breaks menu key-equivalent dispatch,
    /// verified empirically there).
    private static func postCmdC(completion: @escaping () -> Void) {
        guard let keyDown = CGEvent(keyboardEventSource: nil,
                                    virtualKey: CGKeyCode(kVK_ANSI_C),
                                    keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil,
                                  virtualKey: CGKeyCode(kVK_ANSI_C),
                                  keyDown: false)
        else {
            completion()
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            keyUp.post(tap: .cghidEventTap)
            completion()
        }
    }
}
