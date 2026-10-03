// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TouchIDGuardTests {
    static func run(_ suite: TestSuite) {
        typealias Guard = TouchIDGuardSupport

        suite.expect(Guard.isPress(eventType: 14, subtype: 16), "the Touch ID press is a system-defined subtype 16")
        suite.expect(!Guard.isPress(eventType: 14, subtype: 8), "media keys are not the press")
        suite.expect(!Guard.isPress(eventType: 14, subtype: 7), "pointer buttons are not the press")
        suite.expect(!Guard.isPress(eventType: 10, subtype: 16), "a key event is never the press")

        let button: UInt64 = 0x1_0000_0323
        suite.expect(Guard.isBuiltInPress(senderID: Int64(bitPattern: button), builtInButtonID: button),
                     "a press the built-in button sent is the guard's")
        suite.expect(!Guard.isBuiltInPress(senderID: 0x1_0000_0B5F, builtInButtonID: button),
                     "the same event from another keyboard is left to macOS")
        suite.expect(!Guard.isBuiltInPress(senderID: 0, builtInButtonID: button),
                     "a press with no sender is left to macOS")
        suite.expect(!Guard.isBuiltInPress(senderID: Int64(bitPattern: button), builtInButtonID: nil),
                     "without a built-in button nothing is the guard's")

        suite.expect(!Guard.isDown([0, 0, 0, 0]), "a zero state is released")
        suite.expect(Guard.isDown([1, 0, 0, 0]), "a non-zero state is down")
        suite.expect(!Guard.isDown([]), "an empty read is not down")

        suite.expect(Guard.sanitizedHoldDuration(.nan) == Guard.defaultHoldDurationMilliseconds,
                     "a non-finite duration falls back to the default")
        suite.expect(Guard.sanitizedHoldDuration(0) == 400, "a short duration is raised to the minimum")
        suite.expect(Guard.sanitizedHoldDuration(9_000) == 2_000, "a long duration is capped at the maximum")
        suite.expect(Guard.sanitizedHoldDuration(800) == 800, "a duration in range is kept")

        suite.expect(Guard.modeFor(nil) == .hold, "the mode defaults to hold")
        suite.expect(Guard.modeFor("ignore") == .ignore, "ignore is read back")
        suite.expect(Guard.modeFor("nonsense") == .hold, "an unknown mode falls back to hold")

        // A tap is over before the event even arrives.
        suite.expect(Guard.verdict(elapsedSinceEventMilliseconds: 0, down: false,
                                   holdDurationMilliseconds: 800) == .released,
                     "a button already up when the event arrives was a tap")
        // The finger went down 300 ms before the event, so 800 ms is 500 ms later.
        suite.expect(Guard.verdict(elapsedSinceEventMilliseconds: 0, down: true,
                                   holdDurationMilliseconds: 800) == .waiting,
                     "a press seen at the event is still short of 800 ms")
        suite.expect(Guard.verdict(elapsedSinceEventMilliseconds: 499, down: true,
                                   holdDurationMilliseconds: 800) == .waiting,
                     "one millisecond short of the hold keeps waiting")
        suite.expect(Guard.verdict(elapsedSinceEventMilliseconds: 500, down: true,
                                   holdDurationMilliseconds: 800) == .reached,
                     "the press reaches the hold at its duration counted from the finger down")
        suite.expect(Guard.verdict(elapsedSinceEventMilliseconds: 300, down: false,
                                   holdDurationMilliseconds: 800) == .released,
                     "releasing before the hold cancels it")
        suite.expect(Guard.verdict(elapsedSinceEventMilliseconds: 0, down: true,
                                   holdDurationMilliseconds: 0) == .waiting,
                     "an out-of-range duration is clamped, so 0 means the 400 ms minimum")
        suite.expect(Guard.verdict(elapsedSinceEventMilliseconds: 100, down: true,
                                   holdDurationMilliseconds: 0) == .reached,
                     "the clamped minimum is reached 100 ms after the event")

        let budget = Guard.pollBudgetMilliseconds(holdDurationMilliseconds: 800)
        suite.expect(budget > 500 && budget < 700,
                     "the poll budget covers the wait left plus a short margin: \(budget)")
        suite.expect(Guard.pollBudgetMilliseconds(holdDurationMilliseconds: 400) < 300,
                     "the shortest hold polls only briefly")
    }
}
