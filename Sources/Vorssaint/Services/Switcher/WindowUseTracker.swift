// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics

/// Remembers which windows and applications the user actually used, most
/// recent first. The switcher's order is exactly as good as this history.
///
/// Application activation alone cannot answer the question. The system posts
/// nothing when focus moves between two windows of the *same* app, so a
/// history built only from activation is blind to a large part of what the
/// user does, and a history built only from the switcher's own commits knows
/// nothing about the mouse. Focus is therefore observed directly through
/// Accessibility on whichever application is in front, which is the one place
/// a window can take focus without an activation being posted.
///
/// The window server's front-to-back order seeds the history at startup and
/// files windows that were never focused since, so the very first press is
/// already ordered by use instead of by the arbitrary order the window server
/// hands out.
///
/// Accessibility calls block for as long as the target application takes to
/// answer; an app with a hung main thread was measured holding a bare observer
/// install for 1.5 seconds. All of them run on this object's own thread, never
/// on the main run loop, and carry a messaging timeout on top — a stalled main
/// thread here would freeze typing system wide (issues #189 and #275).
final class WindowUseTracker {
    static let shared = WindowUseTracker()

    /// Ceiling for a single Accessibility round trip to an app that may not be
    /// servicing its run loop.
    private static let messagingTimeout: Float = 0.35

    private let stateLock = NSLock()
    private var windowHistory: [CGWindowID] = []
    private var appHistory: [pid_t] = []
    /// False from the moment the feature is switched off. The watcher thread is
    /// stopped from the outside and never joined, so without this a callback
    /// already in flight could write a window back into a history that was
    /// just cleared.
    private var recording = false

    private let lifecycleLock = NSLock()
    private var started = false
    private var watcherThread: Thread?
    private var watcherRunLoop: CFRunLoop?
    private var shouldStopWatcher = false
    private var pendingStartAfterStop = false
    /// Set on the main thread, read by the watcher thread when it retargets.
    private var requestedPID: pid_t?
    /// Applications running when the feature came on, handed to the watcher.
    private var seedRunningPIDs: Set<pid_t> = []

    // Watcher-thread state; never touched from anywhere else.
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var keepAliveSource: CFRunLoopSource?

    private init() {}

    // MARK: - History

    /// Most recently used windows, most recent first.
    var windows: [CGWindowID] { stateLock.withLock { windowHistory } }

    /// Most recently used applications, most recent first.
    var apps: [pid_t] { stateLock.withLock { appHistory } }

    /// Rank of an application; one never seen sorts after every known one.
    func rank(of pid: pid_t) -> Int {
        stateLock.withLock { appHistory.firstIndex(of: pid) ?? Int.max }
    }

    /// Records a switch the switcher itself performed. `previous` becomes the
    /// second-most-recent window, so a quick repeat toggles straight back.
    /// Applied immediately because the window server's order lags an
    /// activation by a frame or two, and a flick is faster than that.
    func recordSwitch(to windowID: CGWindowID?, from previous: CGWindowID?) {
        stateLock.withLock {
            guard recording else { return }
            windowHistory = WindowUseOrder.promoting(target: windowID,
                                                     previous: previous,
                                                     in: windowHistory)
        }
    }

    /// Drops what no longer exists and files windows that were never focused,
    /// using the window server's front-to-back order. Called by the enumerator,
    /// which already has both lists in hand.
    func reconcile(existingWindows: Set<CGWindowID>, frontToBack: FrontToBack, running: Set<pid_t>) {
        stateLock.withLock {
            guard recording else { return }
            windowHistory = WindowUseOrder.reconciled(windowHistory,
                                                      existing: existingWindows,
                                                      frontToBack: frontToBack.windows)
            appHistory = WindowUseOrder.reconciled(appHistory,
                                                   running: running,
                                                   frontToBack: frontToBack.apps)
        }
    }

    private func promote(window windowID: CGWindowID) {
        stateLock.withLock {
            guard recording else { return }
            windowHistory = WindowUseOrder.promoting(windowID, in: windowHistory)
        }
    }

    private func promote(app pid: pid_t) {
        stateLock.withLock {
            guard recording else { return }
            appHistory = WindowUseOrder.promoting(pid, in: appHistory)
        }
    }

    // MARK: - Lifecycle

