// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Exercise the production formatter and field delegate without showing a
/// window, posting a key, or changing application preferences.
enum NotchTimerInputTests {
    static func run(_ suite: TestSuite) {
        for maximum in [23, 59, 180] {
            let formatter = NotchTimerNumberFormatter(range: 0...maximum)
            for input in ["", "0", "9", "١٢", "１２", String(maximum)] {
                suite.expect(formatter.isPartialStringValid(input, newEditingString: nil, errorDescription: nil),
                             "the native number field accepts decimal digits and an empty editing draft: \(input)")
            }
            for input in ["abc", "12a", "-1", "+1", "1.5", "1:30", " 5", "5\n", "⑨", "²", "½", "Ⅸ",
                          "999999999999999999999", String(maximum + 1)] {
                suite.expect(!formatter.isPartialStringValid(input, newEditingString: nil, errorDescription: nil),
                             "invalid keys and pasted values are rejected before changing the native field: \(input)")
            }
        }

        var value = 12
        let field = NotchTimerNumberNativeField()
        let input = NotchTimerNumberField(value: Binding(get: { value }, set: { value = $0 }),
                                         range: 0...59, label: "Seconds")
        let delegate = input.makeCoordinator()
        let editor = NSTextView()
        delegate.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: field))
        field.stringValue = "٣٧"
        delegate.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        suite.expect(value == 37, "native editing updates the bound duration before Start can be clicked")
        _ = delegate.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        suite.expect(value == 12, "Escape restores the selected component's original value")
        field.stringValue = "9"
        delegate.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        delegate.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        suite.expect(field.stringValue == "09", "ending an edit normalizes a one-digit component")
        value = 59
        _ = delegate.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:)))
        suite.expect(value == 59, "arrow adjustment cannot exceed a component's maximum")
        value = 0
        _ = delegate.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
        suite.expect(value == 0, "arrow adjustment cannot underflow a component")

        let focusFormatter = NotchTimerNumberFormatter(range: NotchPomodoroConfiguration.focusRange)
        suite.expect(!focusFormatter.isPartialStringValid("0", newEditingString: nil, errorDescription: nil)
                  && focusFormatter.isPartialStringValid("", newEditingString: nil, errorDescription: nil),
                     "Pomodoro rejects zero but permits clearing an unfinished draft")
        var focus = 25
        let focusInput = NotchTimerNumberField(value: Binding(get: { focus }, set: { focus = $0 }),
                                               range: NotchPomodoroConfiguration.focusRange, label: "Focus")
        let focusDelegate = focusInput.makeCoordinator()
        field.stringValue = ""
        focusDelegate.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        focusDelegate.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        suite.expect(focus == 25 && field.stringValue == "25",
                     "clearing focus and leaving the field preserves the previous duration")
        focus = 1
        _ = focusDelegate.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
        suite.expect(focus == 1, "Pomodoro arrow adjustment respects its one-minute minimum")

        for seconds in [Int.min, 0, 1, 59, 60, 86_399, Int.max] {
            var session = NotchTimerSession()
            session.start(mode: .timer, seconds: seconds, now: 100)
            let expected = min(86_399, max(1, seconds))
            suite.expect(session.duration == Double(expected), "session input clamps safely at second precision")
            suite.expect(!session.finishIfDue(at: 100 + Double(expected) - 0.001),
                         "a precise timer never completes before its last millisecond")
            suite.expect(session.finishIfDue(at: 100 + Double(expected)),
                         "a precise timer completes at its exact deadline")
        }
    }
}
