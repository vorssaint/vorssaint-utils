// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The raw wheel tap's handler is extracted from ScrollInverter.swift on every
/// test build (Tests/generate_sources.py) and fed real wheel events. Only the
/// services it asks and the defaults it reads are replaced here.
enum LinearScrollTapTests {
    enum StandardDefaults { static var standard = Foundation.UserDefaults() }
    final class Exceptions {
        static let shared = Exceptions()
        var excepted: Set<MouseExceptionScope> = []
        func excludesPointerTarget(_ scope: MouseExceptionScope, at point: CGPoint,
                                   sourceProcessID: Int64 = 0) -> Bool {
            excepted.contains(scope)
        }
    }
    final class Target {
        static let shared = Target()
        func contains(_ point: CGPoint) -> Bool { false }
    }
    final class Session {
        static let shared = Session()
        let isActive = true
    }
    final class Inverter {
        typealias UserDefaults = StandardDefaults
        typealias MouseAppExceptions = Exceptions
        typealias ScrollWheelTarget = Target
        typealias SessionActivity = Session
        // Events built here carry this process's id, which the shipped tap
        // skips as its own glide frames.
        static let ownProcessID: Int64 = -1
        let tapStateLock = NSLock()
        var tap: CFMachPort?
        var lastGesturePhaseTimestamp: UInt64?
        var linearCarryVertical: Double = 0
        var linearCarryHorizontal: Double = 0
    }

