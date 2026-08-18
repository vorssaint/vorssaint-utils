// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CommandBarClipboardAccess {
    static func canUseHistory(captureEnabled: Bool, hasSavedItems: Bool) -> Bool {
        captureEnabled || hasSavedItems
    }
}

/// The bar can be visible before home has finished preparing, but only the
/// presentation that asked for that work may receive it.
struct CommandBarPresentationLifecycle {
    enum Surface: Equatable {
        case hidden
        case loadingHome(UUID)
        case home(UUID)
    }

    private(set) var surface: Surface = .hidden

    var isLoadingHome: Bool { surface.isLoadingHome }

    mutating func beginHome(_ id: UUID) {
        surface = .loadingHome(id)
    }

    mutating func hide() {
        surface = .hidden
    }

    func acceptsHomeHydration(_ id: UUID, isVisible: Bool) -> Bool {
        isVisible && surface == .loadingHome(id)
    }

    func acceptsHomeUpdates(_ id: UUID, isVisible: Bool) -> Bool {
        isVisible && surface == .home(id)
    }

    /// A shared cache is useful to whichever Home is current when its work
    /// finishes, even when another presentation started that work. A hidden
    /// panel still rejects the accompanying UI refresh.
    func acceptsSharedCacheCompletion(startedBy _: UUID,
                                      currentID: UUID,
                                      isVisible: Bool) -> Bool {
        acceptsHomeUpdates(currentID, isVisible: isVisible)
    }

    @discardableResult
    mutating func completeHomeHydration(_ id: UUID, isVisible: Bool) -> Bool {
        guard acceptsHomeHydration(id, isVisible: isVisible) else { return false }
        surface = .home(id)
        return true
    }

}

/// A shortcut that needs the panel waits for Home's deferred hydration before
/// it enters confirmation, argument or setup mode. Its presentation id keeps
/// a close or newer opening from running yesterday's request.
struct CommandBarDeferredRowShortcut {
    private var pending: (presentationID: UUID, stableKey: String)?

    mutating func schedule(_ stableKey: String, for presentationID: UUID) {
        pending = (presentationID, stableKey)
    }

    mutating func cancel() {
        pending = nil
    }

    func key(for presentationID: UUID) -> String? {
        pending?.presentationID == presentationID ? pending?.stableKey : nil
    }

    mutating func take(for presentationID: UUID) -> String? {
        guard pending?.presentationID == presentationID else { return nil }
        defer { pending = nil }
        return pending?.stableKey
    }
}

private extension CommandBarPresentationLifecycle.Surface {
    var isLoadingHome: Bool {
        if case .loadingHome = self { return true }
        return false
    }
}

/// One searchable row offered to the command bar's ranking pass. `boost`
/// carries whatever the caller wants to privilege (usage, pinning) so the
/// ranking itself stays a pure function of text.
struct CommandBarCandidate {
    let index: Int
    /// Already folded, so a long list is not re-folded on every keystroke.
    let normalizedTitle: String
    let normalizedKeywords: String
    let boost: Int

    init(index: Int, title: String, keywords: String = "", boost: Int = 0) {
        self.init(index: index,
                  normalizedTitle: CommandBarSearch.normalized(title),
                  normalizedKeywords: CommandBarSearch.normalized(keywords),
                  boost: boost)
    }

    init(index: Int, normalizedTitle: String, normalizedKeywords: String, boost: Int = 0) {
        self.index = index
        self.normalizedTitle = normalizedTitle
        self.normalizedKeywords = normalizedKeywords
        self.boost = boost
    }
}

