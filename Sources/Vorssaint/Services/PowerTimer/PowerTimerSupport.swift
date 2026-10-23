// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PowerTimerAction: String, CaseIterable {
    case sleep, shutDown
}

/// Durations use an uptime deadline so changing the system clock does not
/// shorten them. Clock-time schedules deliberately follow the wall clock.
struct PowerTimerSession: Equatable {
    let action: PowerTimerAction
    let displayDate: Date
    let uptimeDeadline: TimeInterval?

    static func minutes(from input: String) -> Int? {
        guard let value = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...1440).contains(value) else { return nil }
        return value
    }

    static func duration(_ minutes: Int, action: PowerTimerAction,
                         now: Date, uptime: TimeInterval) -> Self? {
        guard (1...1440).contains(minutes), uptime.isFinite else { return nil }
        let seconds = TimeInterval(minutes * 60)
        return Self(action: action, displayDate: now.addingTimeInterval(seconds),
                    uptimeDeadline: uptime + seconds)
    }

    static func clockTime(_ date: Date, action: PowerTimerAction, now: Date) -> Self? {
        let remaining = date.timeIntervalSince(now)
        guard remaining.isFinite, remaining > 0, remaining <= 86400 else { return nil }
        return Self(action: action, displayDate: date, uptimeDeadline: nil)
    }

    func remaining(now: Date, uptime: TimeInterval) -> TimeInterval {
        max(0, uptimeDeadline.map { $0 - uptime } ?? displayDate.timeIntervalSince(now))
    }
}
