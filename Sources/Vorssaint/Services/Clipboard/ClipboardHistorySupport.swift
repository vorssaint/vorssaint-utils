// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClipboardHistorySearchCandidate {
    var index: Int
    var text: String
    var isPinned: Bool
}

enum ClipboardHistorySearch {
    static func rankedIndexes(candidates: [ClipboardHistorySearchCandidate],
                              matching query: String) -> [Int] {
        let normalizedQuery = normalized(query)
        let tokens = queryTokens(normalizedQuery)
        guard !tokens.isEmpty else { return candidates.map(\.index) }

        return candidates
            .compactMap { candidate -> (index: Int, score: Int, originalOrder: Int)? in
                let text = normalized(candidate.text)
                guard tokens.allSatisfy({ text.contains($0) }) else { return nil }
                return (candidate.index,
                        score(for: text,
                              normalizedQuery: normalizedQuery,
                              tokens: tokens,
                              isPinned: candidate.isPinned),
                        candidate.index)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.originalOrder < $1.originalOrder
            }
            .map(\.index)
    }

    static func matches(_ text: String, query: String) -> Bool {
        let normalizedQuery = normalized(query)
        let tokens = queryTokens(normalizedQuery)
        guard !tokens.isEmpty else { return true }
        let normalizedText = normalized(text)
        return tokens.allSatisfy { normalizedText.contains($0) }
    }

    private static func score(for text: String,
                              normalizedQuery: String,
                              tokens: [String],
                              isPinned: Bool) -> Int {
        var score = isPinned ? 30 : 0
        if text == normalizedQuery { score += 1_200 }
        if text.hasPrefix(normalizedQuery) { score += 900 }
        if text.contains(normalizedQuery) { score += 700 }

        let words = Set(text.split(whereSeparator: \.isWhitespace).map(String.init))
        for token in tokens {
            if words.contains(token) {
                score += 140
            } else if words.contains(where: { $0.hasPrefix(token) }) {
                score += 80
            } else {
                score += 40
            }
        }
        return score
    }

    private static func queryTokens(_ normalizedQuery: String) -> [String] {
        normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ClipboardHistorySelection {
    static func initialIndex(totalCount: Int, pinnedCount: Int, query: String) -> Int {
        let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !hasQuery, pinnedCount == 0, totalCount > 1 else { return 0 }
        return 1
    }
}

enum ClipboardHistoryBatch {
    static func combinedText(_ texts: [String]) -> String {
        texts.joined(separator: "\n")
    }

    static func orderedSelectedIndexes<ID: Hashable>(allIDs: [ID], selectedIDs: Set<ID>) -> [Int] {
        allIDs.indices.filter { selectedIDs.contains(allIDs[$0]) }
    }
}

enum ClipboardHistoryPasteboardText {
    static func preferredText(webURLString: String?, plainText: String?) -> String? {
        let plain = trimmed(plainText)
        if let plain,
           let normalizedPlain = normalizedWebURL(plain) {
            return normalizedPlain
        }

        guard let webURL = normalizedWebURL(webURLString) else { return plain }
        guard let plain else { return webURL }
        return shouldPreferWebURL(webURL, over: plain) ? webURL : plain
    }

    private static func shouldPreferWebURL(_ webURL: String, over plain: String) -> Bool {
        if plain.hasPrefix("//") { return true }
        let stripped = stripWebScheme(webURL)
        return plain == stripped.withSlashes || plain == stripped.withoutSlashes
    }

    private static func normalizedWebURL(_ raw: String?) -> String? {
        guard let text = trimmed(raw),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url.absoluteString
    }

    private static func stripWebScheme(_ value: String) -> (withSlashes: String, withoutSlashes: String) {
        let lower = value.lowercased()
        let withSlashes: String
        if lower.hasPrefix("http://") {
            withSlashes = "//" + String(value.dropFirst("http://".count))
        } else if lower.hasPrefix("https://") {
            withSlashes = "//" + String(value.dropFirst("https://".count))
        } else {
            withSlashes = value
        }
        return (withSlashes, String(withSlashes.drop { $0 == "/" }))
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

enum ClipboardHistorySensitiveText {
    static func looksSensitive(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let obviousWords = ["password", "passwd", "secret", "token", "apikey", "api_key", "authorization"]
        if obviousWords.contains(where: lowered.contains) { return true }
        if isWebURL(text) { return false }

        guard text.count >= 20, text.count <= 160, !text.contains(where: { $0.isWhitespace }) else {
            return false
        }
        let hasLetter = text.contains { $0.isLetter }
        let hasDigit = text.contains { $0.isNumber }
        let hasSymbol = text.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
        return hasLetter && hasDigit && hasSymbol
    }

    private static func isWebURL(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return false
        }
        return true
    }
}
