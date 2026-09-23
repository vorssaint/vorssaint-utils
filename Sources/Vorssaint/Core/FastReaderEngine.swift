// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import NaturalLanguage

/// One word (or, for the last token of a chunk that closes a clause or
/// sentence, a word with its trailing punctuation attached) as the reader
/// will show it.
struct ReaderToken {
    let text: String
    /// Grapheme offset, into `text`, of the letter the reader should hold
    /// still under the focus point. See `FastReaderEngine.orpIndex(of:)`.
    let orpIndex: Int
    /// The token's trailing punctuation is a comma, semicolon or colon: a
    /// short pause is due before the next chunk.
    let endsClause: Bool
    /// The token's trailing punctuation is a full stop, exclamation mark,
    /// question mark or ellipsis: a longer pause is due, and a chunk must
    /// not carry on past it into the next sentence.
    let endsSentence: Bool
}

/// A group of tokens flashed to the reader as a single unit.
struct ReaderChunk {
    let tokens: [ReaderToken]
    /// Which token in `tokens` carries the focus letter. The engine always
    /// puts it on the first token today, but the field exists so a future
    /// centering strategy (for instance, the token with the longest word)
    /// does not need a shape change.
    let orpToken: Int

    /// The chunk as one line, tokens separated by a single space. Good
    /// enough for a flashed line of one to three words; nothing here tries
    /// to reproduce the source text's exact original whitespace.
    var text: String { tokens.map(\.text).joined(separator: " ") }
}

/// The knobs a reading session is played back with. Kept as one value type
/// so a session can swap them mid-read (for instance, a speed change) without
/// touching anything else about its state.
struct ReaderOptions {
    var wordsPerMinute: Int
    var chunkSize: Int
    var focusPoint: Bool
    var punctuationPause: Bool
    var longWordScaling: Bool

    static let `default` = ReaderOptions(wordsPerMinute: 200, chunkSize: 1,
                                          focusPoint: true, punctuationPause: true,
                                          longWordScaling: true)
}

/// Tokenization, chunking, focus-point placement and pacing for Rapid Serial
/// Visual Presentation (RSVP) reading: words are flashed one chunk at a time
/// in a fixed spot, rather than read by moving the eyes across a line, which
/// removes the time a normal reader spends on saccades and line returns.
///
/// The "focus point" (Optimal Recognition Point, or ORP, in the RSVP
/// literature) is the letter a reader's eye naturally lands on first when it
/// recognizes a word; centering every chunk on that letter instead of on the
/// word's geometric middle is what keeps the eye still across a run of
/// flashes of differing width. `orpIndex(of:)` below reproduces the Spritz
/// heuristic for finding that letter from a word's length alone.
///
/// This type is pure: no AppKit, no state, nothing that cannot run in the
/// test executable. `FastReaderSession` (Services/FastReader) is the piece
/// that turns these values into a running clock.
enum FastReaderEngine {
    static let wordsPerMinuteRange: ClosedRange<Int> = 200...1200
    static let chunkSizeRange: ClosedRange<Int> = 1...3

