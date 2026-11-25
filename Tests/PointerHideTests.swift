// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PointerHideTests {
    static func run(_ suite: TestSuite) {
        let low = PointerHideSupport.thresholdRange.lowerBound
        let high = PointerHideSupport.thresholdRange.upperBound
        let standard = PointerHideSupport.defaultThreshold

        // MARK: Movement outranks the threshold

        suite.expect(!PointerHideSupport.shouldHide(idleSeconds: .greatestFiniteMagnitude,
                                                    thresholdEnabled: true,
                                                    threshold: standard,
                                                    pointerMoved: true),
                   "a move on this very tick ends the hiding however long the pointer had been still")
        suite.expect(!PointerHideSupport.shouldHide(idleSeconds: standard,
                                                    thresholdEnabled: true,
                                                    threshold: standard,
                                                    pointerMoved: true),
                   "a move at the exact hide boundary still ends the hiding")

        // MARK: The feature can be switched off

        suite.expect(!PointerHideSupport.shouldHide(idleSeconds: .greatestFiniteMagnitude,
                                                    thresholdEnabled: false,
                                                    threshold: standard,
                                                    pointerMoved: false),
                   "with the threshold off an unbounded idle reading never hides the cursor")
        suite.expect(!PointerHideSupport.shouldHide(idleSeconds: 0,
                                                    thresholdEnabled: false,
                                                    threshold: standard,
                                                    pointerMoved: false),
                   "with the threshold off nothing hides on the first tick either")

        // MARK: The boundary is inclusive

        suite.expect(PointerHideSupport.shouldHide(idleSeconds: standard,
                                                   thresholdEnabled: true,
                                                   threshold: standard,
                                                   pointerMoved: false),
                   "an idle reading that has reached the threshold exactly is already long enough")
        suite.expect(!PointerHideSupport.shouldHide(idleSeconds: standard.nextDown,
                                                    thresholdEnabled: true,
                                                    threshold: standard,
                                                    pointerMoved: false),
                   "one representable step short of the threshold is still too soon")

        // MARK: A stored threshold out of range is clamped, never obeyed

        for broken in [0.0, -1, -standard, .greatestFiniteMagnitude, high * 100] {
            let usable = PointerHideSupport.sanitizedThreshold(broken)
            suite.expect(!PointerHideSupport.shouldHide(idleSeconds: usable.nextDown,
                                                        thresholdEnabled: true,
                                                        threshold: broken,
                                                        pointerMoved: false),
                       "an unusable threshold of \(broken) waits rather than hiding the moment it is enabled")
            suite.expect(PointerHideSupport.shouldHide(idleSeconds: usable,
                                                       thresholdEnabled: true,
                                                       threshold: broken,
                                                       pointerMoved: false),
                       "an unusable threshold of \(broken) still hides eventually rather than never")
        }

        // MARK: Sanitizing a stored value

        suite.expect(PointerHideSupport.sanitizedThreshold(low - 1) == low
                && PointerHideSupport.sanitizedThreshold(0) == low
                && PointerHideSupport.sanitizedThreshold(-standard) == low,
               "a threshold under the range is raised to its lower bound")
        suite.expect(PointerHideSupport.sanitizedThreshold(high + 1) == high
                && PointerHideSupport.sanitizedThreshold(high * 100) == high
                && PointerHideSupport.sanitizedThreshold(.greatestFiniteMagnitude) == high,
               "a threshold over the range is pulled back to its upper bound")
        suite.expect(PointerHideSupport.sanitizedThreshold(.nan) == standard
                && PointerHideSupport.sanitizedThreshold(.infinity) == standard
                && PointerHideSupport.sanitizedThreshold(-.infinity) == standard,
               "a threshold that is not a number at all becomes the default")
        suite.expect(PointerHideSupport.sanitizedThreshold(standard) == standard
                && PointerHideSupport.sanitizedThreshold(low) == low
                && PointerHideSupport.sanitizedThreshold(high) == high,
               "a threshold already inside the range is left exactly as stored")
        suite.expect(low <= standard && standard <= high,
               "the default threshold is itself a usable one")

        // MARK: Each escape stands alone

        // Four separate assertions on purpose: one combined check would still
        // pass with a term of the OR missing.
        suite.expect(PointerHideSupport.shouldShow(pointerMoved: true, keyPressed: false,
                                                   displayAsleep: false, screenLocked: false),
                   "pointer movement alone brings the cursor back")
        suite.expect(PointerHideSupport.shouldShow(pointerMoved: false, keyPressed: true,
                                                   displayAsleep: false, screenLocked: false),
                   "a key press alone brings the cursor back")
        suite.expect(PointerHideSupport.shouldShow(pointerMoved: false, keyPressed: false,
                                                   displayAsleep: true, screenLocked: false),
                   "the displays sleeping alone brings the cursor back")
        suite.expect(PointerHideSupport.shouldShow(pointerMoved: false, keyPressed: false,
                                                   displayAsleep: false, screenLocked: true),
                   "the screen locking alone brings the cursor back")
        suite.expect(!PointerHideSupport.shouldShow(pointerMoved: false, keyPressed: false,
                                                    displayAsleep: false, screenLocked: false),
                   "nothing happening means nothing is brought back, however long the cursor has been hidden")

        // MARK: The switched-off service is inert

        // `PointerHideService` is a singleton that owns a run-loop timer and
        // reads and writes the shared defaults, so it is deliberately never
        // built here. The rule its disabled path runs on is this one: an
        // in-range threshold is unreachable while the feature is off, so a
        // second `setEnabled(false)` has no tick left to act on and the cursor
        // it would show is already visible.
        let idleAfterOneTick = standard * 1_000
        suite.expect(!PointerHideSupport.shouldHide(idleSeconds: 0,
                                                    thresholdEnabled: false,
                                                    threshold: standard,
                                                    pointerMoved: false)
                && !PointerHideSupport.shouldHide(idleSeconds: idleAfterOneTick,
                                                  thresholdEnabled: false,
                                                  threshold: standard,
                                                  pointerMoved: false)
                && !PointerHideSupport.shouldHide(idleSeconds: idleAfterOneTick,
                                                  thresholdEnabled: false,
                                                  threshold: brokenHigh,
                                                  pointerMoved: false),
               "every tick of a disabled service reaches the same no-op decision")
    }

    /// A threshold that needs clamping from above, named so the intent reads at
    /// the call site above.
    private static var brokenHigh: Double { 1_000 }
}
