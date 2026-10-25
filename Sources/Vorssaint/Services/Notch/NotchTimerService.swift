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
    /// Wakes for the last seconds of a countdown, which the companion watches.
    private var countdownTask: Task<Void, Never>?
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
        NotchService.shared.reactMascot(.ready)
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
        NotchService.shared.reactMascot(.ready)
    }

    func cancel() {
        alert.stop()
        completionTask?.cancel(); completionTask = nil
        countdownTask?.cancel(); countdownTask = nil
        NotchService.shared.endMascotCountdown(retreating: false)
        session.cancel()
    }

    func suspend() {
        suspended = true
        alert.suspend()
        completionTask?.cancel(); completionTask = nil
        countdownTask?.cancel(); countdownTask = nil
        NotchService.shared.endMascotCountdown(retreating: false)
    }

    func stop() { suspend(); cancel() }

    private func finishIfDue() {
        guard session.finishIfDue(at: now) else { return }
        alert.stop()
        // The notice takes the strip it watched from.
        NotchService.shared.endMascotCountdown(retreating: false)
        let text = FeatureStrings.notchActivities(L10n.shared.language)
        let reaction = NotchMascotSupport.timerReaction(finishing: session.phase)
        NotchService.shared.show(NotchNotice(event: .timer,
            title: session.cycleFinished ? text.pomodoroFinished : text.finished,
            detail: text.phase(session.phase), symbol: "timer", mascot: reaction))
        // It takes the news in the notice, or where it is when the notice cannot show.
        NotchService.shared.reactMascot(reaction)
        alert.start(enabled: NotchTimerSupport.isSoundEnabled())
    }

    private func scheduleCompletion() {
        completionTask?.cancel(); completionTask = nil
        scheduleCountdown()
        guard !suspended, let deadline = session.deadline else { return }
        let remaining = max(0, deadline - now)
        completionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(remaining), clock: .continuous) }
            catch { return }
            guard let self, !Task.isCancelled, !self.suspended, NotchTimerSupport.isEnabled() else { return }
            self.completionTask = nil
            self.finishIfDue()
        }
    }

    /// The companion comes out for a countdown's last seconds. Paused, the
    /// countdown sends it back behind the camera.
    private func scheduleCountdown() {
        countdownTask?.cancel(); countdownTask = nil
        guard !suspended, let deadline = session.deadline else {
            NotchService.shared.endMascotCountdown(retreating: true)
            return
        }
        let remaining = deadline - now
        guard remaining > 1.5 else { return }
        let wait = max(0, remaining - NotchMascotMotion.countdownLead)
        countdownTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(wait), clock: .continuous) }
            catch { return }
            guard let self, !Task.isCancelled, !self.suspended, let deadline = self.session.deadline else { return }
            self.countdownTask = nil
            NotchService.shared.watchMascotCountdown(remaining: deadline - self.now)
        }
    }
}
