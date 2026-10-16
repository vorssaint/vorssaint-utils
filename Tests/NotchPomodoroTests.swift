// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Actual timer service methods compiled against a clock and recording outputs.
/// No test sends media commands to the user's apps or changes their preferences.
enum NotchPomodoroTests {
    final class Preferences {
        var values: [String: Bool] = [:]
        func bool(forKey key: String) -> Bool { values[key] ?? false }
    }
    enum UserDefaults { static var standard = Preferences() }
    enum NotchTimerSupport {
        static var enabled = true
        static func isEnabled() -> Bool { enabled }
        static func isSoundEnabled() -> Bool { true }
    }
    enum L10n {
        static let shared = SelfValue()
        struct SelfValue { let language = AppLanguage.enUS }
    }
    final class NotchPomodoroMediaControl {
        enum Command: String { case play, pause }
        var commands: [Command] = []
        var reply: ((Bool) -> Void)?
        var cancelled = false
        func send(_ command: Command, completion: @escaping (Bool) -> Void) {
            commands.append(command); reply = completion; cancelled = false
        }
        func cancel() { cancelled = true; reply = nil }
    }
    final class Alert {
        var starts = 0
        var chimes = 0
        func start(enabled: Bool) { if enabled { starts += 1 } }
        func chime(enabled: Bool) { if enabled { chimes += 1 } }
        func stop() {}
        func suspend() {}
    }
    final class NotchService {
        static let shared = NotchService()
        func reactMascot(_ reaction: NotchMascotReaction) {}
        func endMascotCountdown(retreating: Bool) {}
        func watchMascotCountdown(remaining: TimeInterval) {}
        func show(_ notice: NotchNotice) {}
    }
    class Fixture {
        var now: TimeInterval = 0
        var session = NotchTimerSession()
        var suspended = true
        var mediaCommandFailed = false
        var completionTask: Task<Void, Never>?
        var countdownTask: Task<Void, Never>?
        let alert = Alert()
        let media = NotchPomodoroMediaControl()
        deinit { completionTask?.cancel(); countdownTask?.cancel(); media.cancel() }
    }

    static func run(_ suite: TestSuite) {
        defer { UserDefaults.standard = Preferences(); NotchTimerSupport.enabled = true }
        for key in [DefaultsKey.notchPomodoroAutoAdvance, DefaultsKey.notchPomodoroControlMedia] {
            suite.expect(Defaults.registeredDefaults[key] as? Bool == false, "Pomodoro automation is opt-in: \(key)")
            suite.expect(SettingsBackupSupport.exportKeys().contains(key), "Pomodoro settings travel in backups: \(key)")
        }
        defaultsAndMedia(suite)
        automaticPhases(suite)
        lifecycle(suite)
        PomodoroSystemPlaybackContract.run(suite)
        PomodoroMediaCancellationTests.run(suite)
    }

    private static func make(media: Bool = true, automatic: Bool = false) -> Service {
        UserDefaults.standard = Preferences()
        UserDefaults.standard.values = [DefaultsKey.notchPomodoroControlMedia: media,
                                       DefaultsKey.notchPomodoroAutoAdvance: automatic]
        NotchTimerSupport.enabled = true
        let service = Service()
        service.syncWithPreferences()
        return service
    }

