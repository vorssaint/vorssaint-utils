// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import CoreGraphics
import Foundation

enum SoftwareOutputVolumeTests {
    static func run(_ suite: TestSuite) {
        engagement(suite)
        exclusions(suite)
        keys(suite)
        storage(suite)
        limits(suite)
        keyRoute(suite)
        clickVolume(suite)
        renderWatch(suite)
        appEngines(suite)
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

    /// The production key route against the mixer's production output branches,
    /// with the output at a software level instead of a CoreAudio or DDC one.
    private static func keyRoute(_ suite: TestSuite) {
        typealias Keys = NotchVolumeRoutingTests
        typealias Hardware = MixerOutputAdjustmentContract.Hardware
        let settings = MonitorVolumeKeySettings(stepPercent: 10, minimumPercent: 20, maximumPercent: 70)
        var tap = Keys.Service()
        var mixer = MixerOutputAdjustmentContract.Mixer()
        func connect(_ level: Double?, muted: Bool = false, limits: MonitorVolumeKeySettings? = nil) {
            let active = limits ?? settings
            Hardware.reset()
            Keys.DispatchQueue.main = MixerOutputAdjustmentContract.Queue()
            mixer = MixerOutputAdjustmentContract.Mixer()
            Keys.AppVolumeMixer.shared = mixer
            Keys.UserDefaults.precise = false
            Keys.NotchService.shared.shownLevels = []
            DisplaySpeakerVolumeTests.Service.shared = DisplaySpeakerVolumeTests.Service()
            DisplaySpeakerVolumeTests.Service.shared.monitorVolumeKeySettings = active
            mixer.softwareOutput = level.map {
                SoftwareOutputVolume(outputUID: x34, stored: ["level": $0, "muted": muted], settings: active)!
            }
            tap = Keys.Service()
        }
        func drain() {
            while !Keys.DispatchQueue.main.jobs.isEmpty { Keys.DispatchQueue.main.runOne() }
        }
        // The tap tries the monitor route first, as `handle` does.
        func route(_ data1: Int, flags: CGEventFlags) -> Bool {
            tap.routeMonitorVolume(.init(data1: data1), flags: flags)
                || tap.routeSoftwareVolume(.init(data1: data1), flags: flags)
        }
        @discardableResult
        func press(_ key: PreciseVolumeMediaKey, flags: CGEventFlags = [], repeats: Int = 0) -> Bool {
            let code = Int(key.rawValue) << 16
            var claimed = route(code | 0x0a00, flags: flags)
            for _ in 0..<repeats { claimed = route(code | 0x0a01, flags: flags) && claimed }
            claimed = route(code | 0x0b00, flags: flags) && claimed
            drain()
            return claimed
        }
        func level() -> Double { mixer.softwareOutput?.level ?? -1 }

        connect(0.5)
        suite.expect(press(.volumeDown), "the software route claims volume down on an output without volume control")
        suite.expectClose(level(), 0.4, "volume down lowers the software level one step")
        suite.expect(mixer.systemOutputVolume.map { abs($0 - 0.4) < 0.0001 } == true,
                     "the panel slider and the island read the software level")
        suite.expect(Keys.NotchService.shared.shownLevels.map { ($0 * 100).rounded() } == [40],
                     "each press shows the indicator with the new level")
        suite.expect(Hardware.writes.isEmpty, "the software level never writes the output's CoreAudio volume")

        press(.volumeUp, flags: [.maskAlternate, .maskShift])
        suite.expectClose(level(), 0.41, "Option and Shift move one percent, as the monitor keys do")

        connect(0.7)
        press(.volumeUp)
        suite.expectClose(level(), 0.7, "volume up at the maximum changes nothing")
        suite.expect(Keys.NotchService.shared.shownLevels.map { ($0 * 100).rounded() } == [70],
                     "volume up at the maximum still shows the maximum")

        connect(0.2)
        press(.volumeDown)
        suite.expectClose(level(), 0.2, "volume down at the minimum changes nothing")

        connect(0.4)
        press(.mute)
        suite.expect(mixer.softwareOutput?.muted == true && mixer.systemOutputMuted == true
                     && Keys.NotchService.shared.shownLevels == [0],
                     "mute silences the output and the indicator shows mute")
        press(.volumeUp)
        suite.expect(mixer.softwareOutput?.muted == false, "volume up ends the mute")
        suite.expectClose(level(), 0.5, "volume up after a mute steps from the level before it")

        connect(1, limits: MonitorVolumeKeySettings(stepPercent: 10))
        suite.expect(press(.volumeDown), "at full level the keys still belong to the software route")
        suite.expectClose(level(), 0.9, "the first press down from full level lowers it one step")

        connect(0.6)
        suite.expect(press(.volumeDown, repeats: 2), "a held key keeps its repeats and its release")
        suite.expectClose(level(), 0.3, "each repeat of a held key is one step")
        press(.mute, repeats: 2)
        suite.expect(mixer.softwareOutput?.muted == true, "a held mute key toggles once")

        connect(0.5)
        suite.expect(!press(.volumeDown, flags: [.maskCommand]), "Command with a volume key goes to macOS")
        suite.expectClose(level(), 0.5, "a key left to macOS keeps the software level")

        connect(nil)
        suite.expect(!press(.volumeDown) && !press(.mute),
                     "with the feature off or the output controlled elsewhere the keys go to macOS")
        suite.expect(Hardware.writes.isEmpty && Keys.NotchService.shared.shownLevels.isEmpty,
                     "a key left to macOS changes nothing in Vorssaint")
    }

    // Vorssaint plays the volume click from its own process, which the
    // output tap leaves out, so the click must carry the software gain itself.
    private static func clickVolume(_ suite: TestSuite) {
        suite.expect(SoftwareOutputVolume.clickVolume(for: nil) == 1,
                     "without a software level the click plays at full volume")
        let lowered = volume(0.3)
        suite.expect(SoftwareOutputVolume.clickVolume(for: lowered) == lowered.gain,
                     "the click plays at the software gain, as loud as the music it follows")
        suite.expect(SoftwareOutputVolume.clickVolume(for: volume(0.3, muted: true)) == 0,
                     "a muted software output plays no click")
    }

    // The stall watchdog needs to know when silence from the output-wide
    // engine is wrong: only while an app it carries is playing on its output.
    private static func renderWatch(_ suite: TestSuite) {
        let own: AudioObjectID = 7
        func carries(_ apps: [(objects: [AudioObjectID], outputUID: String?, isPlaying: Bool)]) -> Bool {
            SoftwareOutputVolume.carriesPlayingAudio(outputUID: x34, excluded: [own, 41], apps: apps)
        }
        suite.expect(carries([([30], x34, true)]), "a playing app on the output means the engine must render")
        suite.expect(!carries([([30], x34, false)]), "a silent app gives the engine nothing to render")
        suite.expect(!carries([([30], "BuiltInSpeakerDevice", true)]),
                     "an app playing on another output is not carried by this engine")
        suite.expect(!carries([([41], x34, true)]),
                     "an app with its own mixer tap is left out of the output-wide engine")
        suite.expect(carries([([41, 42], x34, true)]),
                     "an app with any audio object outside the exclusions is carried")
        suite.expect(!carries([([30], nil, true)]), "an app with no known output is not counted")
        suite.expect(!carries([]), "no apps, nothing to render")
    }

    // An app's own engine and the output-wide tap must never both play the
    // app, or it sounds up to twice as loud as the monitor's own level.
    private static func appEngines(_ suite: TestSuite) {
        let output = volume(0.5)
        suite.expect(SoftwareOutputVolume.appEngineGain(0.8, outputGain: output.gain, excluded: [7, 41], objects: [41]) == 0.8 * output.gain,
                     "an app the output-wide tap leaves out carries the output level in its own engine")
        suite.expect(SoftwareOutputVolume.appEngineGain(0.8, outputGain: output.gain, excluded: [7], objects: [41]) == 0,
                     "an app the output-wide tap still carries stays silent in its own engine until the tap leaves it out")
        suite.expect(SoftwareOutputVolume.appEngineGain(0.8, outputGain: output.gain, excluded: [7, 41], objects: [41, 42]) == 0,
                     "an app with any audio object still in the output-wide tap stays silent in its own engine")
        suite.expect(SoftwareOutputVolume.appEngineGain(0.8, outputGain: nil, excluded: [], objects: [41]) == 0.8,
                     "without the output-wide tap an app engine plays at its own gain")
    }
}
