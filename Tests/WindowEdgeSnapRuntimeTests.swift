// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

private typealias EdgeSnapGeometry = WindowEdgeSnapSupport

/// The production pointer callback, tracking, lookup, target and release bodies
/// are extracted on every test build, and so is the move gesture's callback with
/// its arming and promotion, which hands a modifier move over to the tracking. Scheduling, window server snapshots, AX,
/// screens, preferences, the preview and the placement itself are replaced, and
/// every AX call is counted by where it is asked: on the lookup queue, or on the
/// main run loop that also serves the event taps. Events are passed directly,
/// never posted, and timers run on the test's clock.
enum WindowEdgeSnapRuntimeTests {
    static var accessibilityGranted = true
    static var canBePlaced = true
    static var currentFrame = initialFrame
    static var windowExists = true
    static var buttonDown = false
    static var onLookupQueue = false
    static var lookupQueueAX = 0
    static var mainAXWhileHeld = 0
    static var mainAXAfterRelease = 0
    static var mainLookupsAfterRelease = 0
    /// Seconds since the test began, on which events are stamped and timers
    /// come due. Only a test or a timer moves it.
    static var clock: TimeInterval = 0
    /// The real uptime when the test began. An event timestamp is read in
    /// nanoseconds or in machine ticks by whichever lands nearer the real
    /// clock, so the test's events are stamped close to it.
    static var clockStart: TimeInterval = 0
    /// Off for a test about events posted with no timestamp.
    static var stampsEvents = true
    /// The saved placements of the drop areas, read only under their own key.
    static var zoneActions: String?
    /// Whether the window's app is on the ignored list.
    static var appIgnored = false
    /// Whether the window's server ID can be read from its Accessibility element.
    static var windowIDReadable = true
    /// Whether the app takes a size written to its window.
    static var sizeAccepted = true
    /// The app's assistive flag is on, so a frame write holds it off first.
    static var assistiveFlagOn = false
    /// Every hold a write took on the app's assistive flag.
    static var assistiveHolds: [EnhancedUserInterfaceSuspension] = []
    /// What the drag does to the window while the app takes the next size.
    static var duringSizeWrite: (() -> Void)?
    /// A real timer fires at or after its deadline, here a millisecond after,
    /// so a look set for exactly the rest of a pause finds it complete.
    static let timerLatency: TimeInterval = 0.001
    static let initialFrame = CGRect(x: 100, y: 100, width: 800, height: 500)
    static let pressPoint = CGPoint(x: 200, y: 200)
    static let edgePoint = CGPoint(x: 1439, y: 200)
    static let windowID: CGWindowID = 7
    static let processID: pid_t = 1001
    static let launch = Date(timeIntervalSince1970: 100)

