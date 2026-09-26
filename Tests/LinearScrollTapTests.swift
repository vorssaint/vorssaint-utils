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
        let continuous = deliver(wheel(continuous: true, line: 0, fixed: 4, point: 40))
        suite.expect(continuous?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 30
                        && continuous.map(verticalFixed) == 3,
                     "a wheel reported as continuous is capped in the points and lines apps read")

        configure()
        let trackpad = wheel(continuous: true, line: 0, fixed: 4, point: 40)
        trackpad.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
        suite.expect(deliver(trackpad)?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 40,
                     "a trackpad gesture passes through untouched")
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
