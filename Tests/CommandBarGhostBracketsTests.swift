// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Run with CommandBarGhostBrackets.swift, independently of the application.
@main
struct CommandBarGhostBracketsTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 40),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        editor.font = .systemFont(ofSize: 16)
        editor.string = "2*(3+4"
        window.contentView?.addSubview(editor)
        assert(window.makeFirstResponder(editor))
        let ghost = CommandBarGhostBrackets.GhostView(frame: editor.frame)
        ghost.query = editor.string
        window.contentView?.addSubview(ghost)
        editor.layoutManager?.ensureLayout(for: editor.textContainer!)

        func pixels() -> Data {
            let bitmap = ghost.bitmapImageRepForCachingDisplay(in: ghost.bounds)!
            ghost.cacheDisplay(in: ghost.bounds, to: bitmap)
            return bitmap.representation(using: .png, properties: [:])!
        }

        let withoutGhost = pixels()
        ghost.suffix = ")"
        let withGhost = pixels()
        assert(withGhost != withoutGhost, "inferred brackets draw at the native text position")
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        assert(pixels() == withGhost, "ghost brackets stay at the end when the caret moves")
        assert(editor.string == "2*(3+4", "ghost brackets never enter the editable text")
        assert(ghost.hitTest(.zero) == nil, "the overlay does not intercept editing")
        ghost.query = "another field"
        assert(pixels() == withoutGhost, "another editor's text must not get calculator hints")
        editor.setMarkedText(
            "あ", selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: 1, length: 0))
        ghost.query = editor.string
        assert(editor.hasMarkedText() && pixels() == withoutGhost, "composition suppresses ghost text")
        editor.unmarkText()
        editor.string = "2*(3+4="
        ghost.query = editor.string
        assert(pixels() == withoutGhost, "a trailing equals sign is never covered by ghost text")
        print("Command bar ghost bracket checks passed")
    }
}
