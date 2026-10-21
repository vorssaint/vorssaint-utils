// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Resuming fan control after a restart or wake runs the production decisions
/// against doubles: nothing here can reach the helper or the fans.
enum FanControlResumeContract {
    enum Environment {
        static var available = true
    }
    enum AppFeature {
        case fanControl
        var isAvailable: Bool { Environment.available }
    }
    enum UserDefaults {
        static let standard = Store()
        final class Store {
            var values: [String: Any] = [:]
            func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
            func string(forKey key: String) -> String? { values[key] as? String }
            func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
            func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
            func set(_ value: Any?, forKey key: String) { values[key] = value }
            func removeObject(forKey key: String) { values[key] = nil }
        }
    }
    final class Invalidating {
        var invalidated = false
        func invalidate() { invalidated = true }
    }
    /// The helper end of a request: it records what it was asked to do,
    /// and its reply arrives only when a test delivers one.
    protocol FanControlXPCProtocol {
        func applyConfiguration(_ configuration: Data, withReply reply: @escaping (Data) -> Void)
        func restoreAutomatic(withReply reply: @escaping (Data) -> Void)
    }
    enum FanControlIPC {
        static func encode(_ configuration: FanControlConfiguration) -> Data? {
            try? JSONEncoder().encode(configuration)
        }
    }
    final class Helper: FanControlXPCProtocol {
        var applied: [FanControlConfiguration] = []
        var requests: [String] = []
        func applyConfiguration(_ configuration: Data, withReply reply: @escaping (Data) -> Void) {
            requests.append("apply")
            if let decoded = try? JSONDecoder().decode(FanControlConfiguration.self, from: configuration) {
                applied.append(decoded)
            }
        }
        func restoreAutomatic(withReply reply: @escaping (Data) -> Void) { requests.append("restore") }
    }
    struct AppService {
        func unregister() throws {}
    }
    class Fixture {
        enum AccessState { case notRegistered, requiresApproval, enabled, unavailable }
        /// Counts every reach for the service, which on a real launch
        /// creates it and asks Service Management for the helper's status.
        static var sharedReaches = 0
        private static let instance = Service()
        static var shared: Service {
            sharedReaches += 1
            return instance
        }
        static var helperVersion = "bundled"
        var accessState = AccessState.enabled
        var snapshot = FanControlSnapshot.empty
        var panelIsVisible = false
        var timer: Invalidating?
        var connection: Invalidating?
        var observing = true
        var timedManual: FanControlTimedManual?
        var error: FanControlErrorCode?
        var isWorking = false
        var requestGeneration = 0
        let helper = Helper()
        var pendingReplies: [(FanControlResponse?) -> Void] = []
        var applied: [FanControlConfiguration] {
            get { helper.applied }
            set { helper.applied = newValue }
        }
        /// What the helper was asked to do, in order: "apply" or "restore".
        var requests: [String] { helper.requests }
        var events: [String] = []
        static var appService: AppService { AppService() }
        func refreshAccessState() {}
        func authorize() { events.append("authorize") }
        func startObservingSystemState() { observing = true }
        func startTimerIfNeeded() {}
        func send(_ operation: (FanControlXPCProtocol, @escaping (Data) -> Void) -> Void,
                  completion: @escaping (FanControlResponse?) -> Void) {
            operation(helper) { _ in }
            pendingReplies.append(completion)
        }
        func beginRequest() -> Int {
            requestGeneration += 1
            return requestGeneration
        }
        func finishRequest(_ generation: Int) -> Bool { generation == requestGeneration }
        func restoreThenUnregister() { events.append("unregister") }
        func refresh() { events.append("refresh") }
        func stopObservingSystemState() { observing = false }

        /// The oldest request's reply arrives, or none when nil.
        func reply(_ response: FanControlResponse?) {
            guard !pendingReplies.isEmpty else { return }
            pendingReplies.removeFirst()(response)
        }

        /// A fresh process with nothing in flight, as at launch.
        func resetDoubles() {
            accessState = .enabled
            snapshot = .empty
            panelIsVisible = false
            timer = Invalidating()
            connection = Invalidating()
            observing = true
            error = nil
            isWorking = false
            requestGeneration = 0
            pendingReplies = []
            applied = []
            helper.requests = []
            events = []
        }
    }

