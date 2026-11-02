// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure rules for the duplicate finder. The promise they protect: at least
/// one copy of every file always stays, and a copy is only removed if it
/// still looks exactly as it did when the scan read it.
enum DuplicateFileSupport {
    /// Size thresholds offered in the picker, smallest first.
    static let minimumSizes: [Int64] = [1_000_000, 10_000_000, 100_000_000]
    /// How much of a file the cheap first comparison reads.
    static let partialReadBytes = 64 * 1024
    /// The list stops at this many groups so a huge result stays readable.
    static let maxGroups = 100

    /// Whether ticking one more copy would leave the group with no copy left
    /// unticked. `tickedCount` counts copies already ticked, not including
    /// the one being asked about.
    static func mayTick(tickedCount: Int, groupCount: Int) -> Bool {
        tickedCount + 1 < groupCount
    }

    /// The copy that stays by default: the oldest by modification date, and
    /// among equals the first in the list. A copy without a date is only
    /// chosen when every copy lacks one.
    static func defaultKeepIndex(modified: [Date?]) -> Int {
        var best = 0
        for index in modified.indices.dropFirst() {
            switch (modified[best], modified[index]) {
            case let (current?, candidate?): if candidate < current { best = index }
            case (nil, _?): best = index
            default: break
            }
        }
        return best
    }

    /// Whether a copy still matches what the scan saw, so a file edited after
    /// the scan is never removed on the strength of an old comparison.
    static func unchanged(scannedSize: Int64, scannedModified: Date?,
                          currentSize: Int64?, currentModified: Date?) -> Bool {
        currentSize == scannedSize && currentModified == scannedModified
    }

    /// Largest reclaimable space first, trimmed to the cap. Reclaimable space
    /// is the size times every copy but one.
    static func ranked<T>(_ groups: [T], size: (T) -> Int64, copies: (T) -> Int) -> [T] {
        Array(groups.sorted {
            size($0) * Int64(max(0, copies($0) - 1)) > size($1) * Int64(max(0, copies($1) - 1))
        }.prefix(maxGroups))
    }
}
