// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Runs the production expansion routine against recorded key events, a
/// stand-in paste and a stand-in reading of the focused field. No key reaches
/// the system, the clipboard is never touched and Accessibility is never asked.
enum TextSnippetExpansionTests {
    static let syntheticMarker: Int64 = 1
    /// Everything the routine does, in order: "ask" when it reads the focused
    /// field's selection, "ask text" with the range when it reads the text
    /// before it, "⌫" for each backspace, typed text as itself, "key N" for
    /// any other key, and the stand-in paste's own steps.
    static var log: [String] = []
    static var focusedSelection: (range: NSRange, textLength: Int)?
    static var textBefore: String?
    static var ownWindowIsKey = false

    final class CGEventSource {
        var userData: Int64 = 0
        init?(stateID: CGEventSourceStateID) {}
    }

    final class CGEvent {
        let keyCode: CGKeyCode
        let keyDown: Bool
        var flags: CGEventFlags = []
        var text = ""
        init?(keyboardEventSource: CGEventSource?, virtualKey: CGKeyCode, keyDown: Bool) {
            keyCode = virtualKey
            self.keyDown = keyDown
        }
        func keyboardSetUnicodeString(stringLength: Int, unicodeString: [UInt16]) {
            text = String(decoding: unicodeString.prefix(stringLength), as: UTF16.self)
        }
        func post(tap: CGEventTapLocation) {
            guard keyDown else { return }
            if !text.isEmpty {
                log.append(text)
            } else {
                log.append(keyCode == CGKeyCode(kVK_Delete) ? "⌫" : "key \(keyCode)")
            }
        }
    }

    enum NSWorkspace {
        static let shared = Workspace()
        struct Workspace { let frontmostApplication: Application? = Application() }
        struct Application { let processIdentifier: pid_t = 42 }
    }

    enum SelectedTextReader {
        struct FocusedTextSelection {
            let range: NSRange
            let textLength: Int
            func text(in range: NSRange) -> String? {
                log.append("ask text \(range.location)..<\(NSMaxRange(range))")
                return textBefore
            }
        }
        static func focusedTextSelection(processID: pid_t, timeout: TimeInterval) -> FocusedTextSelection? {
            log.append("ask")
            return focusedSelection.map { FocusedTextSelection(range: $0.range, textLength: $0.textLength) }
        }
    }

    /// Posts at once what the real paste posts after the modifiers come up.
    final class TransientPaste {
        static let shared = TransientPaste()
        func paste(_ text: String,
                   willPostShortcut: (() -> Void)? = nil,
                   didPostShortcut: (() -> Void)? = nil,
                   didFail: (() -> Void)? = nil) -> Bool {
            log.append("modifiers up")
            willPostShortcut?()
            log.append("paste \(text)")
            didPostShortcut?()
            return true
        }
    }

    static func run(_ suite: TestSuite) {
        func reset() {
            log = []
            focusedSelection = nil
            textBefore = nil
            ownWindowIsKey = false
        }
        defer { reset() }
        let completion = (range: NSRange(location: 6, length: 2), textLength: 8)
        let deletes = { (count: Int) in Array(repeating: "⌫", count: count) }

        reset()
        focusedSelection = completion
        textBefore = "gitgra"
        _ = postExpansion(deleteCount: 6, typedTrigger: "gitgra", text: "StartEnd",
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["ask", "ask text 0..<6"] + deletes(7) + ["StartEnd"],
                     "an inline completion after a typed trigger takes one more backspace (issue #1377)")

        reset()
        _ = postExpansion(deleteCount: 6, typedTrigger: "gitgra", text: "StartEnd",
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["ask"] + deletes(6) + ["StartEnd"],
                     "a field without a completion gets exactly the trigger's backspaces")

        reset()
        focusedSelection = (range: NSRange(location: 6, length: 4), textLength: 31)
        textBefore = "gitgra"
        _ = postExpansion(deleteCount: 6, typedTrigger: "gitgra", text: "StartEnd",
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["ask"] + deletes(6) + ["StartEnd"],
                     "a selection short of the end, like a terminal's scrollback, keeps the trigger's backspaces")

        reset()
        ownWindowIsKey = true
        focusedSelection = completion
        textBefore = "gitgra"
        _ = postExpansion(deleteCount: 6, typedTrigger: "gitgra", text: "StartEnd",
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == deletes(6) + ["StartEnd"],
                     "a key panel of ours, like the island's scratchpad, never asks the app behind it")

        reset()
        focusedSelection = completion
        textBefore = "search"
        _ = postExpansion(deleteCount: 6, typedTrigger: "gitgra", text: "StartEnd",
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["ask", "ask text 0..<6"] + deletes(6) + ["StartEnd"],
                     "a selection after text other than the typed trigger, as behind a launcher, keeps the count")

        reset()
        focusedSelection = completion
        _ = postExpansion(deleteCount: 6, typedTrigger: "gitgra", text: "StartEnd",
                          trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["ask", "ask text 0..<6"] + deletes(6) + ["StartEnd"],
                     "a field that gives only its selection and length, or runs out of time, keeps the count")

        reset()
        focusedSelection = completion
        textBefore = ";test"
        _ = postExpansion(deleteCount: 5, typedTrigger: ";test", text: "test123",
                          trailingKeyCode: CGKeyCode(kVK_Space), trailingFlags: [], trailingText: " ")
        suite.expect(log == ["ask", "ask text 1..<6"] + deletes(6) + ["test123", "key \(kVK_Space)"],
                     "a delimiter-completed trigger clears the completion before typing and the delimiter")

        reset()
        focusedSelection = completion
        textBefore = ";test"
        _ = postExpansion(deleteCount: 5, typedTrigger: ";test", text: "first\nsecond",
                          trailingKeyCode: CGKeyCode(kVK_Space), trailingFlags: [], trailingText: " ")
        suite.expect(log == ["modifiers up", "ask", "ask text 1..<6"] + deletes(6) + ["paste first\nsecond "],
                     "a multi-line snippet asks the field only when its backspaces go out with the paste")

        reset()
        focusedSelection = completion
        _ = postExpansion(deleteCount: 0, typedTrigger: "", text: "StartEnd", trailingKeyCode: nil, trailingFlags: [])
        suite.expect(log == ["StartEnd"],
                     "an insertion with no trigger to clear never asks the field or deletes")
    }
}