    private static func defaultsAndMedia(_ suite: TestSuite) {
        let off = make(media: false)
        off.start(mode: .pomodoro, minutes: 1)
        off.now = off.session.deadline!
        off.finishIfDue(automatically: true)
        suite.expect(off.session.completed && off.media.commands.isEmpty, "default Pomodoro waits for the next phase and never touches media")
        off.stop()

        for mode in [NotchTimerMode.timer, .stopwatch] {
            let service = make(automatic: true)
            service.start(mode: mode, minutes: 1)
            service.pauseOrResume(); service.pauseOrResume(); service.cancel()
            suite.expect(service.media.commands.isEmpty, "timer and stopwatch never control media even with both Pomodoro options on")
        }

        let service = make()
        service.start(mode: .pomodoro, minutes: 1)
        suite.expect(service.media.commands == [.play], "starting focus requests play")
        service.syncWithPreferences(); service.syncWithPreferences()
        suite.expect(service.media.commands == [.play], "preference refreshes never replay media or override manual playback")
        service.pauseOrResume()
        suite.expect(service.media.commands.last == .pause && service.session.isPaused, "pausing focus pauses media")
        service.pauseOrResume()
        suite.expect(service.media.commands.last == .play && service.session.isRunning, "resuming focus plays media")
        service.now = service.session.deadline!
        service.finishIfDue()
        suite.expect(service.media.commands.last == .pause && service.session.completed, "focus completion pauses media even before the break starts")
        service.startNext()
        service.pauseOrResume(); service.pauseOrResume()
        suite.expect(service.session.phase == .shortBreak && service.media.commands.suffix(3) == [.pause, .pause, .pause],
                     "starting and resuming breaks only send pause")
        service.now = service.session.deadline!
        service.finishIfDue()
        service.startNext()
        suite.expect(service.session.phase == .focus && service.media.commands.last == .play, "next focus resumes media")
        service.cancel()
        suite.expect(!service.session.hasSession && service.media.commands.last == .pause, "cancelling Pomodoro pauses media")
        service.media.reply?(false)
        suite.expect(!service.mediaCommandFailed, "a late cancel reply cannot leave a warning on an idle timer")
    }

    private static func automaticPhases(_ suite: TestSuite) {
        let service = make(automatic: true)
        service.session.start(mode: .pomodoro, minutes: 1, now: 0,
                              configuration: .init(focusMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 2,
                                                   longBreakInterval: 2, totalSessions: 3))
        service.now = 60
        service.finishIfDue(automatically: true)
        suite.expect(service.session.phase == .shortBreak && service.session.deadline == 120
                     && service.media.commands == [.pause] && service.alert.chimes == 1 && service.alert.starts == 0,
                     "automatic break gets its full duration, one chime and one pause")
        service.now = 120
        service.finishIfDue(automatically: true)
        suite.expect(service.session.phase == .focus && service.media.commands == [.pause, .play], "automatic focus plays once")
        service.now = 180
        service.finishIfDue(automatically: true)
        suite.expect(service.session.phase == .longBreak && service.session.deadline == 300, "configured long breaks are preserved")
        service.now = 300
        service.finishIfDue(automatically: true)
        service.now = 360
        service.finishIfDue(automatically: true)
        suite.expect(service.session.cycleFinished && service.session.deadline == nil && service.media.commands.last == .pause
                     && service.alert.chimes == 4 && service.alert.starts == 1,
                     "last focus ends the cycle, pauses playback and uses the normal completion alert")
        let commands = service.media.commands
        service.finishIfDue(automatically: true)
        suite.expect(service.media.commands == commands, "duplicate deadline callbacks never repeat commands")
        service.stop()

        let manual = make(automatic: true)
        manual.start(mode: .pomodoro, minutes: 1)
        UserDefaults.standard.values[DefaultsKey.notchPomodoroAutoAdvance] = false
        manual.now = manual.session.deadline!
        manual.finishIfDue(automatically: true)
        suite.expect(manual.session.completed, "turning automatic advance off takes effect at the next boundary")
        manual.stop()

        let refreshed = make(automatic: true)
        refreshed.start(mode: .pomodoro, minutes: 1)
        refreshed.now = refreshed.session.deadline!
        refreshed.syncWithPreferences()
        suite.expect(refreshed.session.phase == .shortBreak && refreshed.session.isRunning,
                     "an awake preference refresh at the deadline cannot consume automatic advancement")
        refreshed.stop()
    }

