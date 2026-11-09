// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

extension KeepAwakeLidSleepContract {
    enum EndReason { case manual, timer, battery, quit }
    enum SessionTrigger { case manual, launch, automation }
    enum AppFeature {
        enum keepAwake { static var isAvailable = true }
    }
    enum DefaultsKey {
        static let clamshellPreferred = "preferred"
        static let sleepDisabledFlag = "disabled"
        static let keepAwakePauseWhenLocked = "pause"
        static let dimScreenOnLidClose = "dimScreen"
        static let dimmedDisplaySavedBrightness = "dimmedDisplaySavedBrightness"
        static let defaultDuration = "defaultDuration"
        static let batteryLimit = "batteryLimit"
        static let keepAwakeSwitchUsesUntil = "switchUsesUntil"
        static let keepAwakeUntilTime = "untilTime"
        static let keepAwakeSessionEnd = "sessionEnd"
        static let keepAwakeAutoStart = "autoStart"
    }
    enum UserDefaults {
        static let standard = Store()
        final class Store {
            var values: [String: Any] = [:]
            func set(_ value: Any, forKey key: String) { values[key] = value }
            func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
            func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
            func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
            func object(forKey key: String) -> Any? { values[key] }
            func removeObject(forKey key: String) { values.removeValue(forKey: key) }
        }
    }
    enum SystemInfo {
        static var battery: (isOnBattery: Bool, percent: Int)?
        static func batterySnapshot() -> (isOnBattery: Bool, percent: Int)? { battery }
    }
    struct RunLoop {
        static let main = RunLoop()
        // Tests fire the timers explicitly, without scheduling work on the host.
        func add(_ timer: Timer, forMode mode: Foundation.RunLoop.Mode) {}
    }
    enum Thread {
        static var waits = 0
        static var onWait: (() -> Void)?
        static func sleep(forTimeInterval interval: Double) { waits += 1; onWait?() }
    }
    enum Sudoers {
        // Extracted methods live in a qualified extension, whose lookup must
        // stay inside the fixture rather than finding application transports.
        typealias DispatchQueue = KeepAwakeLidSleepContract.DispatchQueue
        typealias Shell = KeepAwakeLidSleepContract.Shell
        typealias AdminShell = KeepAwakeLidSleepContract.AdminShell
        static var calls: [Bool] = []
        static var results = [true]
        static var disabled = false
        static var configured = true
        static var installCompletions: [(Bool) -> Void] = []
        static let sleepStateQueue = DispatchQueue.native
        static var sleepStateProbeSuspensions = 0
        static var probeWrites: [Bool] = []
        static func pmsetDisableSleepOnQueue(_ on: Bool) -> Bool {
            probeWrites.append(on)
            if configured { disabled = on }
            return configured
        }
        static func install(completion: @escaping (Bool) -> Void) {
            installCompletions.append { ok in completion(ok && isConfigured()) }
        }
        static func execute(_ on: Bool) -> Bool {
            calls.append(on)
            let ok = results.count > 1 ? results.removeFirst() : results[0]
            if ok { disabled = on }
            return ok
        }
        static func pmsetDisableSleep(_ on: Bool) -> Bool {
            DispatchQueue.native.flush()
            return execute(on)
        }
        static func pmsetDisableSleep(_ on: Bool, completion: @escaping (Bool) -> Void) {
            DispatchQueue.native.async { completion(execute(on)) }
        }
    }
    enum AdminShell {
        static var completions: [(Bool) -> Void] = []
        static var prompts = 0
        static var syncResult = false
        static func run(_ command: String, prompt: String, completion: @escaping (Bool) -> Void) {
            prompts += 1; completions.append(completion)
        }
        static func runSync(_ command: String, prompt: String) -> Bool {
            prompts += 1
            if syncResult { Sudoers.disabled = false }
            return syncResult
        }
        static func answer(_ ok: Bool) {
            if ok { Sudoers.disabled = false }
            let ready = completions; completions.removeAll()
            ready.forEach { $0(ok) }
        }
    }
    enum L10n {
        static let shared = Localized()
        struct Localized { let s = Strings() }
        struct Strings {
            let adminPromptClamshellOff = "restore"
            let adminPromptRecover = "recover"
        }
    }
    enum Shell {
        static var status: Int32 = 0
        static var output: String?
        static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
            (status, output ?? "SleepDisabled \(Sudoers.disabled ? 1 : 0)")
        }
    }
    static var onSleep: (() -> Void)?
    static func drain() {
        for _ in 0..<30 {
            let queues = [DispatchQueue.background, DispatchQueue.native, DispatchQueue.main]
            if queues.allSatisfy({ $0.immediate.isEmpty }) { return }
            queues.forEach { $0.flush() }
        }
    }
}

