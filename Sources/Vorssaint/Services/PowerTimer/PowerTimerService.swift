// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// A session never travels in defaults or survives an app restart. Dependencies
/// are injected so permission races, cancellation and execution are tested
/// without sending a real power command.
final class PowerTimerService: ObservableObject {
    enum Failure: Equatable { case permission, keepAwake, execution, invalidTime }
    @Published private(set) var session: PowerTimerSession?
    @Published private(set) var preparing = false
    @Published private(set) var executing = false
    @Published private(set) var failure: Failure?
    private var generation = UUID()
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var holdsAssertion = false
    private let available: () -> Bool
    private let sleepDisabled: () -> Bool
    private let acquireAssertion: () -> Bool
    private let releaseAssertion: () -> Void
    private let authorize: (@escaping (Bool) -> Void) -> Void
    private let execute: (PowerTimerAction, @escaping (Bool) -> Void) -> Void
    private let now: () -> Date
    private let uptime: () -> TimeInterval

    init(available: @escaping () -> Bool, sleepDisabled: @escaping () -> Bool,
         acquireAssertion: @escaping () -> Bool, releaseAssertion: @escaping () -> Void,
         authorize: @escaping (@escaping (Bool) -> Void) -> Void,
         execute: @escaping (PowerTimerAction, @escaping (Bool) -> Void) -> Void,
         now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.available = available; self.sleepDisabled = sleepDisabled
        self.acquireAssertion = acquireAssertion; self.releaseAssertion = releaseAssertion
        self.authorize = authorize; self.execute = execute
        self.now = now; self.uptime = uptime
    }

    func start(minutes: Int, action: PowerTimerAction) {
        start(PowerTimerSession.duration(minutes, action: action, now: now(), uptime: uptime()))
    }

    func start(at date: Date, action: PowerTimerAction) {
        start(PowerTimerSession.clockTime(date, action: action, now: now()))
    }

    private func start(_ candidate: PowerTimerSession?) {
        guard available(), session == nil, !preparing, !executing else { return }
        failure = nil
        guard let candidate else { failure = .invalidTime; return }
        guard !sleepDisabled() else { failure = .keepAwake; return }
        generation = UUID()
        let id = generation
        preparing = true
        observeLifecycle()
        if candidate.action == .shutDown {
            // Resolve Automation while the person is present, never at expiry.
            authorize { [weak self] allowed in self?.arm(candidate, allowed: allowed, id: id) }
        } else {
            arm(candidate, allowed: true, id: id)
        }
    }

    private func arm(_ candidate: PowerTimerSession, allowed: Bool, id: UUID) {
        guard id == generation else { return }
        preparing = false
        tearDown()
        guard available() else { return }
        guard allowed else { failure = .permission; return }
        guard !sleepDisabled() else { failure = .keepAwake; return }
        // Do not perform a late action if the permission prompt outlasted it.
        guard candidate.remaining(now: now(), uptime: uptime()) > 0 else {
            failure = .invalidTime; return
        }
        guard acquireAssertion() else { failure = .execution; return }
        holdsAssertion = true
        session = candidate
        observeLifecycle()
        schedule()
    }

    func remaining() -> TimeInterval {
        session?.remaining(now: now(), uptime: uptime()) ?? 0
    }

    func scheduledDate() -> Date? {
        guard let session else { return nil }
        return session.uptimeDeadline == nil ? session.displayDate : now().addingTimeInterval(remaining())
    }

    func cancel() {
        generation = UUID()
        preparing = false; executing = false; session = nil; failure = nil
        tearDown()
    }

    func syncWithFeatures() {
        if !available() { cancel() }
    }

    /// Called by the one-shot timer, and on wall-clock changes. Consume the
    /// session before issuing the command so reentrant events cannot repeat it.
    func checkDeadline() {
        guard let session else { return }
        guard available() else { cancel(); return }
        guard remaining() <= 0 else { schedule(); return }
        guard !sleepDisabled() else {
            cancel(); failure = .keepAwake; return
        }
        let id = generation
        self.session = nil
        executing = true
        tearDown()
        execute(session.action) { [weak self] ok in
            guard let self, id == self.generation else { return }
            self.executing = false
            if !ok { self.failure = .execution }
        }
    }

    private func schedule() {
        timer?.invalidate()
        guard session != nil else { return }
        let timer = Timer(timeInterval: max(0.01, remaining()), repeats: false) { [weak self] _ in
            self?.checkDeadline()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func observeLifecycle() {
        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in self?.cancel() }))
        observers.append((center, center.addObserver(forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in self?.cancel() }))
        observers.append((center, center.addObserver(forName: .NSSystemClockDidChange,
            object: nil, queue: .main) { [weak self] _ in self?.checkDeadline() }))
    }

    private func tearDown() {
        timer?.invalidate(); timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        if holdsAssertion { holdsAssertion = false; releaseAssertion() }
    }

    deinit { tearDown() }
}
