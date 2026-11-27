// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// A game can change its window level or size without activating a new app,
/// Space or display mode. Watch independently of switcher sessions and their
/// filtered window lists. Only the WindowServer read runs off the main thread.
final class SwitcherExclusiveFullscreenWatch {
    typealias Read = (pid_t, @escaping (Bool?) -> Void) -> Void

    private let frontmostPID: () -> pid_t?
    private let read: Read
    private let onObservation: (Bool) -> Void
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var reading = false
    private var needsFreshRead = false

    init(frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
         read: @escaping Read = SwitcherExclusiveFullscreenWatch.readWindowServer,
         onObservation: @escaping (Bool) -> Void) {
        self.frontmostPID = frontmostPID
        self.read = read
        self.onObservation = onObservation
    }

    deinit { stop() }

    private static func readWindowServer(for pid: pid_t, completion: @escaping (Bool?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = SwitcherSupport.frontmostAppRaisesFullscreen(
                windows: NotchAppFullscreen.onScreenWindows(ownerPID: pid),
                frontmostPID: pid, ownPID: ProcessInfo.processInfo.processIdentifier,
                displays: Array(NotchAppFullscreen.activeDisplays().values))
            DispatchQueue.main.async { completion(result) }
        }
    }

    func start() {
        guard timer == nil else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let notifications: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.didActivateApplicationNotification),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification),
            (.default, NSApplication.didChangeScreenParametersNotification)
        ]
        observers = notifications.map { center, name in
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh(environmentChanged: true)
            }
            return (center, token)
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.3
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refresh(environmentChanged: true)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        needsFreshRead = false
    }

    func refresh(environmentChanged: Bool = false) {
        guard timer != nil else { return }
        if reading {
            // Timer ticks may share a read. An activation, display change or
            // restart needs a new sample even if the frontmost PID is the same.
            if environmentChanged { needsFreshRead = true }
            return
        }
        guard let pid = frontmostPID() else { return }
        reading = true
        read(pid) { [weak self] result in
            guard let self else { return }
            self.reading = false
            guard self.timer != nil else { return }
            if self.needsFreshRead || self.frontmostPID() != pid {
                self.needsFreshRead = false
                self.refresh()
            } else if let result {
                self.onObservation(result)
            }
        }
    }
}