    static func run(_ suite: TestSuite) {
        let service = Service.shared
        let defaults = UserDefaults.standard
        let manual = FanControlConfiguration.manual(level: 100)
        func reset(resume: Bool = true, stored: FanControlConfiguration? = manual,
                   recovery: Bool = false) {
            Environment.available = true
            defaults.values = [:]
            defaults.values[DefaultsKey.fanControlResume] = resume
            defaults.values[DefaultsKey.fanControlRecoveryNeeded] = recovery
            defaults.values[DefaultsKey.fanControlMode] = FanControlMode.manual.rawValue
            if let stored {
                defaults.values[DefaultsKey.fanControlResumeConfiguration] =
                    FanControlConfiguration.encodeResume(stored)
            }
            service.resetDoubles()
            service.timedManual = nil
        }
        var storedResume: String? { defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) }

        reset(resume: false, stored: nil)
        Service.sharedReaches = 0
        Service.recoverIfNeeded()
        suite.expect(Service.sharedReaches == 0,
                     "a launch with no kept control, stored end or recovery never loads the fan control service")
        reset(resume: false, recovery: true)
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.requests == ["restore"],
                     "without resume, a launch after an interrupted session only returns the fans to the system")
        reset(recovery: true)
        Service.recoverIfNeeded()
        suite.expect(service.applied == [manual] && service.requests == ["apply"],
                     "with resume on, a launch re-applies the kept control instead of restoring first")
        reset()
        service.accessState = .requiresApproval
        Service.recoverIfNeeded()
        suite.expect(service.requests.isEmpty && service.events.isEmpty,
                     "a resume never asks for helper approval on its own")
        reset()
        Environment.available = false
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty, "a feature removed from the hub resumes nothing")
        reset()
        defaults.values[DefaultsKey.fanControlResumeConfiguration] =
            #"{"curves":[],"manualLevel":100,"mode":"system"}"#
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty, "a damaged or System value is never re-applied")
        reset()
        defaults.values[DefaultsKey.fanControlMode] = FanControlMode.system.rawValue
        Service.recoverIfNeeded()
        service.workspaceDidWake()
        service.stopIdleWorkIfPossible()
        suite.expect(service.applied.isEmpty && !service.observing,
                     "picking System in the card, with the fans already back there, is never undone by a resume")
        reset()
        defaults.values[DefaultsKey.fanControlHelperVersion] = "registered before the update"
        Service.recoverIfNeeded()
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty,
                     "a helper replaced by an update is registered anew before any resume holds the fans")
        reset()
        defaults.values[DefaultsKey.fanControlHelperVersion] = Service.helperVersion
        Service.recoverIfNeeded()
        suite.expect(service.applied == [manual], "the registered helper resumes as before")

        reset(resume: false, stored: nil)
        service.rememberForResume(manual)
        suite.expect(storedResume == nil, "applied control is not kept while resume is off")
        reset(stored: nil)
        service.rememberForResume(.manual(level: 60))
        suite.expect(FanControlConfiguration.decodeResume(storedResume ?? "") == .manual(level: 60),
                     "applied control is kept while resume is on")

        reset(stored: nil)
        service.snapshot.isCooling = true
        service.snapshot.configuration = manual
        service.resumePreferenceDidChange()
        suite.expect(FanControlConfiguration.decodeResume(storedResume ?? "") == manual,
                     "turning resume on keeps the control already running")
        defaults.values[DefaultsKey.fanControlResume] = false
        service.resumePreferenceDidChange()
        suite.expect(storedResume == nil, "turning resume off forgets the kept control")
        reset(stored: nil)
        service.resumePreferenceDidChange()
        suite.expect(storedResume == nil, "turning resume on with the fans on System keeps nothing")
        reset()
        service.resumePreferenceDidChange()
        suite.expect(storedResume == nil,
                     "turning resume on with the fans on System drops an older kept control, such as a restored one")

        reset()
        service.returnToSystem()
        suite.expect(storedResume == nil && service.requests == ["restore"],
                     "returning to System forgets the kept control and restores the fans")

        reset()
        service.stopIdleWorkIfPossible()
        suite.expect(service.timer == nil && service.connection == nil && service.observing,
                     "idle work stops while a pending resume keeps watching for the next wake")
        reset(resume: false)
        service.stopIdleWorkIfPossible()
        suite.expect(!service.observing, "without a pending resume the sleep observers stop too")

        reset()
        service.workspaceDidWake()
        suite.expect(service.applied == [manual] && service.requests == ["apply"],
                     "waking re-applies the kept control")
        reset(resume: false, recovery: true)
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.requests == ["restore"],
                     "without resume, waking still returns an interrupted session to the system")
        reset(resume: false)
        service.panelIsVisible = true
        service.workspaceDidWake()
        suite.expect(service.requests.isEmpty && service.events == ["refresh"],
                     "without resume, waking only refreshes a visible panel")

        reset()
        Environment.available = false
        service.syncWithPreferences()
        suite.expect(storedResume == nil && service.events == ["unregister"],
                     "removing the feature forgets the kept control before unregistering the helper")
        runTimedManual(suite)
        reset()
    }

    /// A timed manual speed ends through the ordinary return to System, and
    /// nothing (a wake, a launch, a failed or superseded request, a clock
    /// moved back) may keep it running or bring it back without its end.
    static func runTimedManual(_ suite: TestSuite) {
        let service = Service.shared
        let defaults = UserDefaults.standard
        let manual = FanControlConfiguration.manual(level: 100)
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func reset(resume: Bool = true, timed: FanControlTimedManual?, recovery: Bool = false,
                   mode: FanControlMode = .manual) {
            Environment.available = true
            defaults.values = [:]
            defaults.values[DefaultsKey.fanControlResume] = resume
            defaults.values[DefaultsKey.fanControlRecoveryNeeded] = recovery
            defaults.values[DefaultsKey.fanControlMode] = mode.rawValue
            defaults.values[DefaultsKey.fanControlResumeConfiguration] =
                FanControlConfiguration.encodeResume(manual)
            service.resetDoubles()
            service.timedManual = nil
            service.rememberTimedManual(timed)
        }
        /// A new launch: nothing in flight, the timed speed read back from
        /// this Mac's defaults.
        func relaunch() {
            service.resetDoubles()
            service.timedManual = Service.storedTimedManual
        }
        var storedResume: String? { defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) }
        var storedEnd: Double { defaults.double(forKey: DefaultsKey.fanControlManualEnd) }
        var storedMinutes: Int { defaults.integer(forKey: DefaultsKey.fanControlManualEndMinutes) }
        var storedMode: String? { defaults.string(forKey: DefaultsKey.fanControlMode) }
        let fan = FanControlFanReading(index: 0, actualRPM: 2_000, minimumRPM: 1_200,
                                       maximumRPM: 6_000, targetRPM: 2_000, isManuallyControlled: false)
        var onSystem = FanControlSnapshot.empty
        onSystem.fans = [fan]
        var cooling = onSystem
        cooling.isCooling = true
        cooling.configuration = manual

        let tenMinutes = FanControlManualDuration.timed(minutes: 10, from: now)
        suite.expect(tenMinutes == FanControlTimedManual(end: now.addingTimeInterval(600), minutes: 10)
                && FanControlManualDuration.timed(minutes: 60, from: now)?.end == now.addingTimeInterval(3_600)
                && FanControlManualDuration.timed(minutes: FanControlManualDuration.untilChanged,
                                                  from: now) == nil,
               "a timed manual speed ends after the picked minutes; until I change it has no end")
        suite.expect(FanControlManualDuration.timed(minutes: 7, from: now) == nil
                && FanControlManualDuration.timed(minutes: -5, from: now) == nil
                && FanControlManualDuration.validated(7) == FanControlManualDuration.untilChanged
                && FanControlManualDuration.validated(30) == 30,
               "an unknown duration, such as one restored from a backup, keeps the untimed behavior")
        suite.expect(FanControlManualDuration.choices.first == 5
                && FanControlManualDuration.choices.last == FanControlManualDuration.untilChanged
                && Defaults.registeredDefaults[DefaultsKey.fanControlManualMinutes] as? Int
                    == FanControlManualDuration.untilChanged,
               "manual speed stays until changed by default, offered after the timed chips")
        let backupKeys = SettingsBackupSupport.exportKeys()
        suite.expect(backupKeys.contains(DefaultsKey.fanControlManualMinutes)
                && !backupKeys.contains(DefaultsKey.fanControlManualEnd)
                && !backupKeys.contains(DefaultsKey.fanControlManualEndMinutes),
               "the picked duration travels with a backup while the running end and its minutes stay on this Mac")

        let end = now.addingTimeInterval(600)
        let timed = FanControlTimedManual(end: end, minutes: 10)
        suite.expect(!FanControlManualDuration.hasEnded(timed, now: now.addingTimeInterval(599))
                && FanControlManualDuration.hasEnded(timed, now: end)
                && FanControlManualDuration.hasEnded(timed, now: now.addingTimeInterval(7_200)),
               "a timed speed runs until its end, including an end that passed while the Mac slept")
        // A 5 minute speed whose clock moved back 50 minutes right after it
        // started finds its end 55 minutes away.
        suite.expect(FanControlManualDuration.hasEnded(
                    FanControlTimedManual(end: now.addingTimeInterval(55 * 60), minutes: 5), now: now)
                && FanControlManualDuration.hasEnded(
                    FanControlTimedManual(end: now.addingTimeInterval(301), minutes: 5), now: now)
                && !FanControlManualDuration.hasEnded(
                    FanControlTimedManual(end: now.addingTimeInterval(300), minutes: 5), now: now)
                && !FanControlManualDuration.hasEnded(
                    FanControlTimedManual(end: now.addingTimeInterval(3_600), minutes: 60), now: now),
               "an end further away than its picked minutes, from a clock moved back, counts as ended")
        suite.expect(FanControlManualDuration.hasEnded(
                    FanControlTimedManual(end: now.addingTimeInterval(60), minutes: 0), now: now)
                && FanControlManualDuration.hasEnded(
                    FanControlTimedManual(end: now.addingTimeInterval(60), minutes: 7), now: now),
               "an end without valid minutes has nothing to bound it and counts as ended")

        var curveCooling = cooling
        curveCooling.configuration = .curve([FanControlConfiguration.defaultCurve])
        suite.expect(FanControlManualDuration.runningEnd(timed, snapshot: cooling) == end
                && FanControlManualDuration.runningEnd(timed, snapshot: .empty) == nil
                && FanControlManualDuration.runningEnd(timed, snapshot: curveCooling) == nil
                && FanControlManualDuration.runningEnd(nil, snapshot: cooling) == nil,
               "the countdown shows only while the helper confirms the timed manual speed")
        suite.expect(FanControlManualDuration.controlEndsOnItsOwn(runningEnd: end, isCooling: true,
                                                                  mode: .manual, minutes: 10)
                && FanControlManualDuration.controlEndsOnItsOwn(runningEnd: nil, isCooling: false,
                                                                mode: .manual, minutes: 5),
               "the caption names the picked end while a timed speed runs or is about to be applied")
        suite.expect(!FanControlManualDuration.controlEndsOnItsOwn(runningEnd: nil, isCooling: true,
                                                                   mode: .manual, minutes: 5)
                && !FanControlManualDuration.controlEndsOnItsOwn(runningEnd: nil, isCooling: false,
                                                                 mode: .manual, minutes: 0)
                && !FanControlManualDuration.controlEndsOnItsOwn(runningEnd: nil, isCooling: false,
                                                                 mode: .curve, minutes: 5),
               "a running curve or untimed speed keeps the caption that it stays until System")

        reset(timed: timed)
        service.snapshot = cooling
        suite.expect(!service.expireTimedManualIfNeeded(now: now.addingTimeInterval(599))
                && service.requests.isEmpty && service.timedManual == timed
                && storedEnd == end.timeIntervalSinceReferenceDate && storedMinutes == 10,
               "a timed speed keeps running before its end, stored with its minutes")
        suite.expect(service.expireTimedManualIfNeeded(now: end)
                && service.requests == ["restore"]
                && service.timedManual == nil && storedEnd == 0 && storedMinutes == 0
                && storedResume == nil,
               "at its end a timed speed asks the helper to restore the fans and forgets the kept control")
        service.reply(.success(onSystem))
        suite.expect(service.error == nil && !service.isWorking && !service.snapshot.isCooling,
                     "an end the user picked reports no failure once the fans are back on System")
        suite.expect(storedMode == FanControlMode.system.rawValue,
                     "the card shows System once a timed speed hands the fans back")
        suite.expect(!service.expireTimedManualIfNeeded(now: end.addingTimeInterval(1))
                && service.requests == ["restore"],
               "an ended speed is handed back once")

        reset(timed: FanControlManualDuration.timed(minutes: 5, from: now))
        service.snapshot = cooling
        suite.expect(service.expireTimedManualIfNeeded(now: now.addingTimeInterval(-50 * 60 + 10))
                && service.requests == ["restore"] && storedResume == nil,
               "a 5 minute speed ends at once when the clock moves back 50 minutes right after it starts")

        reset(timed: timed, mode: .curve)
        service.snapshot = cooling
        _ = service.expireTimedManualIfNeeded(now: end)
        suite.expect(storedMode == FanControlMode.curve.rawValue,
                     "a curve picked while the timed speed ran stays picked when it ends")

        reset(timed: nil)
        service.snapshot = cooling
        suite.expect(!service.expireTimedManualIfNeeded(now: now.addingTimeInterval(86_400 * 30))
                && service.requests.isEmpty && storedResume != nil
                && storedMode == FanControlMode.manual.rawValue,
               "a manual speed kept until I change it never ends on its own")

        reset(timed: timed)
        service.returnToSystem()
        suite.expect(service.timedManual == nil && storedEnd == 0 && storedMinutes == 0
                && storedResume == nil && service.requests == ["restore"],
               "returning to System early cancels the timed speed")

        reset(timed: FanControlTimedManual(end: Date().addingTimeInterval(-60), minutes: 5), recovery: true)
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.requests == ["restore"]
                && service.timedManual == nil && storedResume == nil
                && storedMode == FanControlMode.system.rawValue,
               "an end passed during sleep hands the fans back on wake instead of resuming them")
        let remaining = FanControlTimedManual(end: Date().addingTimeInterval(300), minutes: 5)
        reset(timed: remaining)
        service.workspaceDidWake()
        service.reply(.success(cooling))
        suite.expect(service.applied == [manual] && service.timedManual == remaining
                && storedEnd == remaining.end.timeIntervalSinceReferenceDate && storedMinutes == 5
                && FanControlConfiguration.decodeResume(storedResume ?? "") == manual,
               "waking before the end resumes the timed speed for the time it had left, kept with its end")

        reset(timed: FanControlTimedManual(end: Date().addingTimeInterval(-60), minutes: 5), recovery: true)
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.requests == ["restore"]
                && storedResume == nil,
               "a launch after the end restores the system instead of resuming the timed speed")
        reset(timed: remaining)
        relaunch()
        Service.recoverIfNeeded()
        service.reply(.success(cooling))
        suite.expect(service.applied == [manual] && service.timedManual == remaining,
                     "a launch before the end resumes the timed speed without extending it")
        reset(timed: nil)
        Service.recoverIfNeeded()
        service.reply(.success(cooling))
        suite.expect(service.applied == [manual] && service.timedManual == nil
                && FanControlConfiguration.decodeResume(storedResume ?? "") == manual,
               "a kept manual speed without an end resumes untimed, as before")
        reset(timed: nil, recovery: true)
        defaults.values[DefaultsKey.fanControlManualEnd] = Date().addingTimeInterval(300).timeIntervalSinceReferenceDate
        relaunch()
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.requests == ["restore"] && storedResume == nil,
                     "a stored end without its minutes is never resumed as an untimed speed")

        // The kept control and its end leave together while a resume waits
        // for the helper, so no outcome of that request resumes it untimed.
        reset(timed: remaining)
        Service.recoverIfNeeded()
        suite.expect(service.applied == [manual] && storedResume == nil && storedEnd == 0
                && storedMinutes == 0,
               "a timed resume in flight keeps neither the control nor its end")
        service.reply(.failure(.controlFailed))
        relaunch()
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.requests == ["restore"],
                     "a timed resume the helper rejects never comes back untimed on the next launch")

        reset(timed: remaining)
        service.workspaceDidWake()
        service.reply(nil)
        relaunch()
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.requests == ["restore"],
                     "a timed resume that gets no reply never comes back untimed on the next wake")

        reset(timed: remaining)
        service.workspaceDidWake()
        service.workspaceWillSleep()
        service.reply(.success(cooling))
        suite.expect(service.timedManual == nil && storedResume == nil && storedEnd == 0,
                     "a reply that arrives after sleep superseded the timed resume keeps nothing")
        service.workspaceDidWake()
        suite.expect(service.applied == [manual]
                && service.requests == ["apply", "restore", "restore"],
               "a timed resume superseded by sleep never comes back untimed on the next wake")

        reset(timed: remaining)
        Service.recoverIfNeeded()
        relaunch()
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.requests == ["restore"],
                     "a timed resume the app quit before confirming never comes back untimed")

        reset(timed: nil)
        service.applyConfiguration(.manual(level: 60),
                                   timed: FanControlManualDuration.timed(minutes: 5, from: Date()))
        service.reply(.failure(.controlFailed))
        relaunch()
        Service.recoverIfNeeded()
        suite.expect(service.applied == [manual] && service.pendingReplies.count == 1,
                     "a timed speed the helper rejects leaves the untimed control kept before it to resume")

        // Turning resume on keeps only a confirmed control that nothing is
        // stopping or replacing: a request in flight decides what runs.
        func runningTimedWithoutResume() {
            reset(resume: false, timed: remaining)
            defaults.values[DefaultsKey.fanControlResumeConfiguration] = nil
            service.snapshot = cooling
        }
        func turnResumeOn() {
            defaults.values[DefaultsKey.fanControlResume] = true
            service.resumePreferenceDidChange()
        }
        runningTimedWithoutResume()
        turnResumeOn()
        suite.expect(FanControlConfiguration.decodeResume(storedResume ?? "") == manual
                && storedEnd == remaining.end.timeIntervalSinceReferenceDate && storedMinutes == 5,
               "turning resume on during a confirmed timed speed keeps it with its end")

        runningTimedWithoutResume()
        service.returnToSystem()
        turnResumeOn()
        suite.expect(storedResume == nil,
                     "turning resume on while a timed speed returns to System keeps nothing")
        service.reply(.success(onSystem))
        relaunch()
        Service.recoverIfNeeded()
        service.workspaceDidWake()
        suite.expect(service.requests.isEmpty && storedResume == nil,
                     "a timed speed stopped before resume was turned on never comes back once the restore succeeds")

        runningTimedWithoutResume()
        service.applyConfiguration(.manual(level: 60), timed: nil)
        turnResumeOn()
        suite.expect(storedResume == nil,
                     "turning resume on while a new speed replaces a timed one keeps neither yet")
        service.reply(.failure(.controlFailed))
        service.reply(.success(onSystem))
        relaunch()
        Service.recoverIfNeeded()
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && storedResume == nil,
                     "a timed speed whose replacement fails after resume was turned on never comes back untimed")

        runningTimedWithoutResume()
        let replacement = FanControlManualDuration.timed(minutes: 10, from: Date())
        service.applyConfiguration(.manual(level: 60), timed: replacement)
        turnResumeOn()
        var replaced = cooling
        replaced.configuration = .manual(level: 60)
        service.reply(.success(replaced))
        suite.expect(FanControlConfiguration.decodeResume(storedResume ?? "") == .manual(level: 60)
                && service.timedManual == replacement && storedMinutes == 10,
               "a replacement confirmed after resume was turned on is kept with its own end")

        reset(resume: false, timed: remaining)
        defaults.values[DefaultsKey.fanControlResumeConfiguration] = nil
        Environment.available = false
        Service.sharedReaches = 0
        Service.recoverIfNeeded()
        suite.expect(Service.sharedReaches == 0,
                     "with fan control off in the hub, a stored end does not load the service at launch")

        reset(timed: remaining)
        Environment.available = false
        service.syncWithPreferences()
        suite.expect(service.timedManual == nil && storedEnd == 0 && storedMinutes == 0,
                     "removing the feature forgets a running timed speed")
    }
}
