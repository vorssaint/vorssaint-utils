// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum ScrollHorizontalModifierTests {
    static func run(_ suite: TestSuite) {
        ownWindowGestures(suite)
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
        suite.expect(AppFeature.scrollHorizontal.enabledKeys == [DefaultsKey.scrollHorizontalEnabled],
                     "horizontal scrolling has its own permission lifecycle")
        suite.expect(AppFeature.availabilityDefaults[AppFeature.scrollHorizontal.availabilityKey] as? Bool == false,
                     "the new feature ships uninstalled")
        suite.expect(AppFeature.scrollHorizontal.settingsDestination
            == AppFeature.scrollInverter.settingsDestination,
            "both direction features open the same scroll settings section")

        // Saved settings remain on through removal/reinstallation. Exercise all
        // installation and toggle combinations without changing the user's defaults.
        for installedInversion in [false, true] {
            for installedHorizontal in [false, true] {
                for vertical in [false, true] {
                    for horizontal in [false, true] {
                        for redirect in [false, true] {
                            let available: (AppFeature) -> Bool = {
                                ($0 == .scrollInverter && installedInversion)
                                    || ($0 == .scrollHorizontal && installedHorizontal)
                            }
                            let boolFor: (String) -> Bool = {
                                switch $0 {
                                case DefaultsKey.scrollInverterEnabled: return vertical
                                case DefaultsKey.scrollInverterHorizontalEnabled: return horizontal
                                case DefaultsKey.scrollHorizontalEnabled: return redirect
                                default: return false
                                }
                            }
                            let direction = ScrollDirectionPreferences(isAvailable: available,
                                boolFor: boolFor, stringFor: { _ in "option" })
                            let wantsInversion = installedInversion && (vertical || horizontal)
                            let wantsRedirect = installedHorizontal && redirect
                            suite.expect(direction.isEnabled == (wantsInversion || wantsRedirect),
                                         "shared tap stays active exactly while an installed feature needs it")
                            let event = wheel(flags: .maskAlternate)
                            ScrollWheelSupport.applyDirection(to: event, isContinuous: false,
                                invertVertical: direction.invertVertical,
                                invertHorizontal: direction.invertHorizontal,
                                horizontalModifier: direction.horizontalModifier)
                            suite.expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                                == (wantsRedirect ? 0 : (installedInversion && vertical ? -1 : 1))
                                && event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
                                == (wantsRedirect ? (installedInversion && horizontal ? -1 : 1) : 0),
                                "removing either feature stops only its own transformation")
                            let active = AppFeature.activeFeatures(using: .accessibility,
                                isAvailable: available, boolFor: boolFor, stringFor: { _ in nil })
                            suite.expect(active.contains(.scrollHorizontal) == wantsRedirect
                                && active.contains(.scrollInverter) == wantsInversion,
                                "permissions report only installed and enabled direction features")
                        }
                    }
                }
            }
        }
    }

    private static func ownWindowGestures(_ suite: TestSuite) {
        let ownPID: Int32 = 41
        let point = CGPoint(x: 100, y: 150)
        func window(_ id: Int, pid: Int32, layer: Int = 0, alpha: Double = 1,
                    frame: CGRect = CGRect(x: 0, y: 0, width: 400, height: 300)) -> [String: Any] {
            [kCGWindowNumber as String: id,
             kCGWindowOwnerPID as String: pid,
             kCGWindowLayer as String: layer,
             kCGWindowAlpha as String: alpha,
             kCGWindowBounds as String: ["X": frame.minX, "Y": frame.minY,
                                        "Width": frame.width, "Height": frame.height]]
        }
        let editor = window(1, pid: ownPID)
        let external = window(2, pid: 52)
        let overlay = window(3, pid: ownPID, layer: 1_000)
        func ownTarget(_ windows: [[String: Any]], at point: CGPoint = point,
                       clickThrough: Set<CGWindowID> = []) -> Bool {
            ScrollWheelSupport.targetsOwnWindow(in: windows, at: point,
                ownProcessID: ownPID, clickThroughWindowIDs: clickThrough)
        }
        suite.expect(ownTarget([editor, external]), "the editor under the pointer owns its wheel gesture")
        suite.expect(ownTarget([overlay, external]), "high-level capture overlays own their wheel gestures")
        suite.expect(!ownTarget([external, editor]), "an external window occludes our editor")
        suite.expect(!ownTarget([overlay, external], clickThrough: [3]),
                     "our click-through overlay does not claim the external app's wheel")
        suite.expect(ownTarget([overlay, editor], clickThrough: [3]),
                     "our editor remains the target beneath a click-through overlay")
        suite.expect(!ownTarget([window(4, pid: ownPID, alpha: 0), external]),
                     "a transparent own window does not claim the wheel")
        suite.expect(!ownTarget([editor], at: CGPoint(x: 500, y: 150)),
                     "an own window elsewhere does not disable horizontal scrolling")
        suite.expect(ownTarget([window(5, pid: ownPID,
            frame: CGRect(x: -400, y: -300, width: 400, height: 300))],
            at: CGPoint(x: -100, y: -150)), "target lookup preserves secondary-display Quartz coordinates")

        for continuous in [false, true] {
            for modifier in [ScrollHorizontalModifier.option, .control] {
                let targetWindows = modifier == .option ? [overlay, external] : [editor, external]
                // The smooth path calls the redirect helper directly; the raw
                // fallback applies it through the direction helper.
                let event = wheel(continuous: continuous, flags: modifier.flag,
                                  line: 2, point: 23, fixed: 2.25)
                suite.expect(!ScrollWheelSupport.redirectVerticalScroll(event, modifier: modifier,
                    targetsOwnWindow: ownTarget(targetWindows)),
                    "smoothing does not claim capture Option or editor Control gestures")
                ScrollWheelSupport.applyDirection(to: event, isContinuous: continuous,
                    invertVertical: false, invertHorizontal: false, horizontalModifier: modifier,
                    targetsOwnWindow: ownTarget(targetWindows))
                suite.expect(event.flags == modifier.flag
                    && event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 2
                    && event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 23
                    && event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == 2.25
                    && event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 0
                    && event.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.horizontalRedirectTag,
                    "own-window wheel gestures retain the modifier, original axis and precise distance")
                suite.expect(ScrollWheelSupport.redirectVerticalScroll(event, modifier: modifier,
                    targetsOwnWindow: ownTarget([external, editor]))
                    && event.flags.isEmpty
                    && event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 23,
                    "the same modifier still redirects the external window in front")
            }
        }
        var lookupCount = 0
        func resolveTarget() -> Bool { lookupCount += 1; return false }
        let ordinary = wheel(flags: [])
        ScrollWheelSupport.redirectVerticalScroll(ordinary, modifier: .option,
            targetsOwnWindow: resolveTarget())
        suite.expect(lookupCount == 0, "unmodified scrolling never queries the window target")
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
