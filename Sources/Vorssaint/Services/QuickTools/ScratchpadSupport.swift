// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How long the scratchpad keeps text that nobody edits. The check runs only
/// when the pad opens, against the buffer file's modification date, so the
/// feature needs no timer at all.
enum ScratchpadRetention: String, CaseIterable {
    case never
    case day
    case week
    case month

    /// Seconds the text may sit unedited before it clears; nil keeps forever.
    var maxIdleInterval: TimeInterval? {
        switch self {
        case .never: return nil
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        }
    }

    /// Corrupt or unknown stored values fall back to keeping the text.
    static func sanitized(_ rawValue: String?) -> ScratchpadRetention {
        guard let rawValue,
              let retention = ScratchpadRetention(rawValue: rawValue) else {
            return .never
        }
        return retention
    }
}

enum ScratchpadSupport {
    /// Whether the saved text expired: it only clears when a retention period
    /// is chosen and the last edit is older than that period. No saved text
    /// (or a clock that moved backwards) never clears.
    static func shouldClear(lastEdited: Date?, now: Date, retention: ScratchpadRetention) -> Bool {
        guard let limit = retention.maxIdleInterval, let lastEdited else { return false }
        let idle = now.timeIntervalSince(lastEdited)
        return idle > limit
    }

    /// Suggested name for the exported file, like "Scratchpad 2026-07-17.txt".
    static func exportFileName(title: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(title) \(formatter.string(from: date)).txt"
    }
}
