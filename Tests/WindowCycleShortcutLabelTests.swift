// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

/// Issue #4325: captions name the window-cycling shortcut as the US ⌘`, which
/// is not the key printed on a German keyboard.
enum WindowCycleShortcutLabelTests {
static func run(_ suite: TestSuite) {
    func layout(_ id: String) -> Data? {
        let sources = (TISCreateInputSourceList(
            [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary, true)?
            .takeRetainedValue() as? [TISInputSource]) ?? []
        guard let source = sources.first(where: {
            guard let pointer = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
            return (Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String) == id
        }), let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }
    defer { GlobalShortcut.refreshLayoutLabels() }

    let sentence = "Click the Dock icon to rotate through windows, like ⌘`."
    if let us = layout("com.apple.keylayout.US") {
        GlobalShortcut.refreshLayoutLabels(layoutData: us)
        suite.expect(GlobalShortcut.windowCycleKeyLabel() == "`",
                     "a US keyboard keeps the backtick on the window-cycling key")
        suite.expect(GlobalShortcut.localizingWindowCycleKey(in: sentence) == sentence,
                     "captions are unchanged on a US keyboard")
    } else {
        suite.expect(false, "keyboard fixture unavailable: US")
    }

    if let german = layout("com.apple.keylayout.German") {
        GlobalShortcut.refreshLayoutLabels(layoutData: german)
        let label = GlobalShortcut.windowCycleKeyLabel()
        let localized = GlobalShortcut.localizingWindowCycleKey(in: sentence)
        suite.expect(label != "`", "a German keyboard does not print a backtick on the window-cycling key")
        suite.expect(localized == "Click the Dock icon to rotate through windows, like ⌘\(label)."
                     && !localized.contains("⌘`"),
                     "captions name the key a German keyboard prints")
    } else {
        suite.expect(false, "keyboard fixture unavailable: German")
    }

    GlobalShortcut.refreshLayoutLabels(layoutData: nil)
    suite.expect(GlobalShortcut.windowCycleKeyLabel() == "`",
                 "captions fall back to the backtick without a keyboard layout")

    let unrelated = "Replace macOS ⌘Tab and the app switcher."
    suite.expect(GlobalShortcut.localizingWindowCycleKey(in: unrelated) == unrelated,
                 "text without the window-cycling shortcut is left alone")
}
}
