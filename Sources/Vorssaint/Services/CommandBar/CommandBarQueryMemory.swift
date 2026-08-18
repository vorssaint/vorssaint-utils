// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the bar noticed about this session: which row was chosen after which
/// few letters, so typing those letters again lands on it.
///
/// Ranking by habit alone cannot answer this. Someone who opens one app all
/// day can still walk past it after typing part of its name, because the habit
/// is attached to the row and not to what they typed to reach it.
///
/// **It is never written down.** The bar promises to forget everything typed
/// into it, and that promise is worth more than remembering a preference
/// between two Macs: this lives in memory for as long as the app runs and goes
/// with it. Choosing the same row twice in one afternoon is where nearly all
/// of the benefit is anyway.
///
/// Pure, so what a prefix is and what one is worth are pinned by tests.
struct CommandBarQueryMemory: Equatable {
    /// Enough prefixes for a session's worth of typing, few enough that the
    /// map never becomes something to think about.
    static let queryLimit = 60
    /// Two rows can honestly compete for the same letters. More than a handful
    /// is not a memory, it is a list of everything.
    static let idsPerQuery = 4
    /// Past this, what was typed is a whole word and the ranking already knows
    /// what to do with it.
    static let longestPrefix = 12

    /// What one remembered choice is worth, at most.
    ///
    /// Deliberately only a tie-breaker. What the bar noticed can reorder rows
    /// that match equally well, but cannot turn a weaker keyword match into a
    /// better answer. A memory that could do that would make the list feel
    /// stuck, which is the classic way learned ranking goes wrong.
    static let maximumBoost = 3

    private struct Pick: Equatable {
        var count: Int
        /// When it was last chosen, counted in choices rather than seconds:
        /// the memory only has to order its own entries, and a clock would
        /// make the rules untestable for nothing.
        var step: Int
    }

    private var picks: [String: [String: Pick]] = [:]

    init() {}

    /// Every leading piece of what was typed, so choosing a row after three
    /// letters also answers the first one and two. Folded the same way the
    /// ranking folds, so memory and search agree about accents and case.
    static func prefixes(of query: String) -> [String] {
        let normalized = CommandBarSearch.normalized(query)
        guard !normalized.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for length in 1...min(normalized.count, longestPrefix) {
            let prefix = String(normalized.prefix(length))
                .trimmingCharacters(in: .whitespaces)
            guard !prefix.isEmpty, seen.insert(prefix).inserted else { continue }
            result.append(prefix)
        }
        return result
    }

    /// Notes that this row was the answer to what was typed. `step` counts
    /// choices, and only has to grow.
    mutating func record(query: String, id: String, step: Int) {
        for prefix in Self.prefixes(of: query) {
            var forPrefix = picks[prefix] ?? [:]
            var pick = forPrefix[id] ?? Pick(count: 0, step: step)
            pick.count = min(pick.count + 1, 99)
            pick.step = step
            forPrefix[id] = pick
            // The rows that answer to one prefix: the least chosen goes first,
            // so a row picked once by mistake cannot hold a place forever.
            if forPrefix.count > Self.idsPerQuery {
                let surplus = forPrefix.sorted {
                    $0.value.count != $1.value.count
                        ? $0.value.count < $1.value.count
                        : $0.value.step < $1.value.step
                }.prefix(forPrefix.count - Self.idsPerQuery)
                for entry in surplus { forPrefix.removeValue(forKey: entry.key) }
            }
            picks[prefix] = forPrefix
        }
        guard picks.count > Self.queryLimit else { return }
        // And the prefixes themselves: the ones not used for longest go.
        let stale = picks.sorted {
            ($0.value.values.map(\.step).max() ?? 0) < ($1.value.values.map(\.step).max() ?? 0)
        }.prefix(picks.count - Self.queryLimit)
        for entry in stale { picks.removeValue(forKey: entry.key) }
    }

    /// What this row is worth for exactly these letters. Nothing at all for a
    /// row that was never chosen after them.
    func boost(query: String, id: String) -> Int {
        let prefix = CommandBarSearch.normalized(query)
        guard !prefix.isEmpty, let pick = picks[prefix]?[id] else { return 0 }
        return min(pick.count, 3) * (Self.maximumBoost / 3)
    }

    /// Forgets one row everywhere, for the person who asks the bar to stop
    /// putting it first.
    mutating func forget(id: String) {
        for (prefix, var forPrefix) in picks where forPrefix[id] != nil {
            forPrefix.removeValue(forKey: id)
            if forPrefix.isEmpty { picks.removeValue(forKey: prefix) } else { picks[prefix] = forPrefix }
        }
    }

    mutating func clear() {
        picks.removeAll()
    }

    var isEmpty: Bool { picks.isEmpty }
}
