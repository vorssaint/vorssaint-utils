// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum ScrollHorizontalModifierTests {
    static func run(_ suite: TestSuite) {
        for continuous in [false, true] {
            for modifier in ScrollHorizontalModifier.allCases {
                for sign: Int64 in [-1, 1] {
                    let event = wheel(continuous: continuous, flags: [modifier.flag, .maskAlphaShift],
                                      line: sign * 2, point: sign * 23, fixed: Double(sign) * 2.25)
                    suite.expect(ScrollWheelSupport.redirectVerticalScroll(event, modifier: modifier),
                                 "selected modifier redirects either wheel representation")
                    suite.expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 0
                        && event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 0
                        && event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == 0,
                        "redirected event has no residual vertical movement")
                    suite.expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == sign * 2
                        && event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == sign * 23
                        && event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == Double(sign) * 2.25,
                        "horizontal event preserves signed line, pixel and fractional distances")
                    suite.expect(event.flags == .maskAlphaShift,
                                 "only the claimed modifier is consumed, preventing app zoom or double redirection")
                    suite.expect(event.getIntegerValueField(.eventSourceUserData) == ScrollWheelSupport.horizontalRedirectTag,
                                 "redirected wheel is marked separately from native side-wheel input")
                    suite.expect((event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0) == continuous,
                                 "redirection preserves the device's scroll representation")
                    suite.expect(!ScrollWheelSupport.redirectVerticalScroll(event, modifier: modifier),
                                 "an already redirected event is not redirected again")

                    let axes = SmoothScrollSupport.axes(
                        vertical: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                        horizontal: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                        shiftPressed: event.flags.contains(.maskShift))
                    suite.expect(axes.vertical == 0 && axes.horizontal == Double(sign * 2),
                                 "smooth scrolling keeps the explicit horizontal direction")
                    let inversion = ScrollWheelSupport.inversionPlan(
                        hasVerticalMovement: axes.vertical != 0, hasHorizontalMovement: axes.horizontal != 0,
                        shiftRedirectsVertical: event.flags.contains(.maskShift),
                        invertVertical: true, invertHorizontal: false)
                    suite.expect(!inversion.vertical && !inversion.horizontal,
                                 "vertical inversion does not flip an explicitly horizontal wheel")
                }
            }
        }

        for modifier in ScrollHorizontalModifier.allCases {
            for other in ScrollHorizontalModifier.allCases where other != modifier {
                for flags: CGEventFlags in [other.flag, [modifier.flag, other.flag]] {
                    let event = wheel(flags: flags)
                    suite.expect(!ScrollWheelSupport.redirectVerticalScroll(event, modifier: modifier)
                        && event.flags == flags
                        && event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 1,
                        "other shortcuts and multi-modifier combinations pass through")
                }
            }
        }

        for field: CGEventField in [.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2,
                                   .scrollWheelEventFixedPtDeltaAxis2] {
            let event = wheel(flags: .maskShift)
            event.setDoubleValueField(field, value: 1)
            suite.expect(!ScrollWheelSupport.redirectVerticalScroll(event, modifier: .shift)
                && event.flags == .maskShift,
                "native horizontal or diagonal movement is not redirected or consumed")
        }
        let noModifier = wheel(flags: [])
        suite.expect(!ScrollWheelSupport.redirectVerticalScroll(noModifier, modifier: .shift),
                     "unmodified scrolling stays vertical")
        let empty = wheel(flags: .maskShift, line: 0, point: 0, fixed: 0)
        suite.expect(!ScrollWheelSupport.redirectVerticalScroll(empty, modifier: .shift),
                     "an empty event does not consume the modifier")
        let fraction = wheel(flags: .maskAlternate, line: 0, point: 0, fixed: 0.25)
        suite.expect(ScrollWheelSupport.redirectVerticalScroll(fraction, modifier: .option)
            && fraction.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == 0.25,
            "sub-line high-resolution ticks survive conversion")

        for continuous in [false, true] {
            for inverted in [false, true] {
                let raw = wheel(continuous: continuous, flags: .maskAlternate, line: 0, point: 2, fixed: 0.25)
                ScrollWheelSupport.applyDirection(to: raw, isContinuous: continuous,
                    invertVertical: true, invertHorizontal: inverted, horizontalModifier: .option)
                suite.expect(raw.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == (inverted ? -2 : 2)
                    && raw.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == (inverted ? -0.25 : 0.25),
                    "raw redirection followed by inversion preserves high-resolution distances")
            }
        }
        let disabled = wheel(flags: .maskAlternate)
        ScrollWheelSupport.applyDirection(to: disabled, isContinuous: false,
            invertVertical: false, invertHorizontal: false, horizontalModifier: nil)
        suite.expect(disabled.flags == .maskAlternate
            && disabled.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 1,
            "disabled redirection leaves the existing raw scroll behavior intact")
        let fallback = wheel(flags: .maskAlternate, line: 0, point: 2, fixed: 0)
        ScrollWheelSupport.redirectVerticalScroll(fallback, modifier: .option)
        ScrollWheelSupport.applyDirection(to: fallback, isContinuous: false,
            invertVertical: false, invertHorizontal: true, horizontalModifier: .option)
        suite.expect(fallback.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == -2,
                     "a point-only wheel redirected before raw fallback retains its distance")

        suite.expect(ScrollHorizontalModifier(storageValue: nil) == .shift
            && ScrollHorizontalModifier(storageValue: "unknown") == .shift,
            "missing or invalid modifier settings use the same default as the picker")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.scrollHorizontalEnabled] as? Bool == false,
                     "existing users retain their current scroll behavior")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [
            DefaultsKey.scrollHorizontalEnabled, DefaultsKey.scrollHorizontalModifier,
        ]), "backup and restore include both horizontal-scroll settings")
        suite.expect(AppFeature.scrollInverter.enabledKeys.contains(DefaultsKey.scrollHorizontalEnabled),
                     "horizontal scrolling alone engages the existing feature's permission lifecycle")
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
