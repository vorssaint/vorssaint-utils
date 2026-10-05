// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure text math: the moved text and the selection that follows it, in
/// UTF-16 units like NSTextView reports them.
enum PlainTextLineMoverTests {
    static func run(_ suite: TestSuite) {
        typealias Move = PlainTextLineMover.Direction

        func check(_ label: String, _ direction: Move, _ text: String, _ selection: NSRange,
                   text expectedText: String, selection expectedSelection: NSRange,
                   file: StaticString = #filePath, line: UInt = #line) {
            guard let moved = PlainTextLineMover.moving(direction, in: text, selection: selection) else {
                suite.expect(false, "\(label): moves", file: file, line: line)
                return
            }
            suite.expect(moved.text == expectedText, "\(label): text is \(moved.text.debugDescription)",
                         file: file, line: line)
            suite.expect(moved.selection == expectedSelection,
                         "\(label): selection is \(moved.selection), expected \(expectedSelection)",
                         file: file, line: line)
            suite.expect(NSMaxRange(moved.selection) <= (moved.text as NSString).length,
                         "\(label): selection stays inside the text", file: file, line: line)
        }

        // Whole-line selections (terminator included) landing on, or leaving,
        // an unterminated last line must not reach past the end of the text.
        check("whole line down onto an unterminated last line", .down, "a\nb\nc", NSRange(location: 2, length: 2),
              text: "a\nc\nb", selection: NSRange(location: 4, length: 1))
        check("whole multi-line block down onto an unterminated last line", .down, "a\nb\nc",
              NSRange(location: 0, length: 4),
              text: "c\na\nb", selection: NSRange(location: 2, length: 3))
        check("unterminated last line up", .up, "a\nb\nc", NSRange(location: 4, length: 1),
              text: "a\nc\nb", selection: NSRange(location: 2, length: 1))
        check("whole line up keeps its terminator", .up, "a\nb\nc", NSRange(location: 2, length: 2),
              text: "b\na\nc", selection: NSRange(location: 0, length: 2))
        check("caret at the end of an unterminated last line", .up, "a\nb", NSRange(location: 3, length: 0),
              text: "b\na", selection: NSRange(location: 1, length: 0))

        // The selected terminator is the one now trailing the moved content,
        // so its length follows the neighbouring line's ending.
        check("whole line up past a CRLF line", .up, "a\r\nb\nc", NSRange(location: 3, length: 2),
              text: "b\r\na\nc", selection: NSRange(location: 0, length: 3))
        check("whole line down past a CRLF line", .down, "a\nb\r\nc", NSRange(location: 0, length: 2),
              text: "b\na\r\nc", selection: NSRange(location: 2, length: 3))
        check("CRLF line down onto an LF line", .down, "a\r\nb\nc", NSRange(location: 0, length: 3),
              text: "b\r\na\nc", selection: NSRange(location: 3, length: 2))
        check("content-only selection ignores the ending change", .down, "a\nb\r\nc", NSRange(location: 0, length: 1),
              text: "b\na\r\nc", selection: NSRange(location: 2, length: 1))
        check("CR-only endings", .down, "a\rb\rc", NSRange(location: 0, length: 2),
              text: "b\ra\rc", selection: NSRange(location: 2, length: 2))

        // Surrogate pairs count as two units, before and after the swap.
        check("whole emoji line down", .down, "😀a\n🎉\nz", NSRange(location: 0, length: 4),
              text: "🎉\n😀a\nz", selection: NSRange(location: 3, length: 4))
        check("partial selection after an emoji", .down, "😀a\n🎉\nz", NSRange(location: 2, length: 1),
              text: "🎉\n😀a\nz", selection: NSRange(location: 5, length: 1))
        check("whole emoji line down onto an unterminated last line", .down, "😀\nb", NSRange(location: 0, length: 3),
              text: "b\n😀", selection: NSRange(location: 2, length: 2))
        check("emoji last line up", .up, "x\n😀", NSRange(location: 2, length: 2),
              text: "😀\nx", selection: NSRange(location: 0, length: 2))
        check("emoji line up past a CRLF line", .up, "x\r\n🎉\nz", NSRange(location: 3, length: 3),
              text: "🎉\r\nx\nz", selection: NSRange(location: 0, length: 4))

        let there = PlainTextLineMover.moving(.down, in: "a\nb\nc", selection: NSRange(location: 2, length: 2))
        let back = there.flatMap { PlainTextLineMover.moving(.up, in: $0.text, selection: $0.selection) }
        suite.expect(back?.text == "a\nb\nc", "moving down then up restores the text")

        suite.expect(PlainTextLineMover.moving(.up, in: "a\nb", selection: NSRange(location: 0, length: 1)) == nil,
                     "the first line cannot move up")
        suite.expect(PlainTextLineMover.moving(.down, in: "a\nb", selection: NSRange(location: 2, length: 1)) == nil,
                     "the last line cannot move down")
        suite.expect(PlainTextLineMover.moving(.down, in: "a", selection: NSRange(location: 0, length: 5)) == nil,
                     "a selection past the end is rejected")
    }
}
