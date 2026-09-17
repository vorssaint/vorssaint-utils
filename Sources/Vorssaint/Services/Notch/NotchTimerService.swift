// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Session state is intentionally memory-only: a settings restore or relaunch
/// must never resurrect a timer from a different day or another Mac.
final class NotchTimerService: ObservableObject {
    static let shared = NotchTimerService()
    @Published private(set) var session = NotchTimerSession()
    private let origin = ContinuousClock.now
    private var completionTask: Task<Void, Never>?
    private var suspended = true
    private let alert = NotchTimerAlert()
    private init() {}

    var now: TimeInterval {
        let parts = origin.duration(to: .now).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    func syncWithPreferences() {
        guard NotchTimerSupport.isEnabled() else { stop(); return }
        suspended = false
        finishIfDue()
        if session.completed { alert.start(enabled: NotchTimerSupport.isSoundEnabled()) }
        scheduleCompletion()
    }

    func start(mode: NotchTimerMode, minutes: Int) {
        guard !suspended, NotchTimerSupport.isEnabled() else { return }
        guard !session.hasSession else { return }
        alert.stop()
        session.start(mode: mode, minutes: minutes, now: now, configuration: .load())
        scheduleCompletion()
    }

    func pauseOrResume() {
        guard !suspended, NotchTimerSupport.isEnabled() else { return }
        finishIfDue()
        if session.isRunning { session.pause(at: now) }
        else if session.isPaused { session.resume(at: now) }
        scheduleCompletion()
    }

    func startNext() {
        guard !suspended, NotchTimerSupport.isEnabled() else { return }
        guard session.canStartNext else { return }
        alert.stop()
        session.startNext(at: now)
        scheduleCompletion()
    }

    func cancel() {
        alert.stop()
        completionTask?.cancel(); completionTask = nil
        session.cancel()
    }

    func suspend() {
        suspended = true
        alert.suspend()
        completionTask?.cancel(); completionTask = nil
    }

    func stop() { suspend(); cancel() }

    private func finishIfDue() {
        guard session.finishIfDue(at: now) else { return }
        alert.stop()
        let text = FeatureStrings.notchActivities(L10n.shared.language)
        NotchService.shared.show(NotchNotice(event: .timer,
            title: session.cycleFinished ? text.pomodoroFinished : text.finished,
            detail: text.phase(session.phase), symbol: "timer"))
        alert.start(enabled: NotchTimerSupport.isSoundEnabled())
    }

    private func scheduleCompletion() {
        completionTask?.cancel(); completionTask = nil
        guard !suspended, session.isRunning else { return }
        let remaining = session.remaining(at: now)
        completionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(remaining), clock: .continuous) }
            catch { return }
            guard let self, !Task.isCancelled, !self.suspended, NotchTimerSupport.isEnabled() else { return }
            self.completionTask = nil
            self.finishIfDue()
        }
    }
}
