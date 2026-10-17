// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Input sounds and the click highlight: the sound library, the synth, the
/// rules that decide when a sound plays, and the highlight's preferences.
enum InputFeedbackTests {
    static func run(_ suite: TestSuite) {
        libraryContracts(suite)
        synthContracts(suite)
        keyContracts(suite)
        scrollContracts(suite)
        comboContracts(suite)
        pressContracts(suite)
        quietContracts(suite)
        presetContracts(suite)
        highlightContracts(suite)
    }

    private static func libraryContracts(_ suite: TestSuite) {
        let ids = InputSoundLibrary.all.map(\.id)
        suite.expect(Set(ids).count == ids.count, "input sound ids are unique (they are persisted)")
        suite.expect(InputSoundLibrary.all.count == 37, "the library has 37 sounds")
        suite.expect(InputSoundFamily.allCases.allSatisfy { !InputSoundLibrary.packs(in: $0).isEmpty },
                     "every sound family has sounds")
        suite.expect(InputSoundLibrary.all.allSatisfy { $0.id.hasPrefix($0.family.rawValue + ".") },
                     "a sound id starts with its family")
        suite.expect(InputSoundLibrary.pack(id: InputSoundLibrary.defaultPackID) != nil
                && InputSoundLibrary.pack(id: Defaults.registeredDefaults[DefaultsKey.inputSoundsKeyboardPack]
                    as? String) != nil,
                     "the default click and key sounds exist")
        suite.expect(InputSoundsSupport.sanitizedPackID("nope", fallback: "desk.crisp") == "desk.crisp"
                && InputSoundsSupport.sanitizedPackID(nil, fallback: "desk.crisp") == "desk.crisp"
                && InputSoundsSupport.sanitizedPackID("toybox.boop", fallback: "desk.crisp") == "toybox.boop"
                && InputSoundsSupport.sanitizedPackID("custom", fallback: "desk.crisp") == "custom",
                     "an unknown saved sound falls back, a known or custom one is kept")
        suite.expect(Set(InputSoundFamily.allCases.map(\.matchingScrollStyle)).count == InputScrollStyle.allCases.count,
                     "every family matches its own scroll style")
        let typebar = InputSoundLibrary.pack(id: "analog.typebar")!
        suite.expect(InputSoundLibrary.keyRecipe(typebar, kind: .returnKey, isRelease: false).modes.count
                > typebar.press.modes.count,
                     "the typewriter rings a bell on Return")
        suite.expect(InputSoundLibrary.keyRecipe(typebar, kind: .returnKey, isRelease: true).modes.count
                == typebar.release.modes.count,
                     "the bell rings on the press, not the release")
        let space = InputSoundLibrary.keyRecipe(typebar, kind: .space, isRelease: false)
        suite.expect(space.modes[0].frequency < typebar.press.modes[0].frequency
                && space.duration > typebar.press.duration,
                     "space is deeper and longer than a letter key")
    }