/// Exercises extracted session, restore, setup and retry bodies together.
/// The only substituted pieces are native transports, time and unrelated UI.
enum KeepAwakeClamshellTests {
    private typealias C = KeepAwakeLidSleepContract
    private typealias Key = C.DefaultsKey
    private static var prefs: C.UserDefaults.Store { C.UserDefaults.standard }

    private static func active() -> C.Service {
        let service = C.reset()
        service.isActive = true; service.clamshellActive = true; service.assertionsHeld = true
        C.Sudoers.disabled = true
        C.UserDefaults.standard.set(true, forKey: C.DefaultsKey.sleepDisabledFlag)
        return service
    }

    /// A fresh process enters the same recovery callback as AppDelegate. Only
    /// the preferences carry over; the system observations are chosen per launch.
    private static func relaunch(configure: (C.Service) -> Void = { _ in }) -> C.Service {
        let saved = prefs.values
        let service = C.reset()
        prefs.values = saved
        configure(service)
        service.recoverIfNeeded { service.activateOnLaunchIfNeeded() }
        C.drain()
        return service
    }

    private static func manualSessions(expect: (Bool, String) -> Void) {
        let indefinite = C.reset()
        indefinite.activate(minutes: 0)
        indefinite.deactivate(reason: .quit); C.drain()
        let resumed = relaunch()
        expect(resumed.isActive && resumed.endDate == nil && resumed.sessionMinutes == 0 && resumed.assertionsHeld,
               "a session until turned off resumes and holds the assertions again")
        resumed.toggle()
        expect(!relaunch().isActive, "turning a restored session off keeps it off after the next relaunch")

        let timed = C.reset()
        timed.activate(minutes: 30)
        let end = timed.endDate
        // Energy Settings changes the next pick without replacing a running session.
        prefs.set(60, forKey: Key.defaultDuration)
        timed.deactivate(reason: .quit); C.drain()
        let resumedTimed = relaunch()
        expect(resumedTimed.isActive && resumedTimed.endDate == end && resumedTimed.sessionMinutes == 30
               && prefs.integer(forKey: Key.defaultDuration) == 60,
               "the panel keeps the original preset and deadline after the default duration changes")
        let oldTimer = resumedTimed.endTimer
        resumedTimed.extend(minutes: 15)
        let extended = resumedTimed.endDate
        expect(extended == end?.addingTimeInterval(15 * 60) && oldTimer?.isValid == false,
               "extending a restored preset replaces its timer and advances the original deadline")
        // No quit cleanup: the active record also exists before a forced exit.
        let afterExtension = relaunch()
        expect(afterExtension.endDate == extended && afterExtension.sessionMinutes == 30,
               "an extended session survives an interrupted run with its own preset")
        afterExtension.toggle()
        expect(!afterExtension.isActive && !relaunch().isActive, "stopping the original preset clears the extended session")

        let until = C.reset()
        let untilEnd = Date().addingTimeInterval(3600)
        until.activate(until: untilEnd)
        prefs.set(60, forKey: Key.defaultDuration)
        prefs.set(false, forKey: Key.keepAwakeSwitchUsesUntil)
        until.deactivate(reason: .quit); C.drain()
        let resumedUntil = relaunch()
        expect(resumedUntil.isActive && resumedUntil.endDate == untilEnd && resumedUntil.sessionMinutes == nil,
               "a chosen end time stays on its own panel control after choosing a new default preset")
        var timerEnds = 0
        resumedUntil.onSessionEnded = { if $0 == .timer { timerEnds += 1 } }
        resumedUntil.endTimer?.fire()
        expect(timerEnds == 1 && !resumedUntil.assertionsHeld && !relaunch().isActive,
               "the scheduled timer ends a restored session and clears its record")

        prefs.set(["end": Date().addingTimeInterval(-60).timeIntervalSinceReferenceDate, "minutes": 30],
                  forKey: Key.keepAwakeSessionEnd)
        let expired = relaunch()
        expect(!expired.isActive && prefs.object(forKey: Key.keepAwakeSessionEnd) == nil,
               "a session that expired while the app was closed is discarded")
        // The old, unreleased scalar record cannot tell a launch start from a manual one.
        prefs.set(0.0, forKey: Key.keepAwakeSessionEnd)
        expect(!relaunch().isActive && prefs.object(forKey: Key.keepAwakeSessionEnd) == nil,
               "an ambiguous legacy record never starts an indefinite session")
    }

