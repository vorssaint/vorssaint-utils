// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The formatting toolbar writes Markdown into the plain text the pad already
/// stores, so what it produces has to read back the way a typist would have
/// written it, and a second click on the same mark has to take it off again.
enum ScratchpadMarkTests {
    private static func applying(_ mark: ScratchpadMark,
                                 to text: String,
                                 _ selection: NSRange) -> (text: String, selection: NSRange) {
        let edit = ScratchpadSupport.edit(applying: mark, to: text, selection: selection)
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (result, edit.selection)
    }

    /// Clicks a mark repeatedly, each time from the selection the click before
    /// it left behind, which is what a person actually does. The bug this
    /// guards against passed every single-step check: it only showed up on the
    /// second click, because the first click's own selection was what confused
    /// it.
    private static func clicking(_ mark: ScratchpadMark,
                                 _ times: Int,
                                 from text: String,
                                 _ selection: NSRange) -> String {
        var current = text
        var range = selection
        for _ in 0..<times {
            let edit = ScratchpadSupport.edit(applying: mark, to: current, selection: range)
            current = (current as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
            range = edit.selection
        }
        return current
    }

    static func run(_ expect: (Bool, String) -> Void) {
        // Two clicks put the text back where it started. Heading is the one
        // exception by design, since it walks its levels on the way out.
        for mark in [ScratchpadMark.bold, .italic, .strikethrough, .code, .link,
                     .bullet, .quote, .numbered] {
            let round = clicking(mark, 2, from: "note", NSRange(location: 0, length: 4))
            expect(round == "note", "\(mark.rawValue) twice leaves the text alone, got \(round)")
        }
        let headingCycle = clicking(.heading, 4, from: "note", NSRange(location: 0, length: 4))
        expect(headingCycle == "note", "heading comes back off after its levels, got \(headingCycle)")

        // The reported case: an italic word inside bold grew a star on every
        // click instead of toggling.
        let insideBold = clicking(.italic, 2, from: "**note**", NSRange(location: 2, length: 4))
        expect(insideBold == "**note**",
               "italic inside bold toggles without touching the bold, got \(insideBold)")
        let fourClicks = clicking(.italic, 4, from: "**note**", NSRange(location: 2, length: 4))
        expect(fourClicks == "**note**", "and keeps toggling, got \(fourClicks)")
        let boldInsideItalic = clicking(.bold, 2, from: "*note*", NSRange(location: 1, length: 4))
        expect(boldInsideItalic == "*note*",
               "and the same the other way round, got \(boldInsideItalic)")


        let wrapped = applying(.bold, to: "note", NSRange(location: 0, length: 4))
        expect(wrapped.text == "**note**", "bold wraps the selection, got \(wrapped.text)")
        expect(wrapped.selection == NSRange(location: 2, length: 4),
               "the words stay selected, not the markers, got \(wrapped.selection)")

        // The selection the first click leaves behind is what the second one
        // reads, so the pair has to be found from outside the selection.
        let unwrapped = applying(.bold, to: "**note**", NSRange(location: 2, length: 4))
        expect(unwrapped.text == "note", "a second click takes bold off, got \(unwrapped.text)")

        let spanned = applying(.strikethrough, to: "~~gone~~", NSRange(location: 0, length: 8))
        expect(spanned.text == "gone", "markers inside the selection come off, got \(spanned.text)")

        let caret = applying(.bold, to: "", NSRange(location: 0, length: 0))
        expect(caret.text == "****" && caret.selection.location == 2,
               "with no selection the caret lands between the markers, got \(caret.text)")

        // Italic's marker is also half of bold's, and a single character cannot
        // tell the two apart: what does is whether the run of stars is odd.
        let nested = applying(.italic, to: "**note**", NSRange(location: 2, length: 4))
        expect(nested.text == "***note***", "italic nests inside bold, got \(nested.text)")
        let unnested = applying(.italic, to: "***note***", NSRange(location: 3, length: 4))
        expect(unnested.text == "**note**",
               "and comes back off leaving bold alone, got \(unnested.text)")
        let wholeNested = applying(.italic, to: "***note***", NSRange(location: 0, length: 10))
        expect(wholeNested.text == "**note**",
               "from the whole span too, got \(wholeNested.text)")
        let plainItalic = applying(.italic, to: "note", NSRange(location: 0, length: 4))
        expect(plainItalic.text == "*note*", "italic alone still wraps, got \(plainItalic.text)")
        let offAgain = applying(.italic, to: "*note*", NSRange(location: 1, length: 4))
        expect(offAgain.text == "note", "and comes off, got \(offAgain.text)")
        // Bold over an italic word keeps the italic star it is wrapped around.
        let boldOverItalic = applying(.bold, to: "*note*", NSRange(location: 0, length: 6))
        expect(boldOverItalic.text == "***note***",
               "bold wraps an italic word, got \(boldOverItalic.text)")

        let firstHeading = applying(.heading, to: "", NSRange(location: 0, length: 0))
        expect(firstHeading.text == "# ", "an empty pad still takes a heading, got \(firstHeading.text)")

        let heading = applying(.heading, to: "Title", NSRange(location: 2, length: 0))
        expect(heading.text == "# Title", "heading prefixes the caret's line, got \(heading.text)")
        expect(heading.selection.location == 4, "the caret keeps its place in the words")

        // Every size the preview draws has to be reachable from the one button,
        // so clicking again steps down a level before taking the heading off.
        let second = applying(.heading, to: "# Title", NSRange(location: 4, length: 0))
        expect(second.text == "## Title", "a second click steps down a level, got \(second.text)")
        let third = applying(.heading, to: "## Title", NSRange(location: 4, length: 0))
        expect(third.text == "### Title", "and a third, got \(third.text)")
        let unheading = applying(.heading, to: "### Title", NSRange(location: 4, length: 0))
        expect(unheading.text == "Title", "the last click takes the heading off, got \(unheading.text)")

        // Swapping one line mark for another replaces it rather than stacking.
        let swapped = applying(.heading, to: "- item", NSRange(location: 3, length: 0))
        expect(swapped.text == "# item", "a bullet becomes a heading, got \(swapped.text)")

        let bullets = applying(.bullet, to: "one\ntwo", NSRange(location: 1, length: 5))
        expect(bullets.text == "- one\n- two", "every touched line gets a bullet, got \(bullets.text)")

        let unbulleted = applying(.bullet, to: "- one\n- two", NSRange(location: 2, length: 7))
        expect(unbulleted.text == "one\ntwo", "and gives them all back, got \(unbulleted.text)")

        let blankKept = applying(.bullet, to: "one\n\ntwo", NSRange(location: 0, length: 8))
        expect(blankKept.text == "- one\n\n- two", "blank lines stay blank, got \(blankKept.text)")

        // Selections arrive in UTF-16 units from the text view. Reading them as
        // Characters would put the markers inside the emoji.
        let afterEmoji = applying(.bold, to: "🙂ab", NSRange(location: 2, length: 2))
        expect(afterEmoji.text == "🙂**ab**", "marks land past an emoji, got \(afterEmoji.text)")

        let quoted = applying(.quote, to: "said", NSRange(location: 0, length: 0))
        expect(quoted.text == "> said", "quote prefixes the line, got \(quoted.text)")

        let inlineCode = applying(.code, to: "ls -la", NSRange(location: 0, length: 6))
        expect(inlineCode.text == "`ls -la`", "code wraps in backticks, got \(inlineCode.text)")

        // Numbering is written out, so the list reads correctly as plain text
        // and not only once the preview has renumbered it.
        let numbered = applying(.numbered, to: "one\ntwo\nthree", NSRange(location: 0, length: 13))
        expect(numbered.text == "1. one\n2. two\n3. three",
               "each line takes its own number, got \(numbered.text)")
        let unnumbered = applying(.numbered, to: "1. one\n2. two", NSRange(location: 0, length: 13))
        expect(unnumbered.text == "one\ntwo", "and gives them all back, got \(unnumbered.text)")
        let renumbered = applying(.numbered, to: "9. one\n10. two", NSRange(location: 0, length: 14))
        expect(renumbered.text == "one\ntwo", "however many digits they ran to, got \(renumbered.text)")

        // A list that is already a bullet list becomes a numbered one rather
        // than collecting both marks.
        let converted = applying(.numbered, to: "- one\n- two", NSRange(location: 0, length: 11))
        expect(converted.text == "1. one\n2. two", "bullets convert, got \(converted.text)")

        let link = applying(.link, to: "docs", NSRange(location: 0, length: 4))
        expect(link.text == "[docs](url)", "link wraps the words, got \(link.text)")
        expect(link.selection == NSRange(location: 7, length: 3),
               "and leaves the address selected to type over, got \(link.selection)")

        // The address is what the first click leaves selected, so that is the
        // state the second click has to recognise and undo.
        let unlinked = applying(.link, to: "[docs](url)", NSRange(location: 7, length: 3))
        expect(unlinked.text == "docs", "a second click takes the link off, got \(unlinked.text)")
        expect(unlinked.selection == NSRange(location: 0, length: 4),
               "leaving the words selected, got \(unlinked.selection)")
        let fromLabel = applying(.link, to: "see [docs](https://x.dev) now", NSRange(location: 5, length: 4))
        expect(fromLabel.text == "see docs now", "or from the words, got \(fromLabel.text)")
        let fromWhole = applying(.link, to: "[docs](url)", NSRange(location: 0, length: 11))
        expect(fromWhole.text == "docs", "or from the whole link, got \(fromWhole.text)")

        // A caret resting against a link's edge is about to write a new one.
        let beside = applying(.link, to: "[docs](url)", NSRange(location: 11, length: 0))
        expect(beside.text == "[docs](url)[](url)",
               "a caret beside a link writes a new one, got \(beside.text)")

        // Command-F is the system's find, so the pad only has to agree that
        // the key is its own rather than the text view's.
        func shortcut(_ key: String) -> ScratchpadFocusedShortcut.Action? {
            ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: key,
                                             commandOnly: true,
                                             canCreatePad: true,
                                             canClosePad: true)
        }
        expect(shortcut("f") == .find, "Command-F opens find")
        expect(shortcut("F") == .find, "however the shift key left it cased")
        expect(ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: "f",
                                                commandOnly: false,
                                                canCreatePad: true,
                                                canClosePad: true) == nil,
               "a plain f is text, not a shortcut")
        func shifted(_ key: String) -> ScratchpadFocusedShortcut.Action? {
            ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: key,
                                             commandOnly: true,
                                             shift: true,
                                             canCreatePad: true,
                                             canClosePad: true)
        }
        expect(shortcut("g") == .findNext, "Command-G finds the next match")
        expect(shifted("G") == .findPrevious, "Shift-Command-G finds the previous match")
        expect(shifted("t") == nil && shifted("w") == nil && shifted("f") == nil,
               "Shift only belongs to G, so Shift-Command-T and W stay the text's")

        // The pad-wide size is stored, so it arrives as whatever was last
        // written there, including from a build with a different range.
        expect(ScratchpadSupport.sanitizedTextSize(12) == 12, "a size in range is left alone")
        expect(ScratchpadSupport.sanitizedTextSize(2) == ScratchpadSupport.textSizeRange.lowerBound,
               "a size below the range is clamped up")
        expect(ScratchpadSupport.sanitizedTextSize(400) == ScratchpadSupport.textSizeRange.upperBound,
               "a size above the range is clamped down")
        expect(ScratchpadSupport.sanitizedTextSize(.nan) == ScratchpadSupport.defaultTextSize,
               "a corrupt size falls back to the default rather than drawing nothing")
        expect(ScratchpadSupport.textSizeRange.contains(ScratchpadSupport.defaultTextSize),
               "and the default is inside the range the slider offers")
        expect(ScratchpadSupport.defaultTextSize == 13,
               "an untouched pad keeps the 13 it drew at before the slider")

        // A range that outlived the text it was measured against is clamped
        // rather than trusted; NSString would raise on it.
        let stale = applying(.bold, to: "hi", NSRange(location: 40, length: 9))
        expect(stale.text == "hi****", "an out-of-date selection cannot crash, got \(stale.text)")

        // Select All over a heading, then take it off: the selection shrinks
        // with the text rather than running on into the line below.
        let unheaded = applying(.heading, to: "### a\nnext", NSRange(location: 0, length: 5))
        expect(unheaded.text == "a\nnext" && unheaded.selection == NSRange(location: 0, length: 1),
               "a removed prefix does not stretch the selection, got \(unheaded.selection)")

        // Indentation nests a list, so a mark sits after it and comes back off.
        expect(clicking(.bullet, 1, from: "- a\n  - b", NSRange(location: 6, length: 0)) == "- a\n  b",
               "a nested bullet comes off rather than stacking")
        expect(clicking(.bullet, 2, from: "- a\n  - b", NSRange(location: 6, length: 0)) == "- a\n  - b",
               "and goes back on at its own depth")

        // Markdown does not close a mark against a space, so the space a drag
        // picks up after a word stays outside the markers.
        expect(applying(.bold, to: "hello world", NSRange(location: 0, length: 6)).text == "**hello** world",
               "a trailing space stays outside the markers")
    }
}
