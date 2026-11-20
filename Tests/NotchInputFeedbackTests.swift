// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchInputFeedbackTests {
    static func run(_ suite: TestSuite) {
        modifierHoldTracker(suite)
        modifierIndicator(suite)
        pasteDetector(suite)
    }

    private static func modifierHoldTracker(_ suite: TestSuite) {
        var tracker = NotchModifierHoldTracker()
        suite.expect(tracker.update(capsLock: true, shiftDown: false, otherModifiersDown: false, at: 1.0) == .capsLock,
                     "Caps Lock ON reports immediately")
        suite.expect(tracker.update(capsLock: false, shiftDown: false, otherModifiersDown: false, at: 1.1) == nil,
                     "Caps Lock OFF clears indicator immediately")

        suite.expect(tracker.update(capsLock: false, shiftDown: true, otherModifiersDown: false, at: 2.0) == nil,
                     "initial Shift press waits for hold debounce threshold")
        suite.expect(tracker.tick(at: 2.15) == nil,
                     "Shift held under 220ms does not trigger indicator")
        suite.expect(tracker.tick(at: 2.23) == .shift,
                     "Shift held at least 220ms activates Shift indicator")

        suite.expect(tracker.update(capsLock: true, shiftDown: true, otherModifiersDown: false, at: 2.5) == .both,
                     "Caps Lock ON + held Shift reports combined indicator")
        suite.expect(tracker.update(capsLock: true, shiftDown: true, otherModifiersDown: true, at: 2.6) == .capsLock,
                     "Cmd/Ctrl/Opt cancels Shift hold while keeping Caps Lock indicator")
    }

    private static func modifierIndicator(_ suite: TestSuite) {
        let strings = NotchInputFeedbackStrings.localized(.enUS)
        suite.expect(NotchModifierIndicator.capsLock.wings.leading == NotchModifierIndicator.capsLock.wings.trailing
                        && NotchModifierIndicator.shift.wings.leading == NotchModifierIndicator.shift.wings.trailing
                        && NotchModifierIndicator.both.wings.leading == NotchModifierIndicator.both.wings.trailing,
                     "modifier wings stay symmetric around camera housing")
        suite.expect(NotchModifierIndicator.capsLock.label(strings) == "CAPS"
                        && NotchModifierIndicator.shift.label(strings) == "SHIFT"
                        && NotchModifierIndicator.both.label(strings) == "CAPS · ⇧",
                     "modifier indicator labels map cleanly per state")
    }

    private static func pasteDetector(_ suite: TestSuite) {
        suite.expect(NotchPasteDetector.isPasteKey(keyCode: 9, charactersIgnoringModifiers: "v", command: true, control: false)
                        && !NotchPasteDetector.isPasteKey(keyCode: 9, charactersIgnoringModifiers: "v", command: false, control: false)
                        && !NotchPasteDetector.isPasteKey(keyCode: 9, charactersIgnoringModifiers: "v", command: true, control: true)
                        && !NotchPasteDetector.isPasteKey(keyCode: 8, charactersIgnoringModifiers: "c", command: true, control: false),
                     "paste key detection matches Command-V without Control")

        var detector = NotchPasteDetector()
        suite.expect(detector.recordPaste(at: 10.0)
                        && !detector.recordPaste(at: 10.12)
                        && detector.recordPaste(at: 10.26),
                     "paste burst detector debounces duplicates inside 250ms window")
    }
}