    private static func synthContracts(_ suite: TestSuite) {
        var allAudible = true
        var allBounded = true
        for pack in InputSoundLibrary.all {
            for recipe in [pack.press, pack.release] {
                let samples = InputSoundSynth.render(recipe)
                let peak = samples.map { abs($0) }.max() ?? 0
                if peak < 0.05 { allAudible = false }
                if peak > 1 || samples.contains(where: { !$0.isFinite }) { allBounded = false }
            }
        }
        suite.expect(allAudible, "every library sound renders audibly")
        suite.expect(allBounded, "every library sound stays within full scale")
        for style in InputScrollStyle.allCases {
            let samples = InputSoundSynth.render(style.recipe)
            suite.expect(!samples.isEmpty && (samples.map { abs($0) }.max() ?? 0) > 0.05,
                         "scroll style \(style.rawValue) renders audibly")
        }
        let recipe = InputSoundLibrary.pack(id: "desk.thock")!.press
        suite.expect(InputSoundSynth.render(recipe, variation: 2) == InputSoundSynth.render(recipe, variation: 2),
                     "a render is deterministic")
        suite.expect(InputSoundSynth.render(recipe, variation: 1) != InputSoundSynth.render(recipe, variation: 2),
                     "variations differ, so repeated keys are not identical")
        let long = InputSoundRecipe(duration: 30, modes: [.init(frequency: 440, decay: 10, amplitude: 1)])
        suite.expect(Double(InputSoundSynth.render(long).count)
                <= InputSoundSynth.maximumDuration * InputSoundSynth.sampleRate + 1,
                     "a render is capped at the longest allowed sound")
        let tail = InputSoundSynth.render(recipe)
        suite.expect(abs(tail.last ?? 1) < 0.001, "a render fades out instead of ending in a click")
        for step in [0, 4, 5, 14, 99] {
            suite.expect(!InputSoundSynth.render(InputSoundLibrary.comboChime(step: step)).isEmpty,
                         "combo chime \(step) renders")
        }
        suite.expect(InputSoundLibrary.comboChime(step: 5).modes[0].frequency
                > InputSoundLibrary.comboChime(step: 4).modes[0].frequency,
                     "each combo step is a higher note")
    }

    private static func keyContracts(_ suite: TestSuite) {
        suite.expect(InputSoundsSupport.keyKind(keyCode: 49) == .space
                && InputSoundsSupport.keyKind(keyCode: 36) == .returnKey
                && InputSoundsSupport.keyKind(keyCode: 76) == .returnKey
                && InputSoundsSupport.keyKind(keyCode: 51) == .delete
                && InputSoundsSupport.keyKind(keyCode: 117) == .delete
                && InputSoundsSupport.keyKind(keyCode: 56) == .modifier
                && InputSoundsSupport.keyKind(keyCode: 0) == .regular
                && InputSoundsSupport.keyKind(keyCode: 12) == .regular,
                     "keys are reduced to their kind")
        suite.expect(InputSoundsSupport.modifierIsDown(keyCode: 56, flags: .maskShift) == true
                && InputSoundsSupport.modifierIsDown(keyCode: 56, flags: []) == false
                && InputSoundsSupport.modifierIsDown(keyCode: 55, flags: .maskCommand) == true
                && InputSoundsSupport.modifierIsDown(keyCode: 0, flags: .maskShift) == nil,
                     "a modifier's own flag tells its press from its release")
        var keyboardOff = InputSoundsConfig()
        keyboardOff.keyboardEnabled = false
        keyboardOff.typingComboEnabled = false
        let keyMask = ListenOnlyEventTap.mask([.keyDown])
        suite.expect(InputSoundsSupport.eventMask(for: keyboardOff) & keyMask == 0,
                     "click-only sounds never listen to the keyboard")
        var keyboardOn = keyboardOff
        keyboardOn.keyboardEnabled = true
        suite.expect(InputSoundsSupport.eventMask(for: keyboardOn) & keyMask != 0,
                     "key sounds listen to the keyboard")
        suite.expect(InputSoundsSupport.eventMask(for: keyboardOff) & ListenOnlyEventTap.mask([.scrollWheel]) == 0,
                     "scroll ticks off means no scroll events")
        suite.expect(InputSoundsSupport.pan(pointerX: 0, across: CGRect(x: 0, y: 0, width: 100, height: 10)) < 0
                && InputSoundsSupport.pan(pointerX: 100, across: CGRect(x: 0, y: 0, width: 100, height: 10)) > 0
                && abs(InputSoundsSupport.pan(pointerX: 50, across: CGRect(x: 0, y: 0, width: 100, height: 10))) < 0.01
                && InputSoundsSupport.pan(pointerX: 999, across: CGRect(x: 0, y: 0, width: 100, height: 10)) <= 0.75,
                     "stereo follows the pointer without hard panning")
    }

