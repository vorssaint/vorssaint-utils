// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Vorssaint's own Command-Q, held before it quits.
enum OwnQuitHoldTests {
    static func run(_ suite: TestSuite) {
        let duration = OwnQuitHold.duration

        // A quick press shows the reminder and never quits.
        var tap = OwnQuitHold()
        let tapStart = tap.keyDown(isCommandQ: true, isRepeat: false, confirmedElsewhere: false, at: 10)
        let tapEarly = tap.tick(stillHeld: true, at: 10 + duration / 4)
        let tapRelease = tap.tick(stillHeld: false, at: 10 + duration / 2)
        let tapAfter = tap.tick(stillHeld: false, at: 10 + duration * 2)
        suite.expect(tapStart == .begin && tapEarly == .wait && tapRelease == .cancel
                && tapAfter == .wait && !tap.isHolding,
               "a quick Command-Q shows the reminder and is cancelled on release, not quit later")

        // Holding through the deadline quits once; the key repeats meanwhile
        // never restart the hold or reach the Quit menu item.
        var held = OwnQuitHold()
        _ = held.keyDown(isCommandQ: true, isRepeat: false, confirmedElsewhere: false, at: 0)
        let repeatWhileHeld = held.keyDown(isCommandQ: true, isRepeat: true, confirmedElsewhere: false, at: 0.4)
        let beforeDeadline = held.tick(stillHeld: true, at: duration - 0.01)
        let atDeadline = held.tick(stillHeld: true, at: duration)
        let afterQuit = held.tick(stillHeld: true, at: duration + 0.1)
        suite.expect(repeatWhileHeld == .swallow && beforeDeadline == .wait
                && atDeadline == .quit && afterQuit == .wait,
               "holding Command-Q through the deadline quits exactly once and swallows the repeats")

        // A second hold after a cancelled one starts its own clock.
        var again = OwnQuitHold()
        _ = again.keyDown(isCommandQ: true, isRepeat: false, confirmedElsewhere: false, at: 0)
        _ = again.tick(stillHeld: false, at: duration * 0.9)
        let restart = again.keyDown(isCommandQ: true, isRepeat: false, confirmedElsewhere: false, at: duration)
        let notYet = again.tick(stillHeld: true, at: duration * 1.5)
        suite.expect(restart == .begin && notYet == .wait,
               "a new press after an early release needs its own full hold")

        // Everything that is not a fresh, unconfirmed Command-Q passes.
        var other = OwnQuitHold()
        let typing = other.keyDown(isCommandQ: false, isRepeat: false, confirmedElsewhere: false, at: 0)
        let replayed = other.keyDown(isCommandQ: true, isRepeat: false, confirmedElsewhere: true, at: 0)
        suite.expect(typing == .pass && replayed == .pass && !other.isHolding,
               "other keys and a press Quit Protection already had held pass through untouched")

        // A repeat with no hold running (the press began before the setting
        // was turned on) is swallowed rather than quitting.
        var stray = OwnQuitHold()
        let strayRepeat = stray.keyDown(isCommandQ: true, isRepeat: true, confirmedElsewhere: false, at: 0)
        suite.expect(strayRepeat == .swallow && !stray.isHolding,
               "a Command-Q repeat outside a hold never reaches the Quit menu item")

        suite.expect(duration == QuitProtectionSupport.defaultHoldDurationMilliseconds / 1_000,
               "Vorssaint's own hold matches Quit Protection's default for other apps")
    }
}
