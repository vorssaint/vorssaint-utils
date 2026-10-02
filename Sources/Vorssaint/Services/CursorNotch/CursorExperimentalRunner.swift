// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Foundation

/// Runs an experimental action only after the guard passes. The missing
/// window-title format aborts before any key is posted.
enum CursorExperimentalRunner {
    static func test(action: CursorExperimentalAction, remote: Bool) -> CursorExperimentalBlock? {
        evaluate(action: action, remote: remote)
    }

    @discardableResult
    static func perform(session: CursorSession, action: CursorExperimentalAction, text: String) -> CursorExperimentalBlock? {
        if let block = evaluate(action: action, remote: session.remote) { return block }
        guard let shortcut = CursorShortcutStore.chord(action, in: storedChords()) else { return .noShortcut }
        if let root = session.root { _ = CursorAppBridge.focus(workspace: root) }
        post(shortcut)
        if action == .sendNow {
            let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return nil }
            TransientPaste.shared.paste(message, didPostShortcut: { postReturn() })
        }
        return nil
    }

    private static func evaluate(action: CursorExperimentalAction, remote: Bool) -> CursorExperimentalBlock? {
        let front = NSWorkspace.shared.frontmostApplication
        let frontIsCursor = CursorSessionReducer.isCursorApp(bundleIdentifier: front?.bundleIdentifier,
                                                             name: front?.localizedName)
        let trusted = AXIsProcessTrusted()
        let match = CursorExperimental.verifiedTitleFormat.isEmpty || !trusted ? (0, false) : windowMatch()
        return CursorExperimental.evaluate(CursorExperimentalCheck(
            trusted: trusted,
            frontIsCursor: frontIsCursor,
            windowCount: match.0,
            shortcutConfigured: CursorShortcutStore.chord(action, in: storedChords()) != nil,
            remote: remote,
            focusedMatches: match.1
        ))
    }

    private static func storedChords() -> String {
        UserDefaults.standard.string(forKey: DefaultsKey.notchCursorShortcuts) ?? ""
    }

    /// Counts titles that contain the verified format. The empty format never asks Accessibility.
    private static func windowMatch() -> (Int, Bool) {
        let format = CursorExperimental.verifiedTitleFormat
        guard !format.isEmpty else { return (0, false) }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: CursorSessionReducer.cursorBundleID)
        guard let app = apps.first(where: { !$0.isTerminated }) else { return (0, false) }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        let focused = focusedTitle(element)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return (0, CursorExperimental.matchCount([focused], format: format) == 1)
        }
        let titles = windows.map { title(of: $0) }
        return (CursorExperimental.matchCount(titles, format: format),
                CursorExperimental.matchCount([focused], format: format) == 1)
    }

    private static func focusedTitle(_ application: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value, CFGetTypeID(window) == AXUIElementGetTypeID() else { return "" }
        return title(of: unsafeBitCast(window, to: AXUIElement.self))
    }

    private static func title(of window: AXUIElement) -> String {
        AXUIElementSetMessagingTimeout(window, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success,
              let title = value as? String else { return "" }
        return title
    }

    private static func post(_ shortcut: GlobalShortcut) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: false)
        else { return }
        let flags = eventFlags(shortcut.modifiers)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postReturn() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false)
        else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func eventFlags(_ modifiers: GlobalShortcutModifiers) -> CGEventFlags {
        var flags = CGEventFlags()
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        return flags
    }
}

enum CursorNotchFeedback {
    static func play(_ kind: CursorNoticeFacts.Kind) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.notchCursorSounds) else { return }
        let name: String
        switch kind {
        case .finished: name = "Glass"
        case .failed: name = "Basso"
        case .stopped, .needsYou: return
        }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// An approval card is waiting. Stopped turns and the needs-you notice stay quiet.
    static func playApproval() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.notchCursorSounds) else { return }
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    static func tap() {
        guard NotchSupport.usesHapticFeedback() else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
