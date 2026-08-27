// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

/// The low-level "post a synthetic ⌘V" primitive, shared by every feature
/// that needs to replace whatever text is currently selected in the
/// frontmost app: write new text to the pasteboard, then paste over the
/// live selection, which is the only reliable cross-app way to do this since
/// no app is required to honor an AX value write on its text elements.
enum SyntheticPasteSupport {
    /// Posts ⌘V once no modifier key is physically down, checking every 15 ms
    /// for up to ~1.5 s. Someone who keeps a chord pressed longer than that
    /// gets the paste anyway; by then the merge race is long over for most
    /// hands, and never pasting would be worse. The extra beat after the keys
    /// read clean matters: posted right on the release, the target app can
    /// still see the stale modifier state and refuse the key equivalent.
    static func waitForCleanModifiers(attempt: Int = 0, completion: @escaping () -> Void) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if held.isEmpty || attempt >= 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: completion)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            waitForCleanModifiers(attempt: attempt + 1, completion: completion)
        }
    }

    /// Posts the raw ⌘V key-down/key-up pair. Assumes the caller has already
    /// waited for a clean keyboard (see `waitForCleanModifiers`) - this does
    /// not wait itself, unlike some of this enum's other members, so the name
    /// says so rather than leaving two same-looking calls with opposite
    /// contracts. A no-op (with a beep, matching every other synthetic-paste
    /// call site in the app) while secure event input is active - typing into
    /// a password field disables synthetic keyboard events system-wide, so
    /// posting anyway would silently do nothing instead of telling the person
    /// why.
    static func postCmdVAssumingCleanModifiers(completion: @escaping () -> Void) {
        guard !IsSecureEventInputEnabled() else {
            NSSound.beep()
            completion()
            return
        }
        // No explicit event source: an event tied to the HID state inherits
        // whatever the hardware still reports, which right after a caller's
        // own keys can re-poison the flags waitForCleanModifiers just waited
        // out.
        guard let keyDown = CGEvent(keyboardEventSource: nil,
                                    virtualKey: CGKeyCode(kVK_ANSI_V),
                                    keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil,
                                  virtualKey: CGKeyCode(kVK_ANSI_V),
                                  keyDown: false)
        else {
            completion()
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        // No keyboardSetUnicodeString here: a forced character string on the
        // event breaks menu key equivalent dispatch (verified empirically),
        // which is exactly the ⌘V we are trying to trigger.
        keyDown.post(tap: .cghidEventTap)
        // A beat between down and up mirrors a real key press; some apps skip
        // equivalents delivered as a zero-length tap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            keyUp.post(tap: .cghidEventTap)
            completion()
        }
    }

    static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    /// Posts a synthetic Delete/Backspace, which removes an active selection
    /// in essentially every text field — native, web, and browser chrome
    /// alike. Used instead of `replaceSelection(with: "")` for Cut/Delete:
    /// pasting an empty string turned out to be unreliable in some fields
    /// (Notes, a browser's own address bar) where a real Delete keystroke
    /// works everywhere. Waits for a clean keyboard itself, unlike
    /// `postCmdVAssumingCleanModifiers` - callers here have no earlier step
    /// that already waited, so the function owns it.
    static func deleteSelection(completion: (() -> Void)? = nil) {
        waitForCleanModifiers {
            guard !IsSecureEventInputEnabled() else {
                NSSound.beep()
                completion?()
                return
            }
            guard let keyDown = CGEvent(keyboardEventSource: nil,
                                        virtualKey: CGKeyCode(kVK_Delete),
                                        keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil,
                                      virtualKey: CGKeyCode(kVK_Delete),
                                      keyDown: false)
            else {
                completion?()
                return
            }
            keyDown.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                keyUp.post(tap: .cghidEventTap)
                completion?()
            }
        }
    }

    /// Writes `text` to the general pasteboard, pastes it over the frontmost
    /// app's current selection once the keyboard reads clean, then restores
    /// whatever was on the pasteboard before — unless something else changed
    /// the pasteboard in the meantime, in which case the newer content wins
    /// and the snapshot is dropped silently.
    ///
    /// Every actual pasteboard touch runs through `GeneralPasteboardAccess`,
    /// the same serial lane Clipboard History and the URL cleaner use —
    /// touching `NSPasteboard.general` directly from here raced their
    /// background reads of its type cache and crashed the app.
    static func replaceSelection(with text: String,
                                 restoreDelay: TimeInterval = 0.5,
                                 completion: (() -> Void)? = nil) {
        let pasteboard = NSPasteboard.general
        GeneralPasteboardAccess.shared.async({ () -> ([NSPasteboardItem], Int) in
            let snapshotBefore = snapshot(of: pasteboard)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return (snapshotBefore, pasteboard.changeCount)
        }, then: { (snapshotBefore, changeCount) in
            ClipboardHistoryService.shared.ignoreNextChange(upTo: changeCount)
            waitForCleanModifiers {
                postCmdVAssumingCleanModifiers {
                    DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                        GeneralPasteboardAccess.shared.async({ () -> Int? in
                            guard pasteboard.changeCount == changeCount, !snapshotBefore.isEmpty
                            else { return nil }
                            pasteboard.clearContents()
                            pasteboard.writeObjects(snapshotBefore)
                            return pasteboard.changeCount
                        }, then: { restoredChangeCount in
                            if let restoredChangeCount {
                                ClipboardHistoryService.shared.ignoreNextChange(upTo: restoredChangeCount)
                            }
                            completion?()
                        })
                    }
                }
            }
        })
    }
}
