// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Swaps the line under the caret (or every line a selection touches) with
/// the line just above or below it, the way Option-Up/Down works in most
/// code editors. Pure text math so it can be driven from a plain NSRange
/// without touching NSTextView, and tested without one.
enum PlainTextLineMover {
    enum Direction {
        case up
        case down
    }

    /// Nil when there is no adjacent line to swap with (the block already
    /// touches the start or end of the text).
    static func moving(_ direction: Direction,
                       in text: String,
                       selection: NSRange) -> (text: String, selection: NSRange)? {
        let full = text as NSString
        guard selection.location != NSNotFound, NSMaxRange(selection) <= full.length else { return nil }
        let block = full.lineRange(for: selection)
        let offsetInBlock = selection.location - block.location

        switch direction {
        case .up:
            guard block.location > 0 else { return nil }
            let above = full.lineRange(for: NSRange(location: block.location - 1, length: 0))
            let blockPiece = piece(full, block)
            let abovePiece = piece(full, above)
            // The block's own terminator moves to the tail so a block that
            // used to end the text still ends it after trading places.
            let swapped = blockPiece.content + abovePiece.terminator + abovePiece.content + blockPiece.terminator
            let newText = full.substring(to: above.location) + swapped + full.substring(from: NSMaxRange(block))
            let newStart = above.location + offsetInBlock
            return (newText, NSRange(location: newStart, length: selection.length))

        case .down:
            guard NSMaxRange(block) < full.length else { return nil }
            let below = full.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
            let blockPiece = piece(full, block)
            let belowPiece = piece(full, below)
            let swapped = belowPiece.content + blockPiece.terminator + blockPiece.content + belowPiece.terminator
            let newText = full.substring(to: block.location) + swapped + full.substring(from: NSMaxRange(below))
            let newStart = block.location + (belowPiece.content as NSString).length
                + (blockPiece.terminator as NSString).length + offsetInBlock
            return (newText, NSRange(location: newStart, length: selection.length))
        }
    }

    /// Splits a line range into its content and trailing terminator (empty
    /// only for a last line that ends the text without one), so a swap can
    /// relocate a line without gaining or losing its line break.
    private static func piece(_ full: NSString, _ range: NSRange) -> (content: String, terminator: String) {
        var end = 0
        var contentsEnd = 0
        full.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: range)
        let content = full.substring(with: NSRange(location: range.location, length: contentsEnd - range.location))
        let terminator = full.substring(with: NSRange(location: contentsEnd, length: end - contentsEnd))
        return (content, terminator)
    }
}