    private static func scrollContracts(_ suite: TestSuite) {
        let ms: UInt64 = 1_000_000
        var ticker = InputScrollTicker()
        suite.expect(ticker.shouldTick(delta: 1, isContinuous: false, isMomentum: false, timestamp: 100 * ms),
                     "a wheel notch ticks")
        suite.expect(!ticker.shouldTick(delta: 1, isContinuous: false, isMomentum: false, timestamp: 110 * ms),
                     "ticks are paced so a fast wheel does not buzz")
        suite.expect(ticker.shouldTick(delta: -1, isContinuous: false, isMomentum: false, timestamp: 140 * ms),
                     "the next notch after the pause ticks")
        suite.expect(!ticker.shouldTick(delta: 5, isContinuous: false, isMomentum: true, timestamp: 400 * ms),
                     "momentum after a swipe stays silent")
        ticker.reset()
        var ticks = 0
        for index in 0..<20 where ticker.shouldTick(delta: 10, isContinuous: true, isMomentum: false,
                                                     timestamp: UInt64(1_000 + index * 40) * ms) {
            ticks += 1
        }
        suite.expect(ticks == 4, "a trackpad ticks once per stretch of travel (\(ticks))")
    }

    private static func comboContracts(_ suite: TestSuite) {
        let ms: UInt64 = 1_000_000
        var combo = InputTypingCombo()
        var earned: [Int] = []
        for index in 0..<(InputTypingCombo.keysPerStep * 3) {
            if let step = combo.registerKey(at: UInt64(index) * 120 * ms) { earned.append(step) }
        }
        suite.expect(earned == [0, 1, 2], "steady fast typing earns rising chimes (\(earned))")
        if let step = combo.registerKey(at: UInt64(InputTypingCombo.keysPerStep * 3) * 120 * ms + 2_000 * ms) {
            suite.expect(false, "a pause must not earn a chime (\(step))")
        }
        suite.expect(combo.step == 0, "a pause ends the run")
        var slow = InputTypingCombo()
        var slowEarned = 0
        for index in 0..<(InputTypingCombo.keysPerStep * 2) where
            slow.registerKey(at: UInt64(index) * 400 * ms) != nil {
            slowEarned += 1
        }
        suite.expect(slowEarned == 0, "slow typing earns nothing")
    }

    private static func pressContracts(_ suite: TestSuite) {
        let ms: UInt64 = 1_000_000
        var tracker = InputPressTracker()
        tracker.press(at: 0, point: .zero)
        suite.expect(!tracker.checkLongPress(now: 100 * ms), "a short press is not a long press")
        suite.expect(tracker.checkLongPress(now: 600 * ms), "a held press is a long press")
        suite.expect(!tracker.checkLongPress(now: 900 * ms), "a long press sounds once")
        suite.expect(!tracker.release(), "a press without movement is not a drag")
        tracker.press(at: 0, point: .zero)
        suite.expect(!tracker.drag(to: CGPoint(x: 2, y: 2)), "a tremble is not a drag")
        suite.expect(tracker.drag(to: CGPoint(x: 20, y: 0)), "moving far enough starts a drag")
        suite.expect(!tracker.drag(to: CGPoint(x: 40, y: 0)), "a drag starts once")
        suite.expect(!tracker.checkLongPress(now: 900 * ms), "a drag is never a long press")
        suite.expect(tracker.release(), "releasing ends the drag")
        suite.expect(!tracker.drag(to: CGPoint(x: 90, y: 0)), "no drag without a press")
    }

    private static func quietContracts(_ suite: TestSuite) {
        var config = InputSoundsConfig()
        config.quietDuringMicrophone = true
        config.quietBundleIDs = ["us.zoom.xos"]
        suite.expect(InputSoundsSupport.shouldStayQuiet(config: config, frontmostBundleID: nil, microphoneInUse: true),
                     "a microphone in use quiets the sounds")
        suite.expect(InputSoundsSupport.shouldStayQuiet(config: config, frontmostBundleID: "us.zoom.xos",
                                                        microphoneInUse: false),
                     "a quiet app quiets the sounds")
        suite.expect(!InputSoundsSupport.shouldStayQuiet(config: config, frontmostBundleID: "com.apple.Safari",
                                                         microphoneInUse: false),
                     "other apps hear the sounds")
        config.quietDuringMicrophone = false
        suite.expect(!InputSoundsSupport.shouldStayQuiet(config: config, frontmostBundleID: nil, microphoneInUse: true),
                     "the microphone rule can be turned off")
        suite.expect(InputSoundsSupport.decodeBundleIDs(" a \nb\n\na\n") == ["a", "b"]
                && InputSoundsSupport.encodeBundleIDs(["b", "a", "b"]) == "b\na",
                     "the quiet list trims and drops repeats")
    }

