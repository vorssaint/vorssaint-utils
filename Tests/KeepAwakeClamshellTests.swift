// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

extension KeepAwakeLidSleepContract {
    enum EndReason { case manual, timer, battery, quit }
    enum SessionTrigger { case manual, automation }
    enum AppFeature {
        enum keepAwake { static let isAvailable = true }
    }
    enum DefaultsKey {
        static let clamshellPreferred = "preferred"
        static let sleepDisabledFlag = "disabled"
        static let keepAwakePauseWhenLocked = "pause"
        static let dimScreenOnLidClose = "dimScreen"
        static let dimmedDisplaySavedBrightness = "dimmedDisplaySavedBrightness"
        static let defaultDuration = "defaultDuration"
        static let keepAwakeSwitchUsesUntil = "switchUsesUntil"
        static let keepAwakeUntilTime = "untilTime"
    }
    enum UserDefaults {
        static let standard = Store()
        final class Store {
            var values: [String: Bool] = [:]
            var doubles: [String: Double] = [:]
            var integers: [String: Int] = [:]
            func bool(forKey key: String) -> Bool { values[key] ?? false }
            func set(_ value: Bool, forKey key: String) { values[key] = value }
            func set(_ value: Double, forKey key: String) { doubles[key] = value }
            func set(_ value: Int, forKey key: String) { integers[key] = value }
            func integer(forKey key: String) -> Int { integers[key] ?? 0 }
            func double(forKey key: String) -> Double { doubles[key] ?? 0 }
            func object(forKey key: String) -> Any? { doubles[key] }
            func removeObject(forKey key: String) { doubles[key] = nil }
        }
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
    enum NSSound {
        static var beeps = 0
        static func beep() { beeps += 1 }
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

