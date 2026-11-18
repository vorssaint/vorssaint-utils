// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Session state is intentionally memory-only: a settings restore or relaunch
/// must never resurrect a timer from a different day or another Mac.
final class NotchTimerService: ObservableObject {
    static let shared = NotchTimerService()
    @Published private(set) var session = NotchTimerSession()
    @Published private(set) var mediaCommandFailed = false
    private let origin = ContinuousClock.now
    private var completionTask: Task<Void, Never>?
    /// Wakes for the last seconds of a countdown, which the companion watches.
    private var countdownTask: Task<Void, Never>?
    private var suspended = true
    private let alert = NotchTimerAlert()
    private let media = NotchPomodoroMediaControl()
    private init() {}

    var now: TimeInterval {
        let parts = origin.duration(to: .now).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    func syncWithPreferences() {
        guard NotchTimerSupport.isEnabled() else { stop(); return }
        if !UserDefaults.standard.bool(forKey: DefaultsKey.notchPomodoroControlMedia) {
            media.cancel()
            mediaCommandFailed = false
        }
        let resuming = suspended
        suspended = false
        finishIfDue(automatically: !resuming)
        if session.completed { alert.start(enabled: NotchTimerSupport.isSoundEnabled()) }
        scheduleCompletion()
    }

    func start(mode: NotchTimerMode, minutes: Int) {
        guard !suspended, NotchTimerSupport.isEnabled() else { return }
        guard !session.hasSession else { return }
        alert.stop()
        mediaCommandFailed = false
        session.start(mode: mode, minutes: minutes, now: now, configuration: .load())
        updateMedia()
        scheduleCompletion()
        NotchService.shared.reactMascot(.ready)
    }

    func pauseOrResume() {
        guard !suspended, NotchTimerSupport.isEnabled() else { return }
        finishIfDue()
        if session.isRunning { session.pause(at: now); updateMedia() }
        else if session.isPaused { session.resume(at: now); updateMedia() }
        scheduleCompletion()
    }

    func startNext() {
        guard !suspended, NotchTimerSupport.isEnabled() else { return }
        guard session.canStartNext else { return }
        alert.stop()
        session.startNext(at: now)
        updateMedia()
        scheduleCompletion()
        NotchService.shared.reactMascot(.ready)
    }

    func cancel() {
        if session.mode == .pomodoro, session.hasSession { updateMedia(stopping: true) }
        alert.stop()
        completionTask?.cancel(); completionTask = nil
        countdownTask?.cancel(); countdownTask = nil
        NotchService.shared.endMascotCountdown(retreating: false)
        session.cancel()
        mediaCommandFailed = false
    }

    func suspend() {
        suspended = true
        media.cancel()
        alert.suspend()
        completionTask?.cancel(); completionTask = nil
        countdownTask?.cancel(); countdownTask = nil
        NotchService.shared.endMascotCountdown(retreating: false)
    }

    func stop() { suspend(); cancel() }

    private func finishIfDue(automatically: Bool = false) {
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
        // A live deadline (including a preference refresh that wins the race
        // with its callback) may advance. Wake-up only finishes the old phase.
        if automatically, session.canStartNext,
           UserDefaults.standard.bool(forKey: DefaultsKey.notchPomodoroAutoAdvance) {
            session.startNext(at: now)
            alert.chime(enabled: NotchTimerSupport.isSoundEnabled())
            scheduleCompletion()
        } else {
            alert.start(enabled: NotchTimerSupport.isSoundEnabled())
        }
        updateMedia()
    }

    private func updateMedia(stopping: Bool = false) {
        guard !suspended, NotchTimerSupport.isEnabled(), session.mode == .pomodoro,
              UserDefaults.standard.bool(forKey: DefaultsKey.notchPomodoroControlMedia) else {
            media.cancel()
            mediaCommandFailed = false
            return
        }
        let command: NotchPomodoroMediaControl.Command = !stopping && session.isRunning && session.phase == .focus
            ? .play : .pause
        mediaCommandFailed = false
        media.send(command) { [weak self] accepted in
            guard let self, !self.suspended, self.session.mode == .pomodoro, self.session.hasSession,
                  NotchTimerSupport.isEnabled(),
                  UserDefaults.standard.bool(forKey: DefaultsKey.notchPomodoroControlMedia) else { return }
            self.mediaCommandFailed = !accepted
        }
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
            self.finishIfDue(automatically: true)
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
