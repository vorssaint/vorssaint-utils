// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Puts a string on the general pasteboard, pastes it, and puts back whatever
/// was there before.
///
/// The rules this has to follow are the ones `PastePlainService` already
/// discovered, and getting any of them wrong is silent rather than loud:
/// clipboard history fills with entries the user never copied, a restore
/// clobbers something copied in the meantime, two overlapping writes leave the
/// wrong text on the pasteboard for good, or the ⌘V merges with a modifier the
/// user is still holding and never pastes at all.
///
/// Pasteboard traffic goes through `GeneralPasteboardAccess`, off the caller's
/// thread: reading every flavour of every item round-trips to whichever app owns
/// the clipboard, and a promised flavour that is slow to materialise stalls
/// there. A caller on an event tap cannot afford to wait for that.
final class TransientPaste {
    static let shared = TransientPaste()

    /// Matches `PastePlainService`: long enough for the paste to land, short
    /// enough that the user's own clipboard is theirs again quickly.
    private static let restoreDelay: TimeInterval = 0.5

    private var pendingRestore: (snapshot: [NSPasteboardItem], changeCount: Int)?
    private var restoreWork: DispatchWorkItem?
    private var isPerforming = false

    /// Pastes `text`, then restores the previous contents.
    ///
    /// Returns `false` when a previous paste is still in flight and this one is
    /// dropped, so a caller that destroys something first — deleting a typed
    /// trigger before replacing it — can check before doing the destroying.
    ///
    /// `willPostShortcut` and `didPostShortcut` bracket the synthetic ⌘V on the
    /// main queue. A caller whose own global shortcut *is* ⌘V has to unregister
    /// it across that window, or it catches the synthetic press itself and the
    /// target app never sees a paste.
    @discardableResult
    func paste(_ text: String,
               willPostShortcut: (() -> Void)? = nil,
               didPostShortcut: (() -> Void)? = nil) -> Bool {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.paste(text, willPostShortcut: willPostShortcut, didPostShortcut: didPostShortcut)
            }
            return true
        }
        // A second expansion while the first is still in flight would photograph
        // the first one's text as "the original" and then restore it over the
        // second. Let the first finish and put its own snapshot back.
        guard !isPerforming else { return false }
        isPerforming = true

        let previous = pendingRestore
        restoreWork?.cancel()
        restoreWork = nil

        GeneralPasteboardAccess.shared.async {
            let pasteboard = NSPasteboard.general
            // If the pasteboard still holds our own write from moments ago,
            // keep that write's snapshot rather than photographing our text.
            let snapshot: [NSPasteboardItem]
            if let previous, pasteboard.changeCount == previous.changeCount {
                snapshot = previous.snapshot
            } else {
                snapshot = Self.snapshot(of: pasteboard)
            }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            let changeCount = pasteboard.changeCount
            // Registered here rather than after a hop to main: the history poll
            // could otherwise land between the write and the ignore and record
            // text the user never copied.
            ClipboardHistoryService.shared.ignoreNextChange(upTo: changeCount)

            DispatchQueue.main.async {
                self.pendingRestore = (snapshot, changeCount)
                // The user may still be holding the key that completed the
                // trigger. ⌘V posted on top of a held Shift or Option is a
                // different combination and the target app will not treat it as
                // paste, so wait for a clean keyboard first.
                Self.postPasteWhenModifiersReleased(attempt: 0,
                                                    willPost: willPostShortcut,
                                                    didPost: didPostShortcut) {
                    self.isPerforming = false
                    self.scheduleRestore(snapshot: snapshot, changeCount: changeCount)
                }
            }
        }
        return true
    }

    private func scheduleRestore(snapshot: [NSPasteboardItem], changeCount: Int) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restoreWork = nil
            self.pendingRestore = nil
            GeneralPasteboardAccess.shared.async {
                let pasteboard = NSPasteboard.general
                // Nothing to put back, or the user copied something of their own
                // in the meantime: leave the pasteboard exactly as it is. Doing
                // it in this order matters — clearing first would wipe a
                // clipboard whose contents simply could not be read.
                guard pasteboard.changeCount == changeCount, !snapshot.isEmpty else { return }
                pasteboard.clearContents()
                pasteboard.writeObjects(snapshot)
                ClipboardHistoryService.shared.ignoreNextChange(upTo: pasteboard.changeCount)
            }
        }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay, execute: work)
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    /// Posts ⌘V once no modifier is physically down, checking every 15 ms for up
    /// to ~1.5 s. Someone still holding a key after that gets the paste anyway:
    /// by then the merge race is over for most hands, and never pasting is worse.
    private static func postPasteWhenModifiersReleased(attempt: Int,
                                                       willPost: (() -> Void)?,
                                                       didPost: (() -> Void)?,
                                                       completion: @escaping () -> Void) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if held.isEmpty || attempt >= 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                willPost?()
                postPasteShortcut {
                    didPost?()
                    completion()
                }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            postPasteWhenModifiersReleased(attempt: attempt + 1,
                                           willPost: willPost,
                                           didPost: didPost,
                                           completion: completion)
        }
    }

    private static func postPasteShortcut(completion: @escaping () -> Void) {
        // No explicit event source: one tied to the HID state inherits whatever
        // the hardware still reports, which can re-poison the flags this just
        // waited out.
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
}
