// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.
//
//  Synthesizes keystrokes via CGEvent, posted at the HID tap so they reach the lock screen's secure text field.

import Foundation
import ApplicationServices
import CoreGraphics

enum KeystrokeError: LocalizedError {
    case accessibilityNotGranted
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permission required. Open System Settings → Privacy & Security → Accessibility and enable Vorssaint."
        case .eventCreationFailed:
            return "Couldn't create CGEvent for keystroke."
        }
    }
}

enum KeystrokeInjector {
    /// Returns true if the app has Accessibility permission (no prompt).
    nonisolated static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Triggers the system prompt to grant Accessibility (deep links to System Settings).
    @discardableResult
    nonisolated static func promptForAccessibility() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Types the UTF-8 bytes into whatever has keyboard focus, then presses Return. Takes `Data` rather than `String` so the
    /// caller can hold the plaintext as a zero-able buffer; the brief internal `String` decode is scoped to this call. Blocking.
    nonisolated static func typeAndReturn(_ passwordBytes: Data) throws {
        guard isAccessibilityTrusted() else {
            throw KeystrokeError.accessibilityNotGranted
        }
        guard let text = String(data: passwordBytes, encoding: .utf8) else {
            throw KeystrokeError.eventCreationFailed
        }
        let source = CGEventSource(stateID: .hidSystemState)
        try clearFocusedField(source: source)
        try postUnicodeText(text, source: source)
        try postReturn(source: source)
    }

    /// Wipes anything already typed into the focused field (e.g. a stray keypress
    /// on the lock screen) so it isn't prepended to the password: ⌘→ to the end,
    /// then ⌘⌫ to delete back to the start. Both are positional keys, so this
    /// behaves the same on every keyboard layout — unlike ⌘A, whose "A" moves.
    private nonisolated static func clearFocusedField(source: CGEventSource?) throws {
        let rightArrow: CGKeyCode = 0x7C
        let delete: CGKeyCode = 0x33
        try postKey(rightArrow, flags: .maskCommand, source: source)
        try postKey(delete, flags: .maskCommand, source: source)
    }

    /// Posts a virtual key down/up, wrapped in a real ⌘ down/up when `flags`
    /// includes `.maskCommand` — some text fields ignore a bare flag without it.
    private nonisolated static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = [], source: CGEventSource?) throws {
        let command: CGKeyCode = 0x37
        let usesCommand = flags.contains(.maskCommand)
        if usesCommand {
            guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: true) else {
                throw KeystrokeError.eventCreationFailed
            }
            commandDown.flags = .maskCommand
            commandDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.012)
        }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw KeystrokeError.eventCreationFailed
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
        keyUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
        if usesCommand {
            guard let commandUp = CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: false) else {
                throw KeystrokeError.eventCreationFailed
            }
            commandUp.flags = []
            commandUp.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.012)
        }
    }

    /// Quartz reliably delivers only a small Unicode payload per keyboard event.
    /// Batching at this conservative limit avoids the undocumented truncation seen
    /// with longer payloads, while replacing one down/up pair per character with
    /// one pair per batch.
    nonisolated private static let maximumUnicodeBatchLength = 20
    nonisolated private static let unicodeEventInterval: TimeInterval = 0.004

    /// Posts the password in small UTF-16 batches. Splitting occurs only between
    /// surrogate pairs, so non-BMP password characters are never corrupted.
    private nonisolated static func postUnicodeText(_ text: String, source: CGEventSource?) throws {
        let utf16 = Array(text.utf16)
        try utf16.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var start = 0

            while start < buffer.count {
                var end = min(start + maximumUnicodeBatchLength, buffer.count)
                // Do not split a high/low-surrogate pair across separate key events.
                if end < buffer.count,
                   (0xD800...0xDBFF).contains(buffer[end - 1]) {
                    end -= 1
                }
                try postUnicode(
                    base.advanced(by: start),
                    length: end - start,
                    source: source
                )
                start = end
            }
        }
    }

    /// Unicode injection bypasses keyboard-layout issues. The password is placed
    /// on a key-down event as a text batch; the matching key-up maintains normal
    /// secure-field event semantics.
    private nonisolated static func postUnicode(
        _ unicode: UnsafePointer<UInt16>,
        length: Int,
        source: CGEventSource?
    ) throws {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw KeystrokeError.eventCreationFailed
        }
        keyDown.keyboardSetUnicodeString(stringLength: length, unicodeString: unicode)
        keyUp.keyboardSetUnicodeString(stringLength: length, unicodeString: unicode)
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: unicodeEventInterval)
        keyUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: unicodeEventInterval)
    }

    /// Physical Return key (virtual key 0x24).
    private nonisolated static func postReturn(source: CGEventSource?) throws {
        let returnKey: CGKeyCode = 0x24
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false) else {
            throw KeystrokeError.eventCreationFailed
        }
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
        keyUp.post(tap: .cghidEventTap)
    }
}
