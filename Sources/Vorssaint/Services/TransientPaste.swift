// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Temporarily places plain text on the general pasteboard, pastes it, then
/// restores the previous content if the user did not copy something else.
/// All pasteboard reads share the app's serial lane because promised data can
/// block while its owning process renders it.
final class TransientPaste {
    static let shared = TransientPaste()

    private static let restoreDelay: TimeInterval = 0.5

    private var pendingRestore: (snapshot: [NSPasteboardItem], changeCount: Int)?
    private var restoreWork: DispatchWorkItem?
    private var isPerforming = false

    @discardableResult
    func paste(_ text: String,
               willPostShortcut: (() -> Void)? = nil,
               didPostShortcut: (() -> Void)? = nil,
               didFail: (() -> Void)? = nil) -> Bool {
        guard Thread.isMainThread else { return false }
        guard !isPerforming else { return false }
        isPerforming = true

        let previous = pendingRestore
        restoreWork?.cancel()
        restoreWork = nil

        GeneralPasteboardAccess.shared.async {
            let pasteboard = NSPasteboard.general
            let originalChangeCount = pasteboard.changeCount
            let snapshot: [NSPasteboardItem]?
            if let previous, pasteboard.changeCount == previous.changeCount {
                snapshot = previous.snapshot
            } else {
                snapshot = Self.snapshot(of: pasteboard)
            }
            guard let snapshot else {
                DispatchQueue.main.async {
                    self.isPerforming = false
                    didFail?()
                }
                return
            }
            guard pasteboard.changeCount == originalChangeCount else {
                DispatchQueue.main.async {
                    self.isPerforming = false
                    didFail?()
                }
                return
            }

            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
                DispatchQueue.main.async {
                    self.isPerforming = false
                    didFail?()
                }
                return
            }
            let changeCount = pasteboard.changeCount

            DispatchQueue.main.async {
                ClipboardHistoryService.shared.ignoreNextChange(upTo: changeCount)
                self.pendingRestore = (snapshot, changeCount)
                Self.postPasteWhenModifiersReleased(
                    attempt: 0,
                    willPost: willPostShortcut,
                    didPost: didPostShortcut,
                    didFail: didFail
                ) {
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
                guard pasteboard.changeCount == changeCount else { return }
                pasteboard.clearContents()
                if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
                let restoredCount = pasteboard.changeCount
                DispatchQueue.main.async {
                    ClipboardHistoryService.shared.ignoreNextChange(upTo: restoredCount)
                }
            }
        }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay, execute: work)
    }

    /// Nil means at least one advertised flavor could not be preserved, so the
    /// transient paste fails open instead of clearing incomplete user data.
    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
        guard let items = pasteboard.pasteboardItems else {
            return pasteboard.types?.isEmpty == false ? nil : []
        }
        var snapshot: [NSPasteboardItem] = []
        for item in items {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                copy.setData(data, forType: type)
            }
            snapshot.append(copy)
        }
        return snapshot
    }

    private static func postPasteWhenModifiersReleased(attempt: Int,
                                                       willPost: (() -> Void)?,
                                                       didPost: (() -> Void)?,
                                                       didFail: (() -> Void)?,
                                                       completion: @escaping () -> Void) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if held.isEmpty || attempt >= 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                postPasteShortcut(willPost: willPost) { succeeded in
                    if succeeded {
                        didPost?()
                    } else {
                        didFail?()
                    }
                    completion()
                }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            postPasteWhenModifiersReleased(attempt: attempt + 1,
                                           willPost: willPost,
                                           didPost: didPost,
                                           didFail: didFail,
                                           completion: completion)
        }
    }

    private static func postPasteShortcut(willPost: (() -> Void)?,
                                          completion: @escaping (Bool) -> Void) {
        guard let keyDown = CGEvent(keyboardEventSource: nil,
                                    virtualKey: CGKeyCode(kVK_ANSI_V),
                                    keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil,
                                  virtualKey: CGKeyCode(kVK_ANSI_V),
                                  keyDown: false)
        else {
            completion(false)
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        willPost?()
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            keyUp.post(tap: .cghidEventTap)
            completion(true)
        }
    }
}
