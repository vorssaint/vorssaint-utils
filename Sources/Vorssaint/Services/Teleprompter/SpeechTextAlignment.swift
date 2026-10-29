// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import Foundation

enum SpeechTextAlignment {
    static func annotationFlags(for words: [String]) -> [Bool] {
        var closingAtOrAfter = Array(repeating: false, count: words.count)
        var hasClosing = false
        for index in words.indices.reversed() {
            if words[index].contains("]") {
                hasClosing = true
            }
            closingAtOrAfter[index] = hasClosing
        }

        var flags: [Bool] = []
        var isInsideAnnotation = false
        for (index, word) in words.enumerated() {
            let beginsAnnotation = word.hasPrefix("[") && closingAtOrAfter[index]
            let isAnnotation = isInsideAnnotation || beginsAnnotation
            flags.append(isAnnotation)
            if beginsAnnotation {
                isInsideAnnotation = true
            }
            if isInsideAnnotation && word.contains("]") {
                isInsideAnnotation = false
            }
        }
        return flags
    }

    static func annotationRanges(in text: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var openingIndex: Int?

        for (index, character) in text.enumerated() {
            if character == "[" && openingIndex == nil {
                openingIndex = index
            } else if character == "]", let start = openingIndex {
                ranges.append(start..<(index + 1))
                openingIndex = nil
            }
        }

        return ranges
    }

    static func advancePastAnnotations(
        in text: String,
        ranges: [Range<Int>],
        from offset: Int
    ) -> Int {
        let characters = Array(text)
        var current = max(0, min(offset, characters.count))
        var skippedAnnotation = false

        while current < characters.count {
            if let range = ranges.first(where: { $0.contains(current) }) {
                current = range.upperBound
                skippedAnnotation = true
                continue
            }

            var next = current
            while next < characters.count && characters[next].isWhitespace {
                next += 1
            }

            if let range = ranges.first(where: { $0.lowerBound == next }) {
                current = range.upperBound
                skippedAnnotation = true
                continue
            }

            return skippedAnnotation ? next : current
        }

        return current
    }

    /// Combine character-level and word-level match results into a forward offset.
    static func bestOffset(
        characterResult: Int,
        wordResult: Int,
        agreementTolerance: Int = 20
    ) -> Int {
        if abs(characterResult - wordResult) <= agreementTolerance {
            return (characterResult + wordResult) / 2
        }
        return max(characterResult, wordResult)
    }

    static func shouldCommit(
        characterResult: Int,
        wordResult: Int,
        current: Int,
        rawCandidate: Int,
        candidate: Int,
        confirmed: Bool
    ) -> Bool {
        let bothProgressed = min(characterResult, wordResult) > 0
        let skippedAnnotation = candidate > rawCandidate
        let smallStep = candidate - current <= 15
        return bothProgressed || skippedAnnotation || confirmed || smallStep
    }
}
