// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Coupled resizing for windows placed by Window Layout: when one of them is
/// resized at an edge it shares with another placed window, that neighbour's
/// facing edge follows. Observation runs only while the setting is on, and
/// only for windows the layout placed, never for windows that merely touch.
///
/// Our own writes are recognised by the frame they produced, not by time, so a
/// running drag is never paused. Frames come from Accessibility events and, while
/// the mouse button is down, from a timer as well.
final class WindowStickySnapService {
    static let shared = WindowStickySnapService()

    private struct Tracked {
        var frame: CGRect
        let pid: pid_t
        /// Short settling time after a placement; events before it are ignored.
        var quietUntil: TimeInterval
        var echoes = WindowStickyEchoGuard()
        var idle = WindowStickyIdleTracker()
        var pacer = WindowStickyWritePacer()
        /// The last frame we wrote, for spotting echoes the guard missed.
        var lastWritten: CGRect?
        var lastWriteTime: TimeInterval = 0
        var deferredScheduled = false
    }

    private struct Eligibility {
        let live: Bool
        let checkedAt: TimeInterval
    }

    /// One drag of one window: which neighbours follow at which edge and gap.
    /// Fixed when the drag starts, so a lagging neighbour stays coupled.
    private struct Session {
        let driver: AXUIElement
        var couplings: [(follower: AXUIElement, edge: WindowStickyEdge, gap: CGFloat)]
    }

    /// Settling time of a placement (about a frame generation or two).
    private static let placementQuiet: TimeInterval = 0.15
    private static let eligibilityInterval: TimeInterval = 0.5
    private static let pollInterval: TimeInterval = 1.0 / 60.0
    private static let trackedLimit = 24

    private var tracked: [AXUIElement: Tracked] = [:]
    private var order: [AXUIElement] = []
    private var observers: [pid_t: AXObserver] = [:]
    private var eligibility: [AXUIElement: Eligibility] = [:]
    private var session: Session?
    private var terminationObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var pollTimer: Timer?
    private var polled: [AXUIElement] = []
    private var running = false