    /// The history feeds the switcher and Window Layout's "every app" actions;
    /// with both features off in the hub, nothing observes anything.
    func syncWithFeatures() {
        if AppFeature.switcher.isAvailable || AppFeature.windowLayout.isAvailable {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        stateLock.withLock { recording = true }
        // Read on the main thread and handed over, so the watcher never has to
        // ask AppKit for the application list from its own thread.
        lifecycleLock.withLock {
            seedRunningPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        if let front = NSWorkspace.shared.frontmostApplication {
            promote(app: front.processIdentifier)
            lifecycleLock.withLock { requestedPID = front.processIdentifier }
        }
        startWatcher()
    }

    func stop() {
        guard started else { return }
        started = false
        stateLock.withLock {
            recording = false
            windowHistory.removeAll()
            appHistory.removeAll()
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopWatcher()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        // The application half is exact and free, so it lands right away; the
        // window half needs Accessibility and happens on the watcher thread.
        promote(app: pid)
        lifecycleLock.withLock { requestedPID = pid }
        performOnWatcher { [weak self] in self?.retargetObserver() }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        stateLock.withLock { appHistory.removeAll { $0 == pid } }
    }

    // MARK: - Watcher thread

    private func startWatcher() {
        let thread = lifecycleLock.withLock { () -> Thread? in
            if watcherThread != nil {
                if shouldStopWatcher { pendingStartAfterStop = true }
                return nil
            }
            shouldStopWatcher = false
            pendingStartAfterStop = false
            let thread = Thread { [weak self] in self?.runWatcher() }
            thread.name = "Vorssaint Window Focus"
            thread.qualityOfService = .userInitiated
            watcherThread = thread
            return thread
        }
        thread?.start()
    }

    private func stopWatcher() {
        let snapshot = lifecycleLock.withLock { () -> (runLoop: CFRunLoop?, threadExists: Bool) in
            shouldStopWatcher = true
            pendingStartAfterStop = false
            requestedPID = nil
            return (watcherRunLoop, watcherThread != nil)
        }
        if let runLoop = snapshot.runLoop {
            // Never join: the run loop is stopped from the outside, exactly as
            // the switcher's tap thread is, so a teardown can never deadlock
            // against work the thread is running on the main thread.
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(runLoop) }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopWatcher = false
                watcherThread = nil
            }
        }
    }

    private func performOnWatcher(_ work: @escaping () -> Void) {
        guard let runLoop = lifecycleLock.withLock({ watcherRunLoop }) else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }

    private func runWatcher() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock { watcherRunLoop = runLoop }

            // A source that is never signalled, so the run loop stays alive
            // between front-application changes without a timer waking the
            // machine up for nothing.
            var context = CFRunLoopSourceContext()
            context.perform = { _ in }
            if let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) {
                CFRunLoopAddSource(runLoop, source, .defaultMode)
                keepAliveSource = source
            }

            seedFromWindowServer()
            retargetObserver()

            while !lifecycleLock.withLock({ shouldStopWatcher }) {
                CFRunLoopRun()
            }

            detachObserver()
            if let source = keepAliveSource {
                CFRunLoopRemoveSource(runLoop, source, .defaultMode)
                keepAliveSource = nil
            }

            let restart = lifecycleLock.withLock { () -> Bool in
                watcherRunLoop = nil
                watcherThread = nil
                shouldStopWatcher = false
                defer { pendingStartAfterStop = false }
                return pendingStartAfterStop
            }
            if restart { startWatcher() }
        }
    }

    /// First history of the session: the window server's front-to-back order is
    /// the only account of what was used before the app was even running.
    private func seedFromWindowServer() {
        reconcile(existingWindows: Set(Self.allWindows()),
                  frontToBack: Self.frontToBack(),
                  running: lifecycleLock.withLock { seedRunningPIDs })
    }

    // MARK: - Accessibility observation (watcher thread only)

    /// Watches the front application only. A window can take focus without an
    /// activation being posted solely inside the application that already has
    /// the keyboard, so one observer at a time covers every case the
    /// activation notifications miss — for the cost of a single one.
    private func retargetObserver() {
        guard !lifecycleLock.withLock({ shouldStopWatcher }) else { return }
        guard let pid = lifecycleLock.withLock({ requestedPID }) else { return }
        guard pid != observedPID else {
            readFocusedWindow(of: pid)
            return
        }
        detachObserver()
        guard AXIsProcessTrusted() else { return }

        var created: AXObserver?
        guard AXObserverCreate(pid, Self.focusCallback, &created) == .success, let created else { return }
        let application = AXUIElementCreateApplication(pid)
        // Without this, an unresponsive application holds the install for its
        // full default timeout, on this thread, once per switch.
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            _ = AXObserverAddNotification(created, application, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedPID = pid

        // Activation itself posts no focus change, so the window the app came
        // back to has to be asked for once. Any change that races this arrives
        // through the observer, which is already installed.
        readFocusedWindow(of: pid)
    }

    private func detachObserver() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        if let observedPID {
            let application = AXUIElementCreateApplication(observedPID)
            AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
            for notification in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
                _ = AXObserverRemoveNotification(observer, application, notification as CFString)
            }
        }
        self.observer = nil
        observedPID = nil
    }

    private func readFocusedWindow(of pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return }
        // A misbehaving app can answer with something that is not an element.
        let window = value as! AXUIElement
        guard let windowID = AXWindowResolver.windowID(for: window) else { return }
        promote(window: windowID)
    }

    /// C callback: no captures, so the tracker travels in the refcon.
    private static let focusCallback: AXObserverCallback = { _, element, _, refcon in
        guard let refcon else { return }
        let tracker = Unmanaged<WindowUseTracker>.fromOpaque(refcon).takeUnretainedValue()
        guard let windowID = AXWindowResolver.windowID(for: element) else { return }
        tracker.promote(window: windowID)
    }

    // MARK: - Window server

    /// What is on screen, front to back.
    struct FrontToBack {
        let windows: [CGWindowID]
        let apps: [pid_t]
    }

    /// On-screen windows and their applications, front to back. This is real
    /// z-order, and for anything never seen taking focus it is the only
    /// evidence of how recently it was used.
    static func frontToBack() -> FrontToBack {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] ?? []
        var windows: [CGWindowID] = []
        var apps: [pid_t] = []
        var seenApps = Set<pid_t>()
        for entry in raw where (entry[kCGWindowLayer as String] as? Int) == 0 {
            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            windows.append(windowID)
            if let pid = entry[kCGWindowOwnerPID as String] as? pid_t, seenApps.insert(pid).inserted {
                apps.append(pid)
            }
        }
        return FrontToBack(windows: windows, apps: apps)
    }

    private static func allWindows() -> [CGWindowID] {
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    }
}
