// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

enum SoftwareOutputVolumeTests {
    static func run(_ suite: TestSuite) {
        engagement(suite)
        exclusions(suite)
        keys(suite)
        storage(suite)
        limits(suite)
    }

    private static let x34 = "AppleGFXHDAEngineOutputDP:10001:0:{4C41-3482-00000000}"

    private static func volume(_ level: Double, muted: Bool = false, uid: String = x34) -> SoftwareOutputVolume {
        SoftwareOutputVolume(outputUID: uid, stored: ["level": level, "muted": muted],
                             settings: MonitorVolumeKeySettings())!
    }

    private static func engagement(_ suite: TestSuite) {
        func engages(enabled: Bool = true, settable: Bool = false, monitorSpeakers: Bool = false,
                     permitted: Bool = true, level: Double = 0.5, muted: Bool = false) -> Bool {
            SoftwareOutputVolume.engages(featureEnabled: enabled, outputHasSettableVolume: settable,
                                         hasMonitorSpeakerControl: monitorSpeakers,
                                         audioCapturePermitted: permitted,
                                         volume: volume(level, muted: muted))
        }
        suite.expect(engages(), "a lowered level on an output without volume control engages")
        suite.expect(!engages(enabled: false), "the feature stays off until the person turns it on")
        suite.expect(!engages(settable: true), "an output with its own volume keeps the system volume")
        suite.expect(!engages(monitorSpeakers: true), "DDC monitor speakers keep their own route")
        suite.expect(!engages(permitted: false), "no engine runs without System Audio Recording")
        suite.expect(!engages(level: 1), "an untouched level leaves the audio path alone")
        suite.expect(engages(level: 1, muted: true), "mute at full level still needs the engine")
        suite.expect(engages(level: 0), "silence needs the engine")
    }

    private static func exclusions(_ suite: TestSuite) {
        let own = AudioObjectID(90)
        suite.expect(SoftwareOutputVolume.excludedProcesses(own: own, perAppTapped: []) == [own],
                     "with no adjusted app the tap leaves out only Vorssaint")
        suite.expect(SoftwareOutputVolume.excludedProcesses(own: own, perAppTapped: [41, 12, 41, own]) == [own, 12, 41],
                     "every adjusted app is left out once, in a stable order, so it never plays twice")
        suite.expect(SoftwareOutputVolume.excludedProcesses(own: own, perAppTapped: [12])
                        != SoftwareOutputVolume.excludedProcesses(own: own, perAppTapped: [12, 41]),
                     "a newly adjusted app changes the list, so the tap is rebuilt")
    }

    private static func keys(_ suite: TestSuite) {
        let settings = MonitorVolumeKeySettings(stepPercent: 10, minimumPercent: 20, maximumPercent: 70)
        func stepped(_ start: Double, _ direction: Int, muted: Bool = false, fine: Bool = false) -> SoftwareOutputVolume {
            var value = SoftwareOutputVolume(outputUID: x34, stored: ["level": start, "muted": muted],
                                             settings: settings)!
            value.step(direction, fine: fine, settings: settings)
            return value
        }

        suite.expectClose(stepped(0.5, 1).level, 0.6, "volume up moves one step")
        suite.expectClose(stepped(0.65, 1).level, 0.7, "volume up stops at the maximum")
        suite.expectClose(stepped(0.7, 1).level, 0.7, "volume up at the maximum changes nothing")
        suite.expectClose(stepped(0.5, -1).level, 0.4, "volume down moves one step")
        suite.expectClose(stepped(0.25, -1).level, 0.2, "volume down stops at the minimum")
        suite.expectClose(stepped(0.2, -1).level, 0.2, "volume down at the minimum changes nothing")
        suite.expectClose(stepped(0.5, 1, fine: true).level, 0.51, "a fine press moves one percent, as the monitor keys do")

        let unmuted = stepped(0.4, 1, muted: true)
        suite.expect(!unmuted.muted, "volume up ends a mute")
        suite.expectClose(unmuted.level, 0.5, "volume up after a mute steps from the level before the mute")

        var toggled = volume(0.4)
        toggled.toggleMute()
        suite.expect(toggled.muted && toggled.gain == 0, "mute silences the output")
        toggled.toggleMute()
        suite.expect(!toggled.muted, "a second mute press brings the audio back")
        suite.expectClose(toggled.level, 0.4, "the audio comes back at the level before the mute")

        let floorless = MonitorVolumeKeySettings(stepPercent: 10)
        var down = SoftwareOutputVolume(outputUID: x34, stored: ["level": 0.1], settings: floorless)!
        down.step(-1, fine: false, settings: floorless)
        suite.expect(down.level == 0 && down.muted, "reaching zero mutes, as macOS does for its own outputs")
        down.step(1, fine: false, settings: floorless)
        suite.expect(!down.muted, "volume up from zero ends the mute")
        suite.expectClose(down.level, 0.1, "volume up from zero comes back one step above zero")
    }