    private static func launchAndAutomation(expect: (Bool, String) -> Void) {
        let timed = C.reset()
        timed.activate(minutes: 30)
        timed.matchingConditions = [.power]
        timed.endTimer?.fire()
        expect(timed.isActive && timed.sessionTrigger == .automation && timed.endDate == nil
               && prefs.object(forKey: Key.keepAwakeSessionEnd) == nil,
               "a matching automation takes over the expired timer and clears its manual record")
        timed.deactivate(reason: .quit); C.drain()
        expect(!relaunch().isActive, "an automatic session is left to its conditions after a relaunch")

        prefs.set(true, forKey: Key.keepAwakeAutoStart)
        prefs.set(30, forKey: Key.defaultDuration)
        prefs.set(["end": Date().addingTimeInterval(-60).timeIntervalSinceReferenceDate],
                  forKey: Key.keepAwakeSessionEnd)
        let autoStart = relaunch()
        expect(autoStart.isActive && autoStart.sessionTrigger == .launch && autoStart.sessionMinutes == 30,
               "an expired manual record allows a fresh start at launch with the default preset")
        autoStart.extend(minutes: 15)
        expect(prefs.object(forKey: Key.keepAwakeSessionEnd) == nil,
               "starting at launch and extending its timer create no manual record")
        prefs.set(false, forKey: Key.keepAwakeAutoStart)
        autoStart.deactivate(reason: .quit); C.drain()
        expect(!relaunch().isActive, "turning off start at launch takes effect on the next restart")
    }

    private static func batteryProtection(expect: (Bool, String) -> Void) {
        let timed = C.reset()
        timed.activate(minutes: 30)
        timed.deactivate(reason: .quit); C.drain()
        prefs.set(true, forKey: Key.keepAwakeAutoStart)
        prefs.set(10, forKey: Key.batteryLimit)
        let aboveLimit = relaunch { _ in C.SystemInfo.battery = (true, 11) }
        expect(aboveLimit.isActive && aboveLimit.sessionTrigger == .manual && aboveLimit.batteryTimer != nil,
               "a saved manual session above the battery limit takes precedence over start at launch")
        aboveLimit.deactivate(reason: .quit); C.drain()
        var batteryEnds = 0
        let atLimit = relaunch { service in
            C.SystemInfo.battery = (true, 10)
            service.passwordlessClamshell = false
            C.Sudoers.configured = false
            service.onSessionEnded = { if $0 == .battery { batteryEnds += 1 } }
        }
        expect(batteryEnds == 1 && !atLimit.isActive && !atLimit.assertionsHeld && atLimit.endTimer == nil
               && atLimit.batteryTimer == nil && prefs.object(forKey: Key.keepAwakeSessionEnd) == nil
               && C.Sudoers.installCompletions.isEmpty,
               "battery protection ends the restore once without retrying start at launch or starting lid setup")
    }