    private static func lifecycle(_ suite: TestSuite) {
        let service = make(automatic: true)
        service.start(mode: .pomodoro, minutes: 1)
        service.media.reply?(false)
        suite.expect(service.mediaCommandFailed && service.session.isRunning, "media failure is visible without stopping the timer")
        service.suspend()
        suite.expect(service.media.cancelled && service.completionTask == nil && service.countdownTask == nil,
                     "sleep/lock cancels pending media work and timer callbacks")
        service.now = service.session.deadline! + 3600
        service.syncWithPreferences()
        suite.expect(service.session.completed && service.session.phase == .focus && service.media.commands == [.play, .pause],
                     "wake completes the overdue phase but cannot play media or skip cycles")
        service.startNext()
        service.suspend()
        service.now = service.session.deadline! + 3600
        service.syncWithPreferences()
        suite.expect(service.session.completed && service.session.phase == .shortBreak && service.media.commands.last == .pause,
                     "an overdue break waits for manual focus after wake")
        service.startNext()
        let count = service.media.commands.count
        service.suspend(); service.syncWithPreferences()
        suite.expect(service.media.commands.count == count, "wake before the deadline does not replay an unfinished focus session")
        UserDefaults.standard.values[DefaultsKey.notchPomodoroControlMedia] = false
        service.syncWithPreferences()
        suite.expect(service.media.cancelled && !service.mediaCommandFailed, "disabling media control cancels queued commands and clears failures")
        service.pauseOrResume(); service.pauseOrResume()
        suite.expect(service.media.commands.count == count, "disabled media control leaves playback alone")
        NotchTimerSupport.enabled = false
        service.syncWithPreferences()
        suite.expect(!service.session.hasSession && service.media.cancelled, "removing timer availability stops optional work")
        service.start(mode: .pomodoro, minutes: 1)
        suite.expect(!service.session.hasSession, "disabled timer cannot start through another entry point")
    }
}

enum PomodoroSystemPlaybackContract {
    typealias PIDFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    static var pid: Int32 = 42
    static var terminated = false
    static var missing: String?
    static var sent: [Int32] = []
    static var accepted = true
    static func dlopen(_ path: String, _ mode: Int32) -> UnsafeMutableRawPointer? { nil }
    static func dlclose(_ handle: UnsafeMutableRawPointer) {}
    struct NSRunningApplication {
        init?(processIdentifier: Int32) { if processIdentifier <= 0 { return nil } }
        var isTerminated: Bool { terminated }
    }
    static func function<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
        guard name != missing else { return nil }
        if name == "MRMediaRemoteGetNowPlayingApplicationPID" {
            let read: PIDFunction = { _, reply in reply(PomodoroSystemPlaybackContract.pid) }
            return unsafeBitCast(read, to: T.self)
        }
        if name == "MRMediaRemoteSendCommand" {
            let send: @convention(c) (Int32, CFDictionary?) -> Bool = { command, _ in
                PomodoroSystemPlaybackContract.sent.append(command)
                return PomodoroSystemPlaybackContract.accepted
            }
            return unsafeBitCast(send, to: T.self)
        }
        return nil
    }
    static func run(_ suite: TestSuite) {
        sent = []; pid = 42; terminated = false; missing = nil; accepted = true
        suite.expect(sendSystemPlayback(0) && sendSystemPlayback(1) && sendSystemPlayback(1) && sent == [0, 1, 1],
                     "global transport sends explicit play and idempotent pause, never toggle")
        suite.expect(!sendSystemPlayback(2) && sent == [0, 1, 1], "toggle is not an accepted Pomodoro command")
        pid = 0
        suite.expect(!sendSystemPlayback(0) && sent == [0, 1, 1], "no player never launches an app")
        pid = 42; terminated = true
        suite.expect(!sendSystemPlayback(0) && sent == [0, 1, 1], "an exited player never receives a command")
        terminated = false; missing = "MRMediaRemoteSendCommand"
        suite.expect(!sendSystemPlayback(1), "missing private API fails without a media-key fallback")
        missing = nil; accepted = false
        suite.expect(!sendSystemPlayback(1), "rejected global commands report failure")
    }
}

enum PomodoroMediaCancellationTests {
    static func run(_ suite: TestSuite) {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var commands: [NotchPomodoroMediaControl.Command] = []
        let media = NotchPomodoroMediaControl { command, cancellation in
            lock.withLock { commands.append(command) }
            if command == .play { entered.signal(); _ = release.wait(timeout: .now() + 2) }
            return !cancellation.isCancelled
        }
        var staleReply = false
        var latestReply = false
        media.send(.play) { _ in staleReply = true }
        suite.expect(entered.wait(timeout: .now() + 1) == .success, "first media command starts")
        media.send(.pause) { latestReply = $0 }
        release.signal()
        let until = Date().addingTimeInterval(2)
        while !latestReply, Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        suite.expect(latestReply && !staleReply && lock.withLock({ commands }) == [.play, .pause],
                     "new phase cancels the old request and suppresses its stale completion")
        media.cancel()
    }
}
