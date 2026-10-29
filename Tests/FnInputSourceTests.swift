// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum FnInputSourceTests {
    static func run(_ suite: TestSuite) {
        recognizer(suite)
        readings(suite)
        catalog(suite)
    }

    private typealias Recognizer = FnInputSourceSupport.Recognizer

    private static let millisecond: UInt64 = 1_000_000

    /// One press of Fn on its own, `duration` long, starting at `start`.
    private static func tap(_ recognizer: inout Recognizer, at start: UInt64, duration: UInt64,
                            activity: UInt64 = 7) -> Bool {
        let pressed = recognizer.handle(.fnDown(timestamp: start, otherInputHeld: false, activity: activity))
        let released = recognizer.handle(.fnUp(timestamp: start + duration, otherInputHeld: false,
                                               activity: activity))
        return !pressed && released
    }

    private static func recognizer(_ suite: TestSuite) {
        let start: UInt64 = 5_000 * millisecond
        var recognizer = Recognizer()
        suite.expect(tap(&recognizer, at: start, duration: 80 * millisecond),
                     "a quick tap of Fn on its own switches, on the release and not the press")

        var taps = Recognizer()
        let switched = (0..<10).filter { index in
            tap(&taps, at: start + UInt64(index) * 60 * millisecond, duration: 30 * millisecond)
        }
        suite.expect(switched.count == 10, "ten quick taps in a row switch ten times, once each")

        var limit = Recognizer()
        suite.expect(tap(&limit, at: start, duration: FnInputSourceSupport.tapLimitNanoseconds - 1)
                && !tap(&limit, at: start + 1_000 * millisecond, duration: FnInputSourceSupport.tapLimitNanoseconds)
                && !tap(&limit, at: start + 2_000 * millisecond,
                        duration: FnInputSourceSupport.tapLimitNanoseconds + 1)
                && !tap(&limit, at: start + 3_000 * millisecond, duration: 3_000 * millisecond),
                     "just under the limit is a tap; at it, past it and a long hold switch nothing")

        var chord = Recognizer()
        _ = chord.handle(.fnDown(timestamp: start, otherInputHeld: false, activity: 7))
        _ = chord.handle(.otherInput)
        _ = chord.handle(.otherInput)
        suite.expect(!chord.handle(.fnUp(timestamp: start + 60 * millisecond, otherInputHeld: false, activity: 7)),
                     "Fn with another key switches nothing, even when that key comes up before Fn does")
        suite.expect(tap(&chord, at: start + 500 * millisecond, duration: 50 * millisecond),
                     "the press after a chord starts clean and switches on its own")

        var swallowed = Recognizer()
        _ = swallowed.handle(.fnDown(timestamp: start, otherInputHeld: false, activity: 7))
        suite.expect(!swallowed.handle(.fnUp(timestamp: start + 60 * millisecond, otherInputHeld: false,
                                             activity: 8)),
                     "a key press or click the tap never saw still makes the press a chord")

        var heldBefore = Recognizer()
        _ = heldBefore.handle(.fnDown(timestamp: start, otherInputHeld: true, activity: 7))
        suite.expect(!heldBefore.handle(.fnUp(timestamp: start + 60 * millisecond, otherInputHeld: false,
                                              activity: 7)),
                     "Fn pressed while another key or a modifier is held is part of a chord")

        var heldAfter = Recognizer()
        _ = heldAfter.handle(.fnDown(timestamp: start, otherInputHeld: false, activity: 7))
        suite.expect(!heldAfter.handle(.fnUp(timestamp: start + 60 * millisecond, otherInputHeld: true,
                                             activity: 7)),
                     "Fn released while another key is still down is part of a chord")

        var unmatched = Recognizer()
        suite.expect(!unmatched.handle(.fnUp(timestamp: start, otherInputHeld: false, activity: 7)),
                     "a release without its press switches nothing")

        var interrupted = Recognizer()
        _ = interrupted.handle(.fnDown(timestamp: start, otherInputHeld: false, activity: 7))
        _ = interrupted.handle(.interrupted)
        suite.expect(!interrupted.handle(.fnUp(timestamp: start + 60 * millisecond, otherInputHeld: false,
                                               activity: 7)),
                     "a press the tap lost track of, by a timeout, a stop or sleep, switches nothing")
        suite.expect(tap(&interrupted, at: start + 500 * millisecond, duration: 50 * millisecond),
                     "after an interruption a fresh press switches again")

        var missedRelease = Recognizer()
        _ = missedRelease.handle(.fnDown(timestamp: start, otherInputHeld: false, activity: 7))
        suite.expect(tap(&missedRelease, at: start + 2_000 * millisecond, duration: 40 * millisecond),
                     "a press after a missed release is timed from its own down")

        var backwards = Recognizer()
        _ = backwards.handle(.fnDown(timestamp: start, otherInputHeld: false, activity: 7))
        suite.expect(!backwards.handle(.fnUp(timestamp: start - millisecond, otherInputHeld: false, activity: 7)),
                     "a release stamped before its press switches nothing")

        suite.expect(InputSourceSelection.nextSourceID(currentID: "A", enabledIDs: ["A", "B"]) == "B"
                && InputSourceSelection.nextSourceID(currentID: "B", enabledIDs: ["A", "B"]) == "A"
                && InputSourceSelection.nextSourceID(currentID: "B", enabledIDs: ["A", "B", "C"]) == "C"
                && InputSourceSelection.nextSourceID(currentID: "C", enabledIDs: ["A", "B", "C"]) == "A"
                && InputSourceSelection.nextSourceID(currentID: "A", enabledIDs: ["A"]) == nil
                && InputSourceSelection.nextSourceID(currentID: "A", enabledIDs: []) == nil,
                     "taps cycle A → B → A and A → B → C → A, and one source has nothing to cycle to")
    }

    private static func readings(_ suite: TestSuite) {
        let fn = FnInputSourceSupport.fnKeyCode
        func reading(_ type: CGEventType, keyCode: Int64 = 0, flags: CGEventFlags = [],
                     own: Bool = false) -> FnInputSourceSupport.Reading {
            FnInputSourceSupport.reading(type: type, keyCode: keyCode, flags: flags, isOwnEvent: own)
        }
        suite.expect(reading(.flagsChanged, keyCode: fn, flags: .maskSecondaryFn) == .fnDown
                && reading(.flagsChanged, keyCode: fn, flags: [.maskSecondaryFn, .maskAlphaShift]) == .fnDown
                && reading(.flagsChanged, keyCode: fn) == .fnUp,
                     "the Fn key's own modifier change reads as its press and release")
        suite.expect(reading(.flagsChanged, keyCode: fn, flags: .maskSecondaryFn, own: true) == .otherInput,
                     "an Fn change this app posted never starts a tap")
        suite.expect(reading(.flagsChanged, keyCode: 56, flags: [.maskSecondaryFn, .maskShift]) == .otherInput
                && reading(.flagsChanged, keyCode: 57, flags: [.maskSecondaryFn, .maskAlphaShift]) == .otherInput,
                     "another modifier pressed or released during the press, Caps Lock included, is a chord")
        let systemDefined = CGEventType(rawValue: FnInputSourceSupport.systemDefinedEventTypeRawValue)!
        suite.expect(reading(.keyDown, keyCode: 51, flags: .maskSecondaryFn) == .otherInput
                && reading(.keyUp, keyCode: 123, flags: [.maskSecondaryFn, .maskNumericPad]) == .otherInput
                && reading(systemDefined) == .otherInput,
                     "Fn+Delete, Fn+arrows and media or brightness keys are chords")
        suite.expect(reading(.mouseMoved) == .unrelated && reading(.tapDisabledByTimeout) == .unrelated,
                     "events that are not input pass by without touching the press")

        suite.expect(!FnInputSourceSupport.otherInputHeld(flags: [.maskSecondaryFn, .maskAlphaShift], keyHeld: false),
                     "Caps Lock already on does not stop a tap")
        suite.expect(FnInputSourceSupport.otherInputHeld(flags: .maskCommand, keyHeld: false)
                && FnInputSourceSupport.otherInputHeld(flags: .maskShift, keyHeld: false)
                && FnInputSourceSupport.otherInputHeld(flags: .maskControl, keyHeld: false)
                && FnInputSourceSupport.otherInputHeld(flags: .maskAlternate, keyHeld: false)
                && FnInputSourceSupport.otherInputHeld(flags: .maskSecondaryFn, keyHeld: true),
                     "a held Shift, Control, Option, Command or other key makes the press a chord")

        // What the system reports down at rest on real keyboards: Caps Lock
        // while its lock is on (Magic Keyboard), and 127 on a built-in
        // MacBook keyboard. Neither was pressed, so neither may hold a tap.
        let atRest: Set<CGKeyCode> = [57, 127]
        var idle = FnInputSourceSupport.PressedKeys()
        suite.expect(!idle.anyHeld { atRest.contains($0) },
                     "a code the system reports down without the tap seeing it pressed is not a held key")

        var held = FnInputSourceSupport.PressedKeys()
        held.note(type: .keyDown, keyCode: 0)
        suite.expect(held.anyHeld { $0 == 0 || atRest.contains($0) },
                     "a key pressed and still down is held")
        held.note(type: .keyUp, keyCode: 0)
        suite.expect(!held.anyHeld { $0 == 0 }, "a key pressed and released is no longer held")

        var missedRelease = FnInputSourceSupport.PressedKeys()
        missedRelease.note(type: .keyDown, keyCode: 51)
        suite.expect(!missedRelease.anyHeld { _ in false } && missedRelease.codes.isEmpty,
                     "a key whose release the tap missed clears once the system reports it up")

        var onlyFn = FnInputSourceSupport.PressedKeys()
        onlyFn.note(type: .keyDown, keyCode: fn)
        suite.expect(!onlyFn.anyHeld { _ in true }, "Fn itself never counts as another held key")

        var interrupted = FnInputSourceSupport.PressedKeys()
        interrupted.note(type: .keyDown, keyCode: 0)
        interrupted.reset()
        suite.expect(!interrupted.anyHeld { _ in true }, "an interruption forgets every press")

        suite.expect(FnInputSourceSupport.systemAction(raw: NSNumber(value: 0)) == .nothing
                && FnInputSourceSupport.systemAction(raw: NSNumber(value: 1)) == .something
                && FnInputSourceSupport.systemAction(raw: NSNumber(value: 2)) == .something
                && FnInputSourceSupport.systemAction(raw: NSNumber(value: 3)) == .something
                && FnInputSourceSupport.systemAction(raw: nil) == .systemDefault,
                     "only an explicit Do Nothing for 🌐 leaves the tap to Vorssaint alone")
    }

    private static func catalog(_ suite: TestSuite) {
        let feature = AppFeature.fnInputSource
        suite.expect(feature.group == .mouseKeyboard
                && feature.enabledKeys == [DefaultsKey.fnInputSourceEnabled]
                && feature.permissions == [.accessibility]
                && !feature.installedByDefault
                && feature.energyProfile == .keyboard,
                     "Fn switching is an opt-in keyboard feature behind Accessibility")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.fnInputSourceEnabled] as? Bool == false
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.fnInputSourceEnabled)
                && SettingsBackupSupport.exportKeys().contains(feature.availabilityKey),
                     "it ships off, and its switch and availability travel with a settings backup")
        suite.expect(feature.settingsDestination == FeatureSettingsDestination(.fnInputSource)
                && FeatureVisibilitySupport.features(for: .fnInputSource) == [.fnInputSource]
                && !FeatureVisibilitySupport.isPageVisible(.fnInputSource, isAvailable: { _ in false }),
                     "its page shows only while the feature is installed")
        suite.expect(!FeaturePreset.allCases.contains { $0.features.contains(feature) },
                     "no preset installs it")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.fnInputSource(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            suite.expect(values.count == 11 && values.allSatisfy { !$0.isEmpty },
                         "\(language.rawValue) has every Fn string")
            suite.expect(strings.systemSection.contains("🌐") && strings.systemOther.contains("🌐"),
                         "\(language.rawValue) names the 🌐 key the way System Settings shows it")
        }
    }
}