    private static func delayedRecovery(expect: (Bool, String) -> Void) {
        func pendingLaunch() -> C.Service {
            let running = C.reset()
            running.activate(minutes: 0)
            prefs.set(true, forKey: Key.sleepDisabledFlag)
            prefs.set(true, forKey: Key.keepAwakeAutoStart)
            return relaunch { _ in
                C.Sudoers.disabled = true
                C.Sudoers.results = [false]
            }
        }
        let running = C.reset()
        running.activate(minutes: 0)
        C.AppFeature.keepAwake.isAvailable = false
        running.syncWithFeatures()
        expect(!running.isActive && !running.assertionsHeld && prefs.object(forKey: Key.keepAwakeSessionEnd) == nil,
               "removing an active feature ends its session and clears the record")

        let closing = C.reset()
        closing.activate(minutes: 30)
        closing.deactivate(reason: .quit); C.drain()
        let unavailable = relaunch { _ in C.AppFeature.keepAwake.isAvailable = false }
        expect(!unavailable.isActive && prefs.object(forKey: Key.keepAwakeSessionEnd) == nil,
               "a cold launch with the feature disabled discards the saved session")

        let waiting = pendingLaunch()
        expect(!waiting.recoveryCompleted && C.AdminShell.prompts == 1, "launch recovery is waiting for authorization")
        C.AppFeature.keepAwake.isAvailable = false
        waiting.syncWithFeatures()
        C.AppFeature.keepAwake.isAvailable = true
        waiting.syncWithFeatures()
        C.AdminShell.answer(true); C.drain()
        expect(waiting.recoveryCompleted && !waiting.isActive && prefs.object(forKey: Key.keepAwakeSessionEnd) == nil,
               "removing and reinstalling Keep Awake during recovery cancels that launch's pending session")
        let nextLaunch = relaunch()
        expect(nextLaunch.sessionTrigger == .launch, "a later launch still honors the enabled start-at-launch preference")

        let stopped = pendingLaunch()
        stopped.activate(minutes: 15)
        stopped.toggle()
        C.AdminShell.answer(true); C.drain()
        expect(stopped.recoveryCompleted && !stopped.isActive && prefs.object(forKey: Key.keepAwakeSessionEnd) == nil,
               "a deliberate stop while recovery is pending wins over both restore and start at launch")
    }

    static func run(expect: (Bool, String) -> Void) {
        let switching = C.reset()
        switching.activate(minutes: 15)
        switching.activate(until: Date().addingTimeInterval(3600))
        expect(switching.isActive && switching.sessionMinutes == nil && switching.endDate != nil,
               "an end time replacing a preset session leaves no duration chip selected")
        switching.activate(minutes: 30)
        expect(switching.sessionMinutes == 30,
               "a preset replacing an end-time session selects that preset")
        switching.deactivate(reason: .manual); C.drain()

        let lastPick = C.reset()
        let end = Date().addingTimeInterval(3600)
        lastPick.activate(until: end)
        lastPick.deactivate(reason: .manual); C.drain()
        lastPick.startLastPick()
        expect(lastPick.endDate == end && lastPick.sessionMinutes == nil,
               "the switch restarts a started end time unchanged")
        lastPick.activate(minutes: 30)
        lastPick.deactivate(reason: .manual); C.drain()
        lastPick.startLastPick()
        expect(lastPick.sessionMinutes == 30,
               "a preset started from any entry point is what the switch restarts")
        lastPick.deactivate(reason: .manual); C.drain()
        prefs.set(true, forKey: Key.keepAwakeSwitchUsesUntil)
        prefs.set(Date().addingTimeInterval(-60).timeIntervalSinceReferenceDate, forKey: Key.keepAwakeUntilTime)
        lastPick.startLastPick()
        expect(lastPick.sessionMinutes == 30,
               "an end time that already passed restarts the saved duration, not a session into tomorrow")
        lastPick.resumeAfterSystemTeardown(); C.drain()
        expect(lastPick.isActive && lastPick.sessionMinutes == 30,
               "clearing permissions keeps the running preset selected")
        lastPick.deactivate(reason: .manual); C.drain()

        manualSessions(expect: expect)
        launchAndAutomation(expect: expect)
        batteryProtection(expect: expect)
        delayedRecovery(expect: expect)

        let staleStatus = C.reset(); staleStatus.isActive = true
        staleStatus.refreshPasswordlessStatus()
        staleStatus.enableClamshell()
        C.DispatchQueue.native.flush(); C.DispatchQueue.main.flush()
        C.Sudoers.configured = false
        C.DispatchQueue.background.flush(); C.DispatchQueue.main.flush()
        expect(staleStatus.passwordlessClamshell,
               "a status request from before a newer enable cannot overwrite that operation's verified result")

        let retainedRule = active(); C.Sudoers.disabled = false
        retainedRule.resumeAfterSystemTeardown(); C.drain()
        expect(retainedRule.clamshellActive && C.Sudoers.disabled && C.Sudoers.calls == [true]
               && C.Sudoers.installCompletions.isEmpty
               && C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag),
               "a teardown that stopped rearms the active session through a rule that remained installed")