    enum SessionActivity {
        final class State { var isActive = true }
        static let shared = State()
    }
    enum AppFeature {
        struct Feature { var isAvailable = true }
        static var windowLayout = Feature()
    }
    enum UserDefaults {
        final class Store {
            func bool(forKey key: String) -> Bool { key == DefaultsKey.windowEdgeSnapEnabled }
            func string(forKey key: String) -> String? {
                key == DefaultsKey.windowEdgeSnapZoneActions ? zoneActions : nil
            }
        }
        static let standard = Store()
    }
    /// Deadlines on the test's clock.
    struct DispatchTime {
        let seconds: TimeInterval
        static func now() -> DispatchTime { DispatchTime(seconds: clock) }
        static func + (time: DispatchTime, delay: Double) -> DispatchTime {
            DispatchTime(seconds: time.seconds + delay)
        }
    }
    final class DispatchQueue {
        final class Jobs {
            var jobs: [() -> Void] = []
            var timers: [(due: TimeInterval, job: () -> Void)] = []
            func async(execute: @escaping () -> Void) { jobs.append(execute) }
            func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) {
                timers.append((deadline.seconds, execute))
            }
            /// The queued jobs and every timer due by `limit`, in the order
            /// they come due, moving the clock on to each one.
            func run(until limit: TimeInterval) {
                while true {
                    if !jobs.isEmpty {
                        jobs.removeFirst()()
                        continue
                    }
                    guard let next = timers.indices.min(by: { timers[$0].due < timers[$1].due }),
                          timers[next].due + timerLatency <= limit else { return }
                    let timer = timers.remove(at: next)
                    clock = max(clock, timer.due + timerLatency)
                    timer.job()
                }
            }
            /// The queued jobs and the timers already due, with no time passing.
            func runDue() { run(until: clock) }
            /// Everything, timers included, as if the pointer then rested until
            /// nothing was left.
            func drain() { run(until: .infinity) }
        }
        static let main = Jobs()
        static let lookup = Jobs()
        init(label: String, qos: DispatchQoS) {}
        func async(execute: @escaping () -> Void) { Self.lookup.async(execute: execute) }
        /// The lookup queue's jobs, run the way the real queue runs them, off
        /// the main run loop.
        static func drainLookups() {
            onLookupQueue = true
            let pending = lookup.jobs
            lookup.jobs.removeAll()
            pending.forEach { $0() }
            onLookupQueue = false
        }
    }
    enum WindowEdgeSnapSupport {
        static var isSystemTilingEnabled = false
        static var isSystemTopWindowOverviewDragEnabled = false
        static func startsAtResizeHandle(_ point: CGPoint, frame: CGRect) -> Bool {
            EdgeSnapGeometry.startsAtResizeHandle(point, frame: frame)
        }
        static func classify(initialFrame: CGRect, currentFrame: CGRect,
                             pointerStart: CGPoint, pointerNow: CGPoint) -> WindowEdgeDragClassification {
            EdgeSnapGeometry.classify(initialFrame: initialFrame, currentFrame: currentFrame,
                                      pointerStart: pointerStart, pointerNow: pointerNow)
        }
        static func locationAvoidingSystemTopDrag(_ point: CGPoint, screenFrames: [CGRect],
                                                  enabledZones: Set<WindowEdgeSnapZone>) -> CGPoint {
            EdgeSnapGeometry.locationAvoidingSystemTopDrag(point, screenFrames: screenFrames,
                                                           enabledZones: enabledZones)
        }
        static func target(at point: CGPoint, screens: [WindowEdgeSnapScreen], velocity: CGVector,
                           enabledZones: Set<WindowEdgeSnapZone>,
                           layout: WindowEdgeSnapLayout) -> WindowEdgeSnapTarget? {
            EdgeSnapGeometry.target(at: point, screens: screens, velocity: velocity,
                                    enabledZones: enabledZones, layout: layout)
        }
    }
    /// The displays the real target lookup sees, in AppKit coordinates. The
    /// right edge of the first is a wall unless a test puts the second past
    /// it, which makes it a seam.
    final class NSScreen {
        let frame: CGRect
        let visibleFrame: CGRect
        init(frame: CGRect, visibleFrame: CGRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
        static let primary = NSScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
        static let beside = NSScreen(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                                     visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055))
        static var screens = [primary]
    }
    enum WindowServerWindowHitTest {
        static func candidate(at point: CGPoint,
                              pidIsEligible: (pid_t) -> Bool) -> WindowServerWindowCandidate? {
            guard windowExists, currentFrame.contains(point), pidIsEligible(processID) else { return nil }
            return WindowServerWindowCandidate(pid: processID, windowID: windowID, frame: currentFrame)
        }
    }
    enum WindowServerSupport {
        static func frame(ofWindowID id: CGWindowID) -> CGRect? {
            windowExists && id == windowID ? currentFrame : nil
        }
    }
    final class NSRunningApplication {
        enum ActivationPolicy { case regular }
        let processIdentifier: pid_t
        let launchDate: Date? = launch
        let activationPolicy = ActivationPolicy.regular
        let bundleIdentifier: String? = "com.example.dragged"
        let executableURL: URL? = nil
        struct ActivationOptions: OptionSet { let rawValue: Int }
        func activate(options: ActivationOptions) -> Bool { true }
        var isTerminated: Bool { !windowExists }
        init?(processIdentifier: pid_t) {
            guard windowExists, processIdentifier == processID else { return nil }
            self.processIdentifier = processIdentifier
        }
    }
    /// The app's assistive flag, held off until resumed.
    final class EnhancedUserInterfaceSuspension {
        static func suspend(forAppOf window: Window) -> EnhancedUserInterfaceSuspension? {
            guard assistiveFlagOn else { return nil }
            let hold = EnhancedUserInterfaceSuspension()
            assistiveHolds.append(hold)
            return hold
        }
        var resumed = 0
        func resume() { resumed += 1 }
    }
    final class WindowLayoutIgnoredApps {
        static let shared = WindowLayoutIgnoredApps()
        func contains(bundleID: String?, executablePath: @autoclosure () -> String?) -> Bool {
            appIgnored && bundleID == "com.example.dragged"
        }
    }
    struct Window {
        let pid: pid_t
        let id: CGWindowID
    }
    typealias AXUIElement = Window
    enum AXError { case success }
    static func AXUIElementCreateApplication(_ pid: pid_t) -> Window { Window(pid: pid, id: 0) }
    static func AXUIElementSetMessagingTimeout(_ window: Window, _ timeout: Float) {}
    static func AXUIElementGetPid(_ window: Window, _ pid: inout pid_t) -> AXError {
        pid = window.pid
        return .success
    }
    enum AXWindowResolver {
        static func windowID(for window: Window) -> CGWindowID? {
            countAX()
            return windowIDReadable ? window.id : nil
        }
    }
    static func AXUIElementPerformAction(_ window: Window, _ action: CFString) {}

    /// Every question to the window's app. Asked from the main run loop it
    /// holds the taps until that app answers.
    static func countAX() {
        if onLookupQueue {
            lookupQueueAX += 1
        } else if buttonDown {
            mainAXWhileHeld += 1
        } else {
            mainAXAfterRelease += 1
        }
    }

    enum Write: Equatable {
        case size(CGSize)
        case position(CGPoint)
        case placement
    }

    class Fixture {
        static let syntheticEventMarker: Int64 = 0x564F5253
        static let ownProcessID: Int64 = 999
        var edgeSnapTap: CFMachPort?
        var edgeSnapPressOrigin: CGPoint?
        var edgeSnapPressCandidate: WindowServerWindowCandidate?
        var edgeSnapSequenceSuppressed = false
        var edgeSnapResolveAttempts = 0
        var edgeSnapLastResolveAt: TimeInterval = 0
        var edgeSnapDrag: WindowEdgeSnapDrag?
        var edgeSnapSequenceGeneration = 0
        var edgeSnapResolving = false
        var edgeSnapLastPointer: CGPoint?
        var edgeSnapTrail = WindowEdgeSnapPointerTrail()
        var edgeSnapFollowsMoveGesture = false
        var edgeSnapStillCheckGeneration = 0
        var edgeSnapStillCheckPending = false
        let edgeSnapResolveQueue = DispatchQueue(label: "test lookup", qos: .userInitiated)
        var activeGesture: WindowPointerGesture?
        var pendingGesture: PendingWindowGesture?
        var gestureTap: CFMachPort?
        var gestureAssistiveMode: EnhancedUserInterfaceSuspension?
        let moveGestureUpdateInterval: TimeInterval = 0
        let resizeGestureUpdateInterval: TimeInterval = 0
        let edgeSnapResolveAttemptLimit = 4
        var replayedClicks = 0
        let edgeSnapSampleInterval: TimeInterval = 0
        var enabledEdgeSnapZones = WindowEdgeSnapZone.allEnabled
        var previews = 0
        var previewShown = false
        var placements: [WindowLayoutFrame] = []
        var placedActions: [WindowLayoutAction] = []
        var lastActions: [WindowLayoutWindowKey: WindowLayoutAction] = [:]
        var frameHistory = WindowLayoutHistory()
        var settledFrames: [WindowLayoutWindowKey: WindowLayoutSettledFrame] = [:]
        var assistiveModeSuspensions: [CGWindowID: EnhancedUserInterfaceSuspension] = [:]
        /// Frame writes the gesture queued, landed only when a test lets the app answer.
        var queuedWrites: [(gesture: WindowPointerGesture, pointer: CGPoint)] = []
        let anchorTolerance: CGFloat = 36
        let frameTolerance = WindowLayoutGeometry.frameTolerance
        /// Frame writes and placements, in the order they reach the window.
        var writes: [Write] = []

        func syncWithPreferences() {}
        func edgeSnapConflictsWithWindowGesture(flags: CGEventFlags) -> Bool { false }
        func edgeSnapQuartzScreenFrames() -> [CGRect] { [CGRect(x: 0, y: 0, width: 1440, height: 900)] }
        var menuBarScreenTopY: CGFloat { NSScreen.primary.frame.maxY }
        static var uptimeSeconds: TimeInterval { clockStart + clock }
        func showEdgeSnapPreview(frame: CGRect) {
            previews += 1
            previewShown = true
        }
        func hideEdgeSnapPreview(immediately: Bool) { previewShown = false }
        func onScreenWindowIDs() -> Set<CGWindowID>? { windowExists ? [windowID] : [] }
        func windowsAttribute(_ app: Window) -> [Window]? {
            countAX()
            if !onLookupQueue, !buttonDown { mainLookupsAfterRelease += 1 }
            return [Window(pid: processID, id: windowID)]
        }
        func target(from window: Window, app: NSRunningApplication,
                    onScreenWindowIDs: Set<CGWindowID>,
                    capability: WindowLayoutTargetCapability) -> WindowLayoutTarget? {
            countAX()
            guard windowExists, canBePlaced else { return nil }
            return WindowLayoutTarget(window: window,
                                      key: WindowLayoutWindowKey(processID: processID,
                                                                 processLaunchTime: launch.timeIntervalSinceReferenceDate,
                                                                 windowID: windowID),
                                      frame: WindowLayoutFrame(origin: currentFrame.origin, size: currentFrame.size))
        }
        func frame(of window: Window) -> WindowLayoutFrame? {
            countAX()
            return WindowLayoutFrame(origin: currentFrame.origin, size: currentFrame.size)
        }
        func canSetFrame(on window: Window) -> Bool {
            countAX()
            return canBePlaced
        }
        func pruneWindowState(keeping key: WindowLayoutWindowKey) {}
        func isTrackedButtonDown() -> Bool { false }
        func flushPending(proxy: CGEventTapProxy?, at point: CGPoint?) {
            guard pendingGesture != nil else { return }
            pendingGesture = nil
            replayedClicks += 1
        }
        func gestureTarget(at point: CGPoint, requiresResize: Bool) -> WindowGestureTarget? {
            guard currentFrame.contains(point), let app = NSRunningApplication(processIdentifier: processID)
            else { return nil }
            return WindowGestureTarget(window: Window(pid: processID, id: windowID), app: app,
                                       frame: WindowLayoutFrame(origin: currentFrame.origin, size: currentFrame.size))
        }
        func bestScreen(for frame: WindowLayoutFrame) -> NSScreen? { NSScreen.screens.first }
        func cancelSettle(for windowID: CGWindowID) {}
        func enqueueGestureApply(_ gesture: WindowPointerGesture, pointer: CGPoint) {
            queuedWrites.append((gesture, pointer))
        }
        func flushGestureApplies() {}
        /// macOS fits a size to the display at the position the window sits
        /// at, and still reports success: a window against the right edge
        /// cannot grow past it until it has moved away.
        func setSize(_ size: CGSize, on window: Window) -> Bool {
            countAX()
            duringSizeWrite?()
            duringSizeWrite = nil
            guard sizeAccepted else { return false }
            writes.append(.size(size))
            let displays = NSScreen.screens.map {
                CGRect(x: $0.frame.minX, y: NSScreen.primary.frame.maxY - $0.frame.maxY,
                       width: $0.frame.width, height: $0.frame.height)
            }
            let display = displays.first { $0.contains(currentFrame.origin) } ?? displays[0]
            currentFrame.size = CGSize(width: min(size.width, display.maxX - currentFrame.minX),
                                       height: min(size.height, display.maxY - currentFrame.minY))
            return true
        }
        func setPosition(_ origin: CGPoint, on window: Window) -> Bool {
            countAX()
            writes.append(.position(origin))
            currentFrame.origin = origin
            return true
        }
        @discardableResult
        func applyPlacement(_ action: WindowLayoutAction, to target: WindowLayoutTarget,
                            visibleFrame: CGRect, historyFrame: WindowLayoutFrame,
                            cyclesRepeatedAction: Bool) -> Bool {
            placements.append(historyFrame)
            placedActions.append(action)
            writes.append(.placement)
            frameHistory.record(historyFrame, for: target.key)
            lastActions[target.key] = action
            return true
        }
    }

    private static func reset() {
        accessibilityGranted = true
        canBePlaced = true
        currentFrame = initialFrame
        windowExists = true
        buttonDown = false
        onLookupQueue = false
        lookupQueueAX = 0
        mainAXWhileHeld = 0
        mainAXAfterRelease = 0
        mainLookupsAfterRelease = 0
        clock = 0
        clockStart = TimeInterval(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
        stampsEvents = true
        zoneActions = nil
        appIgnored = false
        windowIDReadable = true
        sizeAccepted = true
        assistiveFlagOn = false
        assistiveHolds = []
        duringSizeWrite = nil
        NSScreen.screens = [NSScreen.primary]
        WindowEdgeSnapSupport.isSystemTilingEnabled = false
        WindowEdgeSnapSupport.isSystemTopWindowOverviewDragEnabled = false
        DispatchQueue.main.jobs.removeAll()
        DispatchQueue.main.timers.removeAll()
        DispatchQueue.lookup.jobs.removeAll()
    }

    private static func event(_ type: CGEventType, at point: CGPoint) -> CGEvent {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point,
                            mouseButton: .left)!
        event.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(processID))
        event.setIntegerValueField(.eventSourceUserData, value: 0)
        event.timestamp = stampsEvents ? CGEventTimestamp(((clockStart + clock) * 1e9).rounded()) : 0
        return event
    }

    /// One event through the tap callback and every main-queue job it leaves,
    /// the still check and the delayed release checks included, as if the
    /// pointer then rested. Lookups wait for `drainLookups`.
    private static func send(_ host: Host, _ type: CGEventType, _ point: CGPoint) {
        hand(host, type, point)
        DispatchQueue.main.drain()
    }

    /// The release handed to the callback alone, so a test can change the
    /// window before the delayed check that follows it runs.
    private static func releaseOnly(_ host: Host, at point: CGPoint) {
        buttonDown = false
        _ = host.observeEdgeSnapEvent(type: .leftMouseUp, event: event(.leftMouseUp, at: point))
        DispatchQueue.main.jobs.removeFirst()()
    }

    /// One event through the callback and what it leaves, with no time
    /// passing, so no timer comes due.
    private static func hand(_ host: Host, _ type: CGEventType, _ point: CGPoint) {
        if type == .leftMouseDown { buttonDown = true }
        if type == .leftMouseUp { buttonDown = false }
        _ = host.observeEdgeSnapEvent(type: type, event: event(type, at: point))
        DispatchQueue.main.runDue()
    }

    /// A drag step the window follows, while the pointer is still on its way.
    private static func move(_ host: Host, to point: CGPoint) {
        currentFrame = initialFrame.offsetBy(dx: point.x - pressPoint.x, dy: point.y - pressPoint.y)
        hand(host, .leftMouseDragged, point)
    }

    /// Time passing with no event, running whatever comes due meanwhile.
    private static func rest(for seconds: TimeInterval) {
        let end = clock + seconds
        DispatchQueue.main.run(until: end)
        clock = end
    }

    /// A press and a first step that the lookup answers at once, so the drag
    /// is tracked as a move before the pointer heads anywhere.
    private static func pressAndTrack(_ host: Host) {
        send(host, .leftMouseDown, pressPoint)
        clock += 0.01
        move(host, to: CGPoint(x: 240, y: 200))
        DispatchQueue.drainLookups()
        DispatchQueue.main.runDue()
    }

    private static var movedToEdge: CGRect {
        initialFrame.offsetBy(dx: edgePoint.x - pressPoint.x, dy: 0)
    }

    /// A modifier move or resize as the gesture tap promotes it from the press.
    private static func gesture(_ kind: WindowPointerGesture.Kind = .move,
                                snapsAtEdges: Bool = true) -> WindowPointerGesture {
        WindowPointerGesture(window: Window(pid: processID, id: windowID), kind: kind, button: .primary,
                             originalFrame: initialFrame, pointerStart: pressPoint, lastAppliedAt: 0,
                             snapsAtEdges: snapsAtEdges)
    }

    /// The promotion past the drag slop, handed over the way the gesture tap
    /// hands it: the gesture holds the window, and its first step follows.
    private static func take(_ host: Host, _ gesture: WindowPointerGesture,
                             to point: CGPoint = CGPoint(x: 240, y: 200), windowFollows: Bool = true) {
        buttonDown = true
        host.activeGesture = gesture
        host.forwardToEdgeSnap(gesture, .moveGestureBegan(pressOrigin: pressPoint, initialFrame: initialFrame,
                                                          windowID: windowID, processID: processID))
        carry(host, gesture, to: point, windowFollows: windowFollows)
    }

    /// A gesture step. A move writes the window under the pointer itself,
    /// unless the app is still behind with it.
    private static func carry(_ host: Host, _ gesture: WindowPointerGesture, to point: CGPoint,
                              windowFollows: Bool = true) {
        if case .move = gesture.kind, windowFollows {
            currentFrame = initialFrame.offsetBy(dx: point.x - pressPoint.x, dy: point.y - pressPoint.y)
        }
        host.forwardToEdgeSnap(gesture, .dragged(location: point, time: clockStart + clock))
        DispatchQueue.main.runDue()
    }

    /// The app answers every frame write queued so far, in order.
    private static func land(_ host: Host) {
        let writes = host.queuedWrites
        host.queuedWrites.removeAll()
        for write in writes { host.apply(write.gesture, pointer: write.pointer) }
        DispatchQueue.main.runDue()
    }

    /// The release, handed over once the gesture has written its last frame.
    private static func drop(_ host: Host, _ gesture: WindowPointerGesture, at point: CGPoint) {
        buttonDown = false
        host.activeGesture = nil
        host.forwardToEdgeSnap(gesture, .up(location: point, time: clockStart + clock))
        DispatchQueue.main.drain()
    }

    static func run(_ suite: TestSuite) {
        defer { reset() }

        reset()
        let content = Host()
        send(content, .leftMouseDown, pressPoint)
        send(content, .leftMouseDragged, CGPoint(x: 240, y: 200))
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        for step in 1...12 { send(content, .leftMouseDragged, CGPoint(x: 240 + step * 20, y: 200)) }
        send(content, .leftMouseUp, CGPoint(x: 480, y: 200))
        suite.expect(lookupQueueAX > 0 && mainAXWhileHeld == 0 && mainAXAfterRelease == 0
                     && content.previews == 0 && content.placements.isEmpty,
                     "a drag inside an app asks that app only from the lookup queue, never from the main run loop the taps share")

        reset()
        let contentToEdge = Host()
        send(contentToEdge, .leftMouseDown, pressPoint)
        send(contentToEdge, .leftMouseDragged, CGPoint(x: 240, y: 200))
        send(contentToEdge, .leftMouseDragged, edgePoint)
        send(contentToEdge, .leftMouseUp, edgePoint)
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        suite.expect(mainAXWhileHeld == 0 && mainAXAfterRelease == 0 && contentToEdge.placements.isEmpty,
                     "a drag inside an app that ends over a snap zone never asks that app from the main run loop")

        reset()
        let quick = Host()
        send(quick, .leftMouseDown, pressPoint)
        send(quick, .leftMouseDragged, CGPoint(x: 240, y: 200))
        send(quick, .leftMouseUp, CGPoint(x: 250, y: 200))
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        suite.expect(mainAXWhileHeld == 0 && mainAXAfterRelease == 0
                     && !quick.edgeSnapResolving && quick.edgeSnapDrag == nil,
                     "a short drag inside an app released before its lookup never asks that app from the main run loop")

        reset()
        canBePlaced = false
        let fixed = Host()
        send(fixed, .leftMouseDown, pressPoint)
        for step in 1...5 {
            send(fixed, .leftMouseDragged, CGPoint(x: 200 + step * 40, y: 200))
            DispatchQueue.drainLookups()
            DispatchQueue.main.drain()
            fixed.edgeSnapLastResolveAt = 0
        }
        send(fixed, .leftMouseUp, CGPoint(x: 400, y: 200))
        suite.expect(mainAXWhileHeld == 0 && mainAXAfterRelease == 0,
                     "a drag inside a window that cannot be placed, such as a full-screen one, never asks its app from the main run loop")

        reset()
        canBePlaced = false
        let fixedMove = Host()
        send(fixedMove, .leftMouseDown, pressPoint)
        currentFrame = movedToEdge
        send(fixedMove, .leftMouseDragged, edgePoint)
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        send(fixedMove, .leftMouseUp, edgePoint)
        suite.expect(fixedMove.previews == 0 && fixedMove.placements.isEmpty
                     && mainLookupsAfterRelease == 1,
                     "a window that cannot be placed shows no preview, is not placed at an edge and is looked up once at release")

        reset()
        let midScreen = Host()
        let midPoint = CGPoint(x: 700, y: 200)
        send(midScreen, .leftMouseDown, pressPoint)
        currentFrame = initialFrame.offsetBy(dx: midPoint.x - pressPoint.x, dy: 0)
        send(midScreen, .leftMouseDragged, midPoint)
        send(midScreen, .leftMouseUp, midPoint)
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        suite.expect(mainAXAfterRelease == 0 && midScreen.placements.isEmpty,
                     "a window moved but released away from every snap zone never asks its app from the main run loop")

        reset()
        let titleBar = Host()
        send(titleBar, .leftMouseDown, pressPoint)
        currentFrame = initialFrame.offsetBy(dx: 40, dy: 0)
        send(titleBar, .leftMouseDragged, CGPoint(x: 240, y: 200))
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        currentFrame = movedToEdge
        send(titleBar, .leftMouseDragged, edgePoint)
        let previewedWhileHeld = titleBar.previews == 1
        send(titleBar, .leftMouseUp, edgePoint)
        suite.expect(previewedWhileHeld && mainAXWhileHeld == 0 && titleBar.placements
                        == [WindowLayoutFrame(origin: initialFrame.origin, size: initialFrame.size)],
                     "a window dragged to an edge previews the zone, snaps on release and keeps its starting frame for Restore")

        reset()
        zoneActions = "right=rightThird"
        let chosenEdge = Host()
        send(chosenEdge, .leftMouseDown, pressPoint)
        currentFrame = initialFrame.offsetBy(dx: 40, dy: 0)
        send(chosenEdge, .leftMouseDragged, CGPoint(x: 240, y: 200))
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        currentFrame = movedToEdge
        send(chosenEdge, .leftMouseDragged, edgePoint)
        send(chosenEdge, .leftMouseUp, edgePoint)
        suite.expect(chosenEdge.placedActions == [.rightThird],
                     "a window dropped on an area set to another placement lands in that placement")

        reset()
        var splitRight = WindowEdgeSnapLayout.standard
        splitRight.setPartCount(2, for: .right)
        zoneActions = splitRight.storageValue
        let splitEdge = Host()
        send(splitEdge, .leftMouseDown, pressPoint)
        currentFrame = initialFrame.offsetBy(dx: 40, dy: 0)
        send(splitEdge, .leftMouseDragged, CGPoint(x: 240, y: 200))
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        currentFrame = movedToEdge
        send(splitEdge, .leftMouseDragged, edgePoint)
        let lowerArea = CGPoint(x: edgePoint.x, y: 600)
        currentFrame = movedToEdge.offsetBy(dx: 0, dy: lowerArea.y - edgePoint.y)
        send(splitEdge, .leftMouseDragged, lowerArea)
        send(splitEdge, .leftMouseUp, lowerArea)
        suite.expect(splitEdge.previews == 2 && splitEdge.placedActions == [.bottomHalf],
                     "sliding down a split edge previews each area in turn and drops into the one under the pointer")

        reset()
        let flick = Host()
        send(flick, .leftMouseDown, pressPoint)
        currentFrame = movedToEdge
        send(flick, .leftMouseDragged, edgePoint)
        send(flick, .leftMouseUp, edgePoint)
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        suite.expect(flick.placements.count == 1,
                     "a window flicked to an edge snaps even when the release beats its lookup")

        reset()
        let lateAdopted = Host()
        send(lateAdopted, .leftMouseDown, pressPoint)
        send(lateAdopted, .leftMouseDragged, CGPoint(x: 240, y: 200))
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        releaseOnly(lateAdopted, at: edgePoint)
        currentFrame = movedToEdge
        DispatchQueue.main.drain()
        suite.expect(lateAdopted.placements.count == 1,
                     "a window whose new frame reaches the window server after the release still snaps")

        reset()
        let lateUnresolved = Host()
        send(lateUnresolved, .leftMouseDown, pressPoint)
        send(lateUnresolved, .leftMouseDragged, CGPoint(x: 240, y: 200))
        releaseOnly(lateUnresolved, at: edgePoint)
        currentFrame = movedToEdge
        DispatchQueue.main.drain()
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        suite.expect(lateUnresolved.placements.count == 1,
                     "a late window frame still snaps when the release also beat the lookup")

        reset()
        WindowEdgeSnapSupport.isSystemTopWindowOverviewDragEnabled = true
        let resting = Host()
        send(resting, .leftMouseDown, pressPoint)
        currentFrame = movedToEdge
        send(resting, .leftMouseDragged, edgePoint)
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        let previewedOnArrival = resting.previews == 1 && resting.edgeSnapDrag?.isMoving == true
        let topEdge = event(.leftMouseDragged, at: CGPoint(x: 700, y: 0))
        _ = resting.observeEdgeSnapEvent(type: .leftMouseDragged, event: topEdge)
        DispatchQueue.main.drain()
        suite.expect(previewedOnArrival && topEdge.location.y > 0,
                     "a lookup landing while the window rests at an edge shows the preview and protects the next top-edge event")

        reset()
        let cancelled = Host()
        send(cancelled, .leftMouseDown, pressPoint)
        send(cancelled, .leftMouseDragged, CGPoint(x: 240, y: 200))
        _ = cancelled.observeEdgeSnapEvent(type: .tapDisabledByTimeout, event: CGEvent(source: nil)!)
        DispatchQueue.main.drain()
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        let adoptedStale = cancelled.edgeSnapDrag != nil
        send(cancelled, .leftMouseUp, CGPoint(x: 240, y: 200))
        send(cancelled, .leftMouseDown, pressPoint)
        send(cancelled, .leftMouseDragged, CGPoint(x: 240, y: 200))
        suite.expect(!adoptedStale && DispatchQueue.lookup.jobs.count == 1,
                     "a lookup still running when tracking is cancelled is dropped, and the next drag starts its own")

        reset()
        let flung = Host()
        pressAndTrack(flung)
        clock += 0.01
        move(flung, to: edgePoint)
        let previewedAtWall = flung.previews == 1
        send(flung, .leftMouseUp, edgePoint)
        suite.expect(previewedAtWall && flung.placements.count == 1,
                     "a window flung at an edge with no display past it previews on arrival and snaps when let go at once")

        reset()
        NSScreen.screens = [NSScreen.primary, NSScreen.beside]
        let passing = Host()
        pressAndTrack(passing)
        clock += 0.01
        move(passing, to: edgePoint)
        send(passing, .leftMouseUp, edgePoint)
        suite.expect(passing.previews == 0 && passing.placements.isEmpty,
                     "a window carried through a seam at speed shows no preview and is not placed")

        reset()
        NSScreen.screens = [NSScreen.primary, NSScreen.beside]
        let stopping = Host()
        pressAndTrack(stopping)
        clock += 0.01
        move(stopping, to: edgePoint)
        let hiddenWhileFast = stopping.previews == 0
        DispatchQueue.main.drain()
        let shownOnceStill = stopping.previews == 1
        send(stopping, .leftMouseUp, edgePoint)
        suite.expect(hiddenWhileFast && shownOnceStill && stopping.placements.count == 1,
                     "a pointer that arrives fast and stops at a seam shows the preview once still, with no further event, and snaps")

        reset()
        NSScreen.screens = [NSScreen.primary, NSScreen.beside]
        let streaming = Host()
        pressAndTrack(streaming)
        var mostPending = DispatchQueue.main.timers.count
        for step in 1...30 {
            clock += 0.01
            move(streaming, to: CGPoint(x: min(240 + CGFloat(step) * 40, edgePoint.x), y: 200))
            mostPending = max(mostPending, DispatchQueue.main.timers.count)
        }
        let hiddenWhileStreaming = streaming.previews == 0
        DispatchQueue.main.drain()
        suite.expect(mostPending == 1 && hiddenWhileStreaming && streaming.previews == 1,
                     "a drag keeps one still check waiting however many events it sends, and that check still finds the stop")

        reset()
        NSScreen.screens = [NSScreen.primary, NSScreen.beside]
        let again = Host()
        pressAndTrack(again)
        hand(again, .leftMouseUp, CGPoint(x: 240, y: 200))
        currentFrame = initialFrame
        clock += 0.01
        hand(again, .leftMouseDown, pressPoint)
        clock += 0.01
        move(again, to: CGPoint(x: 240, y: 200))
        DispatchQueue.drainLookups()
        DispatchQueue.main.runDue()
        clock += 0.01
        move(again, to: edgePoint)
        let hiddenOnSecondArrival = again.previews == 0
        // The first drag's check comes due here and must end without waiting
        // again, leaving the second drag's own check as the only one.
        rest(for: 0.08)
        let oneCheckLeft = DispatchQueue.main.timers.count == 1
        DispatchQueue.main.drain()
        suite.expect(hiddenOnSecondArrival && oneCheckLeft && again.previews == 1,
                     "a release and a new press drop the waiting still check, and the next drag gets its own")

        reset()
        NSScreen.screens = [NSScreen.primary, NSScreen.beside]
        stampsEvents = false
        let unstamped = Host()
        pressAndTrack(unstamped)
        clock += 0.01
        move(unstamped, to: CGPoint(x: 1400, y: 200))
        rest(for: 0.2)
        for step in 1...15 {
            clock += 0.01
            move(unstamped, to: CGPoint(x: 1400 + CGFloat(step) * 2, y: 200))
        }
        let previewedWhileCreeping = unstamped.previews == 1
        send(unstamped, .leftMouseUp, CGPoint(x: 1430, y: 200))
        suite.expect(previewedWhileCreeping && unstamped.placements.count == 1,
                     "events posted with no timestamp are timed by the clock, so creeping onto a seam previews and snaps")

        reset()
        let modifierMove = Host()
        let move = gesture()
        take(modifierMove, move)
        DispatchQueue.drainLookups()
        DispatchQueue.main.runDue()
        carry(modifierMove, move, to: edgePoint)
        let previewedDuringMove = modifierMove.previews == 1
        drop(modifierMove, move, at: edgePoint)
        suite.expect(previewedDuringMove && mainAXWhileHeld == 0 && modifierMove.placedActions == [.rightHalf]
                        && modifierMove.placements == [WindowLayoutFrame(origin: initialFrame.origin,
                                                                         size: initialFrame.size)],
                     "a window carried to an edge by the modifier move previews the zone, snaps on release and keeps its starting frame for Restore")

        reset()
        zoneActions = "right=rightThird"
        let modifierChosen = Host()
        take(modifierChosen, move)
        DispatchQueue.drainLookups()
        carry(modifierChosen, move, to: edgePoint)
        drop(modifierChosen, move, at: edgePoint)
        suite.expect(modifierChosen.placedActions == [.rightThird],
                     "a modifier move dropped on an area set to another placement lands in that placement")

        reset()
        let modifierZoneOff = Host()
        modifierZoneOff.enabledEdgeSnapZones.remove(.right)
        take(modifierZoneOff, move)
        DispatchQueue.drainLookups()
        carry(modifierZoneOff, move, to: edgePoint)
        drop(modifierZoneOff, move, at: edgePoint)
        suite.expect(modifierZoneOff.previews == 0 && modifierZoneOff.placements.isEmpty,
                     "a modifier move dropped on a switched-off zone shows no preview and stays where it was dropped")

        reset()
        let modifierMidScreen = Host()
        take(modifierMidScreen, move)
        DispatchQueue.drainLookups()
        carry(modifierMidScreen, move, to: CGPoint(x: 700, y: 200))
        drop(modifierMidScreen, move, at: CGPoint(x: 700, y: 200))
        suite.expect(modifierMidScreen.previews == 0 && modifierMidScreen.placements.isEmpty
                        && mainAXAfterRelease == 0,
                     "a modifier move released away from every zone leaves the window where it was dropped")

        reset()
        let modifierFlick = Host()
        take(modifierFlick, move, to: edgePoint)
        drop(modifierFlick, move, at: edgePoint)
        suite.expect(modifierFlick.placements.count == 1,
                     "a modifier move flicked to an edge snaps even when the release beats its lookup")

        reset()
        let modifierResize = Host()
        let resize = gesture(.resize([.right]))
        take(modifierResize, resize)
        carry(modifierResize, resize, to: edgePoint)
        drop(modifierResize, resize, at: edgePoint)
        suite.expect(modifierResize.previews == 0 && modifierResize.placements.isEmpty
                        && DispatchQueue.lookup.jobs.isEmpty && lookupQueueAX + mainAXAfterRelease == 0,
                     "a modifier resize dragged to an edge never previews, snaps or asks its app")

        reset()
        let modifierSnapOff = Host()
        let unsnapped = gesture(snapsAtEdges: false)
        take(modifierSnapOff, unsnapped)
        carry(modifierSnapOff, unsnapped, to: edgePoint)
        drop(modifierSnapOff, unsnapped, at: edgePoint)
        suite.expect(modifierSnapOff.previews == 0 && modifierSnapOff.placements.isEmpty,
                     "a modifier move begun while edge snapping is off never snaps")

        reset()
        WindowEdgeSnapSupport.isSystemTilingEnabled = true
        let modifierSystemTiling = Host()
        take(modifierSystemTiling, move)
        DispatchQueue.drainLookups()
        carry(modifierSystemTiling, move, to: edgePoint)
        drop(modifierSystemTiling, move, at: edgePoint)
        suite.expect(modifierSystemTiling.previews == 0 && modifierSystemTiling.placements.isEmpty,
                     "with macOS tiling on, a modifier move does not snap")

        reset()
        let modifierDropped = Host()
        take(modifierDropped, move)
        DispatchQueue.drainLookups()
        carry(modifierDropped, move, to: edgePoint)
        let previewedBeforeDrop = modifierDropped.previews == 1
        modifierDropped.forwardToEdgeSnap(move, .moveGestureDropped)
        DispatchQueue.main.drain()
        let hiddenOnDrop = !modifierDropped.previewShown
        carry(modifierDropped, move, to: CGPoint(x: edgePoint.x, y: 300))
        modifierDropped.forwardToEdgeSnap(move, .up(location: edgePoint, time: clockStart + clock))
        DispatchQueue.main.drain()
        suite.expect(previewedBeforeDrop && hiddenOnDrop && modifierDropped.previews == 1
                        && modifierDropped.placements.isEmpty,
                     "a modifier move the system cuts off mid-drag hides the preview and nothing after it snaps")

        reset()
        let modifierLagging = Host()
        take(modifierLagging, move, to: CGPoint(x: 240, y: 200), windowFollows: false)
        DispatchQueue.drainLookups()
        DispatchQueue.main.runDue()
        for step in 1...6 {
            clock += 0.05
            carry(modifierLagging, move, to: CGPoint(x: 240 + CGFloat(step) * 150, y: 200), windowFollows: false)
        }
        clock += 0.05
        carry(modifierLagging, move, to: edgePoint, windowFollows: false)
        let previewedWhileLagging = modifierLagging.previews == 1
        drop(modifierLagging, move, at: edgePoint)
        suite.expect(previewedWhileLagging && modifierLagging.placedActions == [.rightHalf],
                     "a modifier move previews and snaps even while the window server still shows the window behind the pointer")

        reset()
        let modifierLaggingFlick = Host()
        take(modifierLaggingFlick, move, to: edgePoint, windowFollows: false)
        drop(modifierLaggingFlick, move, at: edgePoint)
        suite.expect(modifierLaggingFlick.placements.count == 1,
                     "a modifier move flicked to an edge snaps when the release beats both its lookup and the window server")

        reset()
        appIgnored = true
        let modifierIgnored = Host()
        take(modifierIgnored, move)
        DispatchQueue.drainLookups()
        carry(modifierIgnored, move, to: edgePoint)
        drop(modifierIgnored, move, at: edgePoint)
        suite.expect(modifierIgnored.previews == 0 && modifierIgnored.placements.isEmpty,
                     "a modifier move of a listed app's window carried in the background never snaps")

        reset()
        let titleBarDuringGesture = Host()
        send(titleBarDuringGesture, .leftMouseDown, pressPoint)
        titleBarDuringGesture.pendingGesture = PendingWindowGesture(
            down: event(.leftMouseDown, at: pressPoint), button: .primary, kind: .move,
            window: Window(pid: processID, id: windowID), app: NSRunningApplication(processIdentifier: processID)!,
            originalFrame: initialFrame, origin: pressPoint)
        currentFrame = initialFrame.offsetBy(dx: 40, dy: 0)
        send(titleBarDuringGesture, .leftMouseDragged, CGPoint(x: 240, y: 200))
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        currentFrame = movedToEdge
        send(titleBarDuringGesture, .leftMouseDragged, edgePoint)
        send(titleBarDuringGesture, .leftMouseUp, edgePoint)
        suite.expect(titleBarDuringGesture.previews == 0 && titleBarDuringGesture.placements.isEmpty,
                     "a title bar drag seen while the move gesture holds a press is not tracked toward an edge")

        reset()
        let titleBarDuringMove = Host()
        send(titleBarDuringMove, .leftMouseDown, pressPoint)
        titleBarDuringMove.activeGesture = gesture()
        currentFrame = initialFrame.offsetBy(dx: 40, dy: 0)
        send(titleBarDuringMove, .leftMouseDragged, CGPoint(x: 240, y: 200))
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        currentFrame = movedToEdge
        send(titleBarDuringMove, .leftMouseDragged, edgePoint)
        send(titleBarDuringMove, .leftMouseUp, edgePoint)
        suite.expect(titleBarDuringMove.previews == 0 && titleBarDuringMove.placements.isEmpty,
                     "a title bar drag seen while a move gesture is under way is not tracked toward an edge")

        reset()
        canBePlaced = false
        let modifierUnplaceable = Host()
        take(modifierUnplaceable, move)
        for step in 1...5 {
            DispatchQueue.drainLookups()
            DispatchQueue.main.runDue()
            modifierUnplaceable.edgeSnapLastResolveAt = 0
            clock += 0.1
            carry(modifierUnplaceable, move, to: CGPoint(x: 240 + CGFloat(step) * 200, y: 200))
        }
        carry(modifierUnplaceable, move, to: edgePoint)
        drop(modifierUnplaceable, move, at: edgePoint)
        suite.expect(mainLookupsAfterRelease == 0 && modifierUnplaceable.placements.isEmpty,
                     "a modifier move whose window every lookup turned down is not looked up again at release")

        // The gesture tap's own callback, with real events carrying the chord.
        let chord: CGEventFlags = [.maskControl, .maskCommand]
        let dummyTap = CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
        /// One event through the move gesture's callback and the jobs it
        /// leaves. Returns whether the event went on to the app.
        func gestureEvent(_ host: Host, _ type: CGEventType, _ point: CGPoint,
                          flags: CGEventFlags = chord) -> Bool {
            if type == .leftMouseDown { buttonDown = true }
            if type == .leftMouseUp { buttonDown = false }
            let pointerEvent = event(type, at: point)
            pointerEvent.flags = flags
            let passed = host.handleGestureEvent(proxy: nil, type: type, event: pointerEvent) != nil
            DispatchQueue.main.runDue()
            return passed
        }
        func chordDrag(_ host: Host, flags: CGEventFlags = chord) -> (heldPress: Bool, preview: Bool) {
            let pressPassed = gestureEvent(host, .leftMouseDown, pressPoint, flags: flags)
            _ = gestureEvent(host, .leftMouseDragged, CGPoint(x: 240, y: 200), flags: flags)
            DispatchQueue.drainLookups()
            DispatchQueue.main.runDue()
            clock += 0.05
            _ = gestureEvent(host, .leftMouseDragged, edgePoint, flags: flags)
            return (!pressPassed, host.previewShown)
        }

        reset()
        let tapMove = Host()
        tapMove.edgeSnapTap = dummyTap
        let tapMoveDrag = chordDrag(tapMove)
        let releaseSwallowed = !gestureEvent(tapMove, .leftMouseUp, edgePoint)
        DispatchQueue.main.drain()
        suite.expect(tapMoveDrag.heldPress && tapMoveDrag.preview && releaseSwallowed
                        && tapMove.placedActions == [.rightHalf]
                        && tapMove.placements == [WindowLayoutFrame(origin: initialFrame.origin,
                                                                    size: initialFrame.size)],
                     "a chord drag through the gesture tap previews the zone, snaps on release and keeps its starting frame for Restore")

        reset()
        let tapResize = Host()
        tapResize.edgeSnapTap = dummyTap
        let tapResizeDrag = chordDrag(tapResize, flags: chord.union(.maskShift))
        _ = gestureEvent(tapResize, .leftMouseUp, edgePoint, flags: chord.union(.maskShift))
        DispatchQueue.main.drain()
        suite.expect(tapResizeDrag.heldPress && !tapResizeDrag.preview && tapResize.placements.isEmpty
                        && mainAXWhileHeld + lookupQueueAX + mainAXAfterRelease == 0,
                     "a resize chord through the gesture tap never previews, snaps or asks for the window's server ID")

        reset()
        let tapSnapOff = Host()
        let tapSnapOffDrag = chordDrag(tapSnapOff)
        _ = gestureEvent(tapSnapOff, .leftMouseUp, edgePoint)
        DispatchQueue.main.drain()
        suite.expect(tapSnapOffDrag.heldPress && !tapSnapOffDrag.preview && tapSnapOff.placements.isEmpty
                        && mainAXWhileHeld + lookupQueueAX + mainAXAfterRelease == 0,
                     "a chord drag while edge snapping is off moves the window without snapping or asking for its server ID")

        reset()
        let tapClick = Host()
        tapClick.edgeSnapTap = dummyTap
        _ = gestureEvent(tapClick, .leftMouseDown, pressPoint)
        _ = gestureEvent(tapClick, .leftMouseUp, pressPoint)
        DispatchQueue.main.drain()
        suite.expect(tapClick.replayedClicks == 1 && mainAXWhileHeld + mainAXAfterRelease == 0,
                     "a plain chord click is handed back without asking for the window's server ID")

        reset()
        windowIDReadable = false
        let tapNoID = Host()
        tapNoID.edgeSnapTap = dummyTap
        let tapNoIDDrag = chordDrag(tapNoID)
        _ = gestureEvent(tapNoID, .leftMouseUp, edgePoint)
        DispatchQueue.main.drain()
        suite.expect(!tapNoIDDrag.preview && tapNoID.placements.isEmpty,
                     "a chord drag whose window has no readable server ID moves without snapping")

        reset()
        let tapCutOff = Host()
        tapCutOff.edgeSnapTap = dummyTap
        let tapCutOffDrag = chordDrag(tapCutOff)
        _ = tapCutOff.handleGestureEvent(proxy: nil, type: .tapDisabledByTimeout, event: CGEvent(source: nil)!)
        DispatchQueue.main.runDue()
        let hiddenOnCutOff = !tapCutOff.previewShown
        _ = gestureEvent(tapCutOff, .leftMouseUp, edgePoint)
        DispatchQueue.main.drain()
        suite.expect(tapCutOffDrag.preview && hiddenOnCutOff && tapCutOff.placements.isEmpty,
                     "a chord drag the system cuts off through the gesture tap hides the preview and never snaps")
        let key = WindowLayoutWindowKey(processID: processID,
                                        processLaunchTime: launch.timeIntervalSinceReferenceDate,
                                        windowID: windowID)
        let startingFrame = WindowLayoutFrame(origin: initialFrame.origin, size: initialFrame.size)
        /// Parks the window on the right half the way a placement does, with
        /// its earlier frame kept for Restore.
        func park(_ host: Host) -> CGRect {
            let parked = host.placement(for: .rightHalf, current: startingFrame,
                                        visibleFrame: NSScreen.primary.visibleFrame).frame
            host.lastActions[key] = .rightHalf
            host.frameHistory.record(startingFrame, for: key)
            currentFrame = CGRect(origin: parked.origin, size: parked.size)
            return currentFrame
        }
        /// A modifier move taking the window at `grab`, its pointer since gone on to `pointer`.
        func carryOff(_ host: Host, from frame: CGRect, grab: CGPoint, pointer: CGPoint) -> WindowPointerGesture {
            let gesture = WindowPointerGesture(window: Window(pid: processID, id: windowID), kind: .move,
                                               button: .primary, originalFrame: frame, pointerStart: grab,
                                               lastAppliedAt: 0, snapsAtEdges: true, lastPointer: pointer)
            buttonDown = true
            host.activeGesture = gesture
            host.forwardToEdgeSnap(gesture, .moveGestureBegan(pressOrigin: grab, initialFrame: frame,
                                                              windowID: windowID, processID: processID))
            DispatchQueue.main.runDue()
            return gesture
        }
        func restoreEntry(_ host: Host, at frame: CGRect) -> WindowLayoutFrame? {
            var history = host.frameHistory
            return history.popPrevious(for: key, current: WindowLayoutFrame(origin: frame.origin, size: frame.size))
        }
        /// Restore after a snap that followed a given-back frame: that frame,
        /// and nothing older behind it, since the earlier entry was spent.
        func restoresOnly(_ host: Host, _ frame: WindowLayoutFrame, from parked: CGRect) -> Bool {
            restoreEntry(host, at: parked) == frame
                && restoreEntry(host, at: CGRect(origin: frame.origin, size: frame.size)) == nil
        }

        reset()
        let unparkHost = Host()
        let parkedRect = park(unparkHost)
        let grab = CGPoint(x: parkedRect.midX, y: parkedRect.minY + 10)
        let restingPointer = CGPoint(x: grab.x - 30, y: grab.y + 5)
        let unparking = carryOff(unparkHost, from: parkedRect, grab: grab, pointer: restingPointer)
        land(unparkHost)
        // Half the earlier width left of the pointer would reach past the
        // display's right edge, so the window sits against it instead.
        let fittedX = NSScreen.primary.visibleFrame.maxX - initialFrame.width
        let restoredUnderPointer = currentFrame == CGRect(x: fittedX, y: restingPointer.y - 10,
                                                          width: initialFrame.width, height: initialFrame.height)
        // The window server lags behind for the rest of the drag.
        let leftEdge = CGPoint(x: 1, y: 400)
        for step in 1...4 {
            clock += 0.05
            let point = CGPoint(x: restingPointer.x + (leftEdge.x - restingPointer.x) * CGFloat(step) / 4, y: 400)
            unparkHost.forwardToEdgeSnap(unparking, .dragged(location: point, time: clockStart + clock))
            DispatchQueue.drainLookups()
            DispatchQueue.main.runDue()
        }
        drop(unparkHost, unparking, at: leftEdge)
        let restoredAtGrab = WindowLayoutFrame(origin: CGPoint(x: fittedX - (restingPointer.x - grab.x), y: grab.y - 10),
                                               size: initialFrame.size)
        suite.expect(restoredUnderPointer,
                     "a modifier move that carries off a snapped window gives back its earlier size under the pointer, even with the pointer at rest")
        suite.expect(unparkHost.placedActions == [.leftHalf] && unparkHost.placements == [restoredAtGrab]
                        && unparkHost.lastActions[key] == .leftHalf
                        && restoresOnly(unparkHost, restoredAtGrab, from: parkedRect),
                     "a window given back its size snaps again at the next edge, and Restore then returns the given-back size, not the parked frame")

        reset()
        sizeAccepted = false
        let refusedHost = Host()
        let refusedRect = park(refusedHost)
        _ = carryOff(refusedHost, from: refusedRect, grab: grab, pointer: restingPointer)
        land(refusedHost)
        suite.expect(currentFrame.size == refusedRect.size && refusedHost.lastActions[key] == .rightHalf
                        && restoreEntry(refusedHost, at: refusedRect) == startingFrame,
                     "an app that refuses the earlier size keeps its window's Restore frame")

        reset()
        let movedByHand = Host()
        let handRect = park(movedByHand).offsetBy(dx: -200, dy: 0)
        currentFrame = handRect
        let handGrab = CGPoint(x: handRect.midX, y: handRect.minY + 10)
        _ = carryOff(movedByHand, from: handRect, grab: handGrab, pointer: handGrab)
        land(movedByHand)
        suite.expect(currentFrame == handRect && movedByHand.lastActions[key] == .rightHalf
                        && restoreEntry(movedByHand, at: handRect) == startingFrame,
                     "a modifier move of a window no longer where its last placement left it keeps its size and its Restore frame")

        reset()
        let settlingHost = Host()
        let settlingRect = park(settlingHost)
        let assistiveFlag = EnhancedUserInterfaceSuspension()
        settlingHost.assistiveModeSuspensions[windowID] = assistiveFlag
        _ = carryOff(settlingHost, from: settlingRect, grab: grab, pointer: restingPointer)
        land(settlingHost)
        let heldDuringDrag = assistiveFlag.resumed == 0
        settlingHost.activeGesture = nil
        settlingHost.endGestureAssistiveMode()
        suite.expect(heldDuringDrag && assistiveFlag.resumed == 1,
                     "carrying off a window whose placement is still settling gives the app's assistive flag back when the gesture ends")

        // A title bar drag of a snapped window: the window server or the app
        // carries the window, which here follows the pointer from the press.
        let titleBarGrab = CGPoint(x: parkedRect.midX, y: parkedRect.minY + 14)
        func carryParked(_ host: Host, to point: CGPoint) {
            clock += 0.01
            let size = currentFrame.size
            currentFrame = CGRect(origin: CGPoint(x: parkedRect.minX + point.x - titleBarGrab.x,
                                                  y: parkedRect.minY + point.y - titleBarGrab.y),
                                  size: size)
            hand(host, .leftMouseDragged, point)
        }
        /// Where a window given back its earlier size sits once its title bar,
        /// grabbed in the middle, is at `point`, kept on the display.
        func unparkedAt(_ point: CGPoint) -> CGRect {
            let visible = NSScreen.primary.visibleFrame
            return CGRect(x: max(visible.minX, min(point.x - initialFrame.width / 2, visible.maxX - initialFrame.width)),
                          y: point.y - 14, width: initialFrame.width, height: initialFrame.height)
        }
        /// A press on the title bar and a first step that the lookup answers
        /// at once, so the drag is seen moving the window.
        func pressTitleBar(_ host: Host) {
            send(host, .leftMouseDown, titleBarGrab)
            carryParked(host, to: CGPoint(x: titleBarGrab.x - 20, y: titleBarGrab.y))
            DispatchQueue.drainLookups()
            DispatchQueue.main.runDue()
        }
        let away = CGPoint(x: titleBarGrab.x - 30, y: titleBarGrab.y)

        reset()
        let unparkedByTitleBar = Host()
        _ = park(unparkedByTitleBar)
        pressTitleBar(unparkedByTitleBar)
        carryParked(unparkedByTitleBar, to: away)
        let nothingAskedWhileHeld = mainAXWhileHeld == 0
        let keptUntilLanded = unparkedByTitleBar.lastActions[key] == .rightHalf
        DispatchQueue.drainLookups()
        DispatchQueue.main.runDue()
        suite.expect(nothingAskedWhileHeld && keptUntilLanded
                        && unparkedByTitleBar.writes == [Write.size(initialFrame.size),
                                                         .position(unparkedAt(away).origin),
                                                         .size(initialFrame.size)]
                        && unparkedByTitleBar.lastActions[key] == nil
                        && restoreEntry(unparkedByTitleBar, at: parkedRect) == nil,
                     "a title bar drag that carries off a snapped window gives back its earlier frame once, under the pointer, and spends Restore's entry once it lands")
        carryParked(unparkedByTitleBar, to: CGPoint(x: away.x - 40, y: away.y))
        DispatchQueue.drainLookups()
        send(unparkedByTitleBar, .leftMouseUp, CGPoint(x: away.x - 40, y: away.y))
        suite.expect(unparkedByTitleBar.writes.count == 3 && unparkedByTitleBar.placements.isEmpty,
                     "a snapped window dragged off by its title bar is given back its size once and stays where it is dropped")

        reset()
        let titleBarResnap = Host()
        _ = park(titleBarResnap)
        pressTitleBar(titleBarResnap)
        carryParked(titleBarResnap, to: away)
        // The frame is still to be written when the window reaches the edge,
        // so it is placed where the window is then.
        let leftEdgeDrop = CGPoint(x: 0, y: 400)
        carryParked(titleBarResnap, to: leftEdgeDrop)
        send(titleBarResnap, .leftMouseUp, CGPoint(x: 0, y: 400))
        let placedBeforeWrite = !titleBarResnap.placements.isEmpty
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        suite.expect(!placedBeforeWrite
                        && titleBarResnap.writes == [Write.size(initialFrame.size), .position(unparkedAt(leftEdgeDrop).origin),
                                               .size(initialFrame.size), .placement]
                        && titleBarResnap.placedActions == [.leftHalf]
                        && titleBarResnap.placements == [WindowLayoutFrame(origin: unparkedAt(away).origin,
                                                                           size: initialFrame.size)]
                        && titleBarResnap.lastActions[key] == .leftHalf
                        && restoresOnly(titleBarResnap,
                                        WindowLayoutFrame(origin: unparkedAt(away).origin, size: initialFrame.size),
                                        from: parkedRect),
                     "a snapped window dragged by its title bar to another edge gets its size back before it snaps, and Restore then returns that size")

        reset()
        sizeAccepted = false
        let titleBarRefused = Host()
        _ = park(titleBarRefused)
        pressTitleBar(titleBarRefused)
        carryParked(titleBarRefused, to: away)
        DispatchQueue.drainLookups()
        DispatchQueue.main.runDue()
        suite.expect(titleBarRefused.lastActions[key] == .rightHalf
                        && restoreEntry(titleBarRefused, at: parkedRect) == startingFrame,
                     "an app that refuses the earlier size during a title bar drag keeps its window's Restore frame")

        reset()
        let titleBarSettling = Host()
        _ = park(titleBarSettling)
        let titleBarFlag = EnhancedUserInterfaceSuspension()
        titleBarSettling.assistiveModeSuspensions[windowID] = titleBarFlag
        pressTitleBar(titleBarSettling)
        carryParked(titleBarSettling, to: away)
        let flagHeldUntilWritten = titleBarFlag.resumed == 0
        DispatchQueue.drainLookups()
        suite.expect(flagHeldUntilWritten && titleBarFlag.resumed == 1
                        && titleBarSettling.assistiveModeSuspensions[windowID] == nil,
                     "a title bar drag off a window whose placement is still settling gives the app's assistive flag back after its write")

        reset()
        let titleBarMovedByHand = Host()
        let handParked = park(titleBarMovedByHand).offsetBy(dx: -200, dy: 0)
        currentFrame = handParked
        let handTitleBar = CGPoint(x: handParked.midX, y: handParked.minY + 14)
        send(titleBarMovedByHand, .leftMouseDown, handTitleBar)
        for step in 1...2 {
            clock += 0.01
            currentFrame = handParked.offsetBy(dx: CGFloat(step) * -20, dy: 0)
            hand(titleBarMovedByHand, .leftMouseDragged, CGPoint(x: handTitleBar.x + CGFloat(step) * -20,
                                                                y: handTitleBar.y))
            DispatchQueue.drainLookups()
            DispatchQueue.main.runDue()
        }
        suite.expect(titleBarMovedByHand.writes.isEmpty && titleBarMovedByHand.lastActions[key] == .rightHalf
                        && restoreEntry(titleBarMovedByHand, at: handParked) == startingFrame,
                     "a title bar drag of a window no longer where its last placement left it keeps its size and its Restore frame")

        reset()
        let insideSnapped = Host()
        _ = park(insideSnapped)
        send(insideSnapped, .leftMouseDown, titleBarGrab)
        for step in 1...3 {
            clock += 0.01
            hand(insideSnapped, .leftMouseDragged, CGPoint(x: titleBarGrab.x - CGFloat(step) * 20,
                                                          y: titleBarGrab.y + CGFloat(step) * 20))
            DispatchQueue.drainLookups()
            DispatchQueue.main.runDue()
        }
        send(insideSnapped, .leftMouseUp, CGPoint(x: titleBarGrab.x - 60, y: titleBarGrab.y + 60))
        suite.expect(insideSnapped.writes.isEmpty && insideSnapped.lastActions[key] == .rightHalf
                        && restoreEntry(insideSnapped, at: parkedRect) == startingFrame,
                     "a drag inside a snapped window that never moves it keeps its size and its Restore frame")

        reset()
        WindowEdgeSnapSupport.isSystemTilingEnabled = true
        let titleBarSystemTiling = Host()
        _ = park(titleBarSystemTiling)
        pressTitleBar(titleBarSystemTiling)
        carryParked(titleBarSystemTiling, to: away)
        DispatchQueue.drainLookups()
        suite.expect(titleBarSystemTiling.writes.isEmpty && titleBarSystemTiling.lastActions[key] == .rightHalf,
                     "a snapped window dragged off by its title bar keeps its size while macOS tiling owns the edges")

        // The first unsnap after an app starts gives back the app's own,
        // wider frame, which does not fit where the right half parked it.
        let farRightGrab = CGPoint(x: parkedRect.maxX - 30, y: parkedRect.minY + 14)
        let farRightPointer = CGPoint(x: farRightGrab.x - 10, y: farRightGrab.y)

        reset()
        let wideModifier = Host()
        _ = park(wideModifier)
        _ = carryOff(wideModifier, from: parkedRect, grab: farRightGrab, pointer: farRightPointer)
        land(wideModifier)
        suite.expect(currentFrame.size == initialFrame.size && currentFrame.minX <= farRightPointer.x
                        && currentFrame.maxX >= farRightPointer.x
                        && currentFrame.maxX <= NSScreen.primary.visibleFrame.maxX,
                     "a modifier move carrying off the right end of a right-half window's title bar gets the whole earlier width, with the pointer still on the window")

        reset()
        let wideTitleBar = Host()
        _ = park(wideTitleBar)
        send(wideTitleBar, .leftMouseDown, farRightGrab)
        for step in 1...2 {
            clock += 0.01
            let point = CGPoint(x: farRightGrab.x - CGFloat(step) * 10, y: farRightGrab.y)
            currentFrame = parkedRect.offsetBy(dx: point.x - farRightGrab.x, dy: 0)
            hand(wideTitleBar, .leftMouseDragged, point)
            DispatchQueue.drainLookups()
            DispatchQueue.main.runDue()
        }
        let wideTitleBarPointer = CGPoint(x: farRightGrab.x - 20, y: farRightGrab.y)
        suite.expect(currentFrame.size == initialFrame.size && currentFrame.minX <= wideTitleBarPointer.x
                        && currentFrame.maxX >= wideTitleBarPointer.x
                        && currentFrame.maxX <= NSScreen.primary.visibleFrame.maxX,
                     "a title bar drag off the right end of a right-half window's title bar gets the whole earlier width, with the pointer still on the window")

        // An earlier frame larger than this display, say from a bigger one.
        let visible = NSScreen.primary.visibleFrame
        let largerFrame = WindowLayoutFrame(origin: CGPoint(x: 50, y: 30), size: CGSize(width: 1800, height: 1100))
        reset()
        let largerByTitleBar = Host()
        _ = park(largerByTitleBar)
        largerByTitleBar.frameHistory = WindowLayoutHistory()
        largerByTitleBar.frameHistory.record(largerFrame, for: key)
        pressTitleBar(largerByTitleBar)
        carryParked(largerByTitleBar, to: away)
        DispatchQueue.drainLookups()
        DispatchQueue.main.runDue()
        suite.expect(currentFrame.size == visible.size && currentFrame.minX <= away.x && currentFrame.maxX >= away.x
                        && currentFrame.minY == parkedRect.minY && largerByTitleBar.lastActions[key] == nil,
                     "a window whose earlier frame is larger than the display gets back the display's visible size, its title bar under the pointer")

        // A window parked on the bottom half whose earlier frame is taller
        // than the room below its title bar: macOS cuts the height.
        reset()
        let cutHost = Host()
        let bottom = cutHost.placement(for: .bottomHalf, current: startingFrame, visibleFrame: visible).frame
        let bottomRect = CGRect(origin: bottom.origin, size: bottom.size)
        let tallerFrame = WindowLayoutFrame(origin: CGPoint(x: 100, y: 40), size: CGSize(width: 800, height: 700))
        cutHost.lastActions[key] = .bottomHalf
        cutHost.frameHistory.record(tallerFrame, for: key)
        currentFrame = bottomRect
        let bottomGrab = CGPoint(x: bottomRect.midX, y: bottomRect.minY + 10)
        _ = carryOff(cutHost, from: bottomRect, grab: bottomGrab, pointer: bottomGrab)
        land(cutHost)
        suite.expect(currentFrame.height < tallerFrame.size.height && cutHost.lastActions[key] == .bottomHalf
                        && restoreEntry(cutHost, at: bottomRect) == tallerFrame,
                     "a window whose earlier height macOS cuts at the bottom of the display keeps its Restore entry")

        reset()
        let movedOnByTitleBar = Host()
        _ = park(movedOnByTitleBar)
        pressTitleBar(movedOnByTitleBar)
        carryParked(movedOnByTitleBar, to: away)
        // The drag carries the window on before the lookup queue gets to it.
        let further = CGPoint(x: away.x - 150, y: away.y + 60)
        carryParked(movedOnByTitleBar, to: further)
        DispatchQueue.drainLookups()
        suite.expect(movedOnByTitleBar.writes == [Write.size(initialFrame.size), .position(unparkedAt(further).origin),
                                                  .size(initialFrame.size)],
                     "a title bar drag places the given-back frame from where the window is when it is written, not where it was sampled")

        reset()
        assistiveFlagOn = true
        let assistiveTitleBar = Host()
        _ = park(assistiveTitleBar)
        pressTitleBar(assistiveTitleBar)
        carryParked(assistiveTitleBar, to: away)
        DispatchQueue.drainLookups()
        suite.expect(assistiveHolds.count == 1 && assistiveHolds[0].resumed == 1 && assistiveTitleBar.writes.count == 3,
                     "a title bar drag holds the app's assistive flag off around the given-back frame and gives it back after")

        reset()
        let clickedDuringWrite = Host()
        _ = park(clickedDuringWrite)
        pressTitleBar(clickedDuringWrite)
        carryParked(clickedDuringWrite, to: away)
        carryParked(clickedDuringWrite, to: leftEdgeDrop)
        send(clickedDuringWrite, .leftMouseUp, leftEdgeDrop)
        // A new press, here on the desktop, comes before the write has landed.
        send(clickedDuringWrite, .leftMouseDown, CGPoint(x: 1400, y: 880))
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        suite.expect(clickedDuringWrite.placements.isEmpty && clickedDuringWrite.writes.count == 3
                        && clickedDuringWrite.lastActions[key] == nil,
                     "a new press before the title bar write lands drops the waiting snap, like any pending release snap, and the given-back frame still lands")

        reset()
        let movedDuringSize = Host()
        _ = park(movedDuringSize)
        pressTitleBar(movedDuringSize)
        carryParked(movedDuringSize, to: away)
        let carriedOn = CGPoint(x: away.x - 60, y: away.y + 30)
        duringSizeWrite = {
            currentFrame.origin = CGPoint(x: currentFrame.minX + carriedOn.x - away.x,
                                          y: currentFrame.minY + carriedOn.y - away.y)
        }
        DispatchQueue.drainLookups()
        suite.expect(movedDuringSize.writes == [Write.size(initialFrame.size), .position(unparkedAt(carriedOn).origin),
                                                .size(initialFrame.size)],
                     "a title bar drag reads where the window is only after the app has taken the size, just before placing it")

        reset()
        NSScreen.screens = [NSScreen.primary, NSScreen.beside]
        let acrossSeam = Host()
        _ = park(acrossSeam)
        let seamGrab = CGPoint(x: parkedRect.maxX - 30, y: parkedRect.minY + 14)
        send(acrossSeam, .leftMouseDown, seamGrab)
        clock += 0.01
        currentFrame = parkedRect.offsetBy(dx: 20, dy: 0)
        hand(acrossSeam, .leftMouseDragged, CGPoint(x: seamGrab.x + 20, y: seamGrab.y))
        DispatchQueue.drainLookups()
        DispatchQueue.main.runDue()
        clock += 0.01
        currentFrame = parkedRect.offsetBy(dx: 30, dy: 0)
        hand(acrossSeam, .leftMouseDragged, CGPoint(x: seamGrab.x + 30, y: seamGrab.y))
        // The pointer crosses onto the display beside before the write runs.
        let pastSeam = CGPoint(x: seamGrab.x + 200, y: seamGrab.y)
        currentFrame = parkedRect.offsetBy(dx: 200, dy: 0)
        DispatchQueue.drainLookups()
        let besideVisible = NSScreen.beside.visibleFrame
        suite.expect(currentFrame.size == initialFrame.size && currentFrame.minX >= besideVisible.minX
                        && currentFrame.minX <= pastSeam.x && currentFrame.maxX >= pastSeam.x,
                     "a title bar drag that has crossed onto another display is given back its frame on that display, under the pointer")

        reset()
        let cutTitleBar = Host()
        let cutBottom = cutTitleBar.placement(for: .bottomHalf, current: startingFrame, visibleFrame: visible).frame
        let cutRect = CGRect(origin: cutBottom.origin, size: cutBottom.size)
        cutTitleBar.lastActions[key] = .bottomHalf
        cutTitleBar.frameHistory.record(tallerFrame, for: key)
        currentFrame = cutRect
        let cutGrab = CGPoint(x: cutRect.midX, y: cutRect.minY + 14)
        send(cutTitleBar, .leftMouseDown, cutGrab)
        for step in 1...2 {
            clock += 0.01
            currentFrame = cutRect.offsetBy(dx: CGFloat(step) * -20, dy: 0)
            hand(cutTitleBar, .leftMouseDragged, CGPoint(x: cutGrab.x + CGFloat(step) * -20, y: cutGrab.y))
            DispatchQueue.drainLookups()
            DispatchQueue.main.runDue()
        }
        let cutLanded = currentFrame
        let cutDrop = CGPoint(x: 0, y: 500)
        send(cutTitleBar, .leftMouseUp, cutDrop)
        DispatchQueue.drainLookups()
        DispatchQueue.main.drain()
        var cutHistory = cutTitleBar.frameHistory
        let farAway = WindowLayoutFrame(origin: CGPoint(x: -5000, y: -5000), size: CGSize(width: 1, height: 1))
        let lastEntry = cutHistory.popPrevious(for: key, current: farAway)
        let entryBefore = cutHistory.popPrevious(for: key, current: farAway)
        suite.expect(cutLanded.height < tallerFrame.size.height && cutTitleBar.placedActions == [.leftHalf]
                        && lastEntry?.size == cutLanded.size && entryBefore == tallerFrame,
                     "a title bar drop after a cut given-back frame keeps, for Restore, the frame the window had, not the size that never landed")
    }
}
