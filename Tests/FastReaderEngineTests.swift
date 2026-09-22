// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FastReaderEngineTests {
    static func run(_ suite: TestSuite) {
        suite.run("fast reader tokenization") { tokenize(suite) }
        suite.run("fast reader focus point") { orp(suite) }
        suite.run("fast reader chunking") { chunking(suite) }
        suite.run("fast reader duration") { duration(suite) }
    }

    private static func tokenize(_ suite: TestSuite) {
        let turkish = FastReaderEngine.tokenize("Hızlı okuma denemesi.")
        suite.expect(turkish.map(\.text) == ["Hızlı", "okuma", "denemesi."],
                     "a Turkish sentence splits into its three words, punctuation kept")
        suite.expect(turkish.last?.endsSentence == true,
                     "the final full stop marks the end of a sentence")
        suite.expect(turkish.first?.endsSentence == false,
                     "a word with no punctuation does not end a sentence")

        let clause = FastReaderEngine.tokenize("Önce bu, sonra şu.")
        suite.expect(clause.first(where: { $0.text.hasSuffix(",") })?.endsClause == true,
                     "a comma marks the end of a clause")

        // Five of the thirteen shipped locales write without spaces between
        // words, so whitespace splitting is not an option here.
        let chinese = FastReaderEngine.tokenize("快速阅读测试")
        suite.expect(chinese.count > 1,
                     "Chinese without spaces still splits into several tokens")
        suite.expect(chinese.allSatisfy { !$0.text.isEmpty },
                     "no Chinese token comes back empty")

        suite.expect(FastReaderEngine.tokenize("").isEmpty,
                     "an empty string yields no tokens")
        suite.expect(FastReaderEngine.tokenize("   \n\t ").isEmpty,
                     "whitespace alone yields no tokens")
        suite.expect(FastReaderEngine.tokenize("... !!! ???").isEmpty,
                     "punctuation alone yields no tokens")
        suite.expect(FastReaderEngine.tokenize("word").count == 1,
                     "a single word yields a single token")
    }

    private static func orp(_ suite: TestSuite) {
        let expected: [(String, Int)] = [
            ("a", 0),
            ("at", 1), ("word", 1), ("words", 1),
            ("reader", 2), ("selection", 2),
            ("tokenization", 3), ("accessibility", 3),
            ("internationalization", 4)
        ]
        for (word, index) in expected {
            suite.expect(FastReaderEngine.orpIndex(of: word) == index,
                         "focus index of \(word) is \(index), got \(FastReaderEngine.orpIndex(of: word))")
        }
        suite.expect(FastReaderEngine.orpIndex(of: "") == 0,
                     "an empty word has a focus index of zero")
        // Counted in graphemes, so Turkish diacritics and emoji each count once.
        suite.expect(FastReaderEngine.orpIndex(of: "değişiklik") == 3,
                     "a ten-grapheme Turkish word has a focus index of three")
        suite.expect(FastReaderEngine.orpIndex(of: "şu") == 1,
                     "a two-grapheme Turkish word has a focus index of one")
        suite.expect(FastReaderEngine.orpIndex(of: "👨‍👩‍👧‍👦") == 0,
                     "a single emoji cluster counts as one grapheme")
    }

    private static func chunking(_ suite: TestSuite) {
        let tokens = FastReaderEngine.tokenize("bir iki üç dört beş altı")
        suite.expect(FastReaderEngine.chunk(tokens, size: 1).count == 6,
                     "six words at size one give six chunks")
        suite.expect(FastReaderEngine.chunk(tokens, size: 2).count == 3,
                     "six words at size two give three chunks")
        suite.expect(FastReaderEngine.chunk(tokens, size: 3).count == 2,
                     "six words at size three give two chunks")

        // A chunk spanning two sentences scrambles the sense of both.
        let sentences = FastReaderEngine.tokenize("Bitti. Yeni cümle başladı.")
        let chunked = FastReaderEngine.chunk(sentences, size: 3)
        suite.expect(chunked.first?.tokens.count == 1,
                     "a sentence ending closes its chunk early")
        suite.expect(chunked.allSatisfy { chunk in
            chunk.tokens.dropLast().allSatisfy { !$0.endsSentence }
        }, "no chunk carries a sentence ending anywhere but its last token")

        let short = FastReaderEngine.chunk(FastReaderEngine.tokenize("tek"), size: 3)
        suite.expect(short.count == 1 && short[0].tokens.count == 1,
                     "fewer tokens than the chunk size still gives one chunk")
        suite.expect(FastReaderEngine.chunk([], size: 2).isEmpty,
                     "no tokens give no chunks")
        suite.expect(chunked.allSatisfy { $0.orpToken == 0 },
                     "the focus sits on the first token of each chunk")
    }

    private static func duration(_ suite: TestSuite) {
        var options = ReaderOptions.default
        options.punctuationPause = false
        options.longWordScaling = false

        let plain = FastReaderEngine.chunk(FastReaderEngine.tokenize("kelime"), size: 1)[0]
        options.wordsPerMinute = 600
        suite.expectClose(FastReaderEngine.duration(for: plain, options: options),
                          0.1, "one word at 600 wpm takes a tenth of a second")

        options.wordsPerMinute = 300
        suite.expectClose(FastReaderEngine.duration(for: plain, options: options),
                          0.2, "one word at 300 wpm takes a fifth of a second")

        let pair = FastReaderEngine.chunk(FastReaderEngine.tokenize("iki kelime"), size: 2)[0]
        suite.expectClose(FastReaderEngine.duration(for: pair, options: options),
                          0.4, "two words take twice as long as one")

        // Raising the speed must never lengthen a chunk, at any option set.
        for punctuation in [false, true] {
            for scaling in [false, true] {
                var walk = ReaderOptions.default
                walk.punctuationPause = punctuation
                walk.longWordScaling = scaling
                var previous = Double.infinity
                for wpm in stride(from: 200, through: 1200, by: 100) {
                    walk.wordsPerMinute = wpm
                    let value = FastReaderEngine.duration(for: pair, options: walk)
                    suite.expect(value.isFinite && value > 0,
                                 "duration at \(wpm) wpm is finite and positive")
                    suite.expect(value <= previous,
                                 "duration never grows as wpm rises (\(wpm) wpm)")
                    previous = value
                }
            }
        }

        options.wordsPerMinute = 300
        options.punctuationPause = true
        let sentence = FastReaderEngine.chunk(FastReaderEngine.tokenize("son."), size: 1)[0]
        suite.expectClose(FastReaderEngine.duration(for: sentence, options: options),
                          0.4, "a sentence ending doubles the word's time")
        let clause = FastReaderEngine.chunk(FastReaderEngine.tokenize("ara,"), size: 1)[0]
        suite.expectClose(FastReaderEngine.duration(for: clause, options: options),
                          0.3, "a clause ending adds half the word's time")

        options.punctuationPause = false
        options.longWordScaling = true
        let long = FastReaderEngine.chunk(
            FastReaderEngine.tokenize("internationalization"), size: 1)[0]
        let short = FastReaderEngine.duration(for: plain, options: options)
        suite.expect(FastReaderEngine.duration(for: long, options: options) > short,
                     "a long word gets more time than a short one")
        // 20 graphemes is 12 over the threshold, 0.6 of scaling, capped at 1.6.
        suite.expectClose(FastReaderEngine.duration(for: long, options: options),
                          0.2 * 1.6, "long-word scaling stops at its cap")
    }
}
