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
    /// A timer started from the menu panel keeps going after the panel
    /// closes, with or without the island, until it is cancelled.
    private var panelOwnsSession = false
    private init() {}

    /// The panel shows the page, or runs a timer started there.
    var panelHolds: Bool {
        PanelModuleDemand.shared.shows(.timer) || (panelOwnsSession && session.hasSession)
    }

    var isEnabled: Bool { NotchTimerSupport.isEnabled(panelHolds: panelHolds) }

    var now: TimeInterval {
        let parts = origin.duration(to: .now).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    func syncWithPreferences() {
        guard isEnabled else { stop(); return }
        suspended = false
        finishIfDue()
        if session.completed { alert.start(enabled: NotchTimerSupport.isSoundEnabled()) }
        scheduleCompletion()
    }

    func start(mode: NotchTimerMode, minutes: Int) {
        guard !suspended, isEnabled else { return }
        guard !session.hasSession else { return }
        alert.stop()
        panelOwnsSession = PanelModuleDemand.shared.shows(.timer)
        session.start(mode: mode, minutes: minutes, now: now, configuration: .load())
        scheduleCompletion()
    }

    func pauseOrResume() {
        guard !suspended, isEnabled else { return }
        finishIfDue()
        if session.isRunning { session.pause(at: now) }
        else if session.isPaused { session.resume(at: now) }
        scheduleCompletion()
    }

    func startNext() {
        guard !suspended, isEnabled else { return }
        guard session.canStartNext else { return }
        alert.stop()
        session.startNext(at: now)
        scheduleCompletion()
    }

    func cancel() {
        alert.stop()
        completionTask?.cancel(); completionTask = nil
        session.cancel()
        // Nothing is left for the panel to keep going.
        if panelOwnsSession {
            panelOwnsSession = false
            NotchService.shared.panelDemandChanged(.timer)
        }
    }

    /// The island stepped away; a timer the panel holds keeps going.
    func islandSuspended() {
        if !panelHolds { suspend() }
    }

    /// The island stopped; a timer the panel holds keeps going.
    func islandStopped() {
        if !panelHolds { stop() }
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
        guard !suspended, let deadline = session.deadline else { return }
        let remaining = max(0, deadline - now)
        completionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(remaining), clock: .continuous) }
            catch { return }
            guard let self, !Task.isCancelled, !self.suspended, self.isEnabled else { return }
            self.completionTask = nil
            self.finishIfDue()
        }
    }
}