    static func run(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.linear-scroll-tap.\(UUID().uuidString)"
        let defaults = Foundation.UserDefaults(suiteName: name)!
        StandardDefaults.standard = defaults
        defer {
            defaults.removePersistentDomain(forName: name)
            Exceptions.shared.excepted = []
        }
        func configure(linear: Bool = true, installed: Bool = true, lines: Int = 3,
                       invert: Bool = false, inverterInstalled: Bool = true,
                       sidewaysKey: ScrollHorizontalModifier? = nil) {
            defaults.set(installed, forKey: AppFeature.linearScroll.availabilityKey)
            defaults.set(linear, forKey: DefaultsKey.linearScrollEnabled)
            defaults.set(lines, forKey: DefaultsKey.linearScrollLines)
            defaults.set(inverterInstalled, forKey: AppFeature.scrollInverter.availabilityKey)
            defaults.set(invert, forKey: DefaultsKey.scrollInverterEnabled)
            defaults.set(sidewaysKey != nil, forKey: AppFeature.scrollHorizontal.availabilityKey)
            defaults.set(sidewaysKey != nil, forKey: DefaultsKey.scrollHorizontalEnabled)
            defaults.set(sidewaysKey?.rawValue, forKey: DefaultsKey.scrollHorizontalModifier)
            Exceptions.shared.excepted = []
        }
        /// One event through the shipped handler; nil when it was held back.
        func deliver(_ event: CGEvent, through inverter: Inverter = Inverter()) -> CGEvent? {
            inverter.handle(type: .scrollWheel, event: event)?.takeUnretainedValue()
        }

        // Notches as a plain Bluetooth wheel sends them with macOS acceleration
        // on: slow, medium and fast turns of the same single notch.
        configure()
        let slow = deliver(wheel(line: 1, fixed: 0.1, point: 1))
        let medium = deliver(wheel(line: 1, fixed: 0.403, point: 5))
        let fast = deliver(wheel(line: 7, fixed: 7.298, point: 73))
        suite.expect([slow, medium, fast].allSatisfy { $0.map(verticalLine) == 3 },
                     "a slow, a medium and a fast notch leave the wheel tap as the same three lines")

        let pointOnly = deliver(wheel(line: 0, fixed: 0, point: 10))
        suite.expect(pointOnly.map(verticalLine) == 3,
                     "a discrete point-only wheel event survives the raw tap and moves one notch")

        configure(lines: 1)
        let fraction = deliver(wheel(line: 1, fixed: 1.5, point: 15))
        suite.expect(fraction.map(verticalLine) == 1 && fraction.map(verticalFixed) == 1,
                     "a high-resolution notch whose line already matches still loses its extra half line")

        configure()
        let carrying = Inverter()
        let quarters = (0..<4).map { _ in deliver(wheel(line: 0, fixed: 0.25, point: 0), through: carrying) }
        let delivered = quarters.compactMap { $0 }
        suite.expect(delivered.map(verticalLine).reduce(0, +) == 3
                        && delivered.allSatisfy { verticalLine($0) != 0 },
                     "four quarter notches add up to one notch, and a quarter that moves no whole line is held back")

        configure()
        let afterException = Inverter()
        _ = deliver(wheel(line: 0, fixed: 0.25, point: 0), through: afterException)
        Exceptions.shared.excepted = [.linearScroll]
        _ = deliver(wheel(line: 1, fixed: 1, point: 10), through: afterException)
        Exceptions.shared.excepted = []
        suite.expect(deliver(wheel(line: 0, fixed: 0.25, point: 0), through: afterException) == nil,
                     "a fractional notch does not carry through an excepted app")

        configure()
        let afterOff = Inverter()
        _ = deliver(wheel(line: 0, fixed: 0.25, point: 0), through: afterOff)
        configure(linear: false)
        _ = deliver(wheel(line: 1, fixed: 1, point: 10), through: afterOff)
        configure()
        suite.expect(deliver(wheel(line: 0, fixed: 0.25, point: 0), through: afterOff) == nil,
                     "a fractional notch does not carry through a disabled interval")

        configure()
        Exceptions.shared.excepted = [.linearScroll]
        let excepted = deliver(wheel(line: 4, fixed: 4, point: 40))
        suite.expect(excepted.map(verticalLine) == 4 && excepted.map(verticalFixed) == 4,
                     "an app on linear scrolling's own list gets the wheel exactly as macOS sent it")

        configure(linear: false)
        let off = deliver(wheel(line: 4, fixed: 4, point: 40))
        configure(installed: false)
        let uninstalled = deliver(wheel(line: 4, fixed: 4, point: 40))
        suite.expect(off.map(verticalLine) == 4 && uninstalled.map(verticalLine) == 4,
                     "linear scrolling switched off or uninstalled leaves the wheel alone")

        configure(invert: true)
        let flipped = deliver(wheel(line: 4, fixed: 4, point: 40))
        configure(invert: true, inverterInstalled: false)
        let inverterRemoved = deliver(wheel(line: 4, fixed: 4, point: 40))
        suite.expect(flipped.map(verticalLine) == -3 && inverterRemoved.map(verticalLine) == 3,
                     "the capped notch is flipped only while the inverter is installed, not because linear scrolling keeps the tap up")

        configure(invert: true)
        Exceptions.shared.excepted = [.scrollDirection]
        let directionExcepted = deliver(wheel(line: 4, fixed: 4, point: 40))
        suite.expect(directionExcepted.map(verticalLine) == 3,
                     "an app excepted from the direction change is still capped by linear scrolling")

        configure(sidewaysKey: .option)
        let sideways = deliver(wheel(line: 4, fixed: 4, point: 40, flags: .maskAlternate))
        suite.expect(sideways.map(verticalLine) == 0
                        && sideways?.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 3,
                     "a modifier-held notch is capped before it is turned sideways")

        configure()
        let nativeZoom = deliver(wheel(line: 4, fixed: 4, point: 40, flags: .maskControl))
        suite.expect(nativeZoom.map(verticalLine) == 4 && nativeZoom.map(verticalFixed) == 4,
                     "Control-wheel keeps native zoom when Control is not the horizontal shortcut")
        configure(sidewaysKey: .control)
        let controlSideways = deliver(wheel(line: 4, fixed: 4, point: 40, flags: .maskControl))
        suite.expect(controlSideways.map(verticalLine) == 0
                        && controlSideways?.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 3,
                     "the explicit Control-to-horizontal shortcut still receives the fixed notch")
        Exceptions.shared.excepted = [.scrollDirection]
        let exceptedZoom = deliver(wheel(line: 4, fixed: 4, point: 40, flags: .maskControl))
        suite.expect(exceptedZoom.map(verticalLine) == 4,
                     "a direction exception also preserves Control-wheel zoom")

        configure()
        let continuous = deliver(wheel(continuous: true, line: 0, fixed: 4, point: 40))
        suite.expect(continuous?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 30
                        && continuous.map(verticalFixed) == 3,
                     "a wheel reported as continuous is capped in the points and lines apps read")

        configure()
        let trackpad = wheel(continuous: true, line: 0, fixed: 4, point: 40)
        trackpad.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
        suite.expect(deliver(trackpad)?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 40,
                     "a trackpad gesture passes through untouched")
        independentDirections(suite, defaults: defaults)
    }