/// Pure text matching and ranking for the command bar. The shape follows the
/// clipboard search (fold, tokenize, score, stable ties) so both searches feel
/// like the same app, but typing mistakes must not break this one: a token
/// also matches as an in-order subsequence of a word ("brlho" finds "brilho")
/// and, as a last resort, within one edit of a word ("birlho" too).
enum CommandBarSearch {
    /// Case, accent and width differences never matter. Folded without a
    /// locale on purpose: Turkish lowercases a capital I to a dotless one, so
    /// a locale-aware fold would stop "insta" from finding a title that begins
    /// with that letter on a Mac set to Turkish.
    static func normalized(_ value: String) -> String {
        let folded = strippingInvisibles(value)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: nil)
            .lowercased()
        // Splitting on any whitespace — not just the ASCII space — treats the
        // full-width space (U+3000) that some input methods produce the same
        // as the half-width one, so "bd　123" folds like "bd 123".
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Drops the characters that take up no space and that nobody can type:
    /// direction marks, zero-width joiners, soft hyphens. At least one widely
    /// installed app carries a left-to-right mark in front of its name, and a
    /// single invisible character was enough to stop the app from being an
    /// exact match for its own name and sink it below everything else.
    private static func strippingInvisibles(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: isInvisible) else { return value }
        return String(String.UnicodeScalarView(value.unicodeScalars.filter { !isInvisible($0) }))
    }

    /// Every format character sits above this point, so plain text never pays
    /// for the lookup.
    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x00AD && scalar.properties.generalCategory == .format
    }

    /// Whether the query names the verb of a format like "Quit %@". Used to
    /// keep a heavy, rare command out of the list until it is asked for, in
    /// every language: the verb is whatever the format says around the name,
    /// and languages written without spaces match by containment.
    static func matchesVerb(_ query: String, in format: String) -> Bool {
        let verb = normalized(format.replacingOccurrences(of: "%@", with: " "))
            .trimmingCharacters(in: .whitespaces)
        guard !verb.isEmpty else { return false }
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return false }
        for token in normalizedQuery.split(separator: " ").map(String.init) where token.count >= 2 {
            for word in verb.split(separator: " ").map(String.init) {
                if word.hasPrefix(token) || token.hasPrefix(word) { return true }
            }
            // Japanese, Chinese and Korean write the verb against the name
            // with no space to split on.
            if verb.contains(token) { return true }
        }
        return false
    }

    static func matches(title: String, keywords: String = "", query: String) -> Bool {
        score(title: title, keywords: keywords, query: query) != nil
    }

    /// Nil when the query does not match; otherwise a comparable score.
    /// Whole-query hits on the title dominate, then per-token quality
    /// (whole word > word prefix > substring > subsequence > one typo).
    static func score(title: String, keywords: String = "", query: String) -> Int? {
        score(normalizedTitle: normalized(title),
              normalizedKeywords: normalized(keywords),
              normalizedQuery: normalized(query))
    }

    /// The scoring itself, over text that is already folded. Everything the
    /// bar ranks per keystroke comes through here.
    static func score(normalizedTitle: String,
                      normalizedKeywords: String,
                      normalizedQuery: String) -> Int? {
        guard !normalizedQuery.isEmpty else { return nil }
        let haystack = normalizedKeywords.isEmpty
            ? normalizedTitle
            : normalizedTitle + " " + normalizedKeywords
        let words = haystack.split(separator: " ").map(String.init)

        var score = 0
        for token in normalizedQuery.split(separator: " ").map(String.init) {
            guard let tokenScore = bestTokenScore(token, in: words, haystack: haystack) else {
                return nil
            }
            score += tokenScore
        }

        if normalizedTitle == normalizedQuery {
            score += 1200
        } else if normalizedTitle.hasPrefix(normalizedQuery) {
            score += 900
        } else if normalizedTitle.contains(normalizedQuery) {
            score += 700
        } else if !normalizedKeywords.isEmpty, normalizedKeywords.contains(normalizedQuery) {
            score += 350
        }
        return score
    }

    /// Indexes of the matching candidates, best first; ties keep the caller's
    /// order so equally good rows stay where the catalog put them.
    static func rankedIndexes(candidates: [CommandBarCandidate], matching query: String) -> [Int] {
        let normalizedQuery = normalized(query)
        let scored: [(index: Int, score: Int, position: Int)] = candidates.enumerated()
            .compactMap { position, candidate in
                guard let base = score(normalizedTitle: candidate.normalizedTitle,
                                       normalizedKeywords: candidate.normalizedKeywords,
                                       normalizedQuery: normalizedQuery) else { return nil }
                return (candidate.index, base + candidate.boost, position)
            }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.position < $1.position }
            .map(\.index)
    }

    private static func bestTokenScore(_ token: String, in words: [String], haystack: String) -> Int? {
        var best: Int?
        for word in words {
            if word == token { return 140 }
            if word.hasPrefix(token) { best = max(best ?? 0, 80) }
        }
        if best == nil, haystack.contains(token) { best = 44 }
        // Fuzzy passes only rescue typing mistakes, so they need some length
        // to bite on; two letters matching half the catalog helps no one.
        // Digit tokens are values, never typos.
        if best == nil, token.count >= 3, !token.allSatisfy(\.isNumber) {
            for word in words where isSubsequence(token, of: word) {
                best = 24
                break
            }
        }
        if best == nil, token.count >= 4, !token.allSatisfy(\.isNumber) {
            for word in words where withinOneEdit(token, word) {
                best = 16
                break
            }
        }
        return best
    }

    /// The positions to keep when ids repeat: the first of each, in order.
    /// Two rows with one id is undefined behaviour in a SwiftUI list, and the
    /// list is stitched together from six providers plus whatever the person
    /// saved, so the last word on it belongs somewhere that tests can reach.
    static func firstOccurrences(of ids: [String]) -> [Int] {
        var seen = Set<String>()
        return ids.indices.filter { seen.insert(ids[$0]).inserted }
    }

    /// Character positions of the title the query literally matched, so the
    /// row can show WHY it is there. Only literal hits are marked: a fuzzy
    /// rescue has no honest range to point at, and highlighting a guess reads
    /// worse than highlighting nothing.
    static func highlightOffsets(title: String, query: String) -> Set<Int> {
        let folded = foldedCharacters(title)
        guard !folded.isEmpty else { return [] }
        var offsets = Set<Int>()
        for token in normalized(query).split(separator: " ").map(Array.init) where !token.isEmpty {
            guard let start = firstIndex(of: token, in: folded) else { continue }
            for position in start..<(start + token.count) { offsets.insert(position) }
        }
        return offsets
    }

    /// Folds each character on its own so the folded array stays aligned with
    /// the original, one position per character.
    private static func foldedCharacters(_ value: String) -> [Character] {
        value.map { character in
            let folded = String(character).folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: nil)
            return folded.first ?? character
        }
    }

    private static func firstIndex(of token: [Character], in haystack: [Character]) -> Int? {
        guard token.count <= haystack.count else { return nil }
        // Word starts first: highlighting "set" inside "Reset" when the title
        // also begins with "Settings" would point at the wrong place.
        for start in 0...(haystack.count - token.count) {
            let isWordStart = start == 0 || haystack[start - 1] == " "
            guard isWordStart else { continue }
            if Array(haystack[start..<(start + token.count)]) == token { return start }
        }
        for start in 0...(haystack.count - token.count)
        where Array(haystack[start..<(start + token.count)]) == token {
            return start
        }
        return nil
    }

    static func isSubsequence(_ needle: String, of word: String) -> Bool {
        guard needle.count <= word.count else { return false }
        var position = word.startIndex
        for character in needle {
            guard let found = word[position...].firstIndex(of: character) else { return false }
            position = word.index(after: found)
        }
        return true
    }

    /// True when the strings are at most one substitution, insertion,
    /// deletion or adjacent swap apart.
    static func withinOneEdit(_ first: String, _ second: String) -> Bool {
        let a = Array(first), b = Array(second)
        if abs(a.count - b.count) > 1 { return false }
        if a == b { return true }
        var i = 0, j = 0
        var edited = false
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                i += 1
                j += 1
                continue
            }
            if edited { return false }
            edited = true
            if a.count == b.count {
                if i + 1 < a.count, j + 1 < b.count, a[i] == b[j + 1], a[i + 1] == b[j] {
                    i += 2
                    j += 2
                } else {
                    i += 1
                    j += 1
                }
            } else if a.count > b.count {
                i += 1
            } else {
                j += 1
            }
        }
        return true
    }
}