    private static func storage(_ suite: TestSuite) {
        let settings = MonitorVolumeKeySettings(maximumPercent: 80)
        func level(_ stored: Any?) -> Double? {
            SoftwareOutputVolume(outputUID: x34, stored: stored, settings: settings)?.level
        }
        suite.expect(level(nil) == 0.8, "an output with no saved level starts at the maximum")
        suite.expect(level(["level": Double.nan]) == 0.8, "a non-finite saved level falls back to the maximum")
        suite.expect(level(["level": -0.5]) == 0.8, "a negative saved level falls back to the maximum")
        suite.expect(level(["level": 1.5]) == 0.8, "a saved level above full scale falls back to the maximum")
        suite.expect(level(["level": 0.9]) == 0.8, "a saved level above a lowered maximum is clamped to it")
        suite.expect(level(["level": "loud"]) == 0.8, "a saved level of the wrong type falls back to the maximum")
        suite.expect(level(["level": 0.3, "muted": "yes"]) == 0.3, "a malformed mute flag keeps the level")
        suite.expect(SoftwareOutputVolume(outputUID: "", stored: nil, settings: settings) == nil,
                     "an output without a UID has nowhere to keep its level")

        var store: [String: Any] = [:]
        let quiet = volume(0.3, uid: x34)
        let other = volume(0.6, muted: true, uid: "BuiltInSpeakerDevice")
        store = SoftwareOutputVolume.saving(quiet, in: store)
        store = SoftwareOutputVolume.saving(other, in: store)
        suite.expect(SoftwareOutputVolume(outputUID: x34, stored: store[x34], settings: .init())?.level == 0.3
                        && SoftwareOutputVolume(outputUID: "BuiltInSpeakerDevice", stored: store["BuiltInSpeakerDevice"],
                                                settings: .init())?.muted == true,
                     "two outputs keep separate saved levels")
    }

    private static func limits(_ suite: TestSuite) {
        var loudest: Float = 0
        for level in stride(from: -1.0, through: 2.0, by: 0.01) {
            for muted in [false, true] {
                let value = SoftwareOutputVolume(outputUID: x34, stored: ["level": level, "muted": muted],
                                                 settings: MonitorVolumeKeySettings())!
                loudest = max(loudest, value.gain)
            }
        }
        suite.expect(loudest <= 1, "the software volume never makes audio louder than the monitor's own level")

        let settings = MonitorVolumeKeySettings(stepPercent: 1, maximumPercent: 60)
        var value = SoftwareOutputVolume(outputUID: x34, stored: ["level": 0.0], settings: settings)!
        var highest = 0.0
        for _ in 0..<100 {
            value.step(1, fine: false, settings: settings)
            highest = max(highest, value.level)
        }
        suite.expect(highest <= 0.6, "100 fast presses never pass the maximum")
        suite.expectClose(highest, 0.6, "100 presses reach the maximum")
    }
}
