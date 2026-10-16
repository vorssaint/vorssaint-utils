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
        let blockPiece = piece(full, block)
        let contentLength = (blockPiece.content as NSString).length
        // Clamped so a selection that runs into the block's own terminator
        // (fully, since a caller never splits one) is measured against the
        // content alone; the terminator is tracked separately below.
        let startOffset = min(selection.location - block.location, contentLength)
        let endOffset = min(NSMaxRange(selection) - block.location, contentLength)
        let selectedContentLength = endOffset - startOffset
        // Whether the selection reached through the block's own terminator,
        // as opposed to stopping at the end of its content.
        let selectionIncludesTerminator = NSMaxRange(selection) - block.location > contentLength

        switch direction {
        case .up:
            guard block.location > 0 else { return nil }
            let above = full.lineRange(for: NSRange(location: block.location - 1, length: 0))
            let abovePiece = piece(full, above)
            // The block's own terminator moves to the tail so a block that
            // used to end the text still ends it after trading places.
            let swapped = blockPiece.content + abovePiece.terminator + abovePiece.content + blockPiece.terminator
            let newText = full.substring(to: above.location) + swapped + full.substring(from: NSMaxRange(block))
            let newStart = above.location + startOffset
            // The moved content is now followed by what used to separate it
            // from "above", whose length may differ from the block's own
            // terminator (a different line ending, or none at the tail).
            let newTerminatorLength = selectionIncludesTerminator ? (abovePiece.terminator as NSString).length : 0
            let newLength = selectedContentLength + newTerminatorLength
            return (newText, NSRange(location: newStart, length: newLength))

        case .down:
            guard NSMaxRange(block) < full.length else { return nil }
            let below = full.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
            let belowPiece = piece(full, below)
            let swapped = belowPiece.content + blockPiece.terminator + blockPiece.content + belowPiece.terminator
            let newText = full.substring(to: block.location) + swapped + full.substring(from: NSMaxRange(below))
            let newStart = block.location + (belowPiece.content as NSString).length
                + (blockPiece.terminator as NSString).length + startOffset
            // Same remapping as above, but here the moved content trades
            // its terminator for what used to trail "below" it — possibly
            // nothing, if the block now lands at the very end of the text.
            let newTerminatorLength = selectionIncludesTerminator ? (belowPiece.terminator as NSString).length : 0
            let newLength = selectedContentLength + newTerminatorLength
            return (newText, NSRange(location: newStart, length: newLength))
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