/// The small text jobs the bar offers for whatever is selected. Pure, so what
/// a word is and where a preview cuts are pinned by tests instead of being
/// decided again in each caller.
enum CommandBarText {
    /// Words the way a person counts them: runs of anything that is not a
    /// space. Scripts written without spaces (Chinese, Japanese) have no word
    /// gaps to count, so there the character count is the honest answer.
    static func wordCount(_ text: String) -> Int {
        let words = text.split(whereSeparator: \.isWhitespace).count
        return words
    }

    static func characterCount(_ text: String) -> Int {
        text.count
    }

    /// A one-line stand-in for the selection, for the heading that says what
    /// the bar is about to act on. Newlines become spaces so a paragraph does
    /// not take the heading apart.
    static func preview(_ text: String, limit: Int = 44) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Whether changing the case of this text would change anything at all.
    /// A row that visibly does nothing is worse than no row.
    static func changesCase(_ text: String, to transform: (String) -> String) -> Bool {
        transform(text) != text
    }
}

/// The split of "brilho 40" into the verb and its value. Only a trailing bare
/// number counts, and only after some text: a number alone is a search, not a
/// command.
struct CommandBarNumberSplit: Equatable {
    let text: String
    let number: Int?
}

extension CommandBarSearch {
    static func splitTrailingNumber(_ query: String) -> CommandBarNumberSplit {
        let tokens = query.split(separator: " ").map(String.init)
        guard tokens.count >= 2, let last = tokens.last else {
            return CommandBarNumberSplit(text: query.trimmingCharacters(in: .whitespaces), number: nil)
        }
        var digits = last
        if digits.hasSuffix("%") { digits = String(digits.dropLast()) }
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let value = Int(digits) else {
            return CommandBarNumberSplit(text: query.trimmingCharacters(in: .whitespaces), number: nil)
        }
        return CommandBarNumberSplit(text: tokens.dropLast().joined(separator: " "), number: value)
    }