    private static func presetContracts(_ suite: TestSuite) {
        let suiteName = "com.vorssaint.tests.inputFeedback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        InputFeedbackPreset.recording.apply(to: defaults, highlightAvailable: false)
        suite.expect(defaults.object(forKey: DefaultsKey.clickHighlightRippleEnabled) == nil,
                     "a preset leaves an uninstalled highlight alone")
        suite.expect(defaults.string(forKey: DefaultsKey.inputSoundsClickPack) == "studio.tap",
                     "a preset sets the click sound")
        InputFeedbackPreset.recording.apply(to: defaults, highlightAvailable: true)
        suite.expect(defaults.bool(forKey: DefaultsKey.clickHighlightRippleEnabled),
                     "a preset sets an installed highlight")
        for preset in InputFeedbackPreset.allCases {
            for (key, value) in preset.values {
                suite.expect(Defaults.registeredDefaults[key] != nil,
                             "preset \(preset.rawValue) writes a registered setting (\(key))")
                suite.expect(SettingsBackupSupport.valueLooksRight(key, value),
                             "preset \(preset.rawValue) writes the right shape for \(key)")
            }
            if let pack = preset.values[DefaultsKey.inputSoundsClickPack] as? String {
                suite.expect(InputSoundLibrary.pack(id: pack) != nil, "preset \(preset.rawValue) names a real sound")
            }
        }
    }

    private static func highlightContracts(_ suite: TestSuite) {
        var config = ClickHighlightConfig()
        config.rippleEnabled = true
        config.rippleOnlyWhileRecording = true
        suite.expect(!config.showsRipple(isRecording: false) && config.showsRipple(isRecording: true),
                     "a recording-only ripple follows the recorder")
        config.spotlightEnabled = true
        config.spotlightOnlyWhileRecording = false
        suite.expect(config.showsSpotlight(isRecording: false), "an always-on spotlight shows without recording")
        suite.expect(ClickHighlightSupport.sanitizedColorHex("#00ff00") == "#00FF00"
                && ClickHighlightSupport.sanitizedColorHex("green") == Defaults.defaultClickHighlightColor
                && ClickHighlightSupport.sanitizedColorHex(nil) == Defaults.defaultClickHighlightColor,
                     "only hex colors are kept")
        suite.expect(ClickHighlightSupport.hex(red: 1, green: 0.5, blue: 0) == "#FF8000",
                     "colors round-trip to hex")
        suite.expect(Defaults.sanitizedClickHighlightSize(5) == Defaults.defaultClickHighlightSize
                && Defaults.sanitizedClickHighlightSize(80) == 80
                && Defaults.sanitizedClickHighlightSpotlightDarkness(2) == Defaults.defaultClickHighlightSpotlightDarkness
                && Defaults.sanitizedInputSoundsVolume(.nan) == Defaults.defaultInputSoundsVolume
                && Defaults.sanitizedInputSoundsVolume(0) == 0,
                     "highlight and volume settings are sanitized")
        let stops = ClickHighlightSupport.spotlightLocations(radius: 100, extent: 1_000)
        suite.expect(stops.count == 4 && stops == stops.sorted() && stops[1] > 0 && stops[2] < 1,
                     "the spotlight fades from clear to dim, in order")
        suite.expect(ClickHighlightSupport.appKitPoint(fromEventLocation: CGPoint(x: 10, y: 0),
                                                       mainDisplayHeight: 900) == CGPoint(x: 10, y: 900),
                     "event points flip into AppKit space")
    }
}
