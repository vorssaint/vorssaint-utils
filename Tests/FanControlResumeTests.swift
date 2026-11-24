// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

/// Resuming fan control after a restart or wake runs the production decisions
/// against doubles: nothing here can reach the helper or the fans.
enum FanControlResumeContract {
    enum Environment {
        static var available = true
    }
    enum ProcessInfo {
        static let processInfo = Thermal()
        final class Thermal { var thermalState = Foundation.ProcessInfo.ThermalState.nominal }
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
            func set(_ value: Any?, forKey key: String) { values[key] = value }
            func removeObject(forKey key: String) { values[key] = nil }
        }
    }
    final class Invalidating {
        var invalidated = false
        var tolerance: TimeInterval = 0
        static func scheduledTimer(withTimeInterval: TimeInterval, repeats: Bool, block: (Invalidating) -> Void) -> Invalidating {
            Invalidating() // Tests advance the production timer using poll().
        }
        func invalidate() { invalidated = true }
    }
    typealias Timer = Invalidating
    final class StatusProxy {
        var statusReads = 0
        var heartbeats = 0
        var restores = 0
        var holdRestore = false
        var heldRestore: (() -> Void)?
        var holdNextStatus = false
        var heldStatus: (() -> Void)?
        var writes: [FanControlConfiguration] = []
        func status(withReply reply: @escaping () -> Void) {
            statusReads += 1
            if holdNextStatus {
                holdNextStatus = false
                heldStatus = reply
            } else { reply() }
        }
        func heartbeat(withReply reply: () -> Void) { heartbeats += 1; reply() }
        func restoreAutomatic(withReply reply: @escaping () -> Void) {
            restores += 1
            if holdRestore { heldRestore = reply } else { reply() }
        }
        func applyConfiguration(_ data: Data, withReply reply: () -> Void) {
            if let configuration = FanControlIPC.decodeConfiguration(data) { writes.append(configuration) }
            reply()
        }
    }
    class Fixture {
        enum AccessState { case notRegistered, requiresApproval, enabled, unavailable }
        final class Registration {
            var unregisterCalls = 0
            func unregister() throws { unregisterCalls += 1 }
        }
        static let appService = Registration()
        static var shared = Service()
        static var helperVersion = "bundled"
        static let log = Logger(subsystem: "com.vorssaint.tests", category: "FanControlResume")
        var accessState = AccessState.enabled
        var snapshot = FanControlSnapshot.empty
        var error: FanControlErrorCode?
        var statusResponse: FanControlResponse?
        let proxy = StatusProxy()
        var tickCount = 0
        var hadActiveControl = false
        var handoffInFlight = false
        var recoveryPollInterval = 2
        var requestGeneration = 0
        var requestInFlight = false
        var panelIsVisible = false
        var timer: Invalidating?
        var connection: Invalidating?
        var observing = true
        var isWorking = false
        var resumeFailures = 0
        var resumeFailed = false
        var scheduledResumes: [TimeInterval] = []
        var applied: [FanControlConfiguration] = []
        var events: [String] = []
        func send(_ operation: (StatusProxy, @escaping () -> Void) -> Void,
                  completion: @escaping (FanControlResponse?) -> Void) {
            operation(proxy) { completion(self.statusResponse) }
        }
        func refreshAccessState() {
            if Self.appService.unregisterCalls > 0 { accessState = .notRegistered }
        }
        func applyConfiguration(_ configuration: FanControlConfiguration, resuming: Bool) {
            applied.append(configuration)
        }
        func scheduleResumeAttempt(after delay: TimeInterval) { scheduledResumes.append(delay) }
        func cancelResumeAttempt() { scheduledResumes.removeAll() }
        func authorize() { events.append("authorize") }
        func refresh() { events.append("refresh") }
        func startObservingSystemState() { observing = true }
        func stopObservingSystemState() { observing = false }
    }

    static func run(_ suite: TestSuite) {
        var service: Service { Service.shared }
        let defaults = UserDefaults.standard
        let manual = FanControlConfiguration.manual(level: 100)
        func reset(resume: Bool = true, stored: FanControlConfiguration? = manual,
                   recovery: Bool = false) {
            Environment.available = true
            Service.appService.unregisterCalls = 0
            defaults.values = [:]
            defaults.values[DefaultsKey.fanControlResume] = resume
            defaults.values[DefaultsKey.fanControlRecoveryNeeded] = recovery
            defaults.values[DefaultsKey.fanControlMode] = FanControlMode.manual.rawValue
            if let stored {
                defaults.values[DefaultsKey.fanControlResumeConfiguration] =
                    FanControlConfiguration.encodeResume(stored)
            }
            Service.shared = Service()
            service.timer = Invalidating()
            service.connection = Invalidating()
            ProcessInfo.processInfo.thermalState = .nominal
        }
        var storedResume: String? { defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) }

        reset(resume: false, recovery: true)
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.proxy.restores == 1,
                     "without resume, a launch after an interrupted session only returns the fans to the system")
        reset(recovery: true)
        Service.recoverIfNeeded()
        suite.expect(service.applied == [manual] && service.events.isEmpty && service.proxy.restores == 0,
                     "with resume on, a launch re-applies the kept control instead of restoring first")
        reset()
        service.accessState = .requiresApproval
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.events.isEmpty && service.proxy.restores == 0,
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

        reset(recovery: true)
        defaults.values[DefaultsKey.fanControlHelperVersion] = "previous"
        var legacy = FanControlSnapshot.empty
        legacy.isCooling = true
        service.statusResponse = .success(legacy)
        service.requestStatus()
        suite.expect(service.snapshot == legacy && Service.helperAwaitsRegistration,
                     "a status reply from the older helper during recovery leaves its registration pending")
        service.statusResponse = .success(.empty)
        service.requestStatus()
        suite.expect(!defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) && Service.helperAwaitsRegistration,
                     "after recovery clears, the old helper still needs replacement")
        defaults.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
        service.requestStatus()
        suite.expect(defaults.string(forKey: DefaultsKey.fanControlHelperVersion) == Service.helperVersion,
                     "a compatible status reply still initializes an unversioned registration")

        reset(recovery: true)
        defaults.values[DefaultsKey.fanControlHelperVersion] = Service.helperVersion
        var idle = FanControlSnapshot.empty
        idle.isCooling = true
        idle.fans = [.init(index: 0, actualRPM: 2_000, minimumRPM: 1_200, maximumRPM: 5_800,
                           targetRPM: 2_000, isManuallyControlled: true)]
        idle.temperatures = [.init(source: .hottestCPU, celsius: 45)]
        idle.gpuPoweredDown = true
        service.statusResponse = .success(idle)
        service.requestStatus()
        let obsolete = service.beginRequest()
        let current = service.beginRequest()
        suite.expect(!service.finishRequest(obsolete, response: nil) && service.snapshot == idle
                        && service.requestInFlight && service.error == nil,
                     "a superseded IPC failure preserves the current sample and in-flight request")
        _ = service.finishRequest(current, response: .success(idle))
        service.statusResponse = nil
        service.requestStatus()
        suite.expect(service.snapshot.availableTemperatureSources.isEmpty
                        && service.snapshot.temperatures == nil && service.snapshot.gpuPoweredDown == nil
                        && service.snapshot.isCooling && service.snapshot.fans == idle.fans
                        && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                        && service.error == .helperUnavailable,
                     "losing the helper clears live readings and GPU sleep while retaining control for recovery")
        var awake = idle
        awake.gpuPoweredDown = false
        awake.temperatures = [.init(source: .hottestGPU, celsius: 54)]
        service.statusResponse = .failure(.alreadyControlled, snapshot: awake)
        service.requestStatus()
        suite.expect(service.snapshot == awake && service.error == .alreadyControlled,
                     "a fresh snapshot from a refused request replaces the lost sample and keeps its error")

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
        suite.expect(storedResume == nil && service.proxy.restores == 1,
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
        suite.expect(service.applied == [manual] && service.events.isEmpty && service.proxy.restores == 0,
                     "waking re-applies the kept control")
        reset(resume: false, recovery: true)
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.proxy.restores == 1,
                     "without resume, waking still returns an interrupted session to the system")
        reset(resume: false)
        service.panelIsVisible = true
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.events == ["refresh"] && service.proxy.restores == 0,
                     "without resume, waking only refreshes a visible panel")


        // A resume can fail for a moment right after a wake, before the fans and
        // sensors answer again. One refusal must not leave the fans on System
        // while the card still shows the curve as chosen.
        reset()
        service.workspaceDidWake()
        service.resumeDidFail(.controlFailed)
        suite.expect(service.scheduledResumes == [FanControlResumePolicy.retryDelays[0]],
                     "a resume refused right after a wake is tried again shortly")
        service.retryResume()
        suite.expect(service.applied == [manual, manual],
                     "the retry re-applies the kept control")
        reset()
        for _ in FanControlResumePolicy.retryDelays { service.resumeDidFail(.controlFailed) }
        suite.expect(service.scheduledResumes == FanControlResumePolicy.retryDelays && !service.resumeFailed,
                     "failed resumes back off through every planned retry")
        service.resumeDidFail(.controlFailed)
        suite.expect(service.scheduledResumes == FanControlResumePolicy.retryDelays && service.resumeFailed,
                     "resuming gives up after the last retry and says so instead of looking active")
        service.workspaceDidWake()
        suite.expect(service.resumeFailures == 0 && !service.resumeFailed
                        && service.applied == [manual],
                     "a later wake starts a fresh resume with the full retry budget")
        reset(resume: false, stored: nil)
        service.resumeDidFail(.controlFailed)
        suite.expect(service.scheduledResumes.isEmpty && !service.resumeFailed,
                     "without resume a failed apply is never retried")
        reset()
        service.resumeDidFail(.controlFailed)
        service.returnToSystem()
        service.retryResume()
        suite.expect(service.scheduledResumes.isEmpty && service.applied.isEmpty,
                     "returning to System cancels a pending resume retry")
        reset()
        service.resumeDidFail(.controlFailed)
        defaults.values[DefaultsKey.fanControlResume] = false
        service.resumePreferenceDidChange()
        suite.expect(service.scheduledResumes.isEmpty, "turning resume off cancels a pending retry")
        reset()
        service.resumeDidFail(.controlFailed)
        service.workspaceWillSleep()
        suite.expect(service.scheduledResumes.isEmpty, "sleep cancels a pending retry; the wake resumes anew")
        reset()
        service.snapshot.isCooling = true
        service.retryResume()
        suite.expect(service.applied.isEmpty, "a retry does nothing once the control is running again")
        reset()
        ProcessInfo.processInfo.thermalState = .serious
        service.retryResume()
        suite.expect(service.applied.isEmpty
                        && service.scheduledResumes == [FanControlResumePolicy.retryDelays[0]],
                     "under thermal pressure a retry waits instead of fighting the system")
        reset()
        service.isWorking = true
        service.retryResume()
        suite.expect(service.applied.isEmpty && service.scheduledResumes.count == 1,
                     "a retry waits for a request already in flight")

        service.snapshot.isCooling = true
        service.retryResume()
        suite.expect(service.scheduledResumes.count == 2 && service.resumeFailures == 0,
                     "a stale active snapshot during restoration does not lose the retry")
        service.isWorking = false
        service.snapshot = .empty
        for _ in 0..<20 {
            ProcessInfo.processInfo.thermalState = .critical
            service.retryResume()
        }
        ProcessInfo.processInfo.thermalState = .fair
        service.retryResume()
        suite.expect(service.applied == [manual] && service.resumeFailures == 0,
                     "waiting for restoration and thermal pressure preserves the full retry budget")
        reset()
        ProcessInfo.processInfo.thermalState = .critical
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.scheduledResumes.count == 1,
                     "a wake under thermal pressure defers even its initial application")
        reset()
        service.resumeDidFail(.controlFailed)
        service.forgetResume()
        defaults.values[DefaultsKey.fanControlMode] = FanControlMode.manual.rawValue
        service.retryResume()
        suite.expect(storedResume == nil && service.applied.isEmpty,
                     "selecting System then Manual cannot bring back an unapplied curve")

        var active = FanControlSnapshot.empty
        active.isCooling = true
        active.configuration = manual
        for reason: FanControlStopReason? in [.hardwareChanged, .temperatureUnavailable, .thermalPressure,
                                               .recovery, .appDisconnected, .timeLimit, nil, .heartbeatLost] {
            reset()
            service.statusResponse = .success(active)
            service.applyConfiguration(manual)
            var stopped = FanControlSnapshot.empty
            stopped.stopReason = reason
            service.statusResponse = .success(stopped)
            service.poll()
            service.requestStatus()
            suite.expect(service.proxy.heartbeats == 1 && service.scheduledResumes.count == (reason == .heartbeatLost ? 1 : 0)
                            && service.resumeFailed == (reason != .heartbeatLost),
                         "polling a stopped session twice honors its reason and schedules at most once")
        }
        reset()
        service.resumeDidFail(.controlFailed, stopReason: .hardwareChanged)
        suite.expect(service.resumeFailed && service.scheduledResumes.isEmpty,
                     "a refused application that lost hardware ownership leaves control with the system")
        reset(resume: false, stored: nil)
        service.snapshot.isCooling = true
        var stopped = FanControlSnapshot.empty
        stopped.stopReason = .heartbeatLost
        service.applyStatus(.success(stopped))
        suite.expect(service.scheduledResumes.isEmpty, "a heartbeat loss only resumes opted-in control")

        var customCurve = FanControlConfiguration.defaultCurve
        customCurve.sensor = .hottestGPU
        let selection = FanControlConfiguration.curve([customCurve])
        let storedCurves = FanControlConfiguration.encodeCurves([customCurve])
        var running = active
        running.configuration = selection
        for panelOpen in [false, true] {
            reset(resume: !panelOpen, stored: nil)
            service.panelIsVisible = panelOpen
            defaults.values[DefaultsKey.fanControlMode] = FanControlMode.curve.rawValue
            defaults.values[DefaultsKey.fanControlCurves] = storedCurves
            defaults.values[DefaultsKey.fanControlCoolingLevel] = 65
            service.statusResponse = .success(running)
            service.applyConfiguration(selection)
            service.statusResponse = .failure(.controlFailed, snapshot: stopped)
            service.poll()
            var readTicks: [Int] = []
            for tick in 1...32 {
                let reads = service.proxy.statusReads
                service.poll()
                if service.proxy.statusReads > reads { readTicks.append(tick) }
            }
            let gaps = zip(readTicks.dropFirst(), readTicks).map { $0.0 - $0.1 }
            suite.expect(readTicks.count >= 3 && readTicks.count < 10 && (gaps.last ?? 0) > (gaps.first ?? 0),
                         "repeated unconfirmed handoffs back off between status checks")
            suite.expect(service.proxy.writes == [selection] && service.proxy.heartbeats == 1 && storedResume == nil
                            && defaults.bool(forKey: DefaultsKey.fanControlResume) == !panelOpen
                            && service.isWorking && service.timer != nil && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                         "a failed heartbeat handoff keeps polling for automatic control through another failed read")
            if panelOpen {
                service.statusResponse = .success(active) // An unrelated active session during recovery.
                service.requestStatus()
                let exitingConnection = service.connection
                let exitingTimer = service.timer
                service.proxy.holdNextStatus = true
                service.requestStatus()
                Service.restoreBeforeTerminationIfNeeded()
                service.statusResponse = .success(.empty)
                let late = service.proxy.heldStatus
                service.proxy.heldStatus = nil
                late?()
                suite.expect(late != nil && !service.requestInFlight && exitingTimer?.invalidated == true && exitingConnection?.invalidated == true
                                && service.connection == nil && service.proxy.restores == 0
                                && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) && service.interruptedStop == stopped.stopReason?.rawValue,
                             "quitting while another session is active only closes the client, and a late idle reply preserves the handoff markers")
                Service.shared = Service() // Preserve only the preferences across relaunch.
                service.panelIsVisible = true
                service.accessState = .requiresApproval
                Service.recoverIfNeeded()
                service.workspaceWillSleep()
                service.workspaceDidWake()
                service.applyConfiguration(manual)
                for _ in 0..<8 { service.poll() }
                suite.expect(service.proxy.statusReads == 0 && service.proxy.restores == 0,
                             "a relaunched client without approval waits without contacting the helper")
                service.accessState = .enabled
                service.proxy.holdNextStatus = true
                service.requestStatus()
                for _ in 0..<60 { service.poll() }
                suite.expect(service.proxy.statusReads == 1 && service.requestInFlight, "polling leaves the in-flight status request alone")
                service.statusResponse = .success(active) // An unrelated session now controls the fans.
                let reply = service.proxy.heldStatus
                service.proxy.heldStatus = nil
                reply?()
                defaults.values[DefaultsKey.fanControlResume] = false
                service.resumePreferenceDidChange()
                defaults.values[DefaultsKey.fanControlResume] = true
                service.resumePreferenceDidChange()
                service.statusResponse = nil
                service.requestStatus()
                service.retryResume()
                suite.expect(service.proxy.writes.isEmpty && service.proxy.heartbeats == 0 && service.applied.isEmpty
                                && service.proxy.restores == 0 && !service.events.contains("authorize")
                                && storedResume == nil && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                             "relaunch, missing approval, sleep and an external session cannot interrupt the pending handoff")
            }
            let priorWrites = service.proxy.writes
            let readsBeforeConfirmation = service.proxy.statusReads
            service.statusResponse = .success(.empty)
            for _ in 0..<120 { service.poll() }
            if !panelOpen {
                suite.expect(service.proxy.statusReads == readsBeforeConfirmation + 1 && service.timer == nil,
                             "the first idle confirmation stops all closed-panel status polling")
            }
            service.requestStatus() // Duplicate idle telemetry.
            service.workspaceDidWake()
            service.retryResume()
            suite.expect(service.snapshot.stopReason == .heartbeatLost && !service.isWorking && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                            && service.proxy.writes == priorWrites && service.scheduledResumes.isEmpty && service.applied.isEmpty,
                         "confirmed automatic control ends the wait without reapplying the failed curve on a later wake")
            suite.expect(storedResume == nil && defaults.bool(forKey: DefaultsKey.fanControlResume)
                            && defaults.string(forKey: DefaultsKey.fanControlMode) == FanControlMode.curve.rawValue
                            && defaults.string(forKey: DefaultsKey.fanControlCurves) == storedCurves
                            && defaults.values[DefaultsKey.fanControlCoolingLevel] as? Int == 65,
                         "loss of session consent preserves the user's selected mode, curves, manual speed and resume setting")
            service.statusResponse = .failure(.controlFailed)
            service.applyConfiguration(selection)
            suite.expect(service.proxy.restores == 1 && !service.awaitingSystemControl && storedResume == nil && service.interruptedStop != nil,
                         "a refused explicit application uses the ordinary restore path without granting new resume consent")
            service.statusResponse = .success(running)
            service.applyConfiguration(selection)
            suite.expect(service.proxy.writes == priorWrites + [selection, selection] && service.snapshot.isCooling && service.interruptedStop == nil
                            && FanControlConfiguration.decodeResume(storedResume ?? "") == selection,
                         "a new explicit application works once the system handoff has been confirmed")
        }
        for restored in [true, false] {
            reset(stored: nil)
            service.statusResponse = .success(active)
            service.applyConfiguration(manual)
            service.proxy.holdRestore = true
            service.workspaceWillSleep()
            service.workspaceWillSleep()
            let reply = service.proxy.heldRestore
            service.proxy.heldRestore = nil
            service.statusResponse = restored ? .success(.empty) : .failure(.controlFailed, snapshot: stopped)
            reply?()
            service.workspaceDidWake()
            suite.expect(reply != nil && service.proxy.restores == 1 && service.isWorking == !restored && (storedResume != nil) == restored
                            && service.scheduledResumes.isEmpty && service.applied == (restored ? [manual] : []) && service.proxy.writes == [manual],
                         "duplicate sleep notifications preserve the first restore reply and only a successful handoff resumes on wake")
        }
        reset(stored: nil)
        service.statusResponse = .success(active)
        service.applyConfiguration(manual)
        let ownedConnection = service.connection
        service.statusResponse = .success(.empty)
        Service.restoreBeforeTerminationIfNeeded()
        suite.expect(service.proxy.restores == 1 && ownedConnection?.invalidated == true && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                     "normal termination still restores an active local session and closes its connection")
        reset()
        Environment.available = false
        service.statusResponse = .success(.empty)
        service.syncWithPreferences()
        suite.expect(storedResume == nil && service.proxy.restores == 1 && Service.appService.unregisterCalls == 1,
                     "removing the feature forgets the kept control before unregistering the helper")
        for failureDuringRemoval in [false, true] {
            for reenable in [false, true] {
                reset(stored: nil)
                defaults.values[DefaultsKey.fanControlHelperVersion] = Service.helperVersion
                service.statusResponse = .success(active)
                service.applyConfiguration(manual)
                service.statusResponse = .failure(.controlFailed, snapshot: stopped)
                if !failureDuringRemoval { service.heartbeat() }
                Environment.available = false
                service.syncWithPreferences()
                suite.expect(service.awaitingSystemControl && storedResume == nil && Service.appService.unregisterCalls == 0
                                && service.interruptedStop == stopped.stopReason?.rawValue && service.timer != nil && service.isWorking,
                             "removing the feature waits for confirmed automatic control even when its own restore first fails")
                if reenable {
                    Environment.available = true
                    service.syncWithPreferences()
                }
                service.statusResponse = .success(.empty)
                service.requestStatus()
                service.requestStatus()
                suite.expect(!service.awaitingSystemControl && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                                && Service.appService.unregisterCalls == (reenable ? 0 : 1) && service.proxy.restores == (failureDuringRemoval ? 1 : 0)
                                && defaults.string(forKey: DefaultsKey.fanControlHelperVersion) == (reenable ? Service.helperVersion : nil),
                             "duplicate status confirmations preserve the registration only when the feature was reenabled")
            }
        }
        reset()
    }
}
