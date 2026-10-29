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
        var consumesZoom = false
        var zoomRequests = 0
        func consumeZoom(_ event: CGEvent, direction: ScrollDirectionPreferences) -> Bool {
            zoomRequests += 1
            return consumesZoom
        }
    }
    final class Switcher {
        static let shared = Switcher()
        var scrollNavigationActive = false
    }
    final class Target {
        static let shared = Target()
        var isOwn = false
        func contains(_ point: CGPoint) -> Bool { isOwn }
    }
    final class Session {
        static let shared = Session()
        var isActive = true
    }
    enum Capture {
        static func steppedLoupeNeedsRawWheel(optionPressed: Bool) -> Bool { false }
    }
    /// Whether the event came in at the HID stage; false stands for a remote
    /// screen's scroll, posted further down.
    final class HIDStage {
        static let shared = HIDStage()
        var passes = true
        func passed(_ event: CGEvent) -> Bool { passes }
    }
    final class Service {
        typealias UserDefaults = DefaultsStore
        typealias MouseAppExceptions = Exceptions
        typealias ScrollInverter = Inverter
        typealias AppSwitcher = Switcher
        typealias ScrollWheelTarget = Target
        typealias SessionActivity = Session
        typealias ScreenshotSelectionController = Capture
        typealias ScrollWheelHIDStage = HIDStage
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
            HIDStage.shared.passes = true
            Inverter.shared.consumesZoom = false
            Inverter.shared.zoomRequests = 0
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
        let drifted = service.engine.remainingVertical
        _ = tick(service, wheel(CGPoint(x: a.x + 1, y: a.y + 1)))
        _ = tick(service, wheel(CGPoint(x: a.x + 6, y: a.y)))
        suite.expectClose(service.engine.remainingVertical, drifted + 80,
                          "a pointer drifting a few points between ticks keeps the glide it is extending")
        let moving = service.engine.remainingVertical
        _ = tick(service, wheel(CGPoint(x: a.x + 6, y: a.y + 20)))
        suite.expectClose(service.engine.remainingVertical, moving + 40,
                          "a pointer still moving while the wheel turns keeps the glide it is extending")
        _ = tick(service, wheel(CGPoint(x: a.x + 6 + SmoothScrollSupport.TargetLatch.driftTolerance + 1, y: a.y + 20)))
        suite.expect(service.engine.remainingVertical == 40,
                     "a pointer that moved past the drift tolerance starts a new glide")
        _ = tick(service, wheel())
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

        // Screen Sharing posts the controlling computer's scroll, trackpad
        // included, at the session tap as phaseless pixel events.
        let local = Service()
        _ = tick(local, wheel())
        let localBudget = local.engine.remainingVertical
        HIDStage.shared.passes = false
        let remote = wheel(b, pid: 42, window: 202)
        remote.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        remote.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 4)
        remote.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 40)
        suite.expect(tick(local, remote) === remote
                && remote.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 40
                && local.engine.remainingVertical == localBudget && local.scheduled
                && local.targetLatch.target?.point == a,
                     "a remote screen's scroll passes through raw and leaves the local glide on its window")
        HIDStage.shared.passes = true

        // An event stamped in mach ticks as the HID tap reads it on Apple
        // Silicon, and the nanoseconds a session tap reports for it (#1689).
        let appleSilicon = EventTimestamp.Timebase(numer: 125, denom: 3)
        let hidTicks: UInt64 = 3_253_805_719_584, sessionNanoseconds: UInt64 = 135_575_238_316_000
        let nowTicks = hidTicks + 24_000
        var ledger = ScrollWheelHIDStageLedger()
        // Posted events carry their poster's process id; hardware carries 0.
        func passed(_ raw: UInt64, source: Int64 = 77) -> Bool {
            ledger.passed(raw, sourceProcessID: source, nowTicks: nowTicks, timebase: appleSilicon)
        }
        func note(_ raw: UInt64) { ledger.note(raw, nowTicks: nowTicks, timebase: appleSilicon) }
        suite.expect(passed(sessionNanoseconds) && passed(0),
                     "with no HID tap watching, every wheel event counts as local")
        ledger.isWatching = true
        suite.expect(passed(sessionNanoseconds + 300_000, source: 0),
                     "a hardware event counts as local whatever its timestamp reads, since it can only come in at the HID stage")
        note(hidTicks)
        suite.expect(passed(sessionNanoseconds),
                     "an event noted in mach ticks at the HID stage is found by the nanoseconds the annotated stage reads")
        let postedAtHID = sessionNanoseconds + 200_000
        note(postedAtHID)
        suite.expect(passed(postedAtHID),
                     "an event posted at the HID stage, in nanoseconds at both stages, is found too")
        suite.expect(!passed(sessionNanoseconds + 100_000) && !passed(0),
                     "while the HID tap watches, only events it noted count as local")
        let capacity = UInt64(ScrollWheelHIDStageLedger.capacity)
        let later = sessionNanoseconds + 1_000_000
        for index in 0..<capacity { note(later + index * 10_000) }
        suite.expect(!passed(sessionNanoseconds) && passed(later) && passed(later + (capacity - 1) * 10_000),
                     "the HID stage ledger keeps the last \(capacity) events, oldest out first")
        ledger.reset()
        suite.expect(passed(sessionNanoseconds + 100_000), "a watch that was torn down counts every event as local again")

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

        defaults.set(true, forKey: AppFeature.scrollZoom.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.pinchZoomEnabled)
        defaults.set(ScrollZoomModifier.control.rawValue, forKey: DefaultsKey.pinchZoomModifier)
        _ = tick(ignored, wheel())
        let pendingZoom = wheel(flags: .maskControl)
        suite.expect(tick(ignored, pendingZoom) === pendingZoom && !ignored.engine.isActive
                        && Inverter.shared.zoomRequests == 1,
                     "a declined configured Pinch tick stays raw and cancels the previous glide")
        Inverter.shared.consumesZoom = true
        suite.expect(tick(ignored, wheel(flags: .maskControl)) == nil && !ignored.engine.isActive,
                     "a handled Zoom tick is consumed without starting a glide")
        defaults.set(false, forKey: AppFeature.scrollZoom.availabilityKey)
        Inverter.shared.consumesZoom = false
        Target.shared.isOwn = true
        defaults.set(true, forKey: AppFeature.scrollZoom.availabilityKey)
        defaults.set(ScrollZoomModifier.option.rawValue, forKey: DefaultsKey.pinchZoomModifier)
        defaults.set(true, forKey: AppFeature.scrollInverter.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.scrollInverterEnabled)
        let ownZoom = Service()
        suite.expect(tick(ownZoom, wheel(flags: .maskAlternate)) == nil && ownZoom.engine.remainingVertical < 0,
                     "a declined zoom on our panel still takes the normal inverted smooth-scroll path")
        Target.shared.isOwn = false
        defaults.set(false, forKey: AppFeature.scrollZoom.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.scrollInverterEnabled)
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
        // A listener is told asynchronously and could note an event after it
        // already reached the wheel taps; an active tap holds it until then.
        let stage = (try? String(contentsOfFile: "Sources/Vorssaint/Services/ScrollWheelHIDStage.swift",
                                 encoding: .utf8)) ?? ""
        suite.expect(stage.contains("tap: .cghidEventTap") && stage.contains("options: .defaultTap"),
                     "the HID stage is watched by an active HID tap, so its note is in before the event moves on")
        let smooth = (try? String(contentsOfFile: "Sources/Vorssaint/Services/SmoothScrollService.swift",
                                  encoding: .utf8)) ?? ""
        let inverter = (try? String(contentsOfFile: "Sources/Vorssaint/Services/ScrollInverter.swift",
                                    encoding: .utf8)) ?? ""
        suite.expect(smooth.contains("ScrollWheelHIDStage.shared.setWatching(true, for: .smoothScroll)")
                && inverter.contains("ScrollWheelHIDStage.shared.setWatching(true, for: .wheelTap)"),
                     "both wheel taps keep the HID stage watched while they run")
        // That stage comes after the session taps that keep the wheel for
        // themselves, so they turn it the way Scroll Direction would.
        let layout = (try? String(contentsOfFile: "Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift",
                                  encoding: .utf8)) ?? ""
        suite.expect(layout.contains("let wheel = ScrollInverter.directionApplied(to: event)")
                && layout.contains("let deltaY = wheel.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)")
                && layout.contains("let fixedDeltaY = wheel.getIntegerValueField(.scrollWheelEventDeltaAxis1)"),
                     "the directional window gesture reads the wheel the way Scroll Direction turns it")
    }
}