    private init() {}

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.windowStickySnapEnabled)
    }

    /// Starts or stops the observation. Stopping removes every observer.
    func sync(wanted: Bool) {
        wanted ? start() : stop()
    }

    private func start() {
        guard !running else { return }
        running = true
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.forget(pid: app.processIdentifier)
        }
        // A live resize may not report every step, so while the button is down
        // the windows under the pointer are read on a timer as well.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            if event.type == .leftMouseDown { self?.startPolling() } else { self?.stopPolling() }
        }
        StickyLog.write(kind: "start")
    }

    func stop() {
        guard running else { return }
        running = false
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
        polled = []
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
        tracked.removeAll()
        order.removeAll()
        eligibility.removeAll()
        session = nil
        StickyLog.write(kind: "stop")
    }

    // MARK: - Layout hooks

    /// Called after Window Layout placed `window`. The placement may still be
    /// settling, so its events are ignored for a moment and the frame is read
    /// again afterwards.
    func layoutPlaced(_ window: AXUIElement) {
        guard running, let frame = Self.frame(of: window) else { return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return }
        // A window that cannot be resized never drives or follows anything.
        guard WindowLayoutService.shared.canSetFrame(on: window) else {
            untrack(window, reason: "not-settable")
            return
        }
        AXUIElementSetMessagingTimeout(window, 0.25)
        let now = ProcessInfo.processInfo.systemUptime
        if tracked[window] == nil {
            guard observe(window, pid: pid) else { return }
            order.append(window)
        }
        var entry = Tracked(frame: frame, pid: pid, quietUntil: now + Self.placementQuiet)
        entry.echoes.noteWrite(frame, now: now)
        tracked[window] = entry
        eligibility[window] = nil
        trimToLimit()
        StickyLog.write(kind: "placed", window: window, frame: frame)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.placementQuiet + 0.05) { [weak self] in
            guard let self, self.tracked[window] != nil, let settled = Self.frame(of: window) else { return }
            self.tracked[window]?.frame = settled
            self.tracked[window]?.echoes.noteWrite(settled, now: ProcessInfo.processInfo.systemUptime)
        }
    }

    /// Called when Window Layout hands the window back (restore, full screen).
    func layoutReleased(_ window: AXUIElement) {
        untrack(window, reason: "released")
    }

    // MARK: - Observation

    private func observe(_ window: AXUIElement, pid: pid_t) -> Bool {
        let observer: AXObserver
        if let existing = observers[pid] {
            observer = existing
        } else {
            var created: AXObserver?
            let callback: AXObserverCallback = { _, element, notification, _ in
                WindowStickySnapService.shared.handle(element, notification: notification as String)
            }
            guard AXObserverCreate(pid, callback, &created) == .success, let created else {
                StickyLog.write(kind: "observe-failed", window: window, note: "create")
                return false
            }
            observers[pid] = created
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            observer = created
        }
        // An app that does not report resizes cannot be coupled; skip it quietly.
        let resized = AXObserverAddNotification(observer, window, kAXWindowResizedNotification as CFString, nil)
        let moved = AXObserverAddNotification(observer, window, kAXWindowMovedNotification as CFString, nil)
        let destroyed = AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, nil)
        StickyLog.write(kind: "observe", window: window,
                        note: "pid=\(pid) resized=\(resized.rawValue) moved=\(moved.rawValue) destroyed=\(destroyed.rawValue)")
        return resized == .success
    }

    private func untrack(_ window: AXUIElement, reason: String) {
        guard let entry = tracked.removeValue(forKey: window) else { return }
        StickyLog.write(kind: "untrack", window: window, frame: entry.frame, note: reason)
        order.removeAll { $0 == window }
        eligibility[window] = nil
        if session?.driver == window { session = nil }
        if let observer = observers[entry.pid] {
            _ = AXObserverRemoveNotification(observer, window, kAXWindowResizedNotification as CFString)
            _ = AXObserverRemoveNotification(observer, window, kAXWindowMovedNotification as CFString)
            _ = AXObserverRemoveNotification(observer, window, kAXUIElementDestroyedNotification as CFString)
            if !tracked.values.contains(where: { $0.pid == entry.pid }) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                observers[entry.pid] = nil
            }
        }
    }

    private func forget(pid: pid_t) {
        for (window, entry) in tracked where entry.pid == pid { untrack(window, reason: "app-quit") }
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    private func trimToLimit() {
        while order.count > Self.trackedLimit, let oldest = order.first { untrack(oldest, reason: "limit") }
    }

    // MARK: - Polling while the button is down

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard running, !tracked.isEmpty, let top = NSScreen.screens.first?.frame.maxY else { return }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: top - mouse.y)
        // Only windows with the pointer on or near them can be the one dragged.
        polled = order.filter { window in
            guard let frame = tracked[window]?.frame else { return false }
            return frame.insetBy(dx: -12, dy: -12).contains(point)
        }
        guard !polled.isEmpty else { return }
        StickyLog.write(kind: "poll-start", note: "windows=\(polled.count)")
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            for window in self.polled { self.process(window, source: "poll") }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        guard let timer = pollTimer else { return }
        timer.invalidate()
        pollTimer = nil
        // One last read in case the final step came after the last tick.
        for window in polled { process(window, source: "poll") }
        polled = []
        StickyLog.write(kind: "poll-stop")
    }

    // MARK: - Coupling

    private func handle(_ window: AXUIElement, notification: String) {
        guard running, tracked[window] != nil else { return }
        if notification == kAXUIElementDestroyedNotification as String {
            untrack(window, reason: "destroyed")
            return
        }
        process(window, source: "ax")
    }

    /// One look at a tracked window, from an Accessibility event or a poll tick.
    private func process(_ window: AXUIElement, source: String) {
        guard running, var entry = tracked[window] else { return }
        // A closed window reads as nil and leaves the layout.
        guard let new = Self.frame(of: window) else {
            untrack(window, reason: "unreadable")
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let old = entry.frame
        let changed = !WindowStickyEchoGuard.matches(old, new, tolerance: 1)
        func log(_ verdict: String) {
            // Poll ticks without a change would flood the log.
            if source == "ax" || changed { StickyLog.write(kind: source, window: window, frame: new, note: verdict) }
        }
        guard changed else {
            log("same")
            return
        }
        entry.frame = new
        let verdict = entry.echoes.classify(reported: new, now: now)
        tracked[window] = entry
        if verdict == .echo { log("echo"); return }
        if now < entry.quietUntil { log("placing"); return }
        // While another window drives, a neighbour that drifts (its app clamps
        // a size) must not drive back.
        if let session, session.driver != window, session.couplings.contains(where: { $0.follower == window }) {
            if WindowStickySmoothing.isMissedEcho(reported: new, lastWritten: entry.lastWritten,
                                                  secondsSinceWrite: now - entry.lastWriteTime) {
                let dev = entry.lastWritten.map { WindowStickySmoothing.deviation(new, $0) } ?? 0
                log("follower-drift missed-echo dev=\(Self.fixed(dev))")
            } else {
                log("follower-drift")
            }
            return
        }
        if WindowStickyEdgeSupport.isPureMove(old: old, new: new) {
            log("move")
            untrack(window, reason: "dragged-away")
            return
        }
        log("drive")
        if session?.driver != window { session = makeSession(driver: window, oldFrame: old) }
        applyCouplings(driverFrame: new, now: now)
        tracked[window]?.idle.note(at: now)
        scheduleSettle(window)
    }

    private func makeSession(driver: AXUIElement, oldFrame: CGRect) -> Session {
        let tolerance = WindowLayoutGaps.windowGap + 4
        let displays = Self.displayFrames()
        var couplings: [(follower: AXUIElement, edge: WindowStickyEdge, gap: CGFloat)] = []
        for follower in order where follower != driver {
            guard let followerFrame = tracked[follower]?.frame,
                  let edge = WindowStickyEdgeSupport.sharedEdge(of: oldFrame, with: followerFrame, tolerance: tolerance),
                  WindowStickyEdgeSupport.shareDisplay(oldFrame, followerFrame, displays: displays)
            else { continue }
            couplings.append((follower, edge, WindowStickyEdgeSupport.facingGap(edge: edge, driver: oldFrame,
                                                                                follower: followerFrame)))
        }
        StickyLog.write(kind: "session", window: driver, frame: oldFrame, note: "followers=\(couplings.count)")
        return Session(driver: driver, couplings: couplings)
    }

    /// Puts every coupled neighbour where it belongs for the driver's frame.
    /// `tolerance` is the jitter floor while dragging and the settle floor at the end.
    private func applyCouplings(driverFrame: CGRect, now: TimeInterval,
                                tolerance: CGFloat = WindowStickySmoothing.jitterThreshold) {
        guard let session else { return }
        for coupling in session.couplings {
            guard let followerEntry = tracked[coupling.follower] else { continue }
            let outcome = WindowStickyEdgeSupport.flushedFrame(
                edge: coupling.edge, driver: driverFrame, follower: followerEntry.frame, gap: coupling.gap,
                tolerance: tolerance)
            guard case .follow(let target) = outcome else {
                if outcome == .unaffected, isOffAtAll(followerEntry.frame, driverFrame: driverFrame, coupling: coupling) {
                    StickyLog.write(kind: "skip", window: coupling.follower, frame: followerEntry.frame, note: "jitter")
                }
                continue
            }
            guard isLive(coupling.follower, frame: followerEntry.frame, now: now) else {
                StickyLog.write(kind: "skip", window: coupling.follower, frame: followerEntry.frame, note: "not-live")
                continue
            }
            // Two writes inside one 120 Hz step are merged into one later write.
            if case .deferred(let delay) = tracked[coupling.follower]?.pacer.decide(now: now) {
                StickyLog.write(kind: "skip", window: coupling.follower, frame: followerEntry.frame,
                                note: "paced delay=\(Self.fixed(CGFloat(delay) * 1000))ms")
                scheduleDeferred(coupling.follower, after: delay)
                continue
            }
            write(target, to: coupling.follower, edge: coupling.edge, now: now)
        }
    }

    /// Whether a skipped follower was off by anything at all (worth a log line).
    private func isOffAtAll(_ frame: CGRect, driverFrame: CGRect,
                            coupling: (follower: AXUIElement, edge: WindowStickyEdge, gap: CGFloat)) -> Bool {
        if case .follow = WindowStickyEdgeSupport.flushedFrame(edge: coupling.edge, driver: driverFrame,
                                                              follower: frame, gap: coupling.gap, tolerance: 0) {
            return true
        }
        return false
    }

    private func scheduleDeferred(_ follower: AXUIElement, after delay: TimeInterval) {
        guard tracked[follower]?.deferredScheduled == false else { return }
        tracked[follower]?.deferredScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.001) { [weak self] in
            guard let self, self.tracked[follower] != nil else { return }
            self.tracked[follower]?.deferredScheduled = false
            guard let driver = self.session?.driver, let frame = Self.frame(of: driver) else { return }
            self.applyCouplings(driverFrame: frame, now: ProcessInfo.processInfo.systemUptime)
        }
    }

    private static func fixed(_ value: CGFloat) -> String {
        // One decimal built by hand: the log is for machines, not for a locale.
        let tenths = Int((abs(value) * 10).rounded())
        return (value < 0 && tenths != 0 ? "-" : "") + "\(tenths / 10).\(tenths % 10)"
    }

    /// When no event came for a moment, the pair is set flush once more, even
    /// if steps of the drag were lost on the way.
    private func scheduleSettle(_ window: AXUIElement) {
        DispatchQueue.main.asyncAfter(deadline: .now() + WindowStickyIdleTracker.interval + 0.02) { [weak self] in
            guard let self, self.session?.driver == window else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard self.tracked[window]?.idle.consumeIfIdle(at: now) == true else { return }
            if let current = Self.frame(of: window) {
                self.tracked[window]?.frame = current
                self.tracked[window]?.echoes.noteWrite(current, now: now)
                var worst: CGFloat = 0
                for coupling in self.session?.couplings ?? [] {
                    guard let followerFrame = self.tracked[coupling.follower]?.frame else { continue }
                    if case .follow(let target) = WindowStickyEdgeSupport.flushedFrame(
                        edge: coupling.edge, driver: current, follower: followerFrame, gap: coupling.gap, tolerance: 0) {
                        worst = max(worst, WindowStickySmoothing.deviation(target, followerFrame))
                    }
                }
                let corrects = WindowStickySmoothing.settleNeeded(deviation: worst)
                StickyLog.write(kind: "settle", window: window, frame: current,
                                note: "deviation=\(Self.fixed(worst)) corrects=\(corrects)")
                if corrects {
                    self.applyCouplings(driverFrame: current, now: now, tolerance: WindowStickySmoothing.settleThreshold)
                }
            }
            // A button still down means the drag only paused; keep the session.
            if NSEvent.pressedMouseButtons & 1 == 0 {
                for coupling in self.session?.couplings ?? [] {
                    guard let pacer = self.tracked[coupling.follower]?.pacer else { continue }
                    StickyLog.write(kind: "drag-end", window: coupling.follower,
                                    note: "writes=\(pacer.count) multi-per-step=\(pacer.multiPerStep)")
                    self.tracked[coupling.follower]?.pacer.resetCount()
                }
                self.session = nil
            }
        }
    }

    /// Whether the follower can be touched at all: on screen where the layout
    /// put it, not minimized, not full screen and settable. Checked at most
    /// twice a second, so a drag does not repeat the lookups for every event.
    private func isLive(_ window: AXUIElement, frame: CGRect, now: TimeInterval) -> Bool {
        // A "no" is re-checked soon: the window list can lag a fresh write, and a
        // cached no would freeze the follower for the whole interval.
        if let cached = eligibility[window],
           now - cached.checkedAt < (cached.live ? Self.eligibilityInterval : Self.eligibilityInterval / 5) {
            return cached.live
        }
        let live = Self.isOnScreenAndFree(window, frame: frame)
            && WindowLayoutService.shared.canSetFrame(on: window)
        eligibility[window] = Eligibility(live: live, checkedAt: now)
        return live
    }

    private func write(_ target: CGRect, to window: AXUIElement, edge: WindowStickyEdge, now: TimeInterval) {
        guard let original = tracked[window]?.frame else { return }
        // Remember the frame before writing, so the echo can never be mistaken
        // for a user move.
        tracked[window]?.echoes.noteWrite(target, now: now)
        tracked[window]?.pacer.noteWrite(at: now)
        tracked[window]?.lastWritten = target
        tracked[window]?.lastWriteTime = now
        // Shrinking writes the size first so the window never passes its far
        // edge; growing moves it first for the same reason.
        let growing = target.width > original.width || target.height > original.height
        if growing {
            Self.setPosition(target.origin, on: window)
            Self.setSize(target.size, on: window)
        } else {
            Self.setSize(target.size, on: window)
            Self.setPosition(target.origin, on: window)
        }
        let actual = Self.frame(of: window) ?? target
        StickyLog.write(kind: "write", window: window, frame: actual,
                        note: "target=\(Int(target.minX)),\(Int(target.minY)),\(Int(target.width)),\(Int(target.height))")
        // The app refused the size (its minimum): the neighbour goes back to
        // where it was and leaves the layout, so nothing is half applied.
        let refused = (edge == .left || edge == .right)
            ? abs(actual.width - target.width) > 2
            : abs(actual.height - target.height) > 2
        if refused {
            StickyLog.write(kind: "reset", window: window, frame: actual,
                            note: "min-size requested=\(Int(target.width))x\(Int(target.height))")
            Self.setSize(original.size, on: window)
            Self.setPosition(original.origin, on: window)
            untrack(window, reason: "size-refused")
            return
        }
        tracked[window]?.frame = actual
        tracked[window]?.echoes.noteWrite(actual, now: now)
    }

    // MARK: - Helpers

    /// Display frames in Accessibility space (origin top left of the primary display).
    private static func displayFrames() -> [CGRect] {
        guard let top = NSScreen.screens.first?.frame.maxY else { return [] }
        return NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
    }

    private static func isOnScreenAndFree(_ window: AXUIElement, frame: CGRect) -> Bool {
        func flag(_ attribute: String) -> Bool {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, attribute as CFString, &raw) == .success else { return false }
            return (raw as? NSNumber)?.boolValue ?? false
        }
        guard !flag("AXFullScreen"), !flag(kAXMinimizedAttribute as String),
              let id = AXWindowResolver.windowID(for: window),
              let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let entry = info.first,
              (entry[kCGWindowIsOnscreen as String] as? Bool) == true,
              let boundsRef = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsRef)
        else { return false }
        // A window parked in a Stage Manager strip reports other bounds.
        return WindowStickyEchoGuard.matches(bounds, frame, tolerance: 2)
    }

    private static func setSize(_ size: CGSize, on window: AXUIElement) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    private static func setPosition(_ origin: CGPoint, on window: AXUIElement) {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return }
        _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }
}

