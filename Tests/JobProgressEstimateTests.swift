// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The conversion bar's estimate between real readings.
enum JobProgressEstimateTests {
    static func run(_ suite: TestSuite) {
        let start = JobProgressEstimate.estimate(elapsed: 0, expected: 4)
        let soon = JobProgressEstimate.estimate(elapsed: 0.5, expected: 4)
        let atExpected = JobProgressEstimate.estimate(elapsed: 4, expected: 4)
        let long = JobProgressEstimate.estimate(elapsed: 400, expected: 4)
        suite.expect(start == 0 && soon > 0.08 && soon < atExpected && atExpected < long,
                     "the bar leaves zero at once and keeps moving while the work goes on")
        suite.expect(abs(atExpected - JobProgressEstimate.ceiling * (1 - exp(-1))) < 0.000_1
                        && long <= JobProgressEstimate.ceiling && long < 1,
                     "the estimate slows toward a ceiling short of done, which only finishing reaches")
        suite.expect(JobProgressEstimate.estimate(elapsed: .infinity, expected: 4) == 0
                        && JobProgressEstimate.estimate(elapsed: 3, expected: 0) == 0,
                     "an unreadable clock or expectation shows nothing rather than a wrong figure")
        suite.expect(JobProgressEstimate.expectedSeconds(bytes: 0, bytesPerSecond: 1_000_000) == 1.2
                        && JobProgressEstimate.expectedSeconds(bytes: 60_000_000, bytesPerSecond: 6_000_000) == 10
                        && JobProgressEstimate.expectedSeconds(bytes: 1e15, bytesPerSecond: 1) == 600
                        && JobProgressEstimate.expectedSeconds(bytes: 100, bytesPerSecond: 0) == 4,
                     "bigger files are expected to take longer, within sensible bounds")
    }
}
