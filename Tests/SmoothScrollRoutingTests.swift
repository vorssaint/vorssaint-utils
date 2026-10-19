// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

/// Production admission, frame generation and cancellation run against real
/// CGEvents. Scheduling, preferences and final delivery are controlled here;
/// this suite never posts input to another process or moves the pointer.
enum SmoothScrollRoutingTests {
    enum DefaultsStore { static var standard = Foundation.UserDefaults() }
    final class Exceptions {
        static let shared = Exceptions()
        var scopes = Set<MouseExceptionScope>()
        func excludesPointerTarget(_ scope: MouseExceptionScope, at point: CGPoint,
                                   sourceProcessID: Int64 = 0) -> Bool { scopes.contains(scope) }
    }
    final class Inverter {
        static let shared = Inverter()
        var isRunning = true
    }
    final class Switcher {
        static let shared = Switcher()
        var scrollNavigationActive = false
    }
    final class Target {
        static let shared = Target()
        func contains(_ point: CGPoint) -> Bool { false }
    }
    final class Session {
        static let shared = Session()
        var isActive = true
    }
    enum Capture {
        static func steppedLoupeNeedsRawWheel(optionPressed: Bool) -> Bool { false }
    }
    enum Shortcuts {
        static let hasActiveSideWheelInterest = false
        static func claimsSideWheel<T>(_ input: T, at point: CGPoint, sourceProcessID: Int64,
                                       eventTimestamp: UInt64) -> Bool { false }
    }
    final class Service {
        typealias UserDefaults = DefaultsStore
        typealias MouseAppExceptions = Exceptions
        typealias ScrollInverter = Inverter
        typealias AppSwitcher = Switcher
        typealias ScrollWheelTarget = Target
        typealias SessionActivity = Session
        typealias ScreenshotSelectionController = Capture
        typealias MouseButtonShortcutService = Shortcuts
        // Test events carry the harness pid; the real service rejects its own.
        static let ownProcessID: Int64 = -1
        var tap: CFMachPort?
        var engine = SmoothScrollSupport.Engine()
        var targetLatch = SmoothScrollSupport.TargetLatch()
        var targetEvent: CGEvent?
        var lastFrameTimestamp: TimeInterval?
        var currentResponse = SmoothScrollSupport.defaultResponse
        var currentCoast = SmoothScrollSupport.defaultCoast
        var carryVertical: Double = 0, carryHorizontal: Double = 0
        var currentFlags: CGEventFlags = []
        var currentScrollRedirected = false, glideFromContinuous = false
        var lastGesturePhaseTimestamp: UInt64?
        var scheduled = false
        func startGlideIfNeeded() { scheduled = true }
        func stopFrameScheduler() { scheduled = false; lastFrameTimestamp = nil }
        func stop() { stopGlide() }
        func syncWithPreferences() {}
    }
    static var posted: [(pid: pid_t, event: CGEvent)] = []
    static func record(_ event: CGEvent, to pid: pid_t) { posted.append((pid, event)) }

    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        let domain = "vorss.tests.smooth-routing.\(UUID().uuidString)"
        let defaults = Foundation.UserDefaults(suiteName: domain)!
        DefaultsStore.standard = defaults
        defaults.set(40, forKey: DefaultsKey.smoothScrollStep)
        defaults.set(SmoothScrollSupport.defaultResponse, forKey: DefaultsKey.smoothScrollResponse)
        defaults.set(0, forKey: DefaultsKey.smoothScrollCoast)
        defer {
            defaults.removePersistentDomain(forName: domain)
            Exceptions.shared.scopes = []
            posted = []
        }
        let a = CGPoint(x: 120, y: 240), b = CGPoint(x: 900, y: 600)
        func wheel(_ point: CGPoint = CGPoint(x: 120, y: 240), pid: Int64 = 41, window: Int = 101,
                   flags: CGEventFlags = []) -> CGEvent {
            // AppKit's public factory supplies a window annotation. Change
            // only the type and wheel fields; no synthetic event is posted.
            let ns = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
                timestamp: 1, windowNumber: window, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            let event = ns.cgEvent!
            event.type = .scrollWheel
            event.location = point
            event.flags = flags
            event.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 1)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 1)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 10)
            return event
        }
        func tick(_ service: Service, _ event: CGEvent) -> CGEvent? {
            service.handle(type: .scrollWheel, event: event)?.takeUnretainedValue()
        }
        func frame(_ service: Service, at time: TimeInterval = 1) {
            service.emitFrame(at: time, firstElapsed: SmoothScrollSupport.frameInterval)
        }
        let original = wheel()
        suite.expect(NSEvent(cgEvent: original)?.windowNumber == 101,
                     "the routing fixture carries an AppKit window annotation")
        let service = Service()
        suite.expect(tick(service, original) == nil && service.scheduled && service.engine.remainingVertical == 40,
                     "an annotated wheel tick is swallowed and queues exactly one glide step")
        frame(service)
        frame(service, at: 1.02)
        suite.expect(posted.count == 2 && posted.allSatisfy {
            $0.pid == 41 && $0.event.location == a && NSEvent(cgEvent: $0.event)?.windowNumber == 101
        }, "every tail frame retains the original process, window and point instead of the current pointer")
        suite.expect(posted.allSatisfy {
            $0.event.getIntegerValueField(.eventSourceUserData) == ScrollWheelSupport.syntheticTag
                && $0.event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1
                && $0.event.timestamp != original.timestamp
        } && original.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 1,
                     "glide frames are marked continuous copies with fresh timestamps and leave the input intact")
        let remaining = service.engine.remainingVertical
        _ = tick(service, wheel())
        suite.expectClose(service.engine.remainingVertical, remaining + 40,
                          "new input at the same target extends the remaining distance")
        service.carryVertical = 0.7
        _ = tick(service, wheel(b))
        suite.expect(service.engine.remainingVertical == 40 && service.carryVertical == 0,
                     "fresh input in another pane drops the old tail and fractional carry immediately")
        frame(service, at: 1.04)
        suite.expect(posted.last?.event.location == b && posted.last?.pid == 41,
                     "the first frame after fresh input goes to the new pane")
        _ = tick(service, wheel(b, pid: 42, window: 202))
        frame(service, at: 1.06)
        suite.expect(posted.last?.pid == 42 && NSEvent(cgEvent: posted.last!.event)?.windowNumber == 202,
                     "a new window at the same point also replaces the receiver")
        _ = tick(service, wheel(b, pid: 42, window: 203, flags: .maskShift))
        suite.expect(service.engine.remainingVertical == 0 && service.engine.remainingHorizontal == 40,
                     "a Shift change still resets the old axis while changing the target")
        service.stopGlide()
        let stoppedCount = posted.count
        frame(service, at: 1.08)
        suite.expect(!service.engine.isActive && !service.scheduled && service.targetEvent == nil
                && service.targetLatch.target == nil && posted.count == stoppedCount,
                     "stopping a glide clears routing and a late frame cannot deliver it")

        for event in [wheel(pid: 0), wheel(window: 0)] {
            let unknown = Service()
            suite.expect(tick(unknown, event) === event && !unknown.engine.isActive && !unknown.scheduled,
                         "an event without a usable receiver passes through without swallowing distance")
        }
        let ignored = Service()
        _ = tick(ignored, wheel())
        let synthetic = wheel()
        synthetic.setIntegerValueField(.eventSourceUserData, value: ScrollWheelSupport.syntheticTag)
        suite.expect(tick(ignored, synthetic) === synthetic && ignored.engine.remainingVertical == 40,
                     "a replayed frame passes through without extending or cancelling the glide")
        Exceptions.shared.scopes = [.smoothScroll]
        let excepted = wheel(b)
        suite.expect(tick(ignored, excepted) === excepted && !ignored.engine.isActive,
                     "fresh input for an excepted app cancels the old tail and stays raw")
        Exceptions.shared.scopes = []
        _ = tick(ignored, wheel())
        let zoom = wheel(flags: .maskControl)
        suite.expect(tick(ignored, zoom) === zoom && !ignored.engine.isActive,
                     "native Control-wheel zoom cancels the previous glide and passes through")
        _ = tick(ignored, wheel())
        let trackpad = wheel()
        trackpad.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        trackpad.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
        suite.expect(tick(ignored, trackpad) === trackpad && !ignored.engine.isActive,
                     "a trackpad gesture cancels a wheel tail without being smoothed")

        let continuous = Service()
        _ = tick(continuous, wheel())
        let driver = wheel()
        driver.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        driver.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 4)
        driver.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 40)
        _ = tick(continuous, driver)
        suite.expect(continuous.engine.remainingVertical == 40 && continuous.glideFromContinuous,
                     "a continuous wheel keeps its pixel distance and replaces the discrete tail")
        defaults.set(true, forKey: AppFeature.scrollInverter.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.scrollInverterEnabled)
        let inverted = Service()
        _ = tick(inverted, wheel())
        suite.expect(inverted.engine.remainingVertical == -40,
                     "smoothing applies vertical inversion once before targeted delivery")
        defaults.set(true, forKey: AppFeature.scrollHorizontal.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.scrollHorizontalEnabled)
        defaults.set(ScrollHorizontalModifier.option.rawValue, forKey: DefaultsKey.scrollHorizontalModifier)
        defaults.set(true, forKey: DefaultsKey.scrollInverterHorizontalEnabled)
        let redirected = Service()
        _ = tick(redirected, wheel(flags: .maskAlternate))
        frame(redirected)
        suite.expect(redirected.engine.remainingVertical == 0 && redirected.engine.remainingHorizontal < 0
                && posted.last?.event.flags.contains(.maskAlternate) == false
                && posted.last!.event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) < 0,
                     "targeted frames retain horizontal redirection and consume its modifier once")
        Exceptions.shared.scopes = [.scrollDirection]
        let directionException = Service()
        _ = tick(directionException, wheel(flags: .maskAlternate))
        suite.expect(directionException.engine.remainingVertical == 40
                && directionException.engine.remainingHorizontal == 0,
                     "a direction exception leaves smoothing enabled without inversion or redirection")
        Exceptions.shared.scopes = []
        defaults.set(false, forKey: DefaultsKey.scrollInverterEnabled)
        defaults.set(false, forKey: DefaultsKey.scrollInverterHorizontalEnabled)
        defaults.set(false, forKey: DefaultsKey.scrollHorizontalEnabled)
        defaults.set(true, forKey: AppFeature.linearScroll.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.linearScrollEnabled)
        defaults.set(3, forKey: DefaultsKey.linearScrollLines)
        let capped = Service()
        let fastNotch = wheel()
        fastNotch.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 7)
        _ = tick(capped, fastNotch)
        suite.expect(capped.engine.remainingVertical == 120,
                     "linear scrolling still caps a fast raw notch before it is smoothed")
        defaults.set(false, forKey: DefaultsKey.linearScrollEnabled)

        posted = []
        let landing = Service()
        _ = tick(landing, wheel())
        for index in 0..<200 where landing.engine.isActive { frame(landing, at: Double(index) * 0.05) }
        let distance = posted.reduce(Int64(0)) { $0 + $1.event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) }
        suite.expect(distance == 40 && !landing.scheduled && landing.targetEvent == nil
                && landing.targetLatch.target == nil,
                     "a complete glide delivers its full distance and releases the original receiver")
        for path in ["Sources/Vorssaint/Services/SmoothScrollService.swift", "Sources/Vorssaint/Services/ScrollInverter.swift"] {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            suite.expect(source.contains("tap: ScrollWheelSupport.tapLocation"),
                         "both wheel taps retain their ordering at the stage with window annotations")
        }
        suite.expect(ScrollWheelSupport.tapLocation == .cgAnnotatedSessionEventTap,
                     "wheel routing starts after the window server identifies its receiver")
    }
}
