// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

private typealias EdgeSnapGeometry = WindowEdgeSnapSupport

/// The production pointer callback, tracking, lookup, target and release bodies
/// are extracted on every test build. Scheduling, window server snapshots, AX,
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
        var isTerminated: Bool { !windowExists }
        init?(processIdentifier: pid_t) {
            guard windowExists, processIdentifier == processID else { return nil }
            self.processIdentifier = processIdentifier
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
            return window.id
        }
    }

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
        var edgeSnapStillCheckGeneration = 0
        var edgeSnapStillCheckPending = false
        let edgeSnapResolveQueue = DispatchQueue(label: "test lookup", qos: .userInitiated)
        var activeGesture: Bool?
        var pendingGesture: Bool?
        let edgeSnapSampleInterval: TimeInterval = 0
        var enabledEdgeSnapZones = WindowEdgeSnapZone.allEnabled
        var previews = 0
        var placements: [WindowLayoutFrame] = []
        var placedActions: [WindowLayoutAction] = []

        func syncWithPreferences() {}
        func edgeSnapConflictsWithWindowGesture(flags: CGEventFlags) -> Bool { false }
        func edgeSnapQuartzScreenFrames() -> [CGRect] { [CGRect(x: 0, y: 0, width: 1440, height: 900)] }
        var menuBarScreenTopY: CGFloat { NSScreen.primary.frame.maxY }
        static var uptimeSeconds: TimeInterval { clockStart + clock }
        func showEdgeSnapPreview(frame: CGRect) { previews += 1 }
        func hideEdgeSnapPreview(immediately: Bool) {}
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
        @discardableResult
        func applyPlacement(_ action: WindowLayoutAction, to target: WindowLayoutTarget,
                            visibleFrame: CGRect, historyFrame: WindowLayoutFrame,
                            cyclesRepeatedAction: Bool) -> Bool {
            placements.append(historyFrame)
            placedActions.append(action)
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
    }
}
