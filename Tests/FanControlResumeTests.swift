// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

/// Exercises fan control recovery with in-memory preferences, registration and
/// XPC replies. Nothing here can reach the helper or the fans.
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
        func invalidate() { invalidated = true }
    }
    final class StatusProxy {
        var statusCalls = 0
        var heartbeats = 0
        var restoreCalls = 0
        var configurations: [FanControlConfiguration] = []
        var holdNextRestore = false
        var heldRestore: (() -> Void)?
        func status(withReply reply: () -> Void) {
            statusCalls += 1
            reply()
        }
        func heartbeat(withReply reply: () -> Void) {
            heartbeats += 1
            reply()
        }
        func applyConfiguration(_ data: Data, withReply reply: () -> Void) {
            if let configuration = FanControlIPC.decodeConfiguration(data) { configurations.append(configuration) }
            reply()
        }
        func restoreAutomatic(withReply reply: @escaping () -> Void) {
            restoreCalls += 1
            if holdNextRestore {
                holdNextRestore = false
                heldRestore = reply
            } else {
                reply()
            }
        }
    }
    class Fixture {
        enum AccessState { case notRegistered, requiresApproval, enabled, unavailable }
        final class Registration {
            var status = AccessState.enabled
            var unregisterCalls = 0
            func unregister() throws {
                unregisterCalls += 1
                status = .notRegistered
            }
        }
        static let shared = Service()
        static var helperVersion = "bundled"
        static let appService = Registration()
        static let log = Logger(subsystem: "com.vorssaint.tests", category: "FanControlResume")
        var accessState = AccessState.enabled
        var snapshot = FanControlSnapshot.empty
        var error: FanControlErrorCode?
        var statusResponse: FanControlResponse?
        var proxy = StatusProxy()
        var requestGeneration = 0
        var requestInFlight = false
        var panelIsVisible = false
        var tickCount = 0
        var pendingStop: StopConfirmation?
        var sleepState = SleepState.awake
        var unregisterAfterRestore = false
        var timer: Invalidating?
        var connection: Invalidating?
        var observing = true
        var isWorking = false
        var resumeFailures = 0
        var resumeFailed = false
        var scheduledResumes: [TimeInterval] = []
        var resumeAttempt: TimeInterval? { scheduledResumes.last }
        var applied: [FanControlConfiguration] = []
        func send(_ operation: (StatusProxy, @escaping () -> Void) -> Void,
                  completion: @escaping (FanControlResponse?) -> Void) {
            operation(proxy) { completion(self.statusResponse) }
        }
        func replyToRestore(_ response: FanControlResponse) {
            statusResponse = response
            let reply = proxy.heldRestore
            proxy.heldRestore = nil
            reply?()
        }
        func refreshAccessState() { accessState = Self.appService.status }
        func authorize() {}
        func replaceRegistrationIfNeeded() -> Bool { false }
        func refreshLocalProbe() {}
        func startTimerIfNeeded() {
            if timer == nil { timer = Invalidating() }
        }
        func applyConfiguration(_ configuration: FanControlConfiguration, resuming: Bool) {
            applied.append(configuration)
        }
        func scheduleResumeAttempt(after delay: TimeInterval) { scheduledResumes.append(delay) }
        func cancelResumeAttempt() { scheduledResumes.removeAll() }
        func startObservingSystemState() { observing = true }
        func stopObservingSystemState() {
            observing = false
            sleepState = .awake
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
            service.accessState = .enabled
            Service.appService.status = .enabled
            Service.appService.unregisterCalls = 0
            service.snapshot = .empty
            service.error = nil
            service.statusResponse = nil
            service.proxy = StatusProxy()
            service.requestInFlight = false
            service.panelIsVisible = false
            service.tickCount = 0
            service.pendingStop = nil
            service.sleepState = .awake
            service.unregisterAfterRestore = false
            service.timer = Invalidating()
            service.connection = Invalidating()
            service.observing = true
            service.applied = []
            service.isWorking = false
            service.resumeFailures = 0
            service.resumeFailed = false
            service.scheduledResumes = []
            ProcessInfo.processInfo.thermalState = .nominal
        }
        var storedResume: String? { defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) }

        reset(resume: false, recovery: true)
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.proxy.restoreCalls == 1,
                     "without resume, a launch after an interrupted session only returns the fans to the system")
        reset(recovery: true)
        Service.recoverIfNeeded()
        suite.expect(service.applied == [manual] && service.proxy.restoreCalls == 0,
                     "with resume on, a launch re-applies the kept control instead of restoring first")
        reset()
        Service.appService.status = .requiresApproval
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.proxy.restoreCalls == 0,
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
        suite.expect(storedResume == nil && service.proxy.restoreCalls == 1,
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
        suite.expect(service.applied == [manual] && service.proxy.restoreCalls == 0,
                     "waking re-applies the kept control")
        reset(resume: false, recovery: true)
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.proxy.restoreCalls == 1,
                     "without resume, waking still returns an interrupted session to the system")
        reset(resume: false)
        service.panelIsVisible = true
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.proxy.statusCalls == 1 && service.proxy.restoreCalls == 0,
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

        for reason: FanControlStopReason? in [.hardwareChanged, .temperatureUnavailable, .thermalPressure,
                                               .recovery, .appDisconnected, .timeLimit, nil, .heartbeatLost] {
            reset()
            service.snapshot.isCooling = true
            var stopped = FanControlSnapshot.empty
            stopped.stopReason = reason
            service.applyStatus(.success(stopped))
            service.applyStatus(.success(stopped))
            suite.expect(service.scheduledResumes.count == (reason == .heartbeatLost ? 1 : 0)
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

        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        func readStatus(_ response: FanControlResponse) {
            service.statusResponse = response
            service.requestStatus()
        }
        func startCurve(panelVisible: Bool = false) {
            reset(stored: curve, recovery: true)
            defaults.values[DefaultsKey.fanControlMode] = FanControlMode.curve.rawValue
            service.panelIsVisible = panelVisible
            var active = FanControlSnapshot.empty
            active.isCooling = true
            active.configuration = curve
            readStatus(.success(active))
        }
        func startRecovery(panelVisible: Bool = false, reason: FanControlStopReason = .heartbeatLost) {
            startCurve(panelVisible: panelVisible)
            var recovering = FanControlSnapshot.empty
            recovering.stopReason = reason
            service.statusResponse = .failure(.controlFailed, snapshot: recovering)
            service.poll()
            let afterHeartbeat = service.requestGeneration
            service.workspaceDidWake()
            service.retryResume()
            service.poll()
            service.poll()
            suite.expect(service.snapshot == recovering && service.error == .controlFailed
                            && service.requestGeneration > afterHeartbeat
                            && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                            && service.timer != nil && service.scheduledResumes.isEmpty && service.applied.isEmpty,
                         "during recovery the timer keeps checking while wake and retry leave the fans alone")
        }

        func confirmRecovery(_ reason: FanControlStopReason?) {
            var restored = FanControlSnapshot.empty
            restored.stopReason = reason
            service.statusResponse = .success(restored)
            service.poll()
            service.poll()
            suite.expect(service.snapshot == restored && service.error == nil
                            && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                            && (service.timer != nil) == service.panelIsVisible,
                         "the timer observes automatic control and finishes recovery even with the panel closed")
            service.requestStatus() // A second reader sees the same stopped session.
        }

        for panelVisible in [false, true] {
            startRecovery(panelVisible: panelVisible)
            confirmRecovery(.heartbeatLost)
            suite.expect(service.scheduledResumes == [FanControlResumePolicy.retryDelays[0]]
                            && service.applied.isEmpty && !service.resumeFailed,
                         "confirming heartbeat recovery twice schedules only one resume")
            service.retryResume()
            suite.expect(service.applied == [curve], "the confirmed heartbeat retry applies the saved curve")
        }
        let protectedStops: [(FanControlStopReason, FanControlStopReason)] = [
            (.hardwareChanged, .hardwareChanged), (.temperatureUnavailable, .temperatureUnavailable),
            (.thermalPressure, .thermalPressure), (.heartbeatLost, .hardwareChanged),
            (.hardwareChanged, .heartbeatLost),
        ]
        for (initial, confirmed) in protectedStops {
            startRecovery(reason: initial)
            confirmRecovery(confirmed)
            suite.expect(service.applied.isEmpty && service.scheduledResumes.isEmpty,
                         "a protection stop during recovery or at confirmation keeps control with the system")
        }

        for wakesBeforeReply in [false, true] {
            startRecovery()
            service.proxy.holdNextRestore = true
            service.workspaceWillSleep()
            if wakesBeforeReply { service.workspaceDidWake() }
            service.replyToRestore(.success(stopped))
            suite.expect(service.applied.isEmpty && service.scheduledResumes.count == (wakesBeforeReply ? 1 : 0),
                         "the sleep restore can confirm the stop and only schedule a retry after wake")
            if wakesBeforeReply { service.retryResume() } else { service.workspaceDidWake() }
            suite.expect(service.applied == [curve], "a wake on either side of the restore reply resumes once")

            startCurve()
            service.proxy.holdNextRestore = true
            service.workspaceWillSleep()
            if wakesBeforeReply { service.workspaceDidWake() }
            service.replyToRestore(.success(.empty))
            if !wakesBeforeReply { service.workspaceDidWake() }
            if !service.scheduledResumes.isEmpty { service.retryResume() }
            suite.expect(service.applied == [curve], "an ordinary sleep restore permits the next wake to resume once")

            for restoreFailed in [false, true] {
                startCurve()
                service.proxy.holdNextRestore = true
                service.workspaceWillSleep()
                suite.expect(service.proxy.heldRestore != nil && service.isWorking,
                             "sleep leaves the requested restore in flight until the helper replies")
                if wakesBeforeReply {
                    service.workspaceDidWake()
                    suite.expect(service.applied.isEmpty && !service.scheduledResumes.isEmpty,
                                 "a wake before the first restore reply defers its application")
                }
                var unsafeStop = FanControlSnapshot.empty
                unsafeStop.stopReason = .hardwareChanged
                let reply: FanControlResponse = restoreFailed
                    ? .failure(.controlFailed, snapshot: unsafeStop) : .success(unsafeStop)
                service.replyToRestore(reply)
                suite.expect(!service.isWorking && service.scheduledResumes.isEmpty && service.applied.isEmpty,
                             "the first evidence of a hardware stop in the sleep reply cancels the deferred resume")
                if restoreFailed {
                    service.retryResume()
                    suite.expect(defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) && service.applied.isEmpty,
                                 "a late retry cannot write the curve during a failed sleep restore")
                    confirmRecovery(.hardwareChanged)
                } else {
                    service.requestStatus() // The same successful stopped snapshot is harmless.
                }
                if !wakesBeforeReply { service.workspaceDidWake() }
                suite.expect(service.scheduledResumes.isEmpty && service.applied.isEmpty
                                && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                             "confirming a protected stop before or after wake keeps control with the system")
            }
        }

        reset(stored: curve, recovery: true)
        service.proxy.holdNextRestore = true
        service.workspaceWillSleep()
        var historicalStop = FanControlSnapshot.empty
        historicalStop.stopReason = .hardwareChanged
        service.replyToRestore(.success(historicalStop))
        service.workspaceDidWake()
        suite.expect(service.applied == [curve] && service.scheduledResumes.isEmpty,
                     "a historical protection reason from a helper already idle at sleep cannot veto the next wake")

        for interveningProtection in [false, true] {
            startRecovery()
            readStatus(.failure(.controlFailed))
            if interveningProtection {
                var unsafeStop = FanControlSnapshot.empty
                unsafeStop.stopReason = .thermalPressure
                readStatus(.failure(.controlFailed, snapshot: unsafeStop))
                readStatus(.failure(.controlFailed))
            }
            confirmRecovery(.heartbeatLost)
            suite.expect(service.scheduledResumes.count == (interveningProtection ? 0 : 1),
                         "an empty telemetry failure preserves the known cause until the repeated confirmation")
        }
        for failure in [FanControlErrorCode.noFans, .unsupportedHardware] {
            startRecovery()
            readStatus(.failure(failure))
            confirmRecovery(.heartbeatLost)
            suite.expect(service.applied.isEmpty && service.scheduledResumes.isEmpty,
                         "an explicit hardware error with an empty sample still vetoes the saved curve")
        }

        for externalCooling in [false, true] {
            startRecovery()
            var external = FanControlSnapshot.empty
            external.isCooling = externalCooling
            readStatus(.failure(.alreadyControlled, snapshot: external))
            // status() can report another client's active session successfully.
            if externalCooling { service.statusResponse = .success(external) }
            let before = service.proxy.statusCalls
            let heartbeats = service.proxy.heartbeats
            Service.restoreBeforeTerminationIfNeeded()
            suite.expect(defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) && service.proxy.restoreCalls == 0,
                         "quitting during contested recovery leaves the other controller's fans alone")
            for _ in 0..<180 { service.poll() }
            let backgroundChecks = service.proxy.statusCalls - before
            suite.expect((1...3).contains(backgroundChecks) && service.proxy.heartbeats == heartbeats
                            && service.applied.isEmpty && service.scheduledResumes.isEmpty,
                         "an external owner receives no heartbeats and only occasional closed-panel status checks")
            service.panelIsVisible = true
            let beforeVisible = service.proxy.statusCalls
            for _ in 0..<6 { service.poll() }
            suite.expect(service.proxy.statusCalls > beforeVisible && service.proxy.heartbeats == heartbeats,
                         "the visible panel still refreshes telemetry for externally controlled fans")
            readStatus(.success(stopped))
            suite.expect(service.scheduledResumes.isEmpty && service.applied.isEmpty,
                         "the external owner giving up control cannot resume the old heartbeat session")
        }

        startRecovery(panelVisible: true)
        confirmRecovery(.heartbeatLost)
        suite.expect(service.scheduledResumes.count == 1, "the heartbeat retry is pending before ownership changes")
        readStatus(.failure(.alreadyControlled))
        suite.expect(service.scheduledResumes.isEmpty, "an empty external-owner status cancels the queued retry immediately")
        service.retryResume()
        readStatus(.success(stopped))
        suite.expect(service.scheduledResumes.isEmpty && service.applied.isEmpty && service.proxy.restoreCalls == 0,
                     "a stale retry and a later idle status cannot rearm the old curve")

        reset(stored: curve)
        service.timer = nil
        service.statusResponse = .failure(.alreadyControlled)
        service.sendConfiguration(curve, resuming: true)
        service.retryResume()
        suite.expect(service.proxy.configurations == [curve] && service.proxy.restoreCalls == 0
                        && service.scheduledResumes.isEmpty && service.applied.isEmpty
                        && service.error == .alreadyControlled && service.timer != nil,
                     "when applying the curve first discovers an external owner, it sends no restore or retry")

        for (alreadyRecovering, reenable) in [(false, false), (true, false), (true, true)] {
            if alreadyRecovering {
                startRecovery()
            } else {
                reset(stored: curve, recovery: true)
                defaults.values[DefaultsKey.fanControlHelperVersion] = Service.helperVersion
                service.timer = nil
                service.statusResponse = .failure(.controlFailed)
            }
            Environment.available = false
            service.syncWithPreferences()
            suite.expect(service.proxy.restoreCalls == 1 && Service.appService.unregisterCalls == 0
                            && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) && service.timer != nil,
                         "removing Fan Control keeps the helper registered through a failed return to automatic")
            if reenable {
                Environment.available = true
                service.syncWithPreferences()
            }
            confirmRecovery(.heartbeatLost)
            let version = defaults.string(forKey: DefaultsKey.fanControlHelperVersion)
            suite.expect(storedResume == nil && service.applied.isEmpty && service.scheduledResumes.isEmpty
                            && Service.appService.unregisterCalls == (reenable ? 0 : 1)
                            && version == (reenable ? Service.helperVersion : nil),
                         "repeated recovery confirmations unregister only once and only while the feature is removed")
        }

        startRecovery()
        defaults.values[DefaultsKey.fanControlResume] = false
        service.resumePreferenceDidChange()
        confirmRecovery(.heartbeatLost)
        service.retryResume()
        suite.expect(storedResume == nil && service.scheduledResumes.isEmpty && service.applied.isEmpty,
                     "disabling resume during recovery leaves control with the system after confirmation")

        reset()
        Environment.available = false
        service.statusResponse = .success(.empty)
        service.syncWithPreferences()
        suite.expect(storedResume == nil && service.proxy.restoreCalls == 1 && Service.appService.unregisterCalls == 1,
                     "removing the feature forgets the kept control before unregistering the helper")
        reset()
    }
}
