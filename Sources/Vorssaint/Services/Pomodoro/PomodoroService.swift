// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Combine
import AppKit

// MARK: - PomodoroService

public final class PomodoroService: ObservableObject {

    // MARK: Singleton

    public static let shared = PomodoroService()

    private init() {
        registerHotkey()
        syncWithPreferences()
    }

    // MARK: Published Properties

    @Published public private(set) var state: PomodoroState = .idle
    @Published public private(set) var currentPhase: PomodoroPhase = .focus
    @Published public private(set) var timeRemaining: TimeInterval = 25 * 60
    @Published public private(set) var totalPhaseDuration: TimeInterval = 25 * 60
    @Published public private(set) var completedCycles: Int = 0

    // MARK: Utility Properties

    public var formattedTime: String {
        PomodoroSupport.formattedTime(timeRemaining)
    }

    public var progress: Double {
        PomodoroSupport.progress(remaining: timeRemaining, total: totalPhaseDuration)
    }

    public var menuBarTitle: String {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.pomodoroShowInMenuBar) else { return "" }
        return PomodoroSupport.menuBarTitle(phase: currentPhase, remaining: timeRemaining, isRunningOrPaused: state != .idle)
    }

    // MARK: Private State

    private var timer: DispatchSourceTimer?
    private var hotkey: QuickToolHotkey?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Preferences (DefaultsKey)

    private var pomodoroEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.pomodoroEnabled)
    }

    private var pomodoroFocusMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: DefaultsKey.pomodoroFocusMinutes)
        return value > 0 ? value : 25
    }

    private var pomodoroShortBreakMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: DefaultsKey.pomodoroShortBreakMinutes)
        return value > 0 ? value : 5
    }

    private var pomodoroLongBreakMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: DefaultsKey.pomodoroLongBreakMinutes)
        return value > 0 ? value : 15
    }

    private var pomodoroLongBreakInterval: Int {
        let value = UserDefaults.standard.integer(forKey: DefaultsKey.pomodoroLongBreakInterval)
        return value > 0 ? value : 4
    }

    private var pomodoroAutoStartBreaks: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.pomodoroAutoStartBreaks)
    }

    private var pomodoroAutoStartFocus: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.pomodoroAutoStartFocus)
    }

    private var pomodoroSoundEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.pomodoroSoundEnabled)
    }

    // MARK: Hotkey Registration

    private func registerHotkey() {
        let key = QuickToolHotkey(id: 91)
        key.onPress = { [weak self] in
            self?.toggle()
        }
        hotkey = key
    }

    // MARK: Public Methods

    public func start() {
        guard pomodoroEnabled else { return }
        guard state != .running else { return }

        if state == .idle || state == .completed {
            syncWithPreferences()
        }

        state = .running
        startTimer()
    }

    public func pause() {
        guard state == .running else { return }
        state = .paused
        stopTimer()
    }

    public func toggle() {
        switch state {
        case .idle, .completed:
            start()
        case .running:
            pause()
        case .paused:
            start()
        }
    }

    public func reset() {
        stopTimer()
        state = .idle
        completedCycles = 0
        currentPhase = .focus
        syncWithPreferences()
    }

    public func skip() {
        stopTimer()
        advanceToNextPhase()
    }

    // MARK: Phase Advancement

    public func advanceToNextPhase() {
        stopTimer()

        let transition = PomodoroSupport.nextPhase(after: currentPhase,
                                                   completedCycles: completedCycles,
                                                   longBreakInterval: pomodoroLongBreakInterval)
        currentPhase = transition.phase
        completedCycles = transition.cycles

        totalPhaseDuration = duration(for: currentPhase)
        timeRemaining = totalPhaseDuration
        state = .idle

        playPhaseTransitionSound()
        postPhaseTransitionAlert()

        handleAutoStart()
    }

    // MARK: Timer

    private func startTimer() {
        stopTimer()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard state == .running else { return }

        timeRemaining -= 1

        if timeRemaining <= 0 {
            timeRemaining = 0
            phaseCompleted()
        }
    }

    private func phaseCompleted() {
        stopTimer()
        state = .completed

        playCompletionSound()
        postCompletionAlert()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.advanceToNextPhase()
        }
    }

    // MARK: Auto-Start Logic

    private func handleAutoStart() {
        switch currentPhase {
        case .focus:
            if pomodoroAutoStartFocus {
                start()
            }
        case .shortBreak, .longBreak:
            if pomodoroAutoStartBreaks {
                start()
            }
        }
    }

    // MARK: Preferences Sync

    public func syncWithPreferences() {
        hotkey?.sync(
            enabled: AppFeature.pomodoro.isAvailable && pomodoroEnabled,
            shortcut: GlobalShortcutRole.pomodoro.savedShortcut,
            storageKey: DefaultsKey.pomodoroShortcut
        )

        totalPhaseDuration = duration(for: currentPhase)

        if state == .idle {
            timeRemaining = totalPhaseDuration
        }
    }

    private func duration(for phase: PomodoroPhase) -> TimeInterval {
        PomodoroSupport.duration(
            for: phase,
            focusMinutes: pomodoroFocusMinutes,
            shortBreakMinutes: pomodoroShortBreakMinutes,
            longBreakMinutes: pomodoroLongBreakMinutes
        )
    }

    // MARK: Sound & Alerts

    private func playCompletionSound() {
        guard pomodoroSoundEnabled else { return }
        if let sound = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: false) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func playPhaseTransitionSound() {
        guard pomodoroSoundEnabled else { return }
        if let sound = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: false) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func postCompletionAlert() {
        let strings = FeatureStrings.pomodoro(L10n.shared.language)
        let title: String
        let body: String

        switch currentPhase {
        case .focus:
            title = strings.notificationFocusFinishedTitle
            body = strings.notificationFocusFinishedBody
        case .shortBreak, .longBreak:
            title = strings.notificationBreakFinishedTitle
            body = strings.notificationBreakFinishedBody
        }

        Notifier.post(title: title, body: body)
    }

    private func postPhaseTransitionAlert() {
        let title: String
        let body: String

        switch currentPhase {
        case .focus:
            title = "Focus Session"
            body = "Let's concentrate for \(pomodoroFocusMinutes) minutes."
        case .shortBreak:
            title = "Short Break"
            body = "Relax for \(pomodoroShortBreakMinutes) minutes."
        case .longBreak:
            title = "Long Break"
            body = "Take a longer rest for \(pomodoroLongBreakMinutes) minutes."
        }

        Notifier.post(title: title, body: body)
    }

    // MARK: Deinit

    deinit {
        stopTimer()
        hotkey?.unregister()
    }
}
