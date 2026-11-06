// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind monitor speaker volume: the step grid, which audio
/// outputs belong to a display, which display an output plays through, mute
/// and key ownership. No display or audio device is touched.
enum DDCVolumeSupportTests {
    static func run(_ suite: TestSuite) {
        steps(suite)
        limits(suite)
        transport(suite)
        matching(suite)
        mute(suite)
        keys(suite)
    }

    private static func steps(_ suite: TestSuite) {
        typealias S = DDCVolumeSupport
        suite.expect(S.volumeCode == 0x62, "speaker volume is VCP 0x62")
        suite.expect(S.steppedValue(current: 50, maximum: 100, direction: 1) == 56,
                     "the default step matches macOS: 50 of 100 moves up to the next sixteenth (56)")
        suite.expect(S.steppedValue(current: 50, maximum: 100, direction: -1) == 44,
                     "a default step down from 50 of 100 lands on the previous sixteenth (44)")
        suite.expect(S.steppedValue(current: 50, maximum: 100, direction: 1, stepPercent: 1) == 51,
                     "a 1% step moves one point")
        suite.expect(S.steppedValue(current: 50, maximum: 100, direction: -1, stepPercent: 2) == 48,
                     "a 2% step moves two points")
        suite.expect(S.steppedValue(current: 20, maximum: 50, direction: 1, stepPercent: 10) == 25,
                     "steps scale with the monitor's own range")
        suite.expect(S.steppedValue(current: 50, maximum: 100, direction: 1, stepPercent: 6.25 / 4) == 52,
                     "Option-Shift moves a quarter of the step")
        suite.expect(S.steppedValue(current: 10, maximum: 20, direction: 1, stepPercent: 1) == 11,
                     "a step smaller than one device unit still moves one unit")
        suite.expect(S.steppedValue(current: 100, maximum: 100, direction: 1) == 100,
                     "volume never passes the monitor's maximum")
        suite.expect(S.steppedValue(current: 0, maximum: 100, direction: -1) == 0,
                     "volume never goes below zero")
        suite.expect(S.steppedValue(current: 3, maximum: 100, direction: 1) == 6,
                     "a level off the grid snaps to the nearest step before moving")
        suite.expect(S.steppedValue(current: 50, maximum: 100, direction: 3) == 69,
                     "coalesced key repeats move several steps at once")
        suite.expect(S.steppedValue(current: 10, maximum: 0, direction: 1) == 19,
                     "a monitor reporting no range is treated as 0-100")
        suite.expect(S.steppedValue(current: 200, maximum: 100, direction: -1) == 94,
                     "a reading above the maximum is clamped before stepping")
        suite.expect(S.sanitizedStep(0) == S.defaultStepPercent, "a missing step reads as the default")
        suite.expect(S.sanitizedStep(.nan) == S.defaultStepPercent, "a broken step reads as the default")
        suite.expect(S.sanitizedStep(90) == 25, "a step is capped at a quarter of the range")
        suite.expect(S.stepChoices.contains(S.defaultStepPercent), "the default step is one of the choices")
        suite.expectClose(S.level(value: 25, maximum: 50), 0.5, "level is value over maximum")
        suite.expectClose(S.level(value: 80, maximum: 0), 0.8, "a missing range reads as 0-100")
    }

    private static func limits(_ suite: TestSuite) {
        typealias S = DDCVolumeSupport
        let range = S.VolumeLimits.sanitized(minimum: 20, maximum: 70)
        suite.expect(S.steppedValue(current: 70, maximum: 100, direction: 1, stepPercent: 5, limits: range) == 70,
                     "volume up stops at the maximum limit")
        suite.expect(S.steppedValue(current: 20, maximum: 100, direction: -1, stepPercent: 5, limits: range) == 20,
                     "volume down stops at the minimum limit")
        suite.expect(S.steppedValue(current: 90, maximum: 100, direction: -1, stepPercent: 5, limits: range) == 70,
                     "a level set above the limit on the monitor comes back inside it")
        suite.expect(S.steppedValue(current: 50, maximum: 200, direction: 1, stepPercent: 5, limits: range) == 60,
                     "limits are percentages of the monitor's own range")
        suite.expect(S.steppedValue(current: 0, maximum: 100, direction: 0, limits: range) == 20,
                     "direction zero only applies the limits")
        suite.expect(S.VolumeLimits.sanitized(minimum: 80, maximum: 30)
                        == S.VolumeLimits(minimumPercent: 29, maximumPercent: 30),
                     "a minimum above the maximum yields to it")
        suite.expect(S.VolumeLimits.sanitized(minimum: -5, maximum: 0) == .full,
                     "missing limits read as the full range")
        suite.expect(S.VolumeLimits.sanitized(minimum: 0, maximum: 400).maximumPercent == 100,
                     "the maximum never passes 100%")
    }

