// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The estimate a conversion's bar shows while its work gives no reading of its own.
enum JobProgressEstimate {
    /// How long a reading counts as current; real progress gets this long before the estimate moves.
    static let readingGrace: TimeInterval = 0.8
    /// The estimate never claims more than this; only finishing reaches the end.
    static let ceiling = 0.95

    /// Rises quickly at first and slows as it nears the ceiling, reaching
    /// about two thirds of it at the expected time.
    static func estimate(elapsed: TimeInterval, expected: TimeInterval) -> Double {
        guard elapsed > 0, expected > 0, elapsed.isFinite, expected.isFinite else { return 0 }
        return ceiling * (1 - exp(-elapsed / expected))
    }

    /// Between a second and a bit and ten minutes, from the file's size.
    static func expectedSeconds(bytes: Double, bytesPerSecond: Double) -> TimeInterval {
        guard bytes.isFinite, bytesPerSecond > 0 else { return 4 }
        return min(600, max(1.2, bytes / bytesPerSecond))
    }
}
