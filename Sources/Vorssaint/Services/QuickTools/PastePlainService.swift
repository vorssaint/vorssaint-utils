// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pastes the clipboard as plain text on a global shortcut: strips fonts,
/// colors and links, pastes, and quietly puts the original rich content back
/// so later normal pastes keep their formatting. Requires Accessibility for
/// the synthesized ⌘V.
final class PastePlainService: ObservableObject {
    static let shared = PastePlainService()

    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 10)

    /// The rich content whose restore is still scheduled, keyed by the change
    /// count of our own plain write. A second shortcut press inside that
    /// window must reuse this snapshot — the pasteboard currently holds the
    /// stripped text, and re-snapshotting it would lose the original for good.
    private var pendingRestore: (snapshot: [NSPasteboardItem], plainChangeCount: Int)?
    private var restoreWork: DispatchWorkItem?
    /// A press is being carried out (possibly waiting for the user to release
    /// the shortcut's modifier keys). Presses landing meanwhile are dropped:
    /// the pasteboard already holds the plain text they would produce.
    private var isPerforming = false
    /// The permission prompt fires at most once per launch, so a shortcut
    /// mashed without Accessibility nags once instead of five times.
    private var promptedForAccessibility = false

    private init() {
        hotkey.onPress = { [weak self] in self?.performPastePlain() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.pastePlain.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.pastePlainEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.pastePlainShortcut,
                                            fallback: .pastePlainDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
    }

    func suspend() {
        hotkey.unregister()
    }

    func performPastePlain() {
        // Without Accessibility the synthesized ⌘V can never be posted: say so
        // (system prompt once, a beep after) instead of silently swallowing the
        // shortcut, which reads as "the feature does nothing" (issue #186).
        guard AXIsProcessTrusted() else {
            if promptedForAccessibility {
                NSSound.beep()
            } else {
                promptedForAccessibility = true
                Permissions.shared.requestAccessibility()
            }
            return
        }
        guard !isPerforming else { return }
        let pasteboard = NSPasteboard.general
        guard let plain = Self.plainText(from: pasteboard), !plain.isEmpty else { return }

        // An app that ships its own matching-style paste does this better
        // than any synthesized ⌘V: the destination decides the typing
        // attributes (a stripped string pasted normally can leave the
        // insertion point stuck with the styling of what it landed in,
        // issue #349), the pasteboard keeps the original formatting for
        // later pastes, and held modifier keys don't matter to a menu
        // press. The strip-and-restore dance below stays as the fallback
        // for every app without that command.
        if pressNativeMatchStyleItem() { return }

        // Deep-copy the current content first: items can't be re-attached to
        // the pasteboard once it is cleared. If the pasteboard still holds our
        // own plain write from a press moments ago, keep that press's rich
        // snapshot instead of photographing the stripped text.
        let snapshot: [NSPasteboardItem]
        if let pending = pendingRestore, pasteboard.changeCount == pending.plainChangeCount {
            snapshot = pending.snapshot
        } else {
            snapshot = Self.snapshot(of: pasteboard)
        }
        restoreWork?.cancel()
        restoreWork = nil

        pasteboard.clearContents()
        pasteboard.setString(plain, forType: .string)
        let plainChangeCount = pasteboard.changeCount
        ClipboardHistoryService.shared.ignoreNextChange(upTo: plainChangeCount)
        pendingRestore = (snapshot, plainChangeCount)

        // The user is still holding the shortcut's modifier keys at this
        // point. Posting ⌘V now would merge with those held keys into a
        // combination the target app does not treat as paste (and with the
        // default ⌥⇧⌘V it can even re-trigger this very hotkey), so nothing
        // would happen (issue #186). Wait for a clean keyboard first.
        isPerforming = true
        postPasteWhenModifiersReleased(attempt: 0) { [weak self] in
            guard let self else { return }
            self.isPerforming = false
            // Put the rich original back once the paste went through, unless
            // the user copied something new in the meantime.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.restoreWork = nil
                self.pendingRestore = nil
                guard pasteboard.changeCount == plainChangeCount, !snapshot.isEmpty else { return }
                pasteboard.clearContents()
                pasteboard.writeObjects(snapshot)
                ClipboardHistoryService.shared.ignoreNextChange(upTo: pasteboard.changeCount)
            }
            self.restoreWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    /// Posts ⌘V once no modifier key is physically down, checking every 15 ms
    /// for up to ~1.5 s. Someone who keeps the chord pressed longer than that
    /// gets the paste anyway; by then the merge race is long over for most
    /// hands, and never pasting would be worse. The extra beat after the keys
    /// read clean matters: posted right on the release, the target app can
    /// still see the stale modifier state and refuse the key equivalent.
    private func postPasteWhenModifiersReleased(attempt: Int, completion: @escaping () -> Void) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if held.isEmpty || attempt >= 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                let shortcut = GlobalShortcut.saved(for: DefaultsKey.pastePlainShortcut,
                                                    fallback: .pastePlainDefault)
                let mustReleaseHotkey = shortcut.isStandardPasteCommand
                if mustReleaseHotkey {
                    // Otherwise our global ⌘V catches the synthetic ⌘V below,
                    // so the target app never receives a paste command.
                    self.hotkey.unregister()
                }
                Self.postPasteShortcut {
                    if mustReleaseHotkey {
                        self.syncWithPreferences()
                    }
                    completion()
                }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            self?.postPasteWhenModifiersReleased(attempt: attempt + 1, completion: completion)
        }
    }

    /// Presses the frontmost app's own matching-style paste when its menus
    /// carry the universal ⌥⇧⌘V equivalent. Found by key equivalent, never by
    /// localized title, same as the mouse navigation menu press. Returns
    /// false when the app has no such command (or refuses the press) so the
    /// caller falls back to the synthesized paste.
    /// Bundles known to carry no ⌥⇧⌘V menu item, so their menu bar is not
    /// re-walked on every single press. An app gets another chance after a
    /// relaunch (the pid changes) — menus rarely grow the item mid-run, and
    /// the synthesized fallback covers it if they do.
    private var noMatchStyleItem: [pid_t: Bool] = [:]

    private func pressNativeMatchStyleItem() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = app.processIdentifier
        if noMatchStyleItem[pid] == true { return false }
        let application = AXUIElementCreateApplication(pid)
        // A busy target must not hold the main thread for AX's default
        // multi-second timeout; every traversed element gets the same bound.
        AXUIElementSetMessagingTimeout(application, 0.35)
        guard let menuBar: AXUIElement = Self.attribute(kAXMenuBarAttribute, from: application) else {
            return false
        }
        var visited = 0
        guard let item = Self.findMatchStyleItem(in: menuBar, depth: 0, visited: &visited) else {
            noMatchStyleItem[pid] = true
            if noMatchStyleItem.count > 64 { noMatchStyleItem.removeAll() }
            return false
        }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// Depth 3 is a direct item of a top level menu (bar, bar item, menu,
    /// item), where every app keeps its paste commands; anything deeper is
    /// out of reach on purpose, and the visited cap keeps a pathological
    /// menu bar from stalling the press.
    private static func findMatchStyleItem(in element: AXUIElement,
                                           depth: Int,
                                           visited: inout Int) -> AXUIElement? {
        guard depth <= 3, visited < 600 else { return nil }
        visited += 1
        AXUIElementSetMessagingTimeout(element, 0.35)

        let command: String? = attribute(kAXMenuItemCmdCharAttribute, from: element)
        let modifiers: NSNumber? = attribute(kAXMenuItemCmdModifiersAttribute, from: element)
        let enabled: NSNumber? = attribute(kAXEnabledAttribute, from: element)
        if QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: command,
                                                    modifierMask: modifiers?.uint32Value,
                                                    isEnabled: enabled?.boolValue != false) {
            return element
        }

        guard depth < 3 else { return nil }
        let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) ?? []
        for child in children {
            if let match = findMatchStyleItem(in: child, depth: depth + 1, visited: &visited) {
                return match
            }
        }
        return nil
    }

    private static func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    /// The clipboard's text without any formatting: the plain string when
    /// present, else the text of its RTF or HTML content.
    static func plainText(from pasteboard: NSPasteboard) -> String? {
        if let plain = pasteboard.string(forType: .string) {
            return plain
        }
        if let rtf = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return attributed.string
        }
        if let html = pasteboard.data(forType: .html),
           let attributed = NSAttributedString(html: html, documentAttributes: nil) {
            return attributed.string
        }
        return nil
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
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

    private static func postPasteShortcut(completion: @escaping () -> Void) {
        // No explicit event source: an event tied to the HID state inherits
        // whatever the hardware still reports, and right after the shortcut's
        // own keys that can re-poison the flags this method just waited out.
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
