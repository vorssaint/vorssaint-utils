// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Pastes the clipboard as plain text on a global shortcut: strips fonts,
/// colors and links, pastes, and quietly puts the original rich content back
/// so later normal pastes keep their formatting. Requires Accessibility for
/// the synthesized ⌘V.
final class PastePlainService: ObservableObject {
    static let shared = PastePlainService()

    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 10)

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

        var releaseHotkey = false
        _ = TransientPaste.shared.paste(
            plain,
            willPostShortcut: { [weak self] in
                guard let self else { return }
                let shortcut = GlobalShortcut.saved(for: DefaultsKey.pastePlainShortcut,
                                                    fallback: .pastePlainDefault)
                releaseHotkey = shortcut.isStandardPasteCommand
                if releaseHotkey { self.hotkey.unregister() }
            },
            didPostShortcut: { [weak self] in
                if releaseHotkey { self?.syncWithPreferences() }
            }
        )
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
}
