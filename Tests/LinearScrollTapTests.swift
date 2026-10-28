// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Carbon.HIToolbox
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
        var isOwn = false
        let clickThroughWindowIDs = Set<CGWindowID>()
        func contains(_ point: CGPoint) -> Bool { isOwn }
    }
    final class Session {
        static let shared = Session()
        let isActive = true
    }
    /// False stands for a remote screen's scroll, posted below the HID stage.
    final class HIDStage {
        static let shared = HIDStage()
        var passes = true
        func passed(_ event: CGEvent) -> Bool { passes }
    }
    /// Mouse button shortcuts' side-wheel reader, extracted as shipped.
    final class SideWheel {
        typealias ScrollInverter = Inverter
        var lastGesturePhaseTimestamp: UInt64?
    }
    final class Switcher {
        static let shared = Switcher()
        var scrollNavigationActive = false
    }
    final class Inverter {
        typealias UserDefaults = StandardDefaults
        typealias MouseAppExceptions = Exceptions
        typealias ScrollWheelTarget = Target
        typealias SessionActivity = Session
        typealias ScrollWheelHIDStage = HIDStage
        typealias AppSwitcher = Switcher
        // Events built here carry this process's id, which the shipped tap
        // skips as its own glide frames.
        static let ownProcessID: Int64 = -1
        let tapStateLock = NSLock()
        var tap: CFMachPort?
        var lastGesturePhaseTimestamp: UInt64?
        var linearCarryVertical: Double = 0
        var linearCarryHorizontal: Double = 0
        let pinchZoomLock = NSLock()
        var zoomState = ScrollZoomGestureState()
        var zoomTarget: ScrollZoomTargetSnapshot?
        var zoomFocusedTarget: WindowServerWindowCandidate?
        var zoomStepLimiter = ScrollZoomStepLimiter()
        var pinchPosts = 0
        var pinchEvents: [(phase: Int64, point: CGPoint?)] = []
        var keyboardPosts: [pid_t] = []
        var zoomInKeyStroke: (keyCode: CGKeyCode, needsShift: Bool)? = (CGKeyCode(kVK_ANSI_Equal), true)
        var zoomOutKeyStroke: (keyCode: CGKeyCode, needsShift: Bool)? = (CGKeyCode(kVK_ANSI_Minus), false)
        var zoomEvents: [CGEvent] = []
        var activationRequests = 0
        func prepareZoomTargetLocked(for event: CGEvent) {}
        func invalidateZoomTargetLocked() {
            zoomTarget = nil
            zoomFocusedTarget = nil
        }
        func requestZoomTargetLocked(at point: CGPoint, modifier: ScrollHorizontalModifier, activate: Bool = false) {
            if activate { activationRequests += 1 }
        }
        func recordZoomEvent(_ event: CGEvent, to targetProcessID: pid_t) {
            zoomEvents.append(event)
            if event.type == .keyDown { keyboardPosts.append(targetProcessID) }
        }
        func postPinch(phase: Int64, magnification: Double, at point: CGPoint?) {
            pinchEvents.append((phase, point))
            if phase == 2 { pinchPosts += 1 }
        }
    }

    final class TargetResolver {
        enum Reader {
            static func onScreenWindowInfo() -> [[String: Any]] {
                [[kCGWindowOwnerPID as String: 42, kCGWindowNumber as String: 7,
                  kCGWindowLayer as String: 0, kCGWindowAlpha as String: 1,
                  kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 100, height: 100).dictionaryRepresentation]]
            }
        }
        enum Focus {
            static var lookup: (pid_t) -> CGWindowID? = { _ in 7 }
            static func focusedWindowID(for pid: pid_t) -> CGWindowID? { lookup(pid) }
        }
        typealias WindowServerSupport = Reader
        typealias WindowActivator = Focus
        typealias ScrollWheelTarget = Target
        let pinchZoomLock = NSLock()
        let zoomTargetQueue = DispatchQueue(label: "vorssaint.tests.zoom-target-request")
        var zoomTarget: ScrollZoomTargetSnapshot?
        var zoomFocusedTarget: WindowServerWindowCandidate?
        var zoomTargetPending: (modifier: ScrollHorizontalModifier, point: CGPoint, activate: Bool)?
        var zoomTargetMiss: (modifier: ScrollHorizontalModifier, point: CGPoint, at: TimeInterval)?
        var zoomTargetGeneration: UInt64 = 0
        var zoomForegroundPID: pid_t? = 1
        var zoomStepLimiter = ScrollZoomStepLimiter()
        var activations: [ScrollHorizontalModifier] = []
        func startZoomTargetTimerLocked() {}
        func activateZoomTarget(_ window: WindowServerWindowCandidate, snapshot: ScrollZoomTargetSnapshot,
                                point: CGPoint, generation: UInt64) {
            activations.append(snapshot.modifier)
        }
    }

    final class Refresher {
        struct Pointer {
            let location = CGPoint.zero
            init?(source: Int?) {}
        }
        enum EventSource {
            enum State { case combinedSessionState }
            static var held: CGEventFlags = .maskAlternate
            static func flagsState(_ state: State) -> CGEventFlags { held }
        }
        struct Direction {
            var zoom: ScrollZoomPreferences {
                .init(isAvailable: true, boolFor: { $0 == DefaultsKey.verticalZoomEnabled },
                      stringFor: { _ in ScrollZoomModifier.option.rawValue })
            }
        }
        typealias CGEvent = Pointer
        typealias CGEventSource = EventSource
        typealias ScrollDirectionPreferences = Direction
        typealias AppSwitcher = Switcher
        let pinchZoomLock = NSLock()
        let zoomTargetQueue = DispatchQueue(label: "vorssaint.tests.zoom-refresh")
        var zoomTargetTimer: DispatchSourceTimer?
        var zoomState = ScrollZoomGestureState()
        var refreshes = 0
        var invalidations = 0
        let didRefresh = DispatchSemaphore(value: 0)
        let didInvalidate = DispatchSemaphore(value: 0)
        func AXIsProcessTrusted() -> Bool { true }
        func invalidateZoomTargetLocked() {
            invalidations += 1
            didInvalidate.signal()
        }
        func requestZoomTargetLocked(at point: CGPoint, modifier: ScrollHorizontalModifier, refresh: Bool) {
            if refresh {
                refreshes += 1
                didRefresh.signal()
            }
        }
    }

    static func run(_ suite: TestSuite) {
        let resolver = TargetResolver()
        defer { TargetResolver.Focus.lookup = { _ in 7 } }
        let point = CGPoint(x: 10, y: 10)
        for modifier in [ScrollHorizontalModifier.command, .option, .control, .command] {
            let entered = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            TargetResolver.Focus.lookup = { _ in
                entered.signal()
                _ = release.wait(timeout: .now() + 2)
                return 7
            }
            resolver.pinchZoomLock.withLock {
                resolver.invalidateZoomTargetLocked()
                resolver.requestZoomTargetLocked(at: point, modifier: modifier)
            }
            suite.expect(entered.wait(timeout: .now() + 2) == .success,
                         "modifier-change prefetch resolves focus on the background queue")
            let previousCount = resolver.activations.count
            resolver.pinchZoomLock.withLock {
                resolver.requestZoomTargetLocked(at: point, modifier: modifier, activate: true)
            }
            release.signal()
            resolver.zoomTargetQueue.sync {}
            suite.expect(resolver.activations.count == previousCount + 1 && resolver.activations.last == modifier,
                         "\(modifier.rawValue) Zoom preserves a wheel activation request during modifier-change prefetch")
        }
        let activationCount = resolver.activations.count
        TargetResolver.Focus.lookup = { _ in 7 }
        resolver.pinchZoomLock.withLock {
            resolver.invalidateZoomTargetLocked()
            resolver.requestZoomTargetLocked(at: point, modifier: .option)
        }
        resolver.zoomTargetQueue.sync {}
        suite.expect(resolver.activations.count == activationCount && resolver.zoomFocusedTarget == nil,
                     "prefetch after a modifier change does not activate an inactive hovered app without a wheel tick")

        let cancelledEntered = DispatchSemaphore(value: 0)
        let cancelledRelease = DispatchSemaphore(value: 0)
        TargetResolver.Focus.lookup = { _ in
            cancelledEntered.signal()
            _ = cancelledRelease.wait(timeout: .now() + 2)
            return 7
        }
        resolver.pinchZoomLock.withLock {
            resolver.invalidateZoomTargetLocked()
            resolver.requestZoomTargetLocked(at: point, modifier: .option, activate: true)
        }
        suite.expect(cancelledEntered.wait(timeout: .now() + 2) == .success,
                     "the old modifier's lookup is pending when its assignment changes")
        resolver.pinchZoomLock.withLock {
            resolver.invalidateZoomTargetLocked()
            resolver.requestZoomTargetLocked(at: point, modifier: .command)
        }
        cancelledRelease.signal()
        cancelledRelease.signal()
        resolver.zoomTargetQueue.sync {}
        suite.expect(resolver.activations.count == activationCount && resolver.zoomTarget?.modifier == .command,
                     "changing the modifier cancels obsolete activation without transferring it to the new prefetch")

        TargetResolver.Focus.lookup = { _ in 7 }
        resolver.pinchZoomLock.withLock {
            resolver.zoomForegroundPID = 42
            resolver.invalidateZoomTargetLocked()
            resolver.requestZoomTargetLocked(at: point, modifier: .control)
        }
        resolver.zoomTargetQueue.sync {}
        suite.expect(resolver.zoomFocusedTarget?.pid == 42 && resolver.activations.count == activationCount,
                     "a newly assigned key becomes ready without activation when its hovered window is already active")
        let name = "com.vorssaint.tests.linear-scroll-tap.\(UUID().uuidString)"
        let defaults = Foundation.UserDefaults(suiteName: name)!
        StandardDefaults.standard = defaults
        defer {
            defaults.removePersistentDomain(forName: name)
            Exceptions.shared.excepted = []
            HIDStage.shared.passes = true
            Switcher.shared.scrollNavigationActive = false
            Target.shared.isOwn = false
        }
        func configure(linear: Bool = true, installed: Bool = true, lines: Int = 3,
                       invert: Bool = false, invertHorizontal: Bool = false, inverterInstalled: Bool = true,
                       sidewaysKey: ScrollHorizontalModifier? = nil) {
            defaults.set(installed, forKey: AppFeature.linearScroll.availabilityKey)
            defaults.set(linear, forKey: DefaultsKey.linearScrollEnabled)
            defaults.set(lines, forKey: DefaultsKey.linearScrollLines)
            defaults.set(inverterInstalled, forKey: AppFeature.scrollInverter.availabilityKey)
            defaults.set(invert, forKey: DefaultsKey.scrollInverterEnabled)
            defaults.set(invertHorizontal, forKey: DefaultsKey.scrollInverterHorizontalEnabled)
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

        configure(invert: true)
        defaults.set(true, forKey: AppFeature.scrollZoom.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.verticalZoomEnabled)
        defaults.set(ScrollZoomModifier.option.rawValue, forKey: DefaultsKey.verticalZoomModifier)
        let unresolvedZoom = deliver(wheel(line: 4, fixed: 4, point: 40, flags: .maskAlternate))
        suite.expect(unresolvedZoom.map(verticalLine) == 4
                        && unresolvedZoom.map(verticalFixed) == 4
                        && unresolvedZoom?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 40,
                     "an unresolved keyboard zoom target keeps the wheel raw instead of inverting or capping it")
        defaults.set(false, forKey: AppFeature.scrollZoom.availabilityKey)

        configure(linear: false, invert: true)
        defaults.set(true, forKey: AppFeature.scrollZoom.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.pinchZoomEnabled)
        defaults.set(ScrollZoomModifier.command.rawValue, forKey: DefaultsKey.pinchZoomModifier)
        Switcher.shared.scrollNavigationActive = true
        let switcherInverter = Inverter()
        let switcherWheel = deliver(wheel(line: 4, fixed: 4, point: 40, flags: .maskCommand),
                                    through: switcherInverter)
        suite.expect(switcherWheel.map(verticalLine) == -4 && switcherInverter.pinchPosts == 0,
                     "Command-wheel keeps inversion and never enters Zoom while the switcher owns scrolling")
        Switcher.shared.scrollNavigationActive = false
        let pinchDirection = ScrollDirectionPreferences(defaults: defaults)
        let ownInverter = Inverter()
        _ = ownInverter.zoomState.update(pinchDirection.zoom)
        ownInverter.zoomState.start()
        Target.shared.isOwn = true
        suite.expect(!ownInverter.consumeZoom(wheel(line: 1, fixed: 1, point: 10, flags: .maskCommand),
                                              direction: pinchDirection) && ownInverter.pinchPosts == 0,
                     "Pinch leaves an own panel's wheel unchanged")
        configure(invert: true)
        defaults.set(true, forKey: AppFeature.scrollZoom.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.pinchZoomEnabled)
        defaults.set(ScrollZoomModifier.option.rawValue, forKey: DefaultsKey.pinchZoomModifier)
        let ownWheel = deliver(wheel(line: 4, fixed: 4, point: 40, flags: .maskAlternate))
        suite.expect(ownWheel.map(verticalLine) == -3,
                     "a panel that declines zoom still receives inversion and the linear cap")
        Target.shared.isOwn = false
        suite.expect(ownInverter.consumeZoom(wheel(line: 1, fixed: 1, point: 10, flags: .maskCommand),
                                             direction: pinchDirection) && ownInverter.pinchPosts == 1,
                     "Pinch still consumes a single tick over an external window")
        let a = CGPoint(x: 10, y: 20), b = CGPoint(x: 30, y: 40)
        let gestures = Inverter()
        gestures.postPinchZoomLocked(1, modifier: .option, at: a)
        gestures.postPinchZoomLocked(1, modifier: .option, at: a)
        gestures.postPinchZoomLocked(-1, modifier: .option, at: b)
        gestures.endPinchZoomLocked()
        suite.expect(gestures.pinchEvents.map(\.phase) == [1, 2, 2, 4, 1, 2, 4]
                     && gestures.pinchEvents.map(\.point) == [a, a, a, a, b, b, b],
                     "moving between views ends the old gesture at its original point before beginning the next")

        defaults.set(false, forKey: DefaultsKey.pinchZoomEnabled)
        let keyboardDirection = ScrollDirectionPreferences(defaults: defaults)
        let keyboardInverter = Inverter()
        _ = keyboardInverter.zoomState.update(keyboardDirection.zoom)
        keyboardInverter.zoomState.start()
        let keyboardWheel = wheel(line: 1, fixed: 1, point: 10, flags: .maskAlternate)
        suite.expect(!keyboardInverter.consumeZoom(keyboardWheel, direction: keyboardDirection)
                        && keyboardInverter.activationRequests == 1 && keyboardInverter.keyboardPosts.isEmpty,
                     "an unresolved keyboard target requests activation without consuming or posting the tick")
        let candidate = WindowServerWindowCandidate(pid: 42, windowID: 7,
            frame: CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000))
        keyboardInverter.zoomTarget = ScrollZoomTargetSnapshot(
            windows: [.init(frame: candidate.frame, isOwn: false, zoomTarget: candidate)],
            modifier: .option, resolvedAt: ProcessInfo.processInfo.systemUptime)
        suite.expect(!keyboardInverter.consumeZoom(keyboardWheel, direction: keyboardDirection)
                        && keyboardInverter.keyboardPosts.isEmpty,
                     "a resolved but unfocused keyboard target is not zoomed")
        keyboardInverter.zoomFocusedTarget = candidate
        suite.expect(keyboardInverter.consumeZoom(keyboardWheel, direction: keyboardDirection)
                        && keyboardInverter.keyboardPosts == [42],
                     "keyboard Zoom posts only after the hovered window is confirmed focused")
        suite.expect(keyboardInverter.consumeZoom(keyboardWheel, direction: keyboardDirection)
                        && keyboardInverter.keyboardPosts == [42],
                     "a high-resolution burst is consumed without posting a second keyboard Zoom step")
        suite.expect(keyboardInverter.consumeZoom(wheel(line: -1, fixed: -1, point: -10, flags: .maskAlternate),
                                                  direction: keyboardDirection)
                        && keyboardInverter.keyboardPosts == [42, 42],
                     "reversing the keyboard Zoom direction posts a step immediately")
        Target.shared.isOwn = true
        suite.expect(!keyboardInverter.consumeZoom(keyboardWheel, direction: keyboardDirection)
                        && keyboardInverter.keyboardPosts == [42, 42] && keyboardInverter.zoomTarget == nil,
                     "an own panel appearing above a cached target stops keyboard Zoom")
        Target.shared.isOwn = false
        defaults.set(false, forKey: AppFeature.scrollZoom.availabilityKey)

        for modifier in ScrollZoomModifier.allCases.compactMap(\.modifier) {
            let preferences = ScrollZoomPreferences(isAvailable: true,
                boolFor: { $0 == DefaultsKey.verticalZoomEnabled }, stringFor: { _ in modifier.rawValue })
            let poster = Inverter()
            _ = poster.zoomState.update(preferences)
            poster.zoomState.start()
            let rightFlag = modifier == .option ? CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK)) : []
            let held = modifier.flag.union(rightFlag)
            let event = wheel(line: 1, fixed: 1, point: 10, flags: held)
            poster.zoomTarget = ScrollZoomTargetSnapshot(
                windows: [.init(frame: candidate.frame, isOwn: false, zoomTarget: candidate)],
                modifier: modifier, resolvedAt: ProcessInfo.processInfo.systemUptime)
            poster.zoomFocusedTarget = candidate
            let direction = ScrollDirectionPreferences(isAvailable: { $0 == .scrollZoom },
                boolFor: { $0 == DefaultsKey.verticalZoomEnabled }, stringFor: { _ in modifier.rawValue })
            suite.expect(poster.consumeZoom(event, direction: direction)
                            && poster.zoomEvents.map(\.type) == [.keyDown, .keyUp, .flagsChanged]
                            && poster.zoomEvents.prefix(2).allSatisfy { $0.flags == [.maskCommand, .maskShift] }
                            && poster.zoomEvents.last?.flags == held,
                         "\(modifier.rawValue) Zoom sends Command-plus and restores the held modifier")
            suite.expect(poster.zoomEvents.allSatisfy {
                $0.getIntegerValueField(.eventSourceStateID) != Int64(CGEventSourceStateID.hidSystemState.rawValue)
                    && $0.getIntegerValueField(.eventSourceStateID) != Int64(CGEventSourceStateID.combinedSessionState.rawValue)
            }, "keyboard Zoom uses a private modifier state instead of the held physical Option or Control")
            if modifier == .option {
                suite.expect(poster.zoomEvents.last?.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_RightOption),
                             "restoring a held right Option uses the right Option key")
            }
            poster.zoomEvents = []
            let reverse = wheel(line: -1, fixed: -1, point: -10, flags: held)
            suite.expect(poster.consumeZoom(reverse, direction: direction)
                            && poster.zoomEvents.prefix(2).allSatisfy { $0.flags == .maskCommand }
                            && (modifier == .command || poster.zoomEvents.last?.flags == held),
                         "\(modifier.rawValue) Zoom reverses without leaking Option or Control into Command-minus")
        }

        let refresher = Refresher()
        _ = refresher.zoomState.update(Refresher.Direction().zoom)
        refresher.zoomState.start()
        refresher.pinchZoomLock.withLock { refresher.startZoomTargetTimerLocked() }
        suite.expect(refresher.didRefresh.wait(timeout: .now() + 2) == .success,
                     "holding a keyboard Zoom modifier refreshes targets without waiting for another wheel tick")
        refresher.zoomTargetQueue.sync { Refresher.EventSource.held = [] }
        _ = refresher.didInvalidate.wait(timeout: .now() + 2)
        let stopped = refresher.pinchZoomLock.withLock { refresher.zoomTargetTimer == nil && refresher.invalidations > 0 }
        suite.expect(stopped, "releasing the Zoom modifier stops background refresh and invalidates the target")
        refresher.pinchZoomLock.withLock { refresher.stopZoomTargetTimerLocked() }

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

        // Screen Sharing posts the controlling computer's scroll below the
        // HID stage as phaseless pixel events, already turned its way.
        configure(invert: true)
        let local = Inverter()
        _ = deliver(wheel(line: 0, fixed: 0.25, point: 0), through: local)
        let carried = local.linearCarryVertical
        HIDStage.shared.passes = false
        let remote = wheel(continuous: true, line: 0, fixed: 4, point: 40)
        suite.expect(deliver(remote, through: local) === remote
                        && remote.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 40
                        && verticalFixed(remote) == 4 && local.linearCarryVertical == carried,
                     "a remote screen's scroll is neither capped nor turned, and leaves the local carry alone")
        HIDStage.shared.passes = true

        // The session taps that keep the wheel read it through this copy.
        configure(invert: true)
        let notch = wheel(line: 2, fixed: 2, point: 20)
        let turned = Inverter.directionApplied(to: notch)
        suite.expect(turned !== notch && verticalLine(turned) == -2 && verticalLine(notch) == 2,
                     "session taps read a local wheel turned the way Scroll Direction turns it, on a copy")
        HIDStage.shared.passes = false
        suite.expect(Inverter.directionApplied(to: notch) === notch,
                     "session taps read a remote screen's scroll as it came")
        HIDStage.shared.passes = true
        Exceptions.shared.excepted = [.scrollDirection]
        suite.expect(Inverter.directionApplied(to: notch) === notch,
                     "session taps read the wheel unturned over an app excepted from Scroll Direction")
        configure(invert: false)
        suite.expect(Inverter.directionApplied(to: notch) === notch,
                     "session taps read the wheel unturned while Scroll Direction is off")

        // Scroll Direction turned the side wheel at the HID stage before
        // Mouse button shortcuts saw it, so saved shortcuts hold the turned
        // direction. A push AppKit calls left reads right while it is on.
        let push = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                           wheel1: 0, wheel2: 0, wheel3: 0)!
        push.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
        push.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 1)
        push.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 1)
        push.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 10)
        configure(invertHorizontal: true)
        suite.expect(SideWheel().sideWheelInput(for: push) == MouseButtonShortcutSupport.sideWheelRightInput,
                     "a side-wheel push reads the way horizontal Scroll Direction turns it, so saved shortcuts keep their direction")
        configure()
        suite.expect(SideWheel().sideWheelInput(for: push) == MouseButtonShortcutSupport.sideWheelLeftInput,
                     "a side-wheel push reads as pushed while horizontal Scroll Direction is off")
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
