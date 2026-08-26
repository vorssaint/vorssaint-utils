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
    /// `completion` runs on the main queue once ⌘V has been posted — which is
    /// the point at which a trailing keystroke can safely follow the pasted
    /// text instead of racing ahead of it.
    func paste(_ text: String, completion: (() -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.paste(text, completion: completion) }
            return
        }
        // A second expansion while the first is still in flight would photograph
        // the first one's text as "the original" and then restore it over the
        // second. Let the first finish and put its own snapshot back.
        guard !isPerforming else {
            completion?()
            return
        }
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

            DispatchQueue.main.async {
                ClipboardHistoryService.shared.ignoreNextChange(upTo: changeCount)
                self.pendingRestore = (snapshot, changeCount)
                // The user may still be holding the key that completed the
                // trigger. ⌘V posted on top of a held Shift or Option is a
                // different combination and the target app will not treat it as
                // paste, so wait for a clean keyboard first.
                Self.postPasteWhenModifiersReleased(attempt: 0) {
                    self.isPerforming = false
                    completion?()
                    self.scheduleRestore(snapshot: snapshot, changeCount: changeCount)
                }
            }
        }
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
                let restored = pasteboard.changeCount
                DispatchQueue.main.async {
                    ClipboardHistoryService.shared.ignoreNextChange(upTo: restored)
                }
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
                                                       completion: @escaping () -> Void) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if held.isEmpty || attempt >= 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                postPasteShortcut()
                completion()
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            postPasteWhenModifiersReleased(attempt: attempt + 1, completion: completion)
        }
    }

    private static func postPasteShortcut() {
        // No explicit event source: one tied to the HID state inherits whatever
        // the hardware still reports, which can re-poison the flags this just
        // waited out.
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil,
                                      virtualKey: CGKeyCode(kVK_ANSI_V),
                                      keyDown: down) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }
}