    private static func independentDirections(_ suite: TestSuite, defaults: Foundation.UserDefaults) {
        // Exercise the actual callback across every independent device/axis
        // choice, keeping linear scrolling and wheel redirection engaged.
        for mouseVertical in [false, true] {
            for mouseHorizontal in [false, true] {
                for trackpadVertical in [false, true] {
                    for trackpadHorizontal in [false, true] {
                        defaults.set(mouseVertical, forKey: DefaultsKey.scrollInverterEnabled)
                        defaults.set(mouseHorizontal, forKey: DefaultsKey.scrollInverterHorizontalEnabled)
                        defaults.set(trackpadVertical, forKey: DefaultsKey.scrollInverterTrackpadEnabled)
                        defaults.set(trackpadHorizontal, forKey: DefaultsKey.scrollInverterTrackpadHorizontalEnabled)
                        defaults.set(true, forKey: AppFeature.scrollInverter.availabilityKey)
                        defaults.set(true, forKey: DefaultsKey.linearScrollEnabled)
                        defaults.set(true, forKey: AppFeature.scrollHorizontal.availabilityKey)
                        defaults.set(true, forKey: DefaultsKey.scrollHorizontalEnabled)
                        defaults.set("option", forKey: DefaultsKey.scrollHorizontalModifier)
                        let preferences = ScrollDirectionPreferences(defaults: defaults)
                        suite.expect(preferences.invertTrackpadVertical == trackpadVertical
                            && preferences.invertTrackpadHorizontal == trackpadHorizontal,
                            "trackpad preferences stay independent of mouse axes")
                        let inverter = Inverter()
                        for phase in [Int64(1), 2, 4, 8] {
                            let event = twoAxisTouch(scrollPhase: phase)
                            _ = inverter.handle(type: .scrollWheel, event: event)
                            suite.expect(verticalLine(event) == (trackpadVertical ? -2 : 2)
                                && verticalFixed(event) == (trackpadVertical ? -2.5 : 2.5)
                                && event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                                    == (trackpadVertical ? -25 : 25)
                                && event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
                                    == (trackpadHorizontal ? -1 : 1)
                                && event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
                                    == (trackpadHorizontal ? -1.25 : 1.25)
                                && event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
                                    == (trackpadHorizontal ? -12 : 12),
                                "touch events reverse only selected trackpad axes and retain fractional deltas")
                            suite.expect(event.flags == .maskAlternate
                                && event.getIntegerValueField(.scrollWheelEventScrollPhase) == phase,
                                "trackpad modifiers and gesture phases reach the app intact")
                        }
                        // Lifted fingers and the phaseless handoff keep the
                        // trackpad's choice; a discrete wheel overrides that history.
                        for momentum in [Int64(1), 2, 3] {
                            let event = twoAxisTouch(momentumPhase: momentum)
                            _ = inverter.handle(type: .scrollWheel, event: event)
                            suite.expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                                    == (trackpadVertical ? -25 : 25),
                                "momentum keeps the same trackpad reversal as finger scrolling")
                        }
                        let transition = twoAxisTouch()
                        transition.setIntegerValueField(.scrollWheelEventScrollCount, value: 1)
                        _ = inverter.handle(type: .scrollWheel, event: transition)
                        suite.expect(transition.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                                == (trackpadVertical ? -25 : 25),
                            "a phaseless gesture transition retains the trackpad direction")
                        let mouse = wheel(line: 4, fixed: 4, point: 40)
                        _ = inverter.handle(type: .scrollWheel, event: mouse)
                        suite.expect(verticalLine(mouse) == (mouseVertical ? -3 : 3),
                            "switching from trackpad momentum to a wheel uses the mouse direction and linear cap")
                        let sideways = wheel(line: 4, fixed: 4, point: 40, flags: .maskAlternate)
                        _ = inverter.handle(type: .scrollWheel, event: sideways)
                        suite.expect(sideways.getIntegerValueField(.scrollWheelEventDeltaAxis2)
                                == (mouseHorizontal ? -3 : 3),
                            "redirected mouse wheels use the mouse horizontal choice")
                    }
                }
            }
        }

        func untouched(_ event: CGEvent, message: String) {
            _ = Inverter().handle(type: .scrollWheel, event: event)
            suite.expect(verticalLine(event) == 2 && verticalFixed(event) == 2.5
                && event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 25, message)
        }
        Exceptions.shared.excepted = [.scrollDirection]
        untouched(twoAxisTouch(scrollPhase: 1), message: "direction exclusions also preserve trackpad scrolling")
        Exceptions.shared.excepted = []
        let zoom = twoAxisTouch(scrollPhase: 1)
        zoom.flags = .maskControl
        untouched(zoom, message: "Control-trackpad zoom keeps its native direction")
        let synthetic = twoAxisTouch(scrollPhase: 1)
        synthetic.setIntegerValueField(.eventSourceUserData, value: ScrollWheelSupport.syntheticTag)
        untouched(synthetic, message: "synthetic glide events are never reversed twice")
        defaults.set(false, forKey: AppFeature.scrollInverter.availabilityKey)
        untouched(twoAxisTouch(scrollPhase: 1), message: "removing inversion stops trackpad reversal even with linear scrolling active")

        defaults.set(true, forKey: AppFeature.scrollInverter.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.scrollInverterEnabled)
        defaults.set(false, forKey: DefaultsKey.scrollInverterHorizontalEnabled)
        defaults.set(false, forKey: DefaultsKey.scrollHorizontalEnabled)
        suite.expect(ScrollDirectionPreferences(defaults: defaults).isEnabled,
                     "trackpad-only reversal keeps the direction tap alive")
    }

    private static func twoAxisTouch(scrollPhase: Int64 = 0, momentumPhase: Int64 = 0) -> CGEvent {
        let event = wheel(continuous: true, line: 2, fixed: 2.5, point: 25, flags: .maskAlternate)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 1.25)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 12)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        return event
    }

    private static func verticalLine(_ event: CGEvent) -> Int64 {
        event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    }

    private static func verticalFixed(_ event: CGEvent) -> Double {
        event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
    }

    private static func wheel(continuous: Bool = false, line: Int64, fixed: Double, point: Int64,
                              flags: CGEventFlags = []) -> CGEvent {
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