    private static func transport(_ suite: TestSuite) {
        typealias S = DDCVolumeSupport
        suite.expect(S.isDisplayAudio(transportType: 0x6470_7274), "DisplayPort audio is display audio")
        suite.expect(S.isDisplayAudio(transportType: 0x6864_6D69), "HDMI audio is display audio")
        suite.expect(!S.isDisplayAudio(transportType: 0x7573_6220), "USB audio keeps the system keys")
        suite.expect(!S.isDisplayAudio(transportType: 0x626C_7468), "Bluetooth audio keeps the system keys")
        suite.expect(!S.isDisplayAudio(transportType: 0x626C_746E), "built-in audio keeps the system keys")
    }

    private static func matching(_ suite: TestSuite) {
        typealias S = DDCVolumeSupport
        let two: [(id: UInt32, name: String)] = [(1, "LG HDR 4K"), (2, "DELL U2723QE")]
        suite.expect(S.matchDisplay(outputName: "LG HDR 4K", displays: two) == 1,
                     "an output named after a display plays through it")
        suite.expect(S.matchDisplay(outputName: "dell u2723qe", displays: two) == 2,
                     "names match regardless of case and punctuation")
        suite.expect(S.matchDisplay(outputName: "U2723QE", displays: two) == 2,
                     "a name missing the vendor prefix still matches")
        suite.expect(S.matchDisplay(outputName: "Studio Display", displays: two) == nil,
                     "with two displays and no matching name the keys stay with the system")
        suite.expect(S.matchDisplay(outputName: "Monitor", displays: [(7, "LG HDR 4K")]) == 7,
                     "a single DDC display is the only place display audio can play")
        suite.expect(S.matchDisplay(outputName: "LG HDR 4K", displays: []) == nil,
                     "no DDC display, no target")
        let same: [(id: UInt32, name: String)] = [(1, "LG HDR 4K"), (2, "LG HDR 4K")]
        suite.expect(S.matchDisplay(outputName: "LG HDR 4K", displays: same) == nil,
                     "two identical monitors are ambiguous and left to the system")
    }

    private static func mute(_ suite: TestSuite) {
        var state = DDCVolumeSupport.MuteState()
        suite.expect(!state.isMuted, "a display starts unmuted")
        suite.expect(state.toggle(current: 40, maximum: 100) == 0, "muting writes zero")
        suite.expect(state.isMuted, "muting is remembered")
        suite.expect(state.toggle(current: 0, maximum: 100) == 40, "unmuting restores the previous level")
        suite.expect(!state.isMuted, "unmuting clears the state")

        _ = state.toggle(current: 30, maximum: 100)
        suite.expect(state.unmuteForStep(current: 0) == 30,
                     "a volume key while muted steps from the remembered level")
        suite.expect(!state.isMuted, "a volume key unmutes")

        _ = state.toggle(current: 0, maximum: 100)
        suite.expect(state.toggle(current: 0, maximum: 100) == 6,
                     "unmuting what was muted from silence restores one step, not silence")

        let range = DDCVolumeSupport.VolumeLimits.sanitized(minimum: 0, maximum: 60)
        _ = state.toggle(current: 90, maximum: 100, limits: range)
        suite.expect(state.toggle(current: 0, maximum: 100, limits: range) == 60,
                     "unmuting a level above the maximum limit restores the limit instead")
    }

    private static func keys(_ suite: TestSuite) {
        typealias S = DDCVolumeSupport
        func data1(_ code: Int, _ state: Int, repeated: Bool = false) -> Int {
            (code << 16) | (state << 8) | (repeated ? 1 : 0)
        }
        suite.expect(S.keyPress(fromData1: data1(0, 0x0a)) == S.KeyPress(key: .volumeUp, isDown: true, isRepeat: false),
                     "volume up press parses")
        suite.expect(S.keyPress(fromData1: data1(1, 0x0b)) == S.KeyPress(key: .volumeDown, isDown: false, isRepeat: false),
                     "volume down release parses")
        suite.expect(S.keyPress(fromData1: data1(7, 0x0a, repeated: true)) == S.KeyPress(key: .mute, isDown: true, isRepeat: true),
                     "mute repeat parses")
        suite.expect(S.keyPress(fromData1: data1(2, 0x0a)) == nil, "brightness keys are not volume keys")
        suite.expect(S.keyPress(fromData1: data1(16, 0x0a)) == nil, "play is not a volume key")
        suite.expect(S.keyPress(fromData1: data1(0, 0x05)) == nil, "unknown key states are ignored")

        var ownership = S.KeyOwnership()
        suite.expect(!ownership.releases(.volumeUp), "a release of a press left to the system goes to the system")
        ownership.claim(.volumeUp)
        suite.expect(ownership.releases(.volumeUp), "a release of a claimed press is taken too")
        suite.expect(!ownership.releases(.volumeUp), "each claim covers one release")
    }
}
