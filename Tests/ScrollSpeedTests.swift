// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Modifier-held mouse scroll speed (issue #521): preferences, shortcut
/// matching and catalog contracts. Both wheel taps have separate routing tests.
enum ScrollSpeedTests {
    static func run(_ suite: TestSuite) {
        suite.expect(ScrollWheelSupport.sanitizedSpeedMultiplier(0)
                        == ScrollWheelSupport.defaultSpeedMultiplier
                        && ScrollWheelSupport.sanitizedSpeedMultiplier(1) == 2
                        && ScrollWheelSupport.sanitizedSpeedMultiplier(3) == 3
                        && ScrollWheelSupport.sanitizedSpeedMultiplier(15) == 15
                        && ScrollWheelSupport.sanitizedSpeedMultiplier(16) == 15,
                     "speed multipliers clamp to 2…15 with a default of 3")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.scrollSpeedEnabled] as? Bool == false
                && Defaults.registeredDefaults[DefaultsKey.scrollSpeedModifier] as? String
                    == ScrollHorizontalModifier.option.rawValue
                && Defaults.registeredDefaults[DefaultsKey.scrollSpeedMultiplier] as? Int
                    == ScrollWheelSupport.defaultSpeedMultiplier,
                     "scroll speed ships off with Option and a 3× multiplier")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [
            DefaultsKey.scrollSpeedEnabled, DefaultsKey.scrollSpeedModifier,
            DefaultsKey.scrollSpeedMultiplier, DefaultsKey.scrollSpeedExceptions,
        ]), "backup and restore include every scroll-speed setting")
        suite.expect(AppFeature.scrollSpeed.enabledKeys == [DefaultsKey.scrollSpeedEnabled]
                && AppFeature.scrollSpeed.permissions == [.accessibility]
                && AppFeature.availabilityDefaults[AppFeature.scrollSpeed.availabilityKey] as? Bool == false
                && AppFeature.scrollSpeed.settingsDestination.sectionAnchor == .scrollSpeed,
                     "scroll speed is an opt-in Accessibility feature with its own Mouse card")
        suite.expect(MouseExceptionScope.scrollSpeed.feature == .scrollSpeed
                && MouseExceptionScope.scrollSpeed.defaultsKey == DefaultsKey.scrollSpeedExceptions,
                     "scroll speed keeps its own apps-to-leave-alone list")

        let disabled = ScrollSpeedPreferences(
            isAvailable: false,
            boolFor: { _ in true },
            stringFor: { _ in ScrollHorizontalModifier.option.rawValue },
            intFor: { _ in 4 })
        suite.expect(disabled.modifier == nil,
                     "uninstalling the feature stands speed down even when its switch is on")

        let prefs = ScrollSpeedPreferences(
            isAvailable: true,
            boolFor: { $0 == DefaultsKey.scrollSpeedEnabled },
            stringFor: { $0 == DefaultsKey.scrollSpeedModifier
                ? ScrollHorizontalModifier.option.rawValue : nil },
            intFor: { $0 == DefaultsKey.scrollSpeedMultiplier ? 4 : 0 })
        suite.expect(prefs.modifier == .option && prefs.multiplier == 4,
                     "installed speed preferences resolve the chosen modifier and factor")

        for modifier in ScrollHorizontalModifier.allCases {
            let event = wheel(flags: modifier.flag)
            let claim = prefs.matchingModifier(for: event, horizontalModifier: nil,
                                               isExcepted: false, targetsOwnWindow: false)
            suite.expect(claim == (modifier == .option ? .option : nil),
                         "speed claims only its own modifier")
        }

        var exceptionChecks = 0, windowChecks = 0
        func excepted() -> Bool { exceptionChecks += 1; return false }
        func ownWindow() -> Bool { windowChecks += 1; return false }
        for event in [wheel(flags: []), wheel(flags: [.maskAlternate, .maskShift]),
                      wheel(flags: .maskAlternate, line: 0, point: 0, fixed: 0)] {
            suite.expect(prefs.matchingModifier(for: event, horizontalModifier: nil,
                                isExcepted: excepted(), targetsOwnWindow: ownWindow()) == nil,
                         "plain, multi-modifier and empty ticks keep their flags")
        }
        let vertical = wheel(flags: .maskAlternate)
        suite.expect(disabled.matchingModifier(for: vertical, horizontalModifier: nil,
                         isExcepted: excepted(), targetsOwnWindow: ownWindow()) == nil
                     && prefs.matchingModifier(for: vertical, horizontalModifier: .option,
                         isExcepted: excepted(), targetsOwnWindow: ownWindow()) == nil
                     && exceptionChecks == 0 && windowChecks == 0,
                     "uninstalled speed, nonmatching ticks and real horizontal shortcuts skip all speed target lookups")
        suite.expect(prefs.matchingModifier(for: vertical, horizontalModifier: nil,
                         isExcepted: true, targetsOwnWindow: ownWindow()) == nil && windowChecks == 0,
                     "an excepted speed tick needs no second window lookup")
        let invalidKeys: [String?] = [nil, "unknown"]
        for stored in invalidKeys {
            let recovered = ScrollSpeedPreferences(isAvailable: true, boolFor: { _ in true },
                                                  stringFor: { _ in stored }, intFor: { _ in 3 })
            suite.expect(recovered.modifier == .option, "missing or unknown speed keys use the displayed Option default")
        }

        let runtime = (try? String(contentsOfFile: "Sources/Vorssaint/App/FeatureRuntime.swift",
                                   encoding: .utf8)) ?? ""
        suite.expect(runtime.contains(
            ".scrollSpeed: { ScrollInverter.shared.syncWithPreferences() }"),
                     "changing speed availability re-syncs the shared wheel tap")
    }

    private static func wheel(flags: CGEventFlags, line: Int64 = 1,
                              point: Int64 = 10, fixed: Double = 1) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                            wheel1: 0, wheel2: 0, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: line)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: point)
        event.flags = flags
        return event
    }
}