    private static func active() -> C.Service {
        let service = C.reset()
        service.isActive = true; service.clamshellActive = true; service.assertionsHeld = true
        C.Sudoers.disabled = true
        C.UserDefaults.standard.set(true, forKey: C.DefaultsKey.sleepDisabledFlag)
        return service
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

        typealias prefs = KeepAwakeLidSleepContract.UserDefaults
        typealias Key = KeepAwakeLidSleepContract.DefaultsKey
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
        prefs.standard.set(true, forKey: Key.keepAwakeSwitchUsesUntil)
        prefs.standard.set(Date().addingTimeInterval(-60).timeIntervalSinceReferenceDate,
                                  forKey: Key.keepAwakeUntilTime)
        lastPick.startLastPick()
        expect(lastPick.sessionMinutes == 30,
               "an end time that already passed restarts the saved duration, not a session into tomorrow")
        lastPick.resumeAfterSystemTeardown(); C.drain()
        expect(lastPick.isActive && lastPick.sessionMinutes == 30,
               "clearing permissions keeps the running preset selected")
        lastPick.deactivate(reason: .manual); C.drain()
        prefs.standard.integers = [:]
        prefs.standard.set(false, forKey: Key.keepAwakeSwitchUsesUntil)
        prefs.standard.removeObject(forKey: Key.keepAwakeUntilTime)

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

        let sleepNow = active(); sleepNow.sessionTrigger = .automation; sleepNow.automationHolds = true
        C.BrightnessService.lid = false; C.policy = false; C.results = [1, 0]
        sleepNow.sleepNow()
        expect(sleepNow.isActive && sleepNow.sessionPausedForScreenLock && !sleepNow.assertionsHeld
               && !sleepNow.automationSuppressedUntilConditionsClear && C.calls == 0,
               "Sleep now pauses an automatic session and waits for the closed-lid restore")
        C.drain()
        expect(C.calls == 1 && !C.Sudoers.disabled,
               "Sleep now requests sleep once the restore succeeds, whatever the lid and lid policy say")
        C.DispatchQueue.main.advance()
        expect(C.calls == 2, "a refused Sleep now retries while powerd catches up with the cleared flag")
        sleepNow.resumeAfterSleepNow(); C.drain()
        expect(sleepNow.isActive && !sleepNow.sessionPausedForScreenLock && sleepNow.assertionsHeld
               && sleepNow.clamshellActive && C.Sudoers.disabled,
               "waking resumes the paused session with closed-lid mode")
        sleepNow.deactivate(reason: .manual); C.drain()

        let lockedOnWake = active(); let wakeEnd = Date().addingTimeInterval(600); lockedOnWake.endDate = wakeEnd
        C.UserDefaults.standard.set(true, forKey: C.DefaultsKey.keepAwakePauseWhenLocked)
        lockedOnWake.sleepNow(); C.drain()
        lockedOnWake.screenLocked = true; lockedOnWake.syncSessionWithScreenLock()
        lockedOnWake.resumeAfterSleepNow(); C.drain()
        expect(lockedOnWake.isActive && lockedOnWake.sessionPausedForScreenLock
               && !lockedOnWake.assertionsHeld && !lockedOnWake.clamshellActive,
               "a screen locked on wake keeps the Sleep now pause until unlock")
        lockedOnWake.screenLocked = false; lockedOnWake.syncSessionWithScreenLock(); C.drain()
        expect(lockedOnWake.assertionsHeld && lockedOnWake.clamshellActive && lockedOnWake.endDate == wakeEnd,
               "unlocking resumes the session with its original end time")
        lockedOnWake.deactivate(reason: .manual); C.drain()

        let expired = active(); expired.endDate = Date().addingTimeInterval(-1)
        expired.sleepNow(); C.drain()
        expired.resumeAfterSleepNow(); C.drain()
        expect(!expired.isActive && !expired.clamshellActive && !C.Sudoers.disabled,
               "a timed session whose end passed during sleep ends on wake")

        let cancelled = active()
        cancelled.sleepNow()
        cancelled.activate(minutes: 15); C.drain()
        expect(C.calls == 0 && cancelled.isActive && cancelled.clamshellActive
               && !cancelled.sessionPausedForScreenLock,
               "a session started before the restore finishes cancels the pending Sleep now")
        cancelled.deactivate(reason: .manual); C.drain()

        let sleepNowFailed = active(); C.Sudoers.results = [false, true]
        sleepNowFailed.sleepNow(); C.drain()
        C.AdminShell.answer(false); C.drain()
        expect(C.calls == 0 && C.NSSound.beeps == 1 && sleepNowFailed.isActive
               && !sleepNowFailed.sessionPausedForScreenLock && sleepNowFailed.assertionsHeld,
               "a failed restore beeps, never requests sleep and resumes the session")
        sleepNowFailed.deactivate(reason: .manual); C.drain(); C.AdminShell.answer(false); C.drain()

        let stillDisabled = C.reset()
        C.UserDefaults.standard.set(true, forKey: C.DefaultsKey.sleepDisabledFlag)
        stillDisabled.sleepNow()
        expect(C.calls == 0 && C.NSSound.beeps == 1, "Sleep now beeps while sleep is still disabled")

        let sleepNowPlain = C.reset(); sleepNowPlain.isActive = true; C.BrightnessService.lid = false
        sleepNowPlain.sleepNow()
        expect(sleepNowPlain.isActive && sleepNowPlain.sessionPausedForScreenLock && C.calls == 1,
               "without closed-lid mode Sleep now pauses the session and sleeps right away")

        let sleepRefused = C.reset(); sleepRefused.isActive = true; sleepRefused.assertionsHeld = true; C.results = [1]
        sleepRefused.sleepNow()
        for _ in 0..<9 { C.DispatchQueue.main.advance() }
        expect(C.calls == 10 && sleepRefused.isActive && !sleepRefused.sessionPausedForScreenLock
               && sleepRefused.assertionsHeld,
               "a sleep refused to the end resumes the session")
    }
}
