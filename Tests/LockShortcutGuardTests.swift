// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LockShortcutGuardTests {
    static func run(_ suite: TestSuite) {
        typealias Guard = LockShortcutGuardSupport

        let qwerty: [Int64: String] = [0: "a", 7: "x", 12: "q", 13: "w"]
        let azerty: [Int64: String] = [0: "q", 12: "a", 13: "z"]
        let dvorak: [Int64: String] = [7: "q", 12: "'"]
        let russianCommand: [Int64: String] = [12: "q"]
        suite.expect(Guard.lockKeyCode { qwerty[$0] } == 12, "QWERTY locks with the key at the US Q position")
        suite.expect(Guard.lockKeyCode { azerty[$0] } == 0,
                     "AZERTY registers the key that types Q, the one the Lock Screen menu item answers")
        suite.expect(Guard.lockKeyCode { dvorak[$0] } == 7, "Dvorak registers its own Q key")
        suite.expect(Guard.lockKeyCode { russianCommand[$0] } == 12,
                     "the Command table decides, like Command-Q does on a Russian layout")
        suite.expect(Guard.lockKeyCode { $0 == 12 ? "Q" : nil } == 12,
                     "an uppercase label still counts as Q")
        suite.expect(Guard.lockKeyCode { _ in nil } == 12, "the US position is used only while no layout can be read")

        suite.expect(Guard.quitProtectionOwnsShortcut(quitEnabled: true, quitMode: .extraModifier, extraModifier: .control),
                     "Command-Q protection confirming with Control owns Control-Command-Q")
        suite.expect(!Guard.quitProtectionOwnsShortcut(quitEnabled: false, quitMode: .extraModifier, extraModifier: .control),
                     "a Command-Q protection that is off owns nothing")
        suite.expect(!Guard.quitProtectionOwnsShortcut(quitEnabled: true, quitMode: .extraModifier, extraModifier: .shift),
                     "another extra key leaves Control-Command-Q to this guard")
        suite.expect(!Guard.quitProtectionOwnsShortcut(quitEnabled: true, quitMode: .hold, extraModifier: .control),
                     "a stored Control choice counts only while the extra key mode is picked")

        suite.expect(Guard.isSecondPress(after: 300, intervalMilliseconds: 600), "a second press inside the interval confirms")
        suite.expect(Guard.isSecondPress(after: 600, intervalMilliseconds: 600), "the interval's own end still confirms")
        suite.expect(!Guard.isSecondPress(after: 601, intervalMilliseconds: 600), "a later press starts over")
        suite.expect(!Guard.isSecondPress(after: -1, intervalMilliseconds: 600), "a clock that went back never confirms")
        suite.expect(Guard.isSecondPress(after: 1_400, intervalMilliseconds: 9_000)
                        && !Guard.isSecondPress(after: 1_600, intervalMilliseconds: 9_000),
                     "an out-of-range interval is clamped to Quit Protection's limit")

        suite.expect(Guard.holdSurvivesFlagsChange(control: true, command: true),
                     "a hold goes on, and locks at its time, while both modifiers are down")
        suite.expect(!Guard.holdSurvivesFlagsChange(control: false, command: true),
                     "letting go of Control ends the hold")
        suite.expect(!Guard.holdSurvivesFlagsChange(control: true, command: false),
                     "letting go of Command ends the hold")

        suite.expect(Guard.modeFor(nil) == .hold, "the mode defaults to hold")
        suite.expect(Guard.modeFor("doublePress") == .doublePress, "double press is read back")
        suite.expect(Guard.modeFor("extraModifier") == .hold, "a mode this guard lacks falls back to hold")
        suite.expect(Guard.holdDurationRange == QuitProtectionSupport.holdDurationRange,
                     "the hold limits are the ones Quit Protection uses")
    }
}