        let removedRule = active(); C.Sudoers.disabled = false; C.Sudoers.configured = false
        removedRule.resumeAfterSystemTeardown()
        expect(!removedRule.clamshellActive && !removedRule.passwordlessClamshell,
               "a teardown discards the stale closed-lid session at once")
        C.drain()
        expect(C.Sudoers.installCompletions.isEmpty && C.Sudoers.calls.isEmpty && C.AdminShell.prompts == 0
               && !C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag)
               && removedRule.clamshellPreferred && !removedRule.clamshellSetupFailed,
               "a removed rule is not requested again right after the teardown, and a confirmed restore clears the marker")
        removedRule.deactivate(reason: .manual); C.drain()
        expect(C.Sudoers.calls.isEmpty && C.AdminShell.prompts == 0,
               "ending that session asks for nothing, since sleep is already back on")
        removedRule.activate(end: nil, trigger: .manual); C.drain()
        expect(C.Sudoers.installCompletions.count == 1,
               "the next session requests the removed rule the usual way")
        C.Sudoers.configured = true
        C.Sudoers.installCompletions.removeFirst()(true); C.drain()
        expect(removedRule.clamshellActive && C.Sudoers.disabled && C.Sudoers.calls == [true],
               "successful rule setup enables closed-lid mode for that session")

        let rearmedDuringRemoval = active(); C.Sudoers.configured = false
        rearmedDuringRemoval.resumeAfterSystemTeardown(); C.drain()
        expect(!rearmedDuringRemoval.clamshellActive && C.Sudoers.installCompletions.isEmpty
               && C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag),
               "sleep turned off again while the rule was being removed keeps its recovery marker")
        rearmedDuringRemoval.deactivate(reason: .manual); C.drain()
        expect(C.Sudoers.calls == [false] && !C.Sudoers.disabled
               && !C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag),
               "ending the session still restores sleep that remained off")

        let unreadableReport = active(); C.Sudoers.disabled = false; C.Sudoers.configured = false; C.Shell.status = 1
        unreadableReport.resumeAfterSystemTeardown(); C.drain()
        expect(C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag),
               "an unreadable sleep report does not drop the recovery marker")
        C.Shell.status = 0

        let pendingSetup = active(); C.Sudoers.disabled = false; C.Sudoers.configured = false
        pendingSetup.prepareClamshellPreference(); C.drain()
        pendingSetup.resumeAfterSystemTeardown(); C.drain()
        expect(C.Sudoers.installCompletions.count == 1,
               "a teardown keeps one pending rule authorization instead of asking twice")
        C.Sudoers.configured = true
        C.Sudoers.installCompletions.removeFirst()(true); C.drain()
        expect(pendingSetup.clamshellActive && C.Sudoers.disabled,
               "the pending authorization can restore the closed-lid session")

        let pendingRestore = active(); C.Sudoers.results = [false, true]
        pendingRestore.deactivate(reason: .manual); C.drain()
        pendingRestore.activate(end: nil, trigger: .manual); C.drain()
        C.Sudoers.disabled = false
        pendingRestore.resumeAfterSystemTeardown(); C.drain()
        expect(!pendingRestore.clamshellActive && C.Sudoers.calls == [false]
               && !C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag),
               "a teardown waits for an older authorized restore before rearming")
        C.AdminShell.answer(true); C.drain()
        expect(pendingRestore.clamshellActive && C.Sudoers.disabled && C.Sudoers.calls == [false, true],
               "the older restore cannot silently turn off a session that has already rearmed")

        let quitting = active()
        var endedBeforeSleep = false
        C.onSleep = { endedBeforeSleep = !quitting.isActive && !quitting.assertionsHeld && !C.Sudoers.disabled }
        quitting.deactivate(reason: .quit)
        expect(C.calls == 1 && endedBeforeSleep && C.Thread.waits == 0,
               "quit restores the system and ends the session before requesting lid sleep synchronously")
        expect(!C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag) && C.AdminShell.prompts == 0,
               "successful quit clears recovery before returning and never asks for a password")

        for policy in [true, false, nil] as [Bool?] {
            let cutoff = active()
            C.connectedToPower = false
            C.externalDisplay = nil
            C.policy = policy
            cutoff.deactivate(reason: .battery)
            C.drain()
            let expectedCalls = policy == true ? 1 : 0
            expect(!C.Sudoers.disabled && C.calls == expectedCalls,
                   "with an unreadable display list the battery cutoff follows the lid policy \(String(describing: policy))")
        }

        for display in [true, false, nil] as [Bool?] {
            let timed = active()
            C.connectedToPower = nil
            C.externalDisplay = display
            timed.deactivate(reason: .timer)
            C.drain()
            let expectedCalls = display == false ? 1 : 0
            expect(!C.Sudoers.disabled && C.calls == expectedCalls,
                   "with unknown power the timer needs a confirmed absence of external displays, got \(String(describing: display))")
        }

        for lid in [false, nil] as [Bool?] {
            let service = active(); C.BrightnessService.lid = lid
            service.deactivate(reason: .quit)
            expect(C.calls == 0 && C.Thread.waits == 0 && !C.Sudoers.disabled,
                   "quit with an open or unknown lid restores normally without sleep or retry waits")
        }
        let plain = C.reset()
        plain.deactivate(reason: .quit)
        expect(C.calls == 0 && C.Sudoers.calls.isEmpty && C.Thread.waits == 0,
               "quit without an owned override or pending lid sleep changes no system power state")

        let refused = active(); C.results = [1]
        refused.deactivate(reason: .quit)
        expect(C.calls == 10 && C.Thread.waits == 9 && C.DispatchQueue.main.pending.isEmpty,
               "quit completes at most ten refused sleep attempts before returning, without a lost async retry")
        let transient = active(); C.results = [1, 1, 0]
        transient.deactivate(reason: .quit)
        expect(C.calls == 3 && C.Thread.waits == 2,
               "quit stops waiting as soon as a transiently refused request succeeds")

        for change in 0..<4 {
            let service = active(); C.results = [1]
            C.Thread.onWait = {
                switch change {
                case 0: C.BrightnessService.lid = false
                case 1: C.policy = false
                case 2: C.assertions = [["AssertType": "PreventSystemSleep", "AssertLevel": 1, "AppliesOnLidClose": true]]
                default: C.assertions = nil
                }
            }
            service.deactivate(reason: .quit)
            expect(C.calls == 1 && C.Thread.waits == 1,
                   "every synchronous retry observes newly opened lids and external protections")
        }

        let failed = active(); C.Sudoers.results = [false]
        failed.deactivate(reason: .quit)
        expect(C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag)
               && C.calls == 0 && C.AdminShell.prompts == 0,
               "failed silent quit keeps recovery evidence and does not bypass native sleep protection")

        let enabling = C.reset(); enabling.isActive = true
        enabling.enableClamshell()
        expect(C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag),
               "an in-flight enable is recorded before its native command or main reply finishes")
        enabling.deactivate(reason: .quit)
        C.DispatchQueue.main.flush()
        expect(C.Sudoers.calls == [true, false] && !C.Sudoers.disabled && !enabling.clamshellActive
               && !C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag),
               "quit drains a pending enable and an obsolete reply cannot resurrect its override or marker")

        let between = active(); C.results = [1, 0]
        between.deactivate(reason: .timer)
        C.drain()
        expect(C.calls == 1 && !C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag),
               "a timer can restore the override while its first lid-sleep request is refused")
        between.deactivate(reason: .quit)
        expect(C.calls == 2, "quit finishes already pending lid sleep even after the override marker was cleared")
        C.DispatchQueue.main.advance()
        expect(C.calls == 2, "a queued retry cannot repeat sleep after quit consumed it")

        let renewed = active(); C.results = [1]
        renewed.deactivate(reason: .timer)
        C.drain()
        renewed.clamshellPreferred = false
        renewed.activate(end: nil, trigger: .manual)
        renewed.deactivate(reason: .manual)
        C.DispatchQueue.main.advance()
        expect(C.calls == 1, "an old retry cannot sleep a later session even if that session ended before the retry")

        let restoring = active(); C.Sudoers.results = [false, true]
        restoring.deactivate(reason: .manual)
        C.drain()
        restoring.activate(end: nil, trigger: .manual)
        C.drain()
        expect(C.Sudoers.calls == [false] && C.AdminShell.prompts == 1,
               "a new session waits while the older restore authorization is pending")
        C.AdminShell.answer(true); C.drain()
        expect(C.Sudoers.calls == [false, true] && C.Sudoers.disabled && restoring.clamshellActive && C.calls == 0,
               "successful delayed restore enables the current session without sleeping or overwriting it")

        let latePrompt = active(); C.Sudoers.results = [false, true]
        latePrompt.deactivate(reason: .manual)
        C.drain()
        latePrompt.deactivate(reason: .quit)
        C.AdminShell.answer(true); C.DispatchQueue.main.flush()
        expect(C.AdminShell.prompts == 1 && C.Sudoers.calls == [false, false] && !C.Sudoers.disabled,
               "quit never waits for or repeats an existing authorization; its late reply cannot re-enable")

        let setup = C.reset(); setup.isActive = true; C.Sudoers.configured = false
        setup.prepareClamshellPreference(); C.drain()
        setup.deactivate(reason: .quit)
        C.Sudoers.installCompletions.forEach { $0(true) }; C.drain()
        expect(!C.Sudoers.calls.contains(true), "successful setup arriving after quit cannot submit an enable")
        let setupProbe = C.reset(); C.Sudoers.configured = false
        setupProbe.prepareClamshellPreference(); setupProbe.deactivate(reason: .quit)
        C.drain()
        expect(C.Sudoers.installCompletions.isEmpty, "a setup probe returning after quit cannot open an authorization prompt")

        let recovering = C.reset(); C.UserDefaults.standard.set(true, forKey: C.DefaultsKey.sleepDisabledFlag)
        C.Sudoers.disabled = true; C.Sudoers.results = [false, true]
        recovering.recoverIfNeeded()
        C.drain()
        recovering.passwordlessClamshell = false
        recovering.activate(end: nil, trigger: .manual)
        C.drain()
        expect(C.Sudoers.calls == [false] && C.Sudoers.installCompletions.isEmpty,
               "launch recovery holds both enable and setup for a new manual session behind its pending off")
        C.AdminShell.answer(true); C.drain()
        expect(C.Sudoers.calls == [false, true] && C.Sudoers.disabled && recovering.clamshellActive,
               "delayed launch recovery completes before the new manual session enables closed-lid mode")

        let unreadable = C.reset(); C.UserDefaults.standard.set(true, forKey: C.DefaultsKey.sleepDisabledFlag)
        C.Shell.status = -1; C.Shell.output = ""; C.Sudoers.results = [false]
        unreadable.recoverIfNeeded(); C.drain()
        C.AdminShell.answer(false); C.DispatchQueue.main.flush()
        expect(C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag),
               "failed power-state reads and refused recovery never erase evidence of an owned override")

        _ = C.reset(); C.Sudoers.disabled = true
        expect(C.Sudoers.isConfigured(), "a probe before authorization verifies the current state")
        let priorWrites = C.Sudoers.probeWrites
        C.Sudoers.restoreSleepWithAuthorization(prompt: "restore", shouldProceed: { true }) { _ in }
        C.drain()
        expect(!C.Sudoers.isConfigured() && C.Sudoers.probeWrites == priorWrites,
               "a pending authorization blocks late probes from reapplying stale disabled-sleep state")
        expect(C.Sudoers.pmsetDisableSleep(false),
               "a silent quit restore can drain the native queue while authorization remains unanswered")
        C.AdminShell.answer(true); C.drain()
        expect(C.Sudoers.isConfigured() && C.Sudoers.probeWrites.last == false && !C.Sudoers.disabled,
               "probes resume only after authorization finishes and then observe the restored state")

        _ = C.reset(); C.Sudoers.disabled = true
        var mayPrompt = true
        C.Sudoers.restoreSleepWithAuthorization(prompt: "restore", shouldProceed: { mayPrompt }) { _ in }
        C.DispatchQueue.native.flush()
        mayPrompt = false
        C.drain()
        expect(C.AdminShell.prompts == 0 && C.Sudoers.sleepStateProbeSuspensions == 0,
               "authorization revalidates on the main thread and releases probe suspension after cancellation")

        let deniedSetup = C.reset(); deniedSetup.isActive = true
        C.Sudoers.results = [false]; C.Sudoers.configured = false
        deniedSetup.enableClamshell(); C.drain()
        expect(C.Sudoers.installCompletions.count == 1,
               "a failed enable offers its one passwordless setup repair")
        C.Sudoers.installCompletions.forEach { $0(false) }; C.drain()
        expect(!deniedSetup.clamshellPreferred && deniedSetup.clamshellSetupFailed
               && C.AdminShell.prompts == 0 && !C.Sudoers.disabled
               && !C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag),
               "denying repair does not ask for another password when the failed enable left sleep enabled")

        _ = C.reset()
        var alreadyRestored = false
        C.Sudoers.restoreSleepWithAuthorization(prompt: "restore", shouldProceed: { true }) { alreadyRestored = $0 }
        C.drain()
        expect(alreadyRestored && C.AdminShell.prompts == 0 && C.Sudoers.sleepStateProbeSuspensions == 0,
               "a confirmed already-restored override succeeds without authorization and releases probes")
        _ = C.reset(); C.Shell.status = -1; C.Shell.output = ""
        C.Sudoers.restoreSleepWithAuthorization(prompt: "restore", shouldProceed: { true }) { _ in }
        C.drain()
        expect(C.AdminShell.prompts == 1 && C.Sudoers.sleepStateProbeSuspensions == 1,
               "an unreadable power report cannot bypass the normal restore authorization")
        C.AdminShell.answer(false); C.drain()

        let staleSetup = active(); C.Sudoers.configured = false
        staleSetup.prepareClamshellPreference(); C.drain()
        C.Sudoers.results = [false]
        staleSetup.deactivate(reason: .manual); C.drain()
        C.Sudoers.configured = true
        C.Sudoers.installCompletions.forEach { $0(true) }; C.drain()
        expect(staleSetup.clamshellPreferred && C.AdminShell.prompts == 1,
               "a setup reply invalidated by restore cannot open another prompt or turn off the saved preference")
        C.BrightnessService.lid = false
        C.AdminShell.answer(true); C.drain()
        expect(!C.Sudoers.disabled && !C.UserDefaults.standard.bool(forKey: C.DefaultsKey.sleepDisabledFlag),
               "late setup probes cannot resurrect the override cleared by authorized restore")
    }
}