    /// Trailing marks that close a sentence, in the order the rest of the
    /// engine treats as canonical. `…` is the single Unicode ellipsis
    /// character (`U+2026`); a run of three ASCII periods is not recognized
    /// as its equivalent, the same way the project's own labels are never
    /// allowed to fall back to `...` in place of it.
    private static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]
    /// Trailing marks that close a clause without ending the sentence.
    private static let clauseEnders: Set<Character> = [",", ";", ":"]

    private static let sentencePauseMultiplier = 2.0
    private static let clausePauseMultiplier = 1.5
    /// Grapheme count above which a word starts asking for extra time.
    private static let longWordThreshold = 8
    /// Additional time, as a fraction of the base duration, per grapheme
    /// past `longWordThreshold`.
    private static let longWordScalingStep = 0.05
    /// Ceiling on the long-word multiplier, so a single very long word (a
    /// URL, a German compound) cannot stall the whole session.
    private static let longWordScalingCap = 1.6

    /// Splits `text` into words, in source order, dropping anything that is
    /// only punctuation or whitespace.
    ///
    /// Built on `NLTokenizer(unit: .word)` rather than splitting on
    /// whitespace, because five of the thirteen shipped locales — Japanese,
    /// Korean and the three Chinese variants — write without spaces between
    /// words, and a whitespace split would turn a whole paragraph in one of
    /// those languages into a single token. `NLLanguageRecognizer` is asked
    /// first so the tokenizer segments with the right language's rules when
    /// it can tell; when it cannot, the tokenizer is left to its own
    /// detection rather than forcing a guess.
    ///
    /// `NLTokenizer` hands back a word's range without the punctuation that
    /// follows it, so each word's trailing punctuation is walked and
    /// reattached by hand here, one mark at a time, stopping at the first
    /// character that is not one of the recognized sentence or clause
    /// enders. That is also what keeps a punctuation-only span (an emoji
    /// row, a run of `...`) from surviving as a token of its own: it never
    /// gets picked up as anyone's trailing punctuation, and a word range
    /// with no letter or digit in it is dropped outright.
    ///
    /// Known and accepted limitation, not fixed here: `NLTokenizer` splits a
    /// URL into several tokens, the same as it would split any other run of
    /// slashes and dots.
    static func tokenize(_ text: String) -> [ReaderToken] {
        guard !text.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .word)
        if let language = NLLanguageRecognizer.dominantLanguage(for: text) {
            tokenizer.setLanguage(language)
        }
        tokenizer.string = text

        var tokens: [ReaderToken] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = text[range]
            guard word.contains(where: { $0.isLetter || $0.isNumber }) else { return true }

            var end = range.upperBound
            var endsClause = false
            var endsSentence = false
            while end < text.endIndex {
                let character = text[end]
                if sentenceEnders.contains(character) {
                    endsSentence = true
                    end = text.index(after: end)
                } else if clauseEnders.contains(character) {
                    endsClause = true
                    end = text.index(after: end)
                } else {
                    break
                }
            }
            // A sentence ending is the stronger claim; a run such as "word.,"
            // (not something real text produces, but not impossible from a
            // pasted selection) should still count as ending the sentence.
            if endsSentence { endsClause = false }

            let fullText = String(text[range.lowerBound..<end])
            tokens.append(ReaderToken(text: fullText, orpIndex: orpIndex(of: fullText),
                                      endsClause: endsClause, endsSentence: endsSentence))
            return true
        }
        return tokens
    }

    /// The Spritz rule for where a reader's eye lands on a word of a given
    /// length, keyed on grapheme count rather than UTF-16 or scalar count so
    /// that a Turkish diacritic or an emoji cluster — either of which can
    /// span several Unicode scalars — still counts as the one character a
    /// reader sees.
    static func orpIndex(of word: String) -> Int {
        switch word.count {
        case 0...1: return 0
        case 2...5: return 1
        case 6...9: return 2
        case 10...13: return 3
        default: return 4
        }
    }

    /// Groups `tokens` into chunks of up to `size` words, clamped into
    /// `chunkSizeRange`. A chunk also closes early the moment it takes on a
    /// token whose `endsSentence` is true, even under the requested size:
    /// letting a chunk straddle two sentences would flash the end of one
    /// thought and the start of the next as if they were one.
    static func chunk(_ tokens: [ReaderToken], size: Int) -> [ReaderChunk] {
        guard !tokens.isEmpty else { return [] }
        let clampedSize = min(max(size, chunkSizeRange.lowerBound), chunkSizeRange.upperBound)

        var chunks: [ReaderChunk] = []
        var current: [ReaderToken] = []
        for token in tokens {
            current.append(token)
            if current.count == clampedSize || token.endsSentence {
                chunks.append(ReaderChunk(tokens: current, orpToken: 0))
                current = []
            }
        }
        if !current.isEmpty {
            chunks.append(ReaderChunk(tokens: current, orpToken: 0))
        }
        return chunks
    }

    /// How long `chunk` should stay on screen under `options`, in seconds.
    ///
    /// The base is `60 / wordsPerMinute` seconds per word, scaled by the
    /// chunk's token count, with `wordsPerMinute` clamped into
    /// `wordsPerMinuteRange` first so a corrupted or hand-edited preference
    /// can never divide by zero or produce a negative interval. On top of
    /// that base, punctuation pausing and long-word scaling — each optional,
    /// each starting from a constant declared above rather than scattered
    /// through this function — can only ever lengthen the result, which is
    /// what keeps raising the words-per-minute setting a reliable way to
    /// make a session move faster and never the reverse.
    static func duration(for chunk: ReaderChunk, options: ReaderOptions) -> TimeInterval {
        let clampedWPM = min(max(options.wordsPerMinute, wordsPerMinuteRange.lowerBound),
                             wordsPerMinuteRange.upperBound)
        var seconds = 60.0 / Double(clampedWPM) * Double(chunk.tokens.count)

        if options.punctuationPause, let last = chunk.tokens.last {
            if last.endsSentence {
                seconds *= sentencePauseMultiplier
            } else if last.endsClause {
                seconds *= clausePauseMultiplier
            }
        }

        if options.longWordScaling {
            let longest = chunk.tokens.map(\.text.count).max() ?? 0
            let over = max(0, longest - longWordThreshold)
            let scale = min(longWordScalingCap, 1 + Double(over) * longWordScalingStep)
            seconds *= scale
        }

        return seconds
    }
}

/// Splits a chunk into the text before its focus character, that character,
/// and the text after it. Pure, and shared: both the floating window and the
/// island draw the same three runs, and a second copy of this would be a
/// second chance for the two surfaces to disagree about where the axis is.
enum FastReaderFocusRuns {
    static func split(_ chunk: ReaderChunk) -> (before: String, focus: String, after: String) {
        guard !chunk.tokens.isEmpty else { return ("", "", "") }
        let tokenIndex = min(max(chunk.orpToken, 0), chunk.tokens.count - 1)
        let target = chunk.tokens[tokenIndex]
        let leadingTokens = chunk.tokens[..<tokenIndex].map(\.text).joined(separator: " ")
        let trailingTokens = chunk.tokens[(tokenIndex + 1)...].map(\.text).joined(separator: " ")

        let characters = Array(target.text)
        guard !characters.isEmpty else { return (leadingTokens, "", trailingTokens) }
        let letterIndex = min(max(target.orpIndex, 0), characters.count - 1)
        let beforeInToken = String(characters[..<letterIndex])
        let focusLetter = String(characters[letterIndex])
        let afterInToken = String(characters[(letterIndex + 1)...])

        let before = leadingTokens.isEmpty ? beforeInToken : leadingTokens + " " + beforeInToken
        let after = trailingTokens.isEmpty ? afterInToken : afterInToken + " " + trailingTokens
        return (before, focusLetter, after)
    }
}