    /// The value typed while the bar asks for a number in place. Accepts an
    /// optional %, rejects everything else, clamps into the command's range.
    static func argumentValue(_ text: String, in range: ClosedRange<Int>) -> Int? {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasSuffix("%") { digits = String(digits.dropLast()) }
        guard !digits.isEmpty, digits.count <= 4, digits.allSatisfy(\.isNumber),
              let value = Int(digits) else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// How often and how recently one command ran. Stored per command id, never
/// per query: what the person typed is never written anywhere.
struct CommandBarUse: Codable, Equatable {
    var count: Int
    var lastUsed: Double
}

/// Usage bookkeeping behind "the order privileges what the person uses most".
enum CommandBarUsage {
    static let storedIDLimit = 200

    static func decode(_ raw: String?) -> [String: CommandBarUse] {
        guard let raw, let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: CommandBarUse].self, from: data)
        else { return [:] }
        return map
    }

    static func encode(_ usage: [String: CommandBarUse]) -> String? {
        guard let data = try? JSONEncoder().encode(usage) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The map after one more run of `id`. Oldest ids fall off past the cap so
    /// the store never grows with the years.
    static func recording(_ usage: [String: CommandBarUse], id: String, now: Double) -> [String: CommandBarUse] {
        var next = usage
        var use = next[id] ?? CommandBarUse(count: 0, lastUsed: now)
        use.count = min(use.count + 1, 999)
        use.lastUsed = now
        next[id] = use
        if next.count > storedIDLimit {
            let surplus = next.sorted { $0.value.lastUsed < $1.value.lastUsed }
                .prefix(next.count - storedIDLimit)
            for entry in surplus { next.removeValue(forKey: entry.key) }
        }
        return next
    }

    /// The ranking boost habit earns. Capped well below a literal text hit so
    /// what the person actually typed always beats what they usually run.
    static func boost(for use: CommandBarUse?, now: Double) -> Int {
        guard let use, use.count > 0 else { return 0 }
        let age = max(0, now - use.lastUsed)
        let weight: Int
        switch age {
        case ..<(2 * 3600): weight = 12
        case ..<(48 * 3600): weight = 8
        case ..<(14 * 86400): weight = 5
        default: weight = 2
        }
        return min(use.count, 40) * weight
    }

    /// What an empty bar offers: the most used commands first, then a few
    /// curated ones worth discovering, never more than `limit`.
    static func suggestionIDs(usage: [String: CommandBarUse],
                              available: [String],
                              curated: [String],
                              limit: Int) -> [String] {
        let availableSet = Set(available)
        var picked: [String] = []
        let used = usage
            .filter { availableSet.contains($0.key) && $0.value.count > 0 }
            .sorted {
                $0.value.count != $1.value.count
                    ? $0.value.count > $1.value.count
                    : $0.value.lastUsed > $1.value.lastUsed
            }
            .map(\.key)
        picked.append(contentsOf: used.prefix(limit))
        for id in curated where picked.count < limit {
            if availableSet.contains(id), !picked.contains(id) {
                picked.append(id)
            }
        }
        return picked
    }
}
