// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Foundation

/// Keeps an immutable window snapshot ready before the switcher shortcut is
/// pressed. Full Accessibility enumeration happens on a worker; the hot path
/// only takes the lock long enough to copy the latest value.
final class SwitcherWindowCatalog {
    static let shared = SwitcherWindowCatalog()

    private static let refreshDebounce: TimeInterval = 0.08
    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXMainWindowChangedNotification,
        kAXFocusedWindowChangedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification
    ]

    private let snapshotLock = NSLock()
    private var storedSnapshot = WindowEnumerator.Snapshot.empty
    private let worker = DispatchQueue(label: "com.vorssaint.switcher-window-catalog",
                                       qos: .userInitiated)

    /// Lifecycle and observer state are main-thread-only.
    private var running = false
    private var generation = 0
    private var refreshInFlight = false
    private var refreshAgain = false
    private var pendingRefresh: DispatchWorkItem?
    private var launchToken: NSObjectProtocol?
    private var terminateToken: NSObjectProtocol?
    private var activationToken: NSObjectProtocol?
    private var observers: [pid_t: AXObserver] = [:]
    private var observedWindows: [pid_t: [CGWindowID: AXUIElement]] = [:]

    private init() {}

    func snapshot() -> WindowEnumerator.Snapshot {
        snapshotLock.withLock { storedSnapshot }
    }

    func start() {
        guard !running else {
            requestRefresh(immediate: true)
            return
        }
        running = true
        generation += 1

        let center = NSWorkspace.shared.notificationCenter
        launchToken = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                         object: nil, queue: .main) { [weak self] _ in
            self?.requestRefresh()
        }
        terminateToken = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self.detachObserver(pid: app.processIdentifier)
            }
            self.requestRefresh()
        }
        activationToken = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            self?.requestRefresh()
        }

        // The public WindowServer list is fast enough to seed a useful first
        // snapshot at startup. Accessibility enriches it on the worker without
        // making the first shortcut wait for every app to answer.
        let request = WindowEnumerator.makeRequest()
        store(WindowEnumerator.captureSnapshot(using: request.withAccessibility(false)))
        beginRefresh(using: request)
    }

    func stop() {
        guard running else { return }
        running = false
        generation += 1
        pendingRefresh?.cancel()
        pendingRefresh = nil
        refreshAgain = false

        let center = NSWorkspace.shared.notificationCenter
        if let launchToken { center.removeObserver(launchToken) }
        if let terminateToken { center.removeObserver(terminateToken) }
        if let activationToken { center.removeObserver(activationToken) }
        launchToken = nil
        terminateToken = nil
        activationToken = nil

        for pid in Array(observers.keys) {
            detachObserver(pid: pid)
        }
        snapshotLock.withLock { storedSnapshot = .empty }
    }

    /// A session uses the existing snapshot immediately, then asks the catalog
    /// to heal any notification an app did not support.
    func refreshAfterSessionStart() {
        requestRefresh(immediate: true)
    }

    private func requestRefresh(immediate: Bool = false) {
        guard running else { return }
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            self.pendingRefresh = nil
            self.beginRefresh(using: WindowEnumerator.makeRequest())
        }
        pendingRefresh = work
        if immediate {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshDebounce,
                                          execute: work)
        }
    }

    private func beginRefresh(using request: WindowEnumerator.Request) {
        guard running else { return }
        if refreshInFlight {
            refreshAgain = true
            return
        }
        refreshInFlight = true
        let expectedGeneration = generation
        worker.async { [weak self] in
            let snapshot = autoreleasepool {
                WindowEnumerator.captureSnapshot(using: request)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshInFlight = false
                guard self.running else { return }
                guard self.generation == expectedGeneration else {
                    if self.refreshAgain {
                        self.refreshAgain = false
                        self.requestRefresh(immediate: true)
                    }
                    return
                }
                self.store(snapshot)
                self.reconcileObservers(with: snapshot.observationTargets)
                if self.refreshAgain {
                    self.refreshAgain = false
                    self.requestRefresh(immediate: true)
                }
            }
        }
    }

    private func store(_ snapshot: WindowEnumerator.Snapshot) {
        snapshotLock.withLock { storedSnapshot = snapshot }
    }

    // MARK: - Accessibility invalidation

    private func reconcileObservers(with targets: [pid_t: WindowEnumerator.ObservationTarget]) {
        guard running else { return }
        for (pid, target) in targets {
            if observers[pid] == nil {
                attachObserver(pid: pid, target: target)
            } else {
                reconcileWindows(pid: pid, target: target)
            }
        }
    }

    private func attachObserver(pid: pid_t, target: WindowEnumerator.ObservationTarget) {
        var observerRef: AXObserver?
        guard AXObserverCreate(pid, switcherWindowCatalogAXCallback, &observerRef) == .success,
              let observer = observerRef else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var registered = false
        for notification in Self.appNotifications {
            if AXObserverAddNotification(observer,
                                         target.appElement,
                                         notification as CFString,
                                         refcon) == .success {
                registered = true
            }
        }
        guard registered else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer),
                           .commonModes)
        observers[pid] = observer
        observedWindows[pid] = [:]
        reconcileWindows(pid: pid, target: target)
    }

    private func reconcileWindows(pid: pid_t, target: WindowEnumerator.ObservationTarget) {
        guard let observer = observers[pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var current = observedWindows[pid] ?? [:]

        for staleID in Array(current.keys) where target.windowsByID[staleID] == nil {
            if let element = current[staleID] {
                for notification in Self.windowNotifications {
                    AXObserverRemoveNotification(observer, element, notification as CFString)
                }
            }
            current[staleID] = nil
        }

        for (windowID, element) in target.windowsByID where current[windowID] == nil {
            for notification in Self.windowNotifications {
                AXObserverAddNotification(observer,
                                          element,
                                          notification as CFString,
                                          refcon)
            }
            // Remember unsupported registrations too; retrying them on every
            // catalog refresh would turn a graceful fallback into repeated IPC.
            current[windowID] = element
        }
        observedWindows[pid] = current
    }

    private func detachObserver(pid: pid_t) {
        if let observer = observers[pid] {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(observer),
                                  .commonModes)
        }
        observers[pid] = nil
        observedWindows[pid] = nil
    }

    fileprivate func handleAXNotification() {
        if Thread.isMainThread {
            requestRefresh()
        } else {
            DispatchQueue.main.async { [weak self] in self?.requestRefresh() }
        }
    }
}

/// C trampoline for AXObserver. The catalog only invalidates its snapshot here;
/// all expensive reads stay on the worker refresh.
private func switcherWindowCatalogAXCallback(_ observer: AXObserver,
                                             _ element: AXUIElement,
                                             _ notification: CFString,
                                             _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let catalog = Unmanaged<SwitcherWindowCatalog>.fromOpaque(refcon).takeUnretainedValue()
    catalog.handleAXNotification()
}
