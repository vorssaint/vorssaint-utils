// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BatteryTimeSupport {
    static func remainingSeconds(timeToEmptyMinutes: Int?,
                                 externalConnected: Bool,
                                 isCharging: Bool) -> TimeInterval? {
        guard !externalConnected,
              !isCharging,
              let minutes = timeToEmptyMinutes,
              (1..<(7 * 24 * 60)).contains(minutes) else { return nil }
        return TimeInterval(minutes * 60)
    }

    static func formatted(seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let totalMinutes = max(1, Int(seconds / 60))
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }
}