/// Measurement log for the coupling, off unless `defaults write <bundle id>
/// windowStickySnapLog -bool YES`. Read it with `Tools/sticky-snap-report.py`.
enum StickyLog {
    static let defaultsKey = "windowStickySnapLog"
    private static let queue = DispatchQueue(label: "vorssaint.sticky-log")
    nonisolated(unsafe) private static var handle: FileHandle?

    static var path: String {
        NSString(string: "~/Library/Logs/Vorssaint/sticky-snap.log").expandingTildeInPath
    }

    static func write(kind: String, window: AXUIElement? = nil, frame: CGRect = .zero, note: String = "") {
        guard UserDefaults.standard.bool(forKey: defaultsKey) else { return }
        let id = window.map { Int(truncatingIfNeeded: CFHash($0)) } ?? 0
        let line = WindowStickyEventLog.line(time: ProcessInfo.processInfo.systemUptime, kind: kind,
                                             window: id, frame: frame, note: note) + "\n"
        queue.async {
            if handle == nil {
                let url = URL(fileURLWithPath: path)
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: path) {
                    FileManager.default.createFile(atPath: path, contents: nil)
                }
                handle = try? FileHandle(forWritingTo: url)
                _ = try? handle?.seekToEnd()
            }
            try? handle?.write(contentsOf: Data(line.utf8))
        }
    }
}
