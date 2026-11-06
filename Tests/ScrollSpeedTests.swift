// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Modifier-held mouse scroll speed (issue #521): sole-modifier matching,
/// delta-field scaling, horizontal/zoom priority, and catalog contracts.
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
        suite.expect(!disabled.isEnabled && disabled.modifier == nil,
                     "uninstalling the feature stands speed down even when its switch is on")

        let prefs = ScrollSpeedPreferences(
            isAvailable: true,
            boolFor: { $0 == DefaultsKey.scrollSpeedEnabled },
            stringFor: { $0 == DefaultsKey.scrollSpeedModifier
                ? ScrollHorizontalModifier.option.rawValue : nil },
            intFor: { $0 == DefaultsKey.scrollSpeedMultiplier ? 4 : 0 })
        suite.expect(prefs.isEnabled && prefs.modifier == .option && prefs.multiplier == 4,
                     "installed speed preferences resolve the chosen modifier and factor")

        for continuous in [false, true] {
            let event = wheel(continuous: continuous, flags: .maskAlternate,
                              line: 2, point: 20, fixed: 2.5)
            suite.expect(prefs.factor(for: event, horizontalModifier: .shift, targetsOwnWindow: false) == 4,
                         "Option alone multiplies either wheel representation")
            suite.expect(ScrollWheelSupport.applyScrollSpeed(
                to: event, isContinuous: continuous, preferences: prefs,
                horizontalModifier: .shift),
                         "applyScrollSpeed reports success for a matching tick")
            suite.expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 8
                && event.flags.isEmpty,
                "speed multiplies the line delta and consumes the modifier")
            if continuous {
                suite.expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 80
                    && event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == 10,
                    "continuous wheels also scale point and fixed-point fields")
            }
        }

        let fraction = wheel(continuous: false, flags: .maskAlternate, line: 0, point: 0, fixed: 0.25)
        suite.expect(ScrollWheelSupport.applyScrollSpeed(
            to: fraction, isContinuous: false, preferences: prefs, horizontalModifier: nil)
            && fraction.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == 1,
            "sub-line high-resolution ticks keep scaled precision")

        let ownWindow = wheel(flags: .maskAlternate)
        suite.expect(prefs.factor(for: ownWindow, horizontalModifier: nil, targetsOwnWindow: true) == nil
            && !ScrollWheelSupport.applyScrollSpeed(
                to: ownWindow, isContinuous: false, preferences: prefs,
                horizontalModifier: nil, targetsOwnWindow: true)
            && ownWindow.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 1
            && ownWindow.flags == .maskAlternate,
            "Vorssaint's own windows keep their wheel gestures")

        let shared = wheel(flags: .maskAlternate)
        suite.expect(prefs.factor(for: shared, horizontalModifier: .option, targetsOwnWindow: false) == nil
            && !ScrollWheelSupport.applyScrollSpeed(
                to: shared, isContinuous: false, preferences: prefs,
                horizontalModifier: .option)
            && shared.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 1
            && shared.flags == .maskAlternate,
            "horizontal redirection with the same modifier wins over speed")

        for other in ScrollHorizontalModifier.allCases where other != .option {
            let event = wheel(flags: other.flag)
            suite.expect(prefs.factor(for: event, horizontalModifier: nil, targetsOwnWindow: false) == nil,
                         "\(other.rawValue) alone does not trigger an Option speed shortcut")
        }
        let combo = wheel(flags: [.maskAlternate, .maskShift])
        suite.expect(prefs.factor(for: combo, horizontalModifier: nil, targetsOwnWindow: false) == nil,
                     "multi-modifier combinations leave speed alone")
        let plain = wheel(flags: [])
        suite.expect(prefs.factor(for: plain, horizontalModifier: nil, targetsOwnWindow: false) == nil,
                     "unmodified scrolling stays at normal speed")

        let bothAxes = wheel(continuous: true, flags: .maskAlternate, line: 1, point: 10, fixed: 1)
        bothAxes.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -2)
        bothAxes.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -20)
        bothAxes.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -2)
        ScrollWheelSupport.scaleScrollDeltas(bothAxes, factor: 3, isContinuous: true)
        suite.expect(bothAxes.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 3
            && bothAxes.getIntegerValueField(.scrollWheelEventDeltaAxis2) == -6
            && bothAxes.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == -60,
            "speed scales vertical and horizontal axes together")

        let trackpad = ScrollWheelEventTraits(isContinuous: true, momentumPhase: 1,
                                              scrollPhase: 0, scrollCount: 0)
        suite.expect(!ScrollWheelSupport.isMouseWheel(trackpad, secondsSinceLastGesturePhase: nil),
                     "momentum events stay classified as touch and never reach speed")

        let runtime = (try? String(contentsOfFile: "Sources/Vorssaint/App/FeatureRuntime.swift",
                                   encoding: .utf8)) ?? ""
        suite.expect(runtime.contains(
            ".scrollSpeed: { ScrollInverter.shared.syncWithPreferences() }"),
                     "installing or removing scroll speed re-syncs the shared wheel tap")
        let inverter = (try? String(contentsOfFile: "Sources/Vorssaint/Services/ScrollInverter.swift",
                                    encoding: .utf8)) ?? ""
        suite.expect(inverter.contains("applyScrollSpeed(")
            && inverter.contains("scrollSpeedWanted"),
                     "the raw wheel path multiplies deltas and can keep the tap alive alone")
        let smooth = (try? String(contentsOfFile: "Sources/Vorssaint/Services/SmoothScrollService.swift",
                                  encoding: .utf8)) ?? ""
        suite.expect(smooth.contains("speedScale")
            && smooth.contains("ScrollSpeedPreferences"),
                     "smooth scrolling folds the same multiplier into the glide budget")
    }

    private static func wheel(continuous: Bool = false, flags: CGEventFlags,
                              line: Int64 = 1, point: Int64 = 10, fixed: Double = 1) -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                            wheel1: 0, wheel2: 0, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: line)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: point)
        event.flags = flags
        return event
    }
}
