// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine

/// Quits an app when its last window closes. Each regular app gets an
/// Accessibility observer that
/// watches windows being created and destroyed; when an app that had at least
/// one window drops to zero standard windows, it's asked to quit (a normal
/// terminate, so unsaved-changes dialogs still appear).
///
/// Predictable by design: apps that launch window-less are never touched, and
/// any app can be kept running through the exception list. Requires
/// Accessibility.
final class AutoQuitService: ObservableObject {
    static let shared = AutoQuitService()

    /// Bundle ids never auto-quit; mirrors the persisted list for the UI.
    @Published private(set) var exceptions: [String] = []

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXMainWindowChangedNotification,
        kAXFocusedWindowChangedNotification,
        kAXApplicationDeactivatedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification
    ]
    private static let windowRefreshNotifications = Set([
        kAXWindowCreatedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXApplicationShownNotification as String,
        kAXMainWindowChangedNotification as String,
        kAXFocusedWindowChangedNotification as String
    ])

    private var running = false
    private var observers: [pid_t: AXObserver] = [:]
    /// Apps that have shown at least one window since we started watching them.
    /// Only these are eligible to quit, so window-less agents stay put.
    private var hadWindows: [pid_t: Bool] = [:]
    private var launchToken: NSObjectProtocol?
    private var terminateToken: NSObjectProtocol?
    private var activateToken: NSObjectProtocol?
    private var spaceChangeToken: NSObjectProtocol?
    private var closeRequestTap: CFMachPort?
    private var closeRequestRunLoopSource: CFRunLoopSource?
    private var recentCloseButtonRequests: [pid_t: Date] = [:]
    private var lastScheduledChecks: [pid_t: Date] = [:]
    /// Apps whose attach is waiting on a retry, so a second round never starts.
    private var retryingApps = Set<pid_t>()
    private var minimizedWindows: [pid_t: Set<CGWindowID>] = [:]
    private struct WindowWatchRetryState {
        let origin: DispatchTime
        var attemptsScheduled: Int
        var pendingTimerID: UUID?
    }
    /// Refreshes that found the app eligible but had no window to watch.
    private var windowWatchRetries: [pid_t: WindowWatchRetryState] = [:]
    private var appsWithUnresolvedMinimizedWindows = Set<pid_t>()

    private let closeRequestGrace: TimeInterval = 5

    private init() {
        reloadExceptions()
    }

    var isRunning: Bool { running }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        let enabled = AppFeature.autoQuit.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.autoQuitEnabled)
        if enabled, Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard !running else { return }
        running = true

        let center = NSWorkspace.shared.notificationCenter
        launchToken = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                         object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.attach(app)
        }
        terminateToken = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.detach(pid: app.processIdentifier)
        }
        // Some apps start as background helpers and only take a Dock icon later,
        // when they finally show a window. They are not "regular" at launch, so
        // the notification above skips them for good and closing their window
        // does nothing. Coming to the front is the moment they are certainly a
        // normal app, and attaching again costs a dictionary lookup.
        activateToken = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                           object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.attach(app)
        }
        // AX cannot describe a window parked on another Space. Keep such apps
        // dormant after the bounded retry round, then try them again when the
        // visible Space changes instead of polling them for their lifetime.
        spaceChangeToken = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            self?.rearmWindowWatchRetries()
        }

        for app in NSWorkspace.shared.runningApplications {
            attach(app)
        }
        startCloseRequestMonitor()
    }

    /// Force-stops all observers and the close-request tap regardless of the
    /// preference. Used before the app resets its own permissions, so a revoked
    /// Accessibility grant can never leave a live tap behind.
    func suspend() { stop() }

    private func stop() {
        guard running else { return }
        running = false
        let center = NSWorkspace.shared.notificationCenter
        if let launchToken { center.removeObserver(launchToken) }
        if let terminateToken { center.removeObserver(terminateToken) }
        if let activateToken { center.removeObserver(activateToken) }
        if let spaceChangeToken { center.removeObserver(spaceChangeToken) }
        launchToken = nil
        terminateToken = nil
        activateToken = nil
        spaceChangeToken = nil
        stopCloseRequestMonitor()
        // Snapshot the keys — detach(pid:) mutates the dictionary.
        for pid in Array(observers.keys) { detach(pid: pid) }
        observers.removeAll()
        hadWindows.removeAll()
        recentCloseButtonRequests.removeAll()
        lastScheduledChecks.removeAll()
        retryingApps.removeAll()
        minimizedWindows.removeAll()
        appsWithUnresolvedMinimizedWindows.removeAll()
        windowWatchRetries.removeAll()
    }

    // MARK: - Per-app observers

    private func attach(_ app: NSRunningApplication) {
        attach(app, attempt: 0)
    }

    private func attach(_ app: NSRunningApplication, attempt: Int) {
        guard running, app.activationPolicy == .regular else { return }
        let pid = app.processIdentifier
        guard pid != getpid(), observers[pid] == nil else { return }
        // An app that never answers is retried on a growing delay below. Since
        // switching to an app also brings us here, a fresh round would start
        // every time the user came back to it; one round at a time is enough.
        if attempt == 0, retryingApps.contains(pid) { return }

        let appElement = AXUIElementCreateApplication(pid)
        // A launching app that is busy (say, blocked on a Keychain prompt)
        // would hold every synchronous AX call below for the 6 second default
        // timeout apiece, freezing the main thread and every event tap with
        // it: typing dies system wide (issue #189). Give up fast and retry
        // with growing spacing until the app services its run loop again.
        AXUIElementSetMessagingTimeout(appElement, 0.35)
        // The probe asks for windows rather than the application's role. A
        // Chromium app (Electron, and the browsers) answers a role query on its
        // application element by switching its renderers into full
        // accessibility mode, and from then on it rebuilds and ships an
        // accessibility tree on every DOM change for the life of the process —
        // a few percent of a core, forever, in an app this feature only ever
        // needed a window count from (issue #953). Windows are the same
        // liveness signal, are what the refresh below reads anyway, and leave
        // that mode alone; WindowEnumerator probes the same way.
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows) == .cannotComplete {
            guard attempt < 6 else { retryingApps.remove(pid); return }
            retryingApps.insert(pid)
            let delay = 5.0 * pow(2.0, Double(attempt))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.running, !app.isTerminated else { return }
                self.attach(app, attempt: attempt + 1)
            }
            return
        }
        retryingApps.remove(pid)

        var observerRef: AXObserver?
        guard AXObserverCreate(pid, autoQuitAXCallback, &observerRef) == .success,
              let observer = observerRef else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.appNotifications {
            AXObserverAddNotification(observer, appElement, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer

        // Watch the windows that already exist and seed the "had windows" flag.
        refreshWindows(pid: pid, observer: observer)
    }

    private func detach(pid: pid_t) {
        if let observer = observers[pid] {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers[pid] = nil
        hadWindows[pid] = nil
        recentCloseButtonRequests[pid] = nil
        lastScheduledChecks[pid] = nil
        retryingApps.remove(pid)
        minimizedWindows[pid] = nil
        appsWithUnresolvedMinimizedWindows.remove(pid)
        windowWatchRetries[pid] = nil
    }

    /// Called from the C observer callback (on the main run loop).
    func handleAX(observer: AXObserver, element: AXUIElement, notification: String) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if pid == 0, let observerPID = pidForObserver(observer) {
            pid = observerPID
        }
        guard pid != 0 else { return }

        if notification == (kAXWindowMiniaturizedNotification as String) {
            markMinimizedWindow(pid: pid, element: element)
            return
        }
        if notification == (kAXWindowDeminiaturizedNotification as String) {
            clearMinimizedWindow(pid: pid, element: element)
        }
        if notification == (kAXUIElementDestroyedNotification as String) {
            clearMinimizedWindow(pid: pid, element: element)
        }

        if Self.windowRefreshNotifications.contains(notification), let observer = observers[pid] {
            refreshWindows(pid: pid, observer: observer)
        }
        let event = Self.autoQuitEvent(for: notification)
        if AutoQuitSupport.shouldScheduleWindowCheck(for: event,
                                                     hasRecentCloseRequest: hasRecentCloseButtonRequest(pid: pid)) {
            scheduleWindowChecks(pid: pid)
        }
    }

    private static func autoQuitEvent(for notification: String) -> AutoQuitWindowEvent {
        if notification == (kAXUIElementDestroyedNotification as String) {
            return .windowDestroyed
        }
        if notification == (kAXApplicationHiddenNotification as String) {
            return .appHidden
        }
        if notification == (kAXApplicationDeactivatedNotification as String) {
            return .appDeactivated
        }
        if notification == (kAXMainWindowChangedNotification as String) {
            return .mainWindowChanged
        }
        if notification == (kAXFocusedWindowChangedNotification as String) {
            return .focusedWindowChanged
        }
        if notification == (kAXWindowCreatedNotification as String) {
            return .windowCreated
        }
        if notification == (kAXWindowDeminiaturizedNotification as String) {
            return .windowDeminiaturized
        }
        if notification == (kAXApplicationShownNotification as String) {
            return .appShown
        }
        return .other
    }

    /// When to look at an app after something closed. A window that just went
    /// away is still on screen while it fades out (measured on macOS 27: about
    /// a quarter of a second), and a look that finds a window simply stops
    /// there. A single look was a coin flip against that fade, and losing it
    /// meant the app was never asked to quit at all. Two more looks settle it,
    /// with room for slower machines.
    private static let closeCheckOffsets: [TimeInterval] = [0.35, 1.0, 2.2]

    /// Accessibility can list no windows for an app the window server still
    /// shows one for: it answers late for an app that is busy, and it cannot
    /// describe a window parked on a Space that is not visible at all. Either
    /// way the app is marked eligible with nothing to watch, so the close that
    /// should quit it destroys a window nobody registered for and no check is
    /// ever scheduled (issue #1008). Look again a few times: Accessibility
    /// usually catches up within the first, and when it never does the retries
    /// stop rather than polling for the life of the app. These are offsets from
    /// the start of one retry round, not delays chained from each retry.
    private static let windowWatchRetryOffsets: [TimeInterval] = [0.5, 1.5, 4.0]

    private func scheduleWindowChecks(pid: pid_t) {
        // Closing several windows at once (or a click plus the window going
        // away right after it) would otherwise pile up a round of checks per
        // window. One round covers them all.
        let now = Date()
        if let last = lastScheduledChecks[pid], now.timeIntervalSince(last) < 0.25 { return }
        lastScheduledChecks[pid] = now
        let origin = DispatchTime.now()
        for offset in Self.closeCheckOffsets {
            DispatchQueue.main.asyncAfter(deadline: origin + offset) { [weak self] in
                self?.checkWindows(pid: pid)
            }
        }
    }

    private func checkWindows(pid: pid_t, confirm: Bool = true) {
        guard running, hadWindows[pid] == true,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        let appIsExcepted = AutoQuitSupport.isExcepted(bundleIdentifier: app.bundleIdentifier,
                                                       bundleURL: app.bundleURL,
                                                       exceptions: exceptions)
        let hiddenByCloseRequest = app.isHidden && hasRecentCloseButtonRequest(pid: pid)

        // Cheap early-outs before any synchronous AX IPC: excepted apps and
        // hidden apps without close intent can never quit below.
        guard !appIsExcepted else { return }
        if app.isHidden && !hiddenByCloseRequest { return }

        let appElement = AXUIElementCreateApplication(pid)
        // Bounded AX: an unresponsive app must not hold the main thread
        // (and with it every event tap) for the 6 second default timeout.
        AXUIElementSetMessagingTimeout(appElement, 0.35)
        let hasMinimizedWindow = hasKnownMinimizedWindow(pid: pid, appElement: appElement)
        let hasVisibleWindow = hasUserFacingWindow(pid: pid, appElement: appElement)
        guard AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                         appIsTerminated: false,
                                                         appIsExcepted: appIsExcepted,
                                                         appIsHidden: app.isHidden,
                                                         hiddenByCloseRequest: hiddenByCloseRequest,
                                                         hasKnownMinimizedWindow: hasMinimizedWindow,
                                                         hasUserFacingWindow: hasVisibleWindow) else { return }
        guard !hasRunningDependentApplication(hostBundleIdentifier: app.bundleIdentifier,
                                              excluding: pid) else { return }

        // Zero windows can be a transient state, most notably when leaving full
        // screen with the green button: the full-screen window is destroyed a
        // moment before the windowed one reappears. Quitting on that flicker
        // would close the app as if the user pressed Cmd-Q. So re-check once the
        // transition has settled, and only quit if the app is still window-less.
        if confirm {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.checkWindows(pid: pid, confirm: false)
            }
            return
        }

        let stillHiddenByCloseRequest = app.isHidden && hasRecentCloseButtonRequest(pid: pid)
        let stillHasKnownMinimizedWindow = hasKnownMinimizedWindow(pid: pid, appElement: appElement)
        let stillHasUserFacingWindow = hasUserFacingWindow(pid: pid, appElement: appElement)
        guard AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                         appIsTerminated: app.isTerminated,
                                                         appIsExcepted: appIsExcepted,
                                                         appIsHidden: app.isHidden,
                                                         hiddenByCloseRequest: stillHiddenByCloseRequest,
                                                         hasKnownMinimizedWindow: stillHasKnownMinimizedWindow,
                                                         hasUserFacingWindow: stillHasUserFacingWindow) else { return }
        guard !hasRunningDependentApplication(hostBundleIdentifier: app.bundleIdentifier,
                                              excluding: pid) else { return }

        hadWindows[pid] = false
        recentCloseButtonRequests[pid] = nil
        minimizedWindows[pid] = nil
        appsWithUnresolvedMinimizedWindows.remove(pid)
        app.terminate()
    }

    private func hasRunningDependentApplication(hostBundleIdentifier: String?,
                                                excluding hostPID: pid_t) -> Bool {
        let bundleURLs = NSWorkspace.shared.runningApplications.compactMap { app -> URL? in
            guard app.processIdentifier != hostPID,
                  !app.isTerminated,
                  app.activationPolicy == .regular else { return nil }
            return app.bundleURL
        }
        return AutoQuitSupport.hasDependentApplication(
            hostBundleIdentifier: hostBundleIdentifier,
            applicationBundleURLs: bundleURLs)
    }

    private func refreshWindows(pid: pid_t, observer: AXObserver) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.35)
        let windows = standardWindows(of: appElement)
        var watchedWindows = 0
        for window in windows {
            if watch(window: window, observer: observer, refcon: refcon) { watchedWindows += 1 }
        }
        recordMinimizedWindows(pid: pid, windows: windows)
        // The window-server scan is only needed when Accessibility handed us
        // nothing.
        let serverWindow = windows.isEmpty ? hasWindowServerUserWindow(pid: pid) : nil
        let foundUserWindow = !windows.isEmpty || serverWindow == true
        if foundUserWindow {
            hadWindows[pid] = true
        }
        // Every user window needs a destroy notification. Accessibility can
        // list none despite the window server seeing one, or an individual
        // registration can fail after the list succeeds.
        if AutoQuitSupport.needsWindowWatchRetry(registeredWindows: watchedWindows,
                                                 listedWindows: windows.count,
                                                 foundUserWindow: foundUserWindow) {
            scheduleWindowWatchRetry(pid: pid)
        } else {
            windowWatchRetries[pid] = nil
        }
    }

    private func scheduleWindowWatchRetry(pid: pid_t) {
        var retry = windowWatchRetries[pid]
            ?? WindowWatchRetryState(origin: .now(), attemptsScheduled: 0, pendingTimerID: nil)
        guard retry.pendingTimerID == nil,
              retry.attemptsScheduled < Self.windowWatchRetryOffsets.count else { return }
        let attempt = retry.attemptsScheduled
        let timerID = UUID()
        retry.attemptsScheduled += 1
        retry.pendingTimerID = timerID
        windowWatchRetries[pid] = retry
        DispatchQueue.main.asyncAfter(
            deadline: retry.origin + Self.windowWatchRetryOffsets[attempt]
        ) { [weak self] in
            guard let self, self.running,
                  var retry = self.windowWatchRetries[pid],
                  retry.pendingTimerID == timerID,
                  let observer = self.observers[pid] else { return }
            retry.pendingTimerID = nil
            self.windowWatchRetries[pid] = retry
            self.refreshWindows(pid: pid, observer: observer)
        }
    }

    private func rearmWindowWatchRetries() {
        // A new Space starts a new bounded round. Removing the state also makes
        // any timer from the previous round stale before the immediate refresh.
        for pid in Array(windowWatchRetries.keys) {
            guard let observer = observers[pid] else {
                windowWatchRetries[pid] = nil
                continue
            }
            windowWatchRetries[pid] = nil
            refreshWindows(pid: pid, observer: observer)
        }
    }

    /// Reports whether the window ended up watched for the one notification the
    /// close path depends on. Only the destroyed one schedules a check, so it
    /// alone decides: a window that refused the miniaturize notifications is
    /// still a window auto-quit can act on.
    private func watch(window: AXUIElement, observer: AXObserver, refcon: UnsafeMutableRawPointer) -> Bool {
        var watched = false
        for notification in Self.windowNotifications {
            let result = AXObserverAddNotification(observer, window, notification as CFString, refcon)
            if notification == kAXUIElementDestroyedNotification {
                watched = AutoQuitSupport.isWindowNotificationRegistered(result)
            }
        }
        return watched
    }

    private func pidForObserver(_ observer: AXObserver) -> pid_t? {
        observers.first { entry in CFEqual(entry.value, observer) }?.key
    }

    private func standardWindows(of appElement: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
           let windows = value as? [AXUIElement] {
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.35)
                if Self.isStandardWindow(window) { Self.appendUnique(window, to: &result) }
            }
        }
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let window = Self.windowAttribute(appElement, attribute as String) {
                AXUIElementSetMessagingTimeout(window, 0.35)
                if Self.isStandardWindow(window) { Self.appendUnique(window, to: &result) }
            }
        }
        return result
    }

    /// A real, user-facing window — not a sheet, palette or system dialog, which
    /// shouldn't keep an app "alive" for this purpose.
    private static func isStandardWindow(_ window: AXUIElement) -> Bool {
        if boolAttribute(window, "AXFullScreen") { return true }
        if boolAttribute(window, kAXMinimizedAttribute as String),
           role(of: window) == (kAXWindowRole as String) {
            return true
        }

        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole) == .success,
           let value = subrole as? String {
            return value == "AXStandardWindow" || value == "AXFullScreenWindow"
        }
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success,
           let value = role as? String {
            return value == "AXWindow"
        }
        return false
    }

    private static func appendUnique(_ window: AXUIElement, to windows: inout [AXUIElement]) {
        guard !windows.contains(where: { CFEqual($0, window) }) else { return }
        windows.append(window)
    }

    private static func windowAttribute(_ appElement: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String, default defaultValue: Bool = false) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return defaultValue }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return (value as? Bool) ?? defaultValue
        }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private func hasUserFacingWindow(pid: pid_t, appElement: AXUIElement) -> Bool {
        let axWindows = standardWindows(of: appElement)
        if axWindows.contains(where: { Self.boolAttribute($0, kAXMinimizedAttribute as String) }) {
            return true
        }
        if let hasWindowServerWindow = hasWindowServerUserWindow(pid: pid) {
            return hasWindowServerWindow
        }
        return !axWindows.isEmpty
    }

    /// Whether the window server still knows a window of this app that the user
    /// has. Apps that keep running with nothing to show are the whole point of
    /// the feature, and plenty of them do not destroy their window on close:
    /// they hide it, which leaves the app with no windows for Accessibility but
    /// a window record here. Those do not count. A window sitting on another
    /// Space does.
    private func hasWindowServerUserWindow(pid: pid_t) -> Bool? {
        guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }

        var visibleSpaces: Set<UInt64>?
        var askedForVisibleSpaces = false

        for window in info {
            guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == pid,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue,
                  width >= 80, height >= 80 else { continue }
            let isOnScreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
                ?? (window[kCGWindowIsOnscreen as String] as? Bool)
                ?? false
            if isOnScreen { return true }

            guard let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            // Asked once per check, and only when there is an off-screen window
            // to judge: the common case never pays for it.
            if !askedForVisibleSpaces {
                visibleSpaces = SpaceWindowBridge.topology()?.visibleSpaces
                askedForVisibleSpaces = true
            }
            let title = window[kCGWindowName as String] as? String ?? ""
            if AutoQuitSupport.offscreenWindowKeepsAppAlive(
                windowSpaces: SpaceWindowBridge.spaces(of: CGWindowID(windowID)),
                visibleSpaces: visibleSpaces,
                hasTitle: !title.isEmpty) {
                return true
            }
        }
        return false
    }

    // MARK: - Close-request monitor

    private func startCloseRequestMonitor() {
        guard closeRequestTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<AutoQuitService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handleCloseRequestEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        closeRequestTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        closeRequestRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopCloseRequestMonitor() {
        if let closeRequestTap {
            CGEvent.tapEnable(tap: closeRequestTap, enable: false)
        }
        if let closeRequestRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), closeRequestRunLoopSource, .commonModes)
        }
        closeRequestTap = nil
        closeRequestRunLoopSource = nil
    }

    private func handleCloseRequestEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let closeRequestTap { CGEvent.tapEnable(tap: closeRequestTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            handleCloseRequestKeyDown(event: event)
            return Unmanaged.passUnretained(event)
        }

        // Accessibility gone (e.g. reset): the AX hit-test below would hang
        // inside the tap and freeze clicks, so let the click through untouched.
        // Cached for the every-click fast path; the live check runs right
        // before the AX hit-test, only for clicks that landed on an eligible
        // window's close-button area.
        guard Permissions.shared.accessibility else { return Unmanaged.passUnretained(event) }

        guard type == .leftMouseDown,
              event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              let candidate = WindowServerTrafficLightHitTest.candidate(
                at: event.location,
                button: .close,
                pidIsEligible: { [weak self] pid in self?.observers[pid] != nil }
              ),
              AXIsProcessTrusted(),
              let pid = closeButtonPID(at: event.location, candidate: candidate) else {
            return Unmanaged.passUnretained(event)
        }
        markCloseButtonRequest(pid: pid)
        return Unmanaged.passUnretained(event)
    }

    private func handleCloseRequestKeyDown(event: CGEvent) {
        let flags = event.flags
        guard flags.contains(.maskCommand), !flags.contains(.maskControl) else { return }
        // Match the character the key actually types under the current layout
        // (virtual key codes are positional: 13 types "z" on AZERTY). Fall back
        // to the QWERTY key code when no character is available.
        let isCloseShortcut: Bool
        if let character = Self.typedCharacter(of: event) {
            isCloseShortcut = character == "w"
        } else {
            isCloseShortcut = AutoQuitSupport.isCommandW(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                command: true, control: false)
        }
        guard isCloseShortcut,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              observers[pid] != nil else { return }
        // Cmd+W may close only a tab, so it is a weak signal: re-check windows
        // shortly (a genuinely closed last window fails the check and quits),
        // but never unlock the hidden-app quit path — otherwise closing a tab
        // and hiding the app would terminate an app whose window (with all its
        // tabs) still exists.
        scheduleWindowChecks(pid: pid)
    }

    private static func typedCharacter(of event: CGEvent) -> String? {
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: characters.count,
                                       actualStringLength: &length,
                                       unicodeString: &characters)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).lowercased()
    }

    private func markCloseButtonRequest(pid: pid_t) {
        recentCloseButtonRequests[pid] = Date()
        // The click landed on the close button of a real window of this app,
        // which is exactly the proof of "this app had a window" the quit path
        // asks for. Without it an app whose window we never heard about
        // through Accessibility could never be quit.
        hadWindows[pid] = true
        scheduleWindowChecks(pid: pid)
    }

    func recordProgrammaticCloseRequest(pid: pid_t) {
        guard running, observers[pid] != nil else { return }
        markCloseButtonRequest(pid: pid)
    }

    private func hasRecentCloseButtonRequest(pid: pid_t) -> Bool {
        guard let date = recentCloseButtonRequests[pid] else { return false }
        if Date().timeIntervalSince(date) <= closeRequestGrace {
            return true
        }
        recentCloseButtonRequests[pid] = nil
        return false
    }

    private func markMinimizedWindow(pid: pid_t, element: AXUIElement) {
        if let id = AXWindowResolver.windowID(for: element) {
            minimizedWindows[pid, default: []].insert(id)
        } else {
            appsWithUnresolvedMinimizedWindows.insert(pid)
        }
    }

    private func clearMinimizedWindow(pid: pid_t, element: AXUIElement) {
        if let id = AXWindowResolver.windowID(for: element) {
            minimizedWindows[pid]?.remove(id)
            if minimizedWindows[pid]?.isEmpty == true {
                minimizedWindows[pid] = nil
            }
        } else {
            appsWithUnresolvedMinimizedWindows.remove(pid)
        }
    }

    private func recordMinimizedWindows(pid: pid_t, windows: [AXUIElement]) {
        let ids = windows.compactMap { window -> CGWindowID? in
            guard Self.boolAttribute(window, kAXMinimizedAttribute as String) else { return nil }
            return AXWindowResolver.windowID(for: window)
        }
        guard !ids.isEmpty else { return }
        minimizedWindows[pid, default: []].formUnion(ids)
    }

    private func hasKnownMinimizedWindow(pid: pid_t, appElement: AXUIElement) -> Bool {
        let windows = standardWindows(of: appElement)
        recordMinimizedWindows(pid: pid, windows: windows)
        return minimizedWindows[pid]?.isEmpty == false || appsWithUnresolvedMinimizedWindows.contains(pid)
    }

    private func closeButtonPID(at point: CGPoint, candidate: TrafficLightCandidate) -> pid_t? {
        guard candidate.pid != getpid(), observers[candidate.pid] != nil else { return nil }
        guard let element = elementAt(point: point),
              let window = Self.topLevelWindow(from: element)
        else { return candidate.pid }

        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        if pid == 0 { return candidate.pid }
        guard pid == candidate.pid else { return nil }

        guard Self.isStandardWindow(window),
              let closeButton = Self.windowAttribute(window, kAXCloseButtonAttribute as String),
              Self.boolAttribute(closeButton, kAXEnabledAttribute as String, default: true),
              let buttonFrame = Self.frame(of: closeButton)
        else { return candidate.pid }

        return buttonFrame.insetBy(dx: -4, dy: -4).contains(point) ? pid : nil
    }

    private func elementAt(point: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        // This runs while a click is being handled, and the app being asked is
        // the one that was just told to close, which is exactly when an app
        // stops answering. A short limit here means a slow answer is dropped
        // rather than holding this app, and every tap it runs, still.
        AXUIElementSetMessagingTimeout(system, 0.15)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success
        else { return nil }
        if let element { AXUIElementSetMessagingTimeout(element, 0.15) }
        return element
    }


    /// An application element answers a role query by switching a Chromium app's
    /// renderers into full accessibility mode for the rest of the process's life
    /// (issue #953), so it must never be asked for one. Its own pid names it:
    /// the element built from that pid is the same element, since Accessibility
    /// compares by value rather than by identity. Asking each element for its
    /// own pid also keeps this right where a parent chain crosses processes,
    /// which a sentinel built once from the starting element would miss.
    private static func isApplicationElement(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != 0 else { return false }
        return CFEqual(element, AXUIElementCreateApplication(pid))
    }

    private static func topLevelWindow(from element: AXUIElement) -> AXUIElement? {
        guard !isApplicationElement(element) else { return nil }
        if role(of: element) == (kAXWindowRole as String) { return element }
        if let window = windowAttribute(element, kAXWindowAttribute as String),
           role(of: window) == (kAXWindowRole as String) {
            return window
        }
        if let window = windowAttribute(element, kAXTopLevelUIElementAttribute as String),
           role(of: window) == (kAXWindowRole as String) {
            return window
        }

        // The chain above a window is the application element itself, so an
        // element that never yields a window — a menu bar item, a detached
        // palette — walks onto it. Asking that element for a role is what puts
        // a Chromium app's renderers into full accessibility mode for the rest
        // of the process's life (issue #953), so stop there instead: the walk
        // already ends with no window in that case.
        var current = element
        for _ in 0..<8 {
            guard let parent = windowAttribute(current, kAXParentAttribute as String) else { return nil }
            if isApplicationElement(parent) { return nil }
            if role(of: parent) == (kAXWindowRole as String) { return parent }
            current = parent
        }
        return nil
    }

    private static func frame(of element: AXUIElement) -> AutoQuitAXFrame? {
        guard let origin = pointAttribute(element, kAXPositionAttribute as String),
              let size = sizeAttribute(element, kAXSizeAttribute as String),
              size.width > 0,
              size.height > 0 else { return nil }
        return AutoQuitAXFrame(origin: origin, size: size)
    }

    private static func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    // MARK: - Exceptions

    func reloadExceptions() {
        let raw = UserDefaults.standard.stringArray(forKey: DefaultsKey.autoQuitExceptions) ?? []
        let sanitized = Defaults.sanitizedAutoQuitExceptions(raw)
        if raw != sanitized {
            UserDefaults.standard.set(sanitized, forKey: DefaultsKey.autoQuitExceptions)
        }
        exceptions = sanitized
    }

    func addException(_ bundleID: String) {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, !exceptions.contains(bundleID) else { return }
        var list = Defaults.sanitizedAutoQuitExceptions(exceptions)
        list.append(bundleID)
        UserDefaults.standard.set(list, forKey: DefaultsKey.autoQuitExceptions)
        reloadExceptions()
    }

    func removeException(_ bundleID: String) {
        guard !isMandatoryException(bundleID) else { return }
        let list = Defaults.sanitizedAutoQuitExceptions(exceptions.filter { $0 != bundleID })
        UserDefaults.standard.set(list, forKey: DefaultsKey.autoQuitExceptions)
        reloadExceptions()
    }

    func isMandatoryException(_ bundleID: String) -> Bool {
        Defaults.mandatoryAutoQuitExceptionBundleIDs.contains(bundleID)
    }
}

/// C trampoline for AXObserver — no captures, so it bridges to a C function
/// pointer; the service is recovered from the refcon.
private func autoQuitAXCallback(_ observer: AXObserver,
                                _ element: AXUIElement,
                                _ notification: CFString,
                                _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let service = Unmanaged<AutoQuitService>.fromOpaque(refcon).takeUnretainedValue()
    service.handleAX(observer: observer, element: element, notification: notification as String)
}

private struct AutoQuitAXFrame {
    var origin: CGPoint
    var size: CGSize

    var minX: CGFloat { origin.x }
    var minY: CGFloat { origin.y }
    var maxX: CGFloat { origin.x + size.width }
    var maxY: CGFloat { origin.y + size.height }

    func contains(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    func insetBy(dx: CGFloat, dy: CGFloat) -> AutoQuitAXFrame {
        AutoQuitAXFrame(origin: CGPoint(x: origin.x + dx, y: origin.y + dy),
                        size: CGSize(width: size.width - dx * 2, height: size.height - dy * 2))
    }
}
