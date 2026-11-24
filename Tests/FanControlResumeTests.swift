// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
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
        var onInvalidate: (() -> Void)?
        var tolerance: TimeInterval = 0
        private var tick: ((Invalidating) -> Void)?
        static func scheduledTimer(withTimeInterval: TimeInterval, repeats: Bool,
                                   block: @escaping (Invalidating) -> Void) -> Invalidating {
            let timer = Invalidating()
            timer.tick = block
            return timer
        }
        func fire() { if !invalidated { tick?(self) } }
        func invalidate() {
            guard !invalidated else { return }
            invalidated = true
            onInvalidate?()
        }
    }
    typealias Timer = Invalidating
    typealias NSXPCConnection = Invalidating
    final class StatusProxy {
        var statusReads = 0
        var heartbeats = 0
        var restores = 0
        var holdRestore = false
        var heldRestore: (() -> Void)?
        var holdNextStatus = false
        var heldStatus: (() -> Void)?
        var holdNextApply = false
        var heldApply: (() -> Void)?
        var onApply: ((FanControlConfiguration) -> Void)?
        var onRestore: (() -> Void)?
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
            onRestore?()
            if holdRestore { heldRestore = reply } else { reply() }
        }
        func applyConfiguration(_ data: Data, withReply reply: @escaping () -> Void) {
            if let configuration = FanControlIPC.decodeConfiguration(data) {
                writes.append(configuration)
                onApply?(configuration)
            }
            if holdNextApply {
                holdNextApply = false
                heldApply = reply
            } else { reply() }
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
        var controller: FanControlRecoveryContract.Controller?
        let proxy = StatusProxy()
        var tickCount = 0
        var hadActiveControl = false
        var recoveryPollInterval = 2
        var requestGeneration = 0
        var requestInFlight: FanControlRequest?
        var panelIsVisible = false
        var timer: Invalidating?
        var connection: Invalidating?
        var observing = true
        var isWorking = false
        var resumeFailures = 0
        var scheduledResumes: [TimeInterval] = []
        var applied: [FanControlConfiguration] = []
        var events: [String] = []
        func send(_ operation: (StatusProxy, @escaping () -> Void) -> Void,
                  completion: @escaping (FanControlResponse?) -> Void) {
            operation(proxy) { completion(self.controller?.statusResponse() ?? self.statusResponse) }
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
                        && service.requestInFlight != nil && service.error == nil,
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
        service.timer = Invalidating()
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
        suite.expect(service.scheduledResumes == FanControlResumePolicy.retryDelays && service.interruption == nil,
                     "failed resumes back off through every planned retry")
        service.resumeDidFail(.controlFailed)
        suite.expect(service.scheduledResumes == FanControlResumePolicy.retryDelays && service.interruption == .resumeFailed,
                     "resuming gives up after the last retry and says so instead of looking active")
        service.workspaceDidWake()
        suite.expect(service.resumeFailures == 0 && service.interruption == nil
                        && service.applied == [manual],
                     "a later wake starts a fresh resume with the full retry budget")
        reset(resume: false, stored: nil)
        service.resumeDidFail(.controlFailed)
        suite.expect(service.scheduledResumes.isEmpty && service.interruption == nil,
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
                            && (service.interruption != nil) == (reason != .heartbeatLost),
                         "polling a stopped session twice honors its reason and schedules at most once")
        }
        reset()
        service.resumeDidFail(.controlFailed, stopReason: .hardwareChanged)
        suite.expect(service.interruption == .resumeFailed && service.scheduledResumes.isEmpty,
                     "a refused application that lost hardware ownership leaves control with the system")
        for keepControl in [false, true] {
            reset(resume: keepControl, stored: nil)
            let controller = FanControlRecoveryContract.Controller()
            controller.activeConfiguration = manual
            service.controller = controller
            service.applyConfiguration(manual)
            controller.lastHeartbeatUptime -= FanControlPolicy.heartbeatLimit + 1
            controller.watchdogTick()
            service.timer?.fire()
            suite.expect(controller.hardware?.restores == 1 && !controller.isRecovering
                            && service.snapshot.stopReason == .heartbeatLost && service.interruptedStop == nil
                            && !service.awaitingSystemControl && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                         "a handoff that succeeds on the first watchdog attempt needs no further confirmation")
            suite.expect(service.scheduledResumes == (keepControl ? [FanControlResumePolicy.retryDelays[0]] : [])
                            && service.interruption == (keepControl ? nil : .stopped(.heartbeatLost))
                            && FanControlConfiguration.decodeResume(storedResume ?? "") == (keepControl ? manual : nil),
                         "a confirmed heartbeat loss preserves the usual opt-in retry and the selected configuration")
        }
        var stopped = FanControlSnapshot.empty
        stopped.stopReason = .heartbeatLost

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
                suite.expect(late != nil && service.requestInFlight == nil && exitingTimer?.invalidated == true && exitingConnection?.invalidated == true
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
                suite.expect(service.proxy.statusReads == 1 && service.requestInFlight != nil, "polling leaves the in-flight status request alone")
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
            suite.expect(service.snapshot == .empty && service.interruption == .stopped(.heartbeatLost)
                            && !service.isWorking && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                            && service.proxy.writes == priorWrites && service.scheduledResumes.isEmpty && service.applied.isEmpty,
                         "confirmed automatic control ends the wait without reapplying the failed curve on a later wake")
            suite.expect(storedResume == nil && defaults.bool(forKey: DefaultsKey.fanControlResume)
                            && defaults.string(forKey: DefaultsKey.fanControlMode) == FanControlMode.curve.rawValue
                            && defaults.string(forKey: DefaultsKey.fanControlCurves) == storedCurves
                            && defaults.values[DefaultsKey.fanControlCoolingLevel] as? Int == 65,
                         "loss of session consent preserves the user's selected mode, curves, manual speed and resume setting")
            service.statusResponse = .failure(.controlFailed)
            service.applyConfiguration(selection)
            suite.expect(service.proxy.restores == 1 && !service.awaitingSystemControl && storedResume == nil
                            && service.interruptedStop == FanControlStopReason.heartbeatLost.rawValue
                            && service.interruption == .stopped(.heartbeatLost),
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
        let exitingService = service
        let ownedTimer = service.timer
        ownedConnection?.onInvalidate = { [weak exitingService, weak ownedConnection] in
            if let ownedConnection { exitingService?.connectionLost(ownedConnection) }
        }
        service.proxy.holdNextStatus = true
        service.requestStatus()
        let lateReadAtExit = service.proxy.heldStatus
        service.proxy.heldStatus = nil
        service.statusResponse = .success(.empty)
        Service.restoreBeforeTerminationIfNeeded()
        service.statusResponse = .success(stopped) // A late idle reply would otherwise schedule a heartbeat retry.
        lateReadAtExit?()
        ownedTimer?.fire()
        suite.expect(lateReadAtExit != nil && service.proxy.restores == 1 && ownedConnection?.invalidated == true
                        && ownedTimer?.invalidated == true && service.requestInFlight == nil && !service.awaitingSystemControl
                        && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) && service.interruptedStop == nil
                        && FanControlConfiguration.decodeResume(storedResume ?? "") == manual
                        && service.scheduledResumes.isEmpty && service.proxy.heartbeats == 0 && service.proxy.writes == [manual],
                     "intentional termination restores once and ignores synchronous invalidation and a late status without revoking consent")
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
        for panelOpen in [false, true] {
            reset(resume: panelOpen, stored: nil)
            MainActor.assumeIsolated { checkCardFeedback(suite, scenario: .sensorStop(panelOpen: panelOpen)) }
        }
        for scenario: CardScenario in [.applyAvailability(.manual), .applyAvailability(.curve),
                                       .activeConnectionLost(statusInFlight: false), .activeConnectionLost(statusInFlight: true),
                                       .failedFirstApply, .acceptedApplyReplyLost(sleepDuringApply: false),
                                       .acceptedApplyReplyLost(sleepDuringApply: true), .confirm(.missingReason),
                                       .confirm(.unobservedSession), .confirm(.knownReason)] {
            reset(stored: nil)
            MainActor.assumeIsolated { checkCardFeedback(suite, scenario: scenario) }
        }
        reset()
    }

    private enum Confirmation { case missingReason, unobservedSession, knownReason }
    private enum CardScenario {
        case sensorStop(panelOpen: Bool), failedFirstApply, acceptedApplyReplyLost(sleepDuringApply: Bool), confirm(Confirmation)
        case activeConnectionLost(statusInFlight: Bool), applyAvailability(FanControlMode)
    }

    @MainActor private static func checkCardFeedback(_ suite: TestSuite, scenario: CardScenario) {
        var service: Service { Service.shared }
        _ = NSApplication.shared
        let attribute = "AXEnhancedUserInterface"
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previous = NSApp.perform(getter, with: attribute)?.takeUnretainedValue() as? NSNumber ?? false
        NSApp.perform(setter, with: true, with: attribute)
        defer { NSApp.perform(setter, with: previous, with: attribute) }
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 340, height: 420),
                              styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let strings = FanControlFeatureStrings.enUS
        func texts(_ node: AnyObject) -> [(id: String?, text: String)] {
            let value = NSSelectorFromString("accessibilityValue")
            if node.accessibilityRole?() == .staticText, let object = node as? NSObject,
               object.responds(to: value), let text = object.perform(value)?.takeUnretainedValue() as? String {
                return [(node.accessibilityIdentifier?(), text)]
            }
            return (node.accessibilityChildren?() ?? []).flatMap { texts($0 as AnyObject) }
        }
        let defaults = UserDefaults.standard
        var mode: Binding<FanControlMode> {
            Section(service: service, modeRaw: Binding(
                get: { defaults.string(forKey: DefaultsKey.fanControlMode) ?? FanControlMode.system.rawValue },
                set: { defaults.set($0, forKey: DefaultsKey.fanControlMode) }
            )).modeBinding
        }
        func renderCard(apply: ((FanControlConfiguration) -> Void)? = nil) -> NSHostingView<FanControlCardContent> {
            let card = FanControlCardContent(
                strings: strings, betaLabel: "Beta", snapshot: service.snapshot, fallbackFanSpeeds: [],
                accessState: service.accessState, error: service.error, isWorking: service.isWorking,
                systemControlUnconfirmed: service.awaitingSystemControl, interruption: service.interruption,
                mode: mode, coolingLevel: .constant(defaults.values[DefaultsKey.fanControlCoolingLevel] as? Int ?? 100),
                curves: .constant([FanControlConfiguration.defaultCurve]),
                resume: .constant(defaults.bool(forKey: DefaultsKey.fanControlResume)),
                temperatureUnit: .celsius, authorize: {}, applyConfiguration: apply ?? service.applyConfiguration,
                stopCooling: service.returnToSystem
            )
            let host: NSHostingView<FanControlCardContent>
            if let mounted = window.contentView as? NSHostingView<FanControlCardContent> {
                host = mounted
                host.rootView = card
            } else {
                host = NSHostingView(rootView: card)
                window.contentView = host
            }
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            return host
        }
        func button(labeled label: String, in node: AnyObject) -> AnyObject? {
            if node.accessibilityRole?() == .button, node.accessibilityLabel?() == label { return node }
            for child in node.accessibilityChildren?() ?? [] {
                if let match = button(labeled: label, in: child as AnyObject) { return match }
            }
            return nil
        }
        func expectFeedback(status: String, message: String?, _ context: String) {
            let warnings = [strings.temperatureUnavailable, strings.safetyStopped, strings.failed, strings.applyFailed,
                            strings.helperUnavailable, strings.awaitingSystemControl, strings.alreadyControlled]
            let rendered = texts(renderCard())
            let headers = rendered.filter { $0.id == "fanControl.status" }.map { $0.text }
            let messages = rendered.map { $0.text }.filter(warnings.contains)
            suite.expect(headers == [status] && messages == (message.map { [$0] } ?? []),
                         "\(context): got headers \(headers), messages \(messages)")
        }
        func pollUntilStatusRead() {
            let previousReads = service.proxy.statusReads
            for _ in 0..<60 {
                service.timer?.fire()
                if service.proxy.statusReads > previousReads { break }
            }
            suite.expect(service.proxy.statusReads == previousReads + 1,
                         "the scheduled timer polls the helper while waiting for confirmation")
        }

        let panelOpen: Bool
        switch scenario {
        case .applyAvailability(let selection):
            mode.wrappedValue = selection
            defaults.set(65, forKey: DefaultsKey.fanControlCoolingLevel)
            let controller = FanControlRecoveryContract.Controller()
            let active = controller.statusResponse()
            let manual = selection == .manual
            let label = manual ? strings.applyManual : strings.applyCurve
            let configuration = manual ? FanControlConfiguration.manual(level: 65) : .curve([FanControlConfiguration.defaultCurve])
            func expectApply(enabled: Bool, _ context: String) {
                var applications: [FanControlConfiguration] = []
                let host = renderCard { applications.append($0) }
                guard let apply = button(labeled: label, in: host) else {
                    suite.expect(false, "\(label) is missing \(context)")
                    return
                }
                suite.expect(apply.isAccessibilityEnabled?() == enabled, "\(label) reports the wrong availability \(context)")
                _ = apply.accessibilityPerformPress?()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                suite.expect(applications == (enabled ? [configuration] : []), "\(label) dispatched \(applications) \(context)")
            }
            service.applyStatus(active)
            expectApply(enabled: true, "during normal control")
            service.observeFailedHandoff(nil)
            // A relaunched service remembers the pending handoff independently of isWorking.
            Service.shared = Service()
            service.applyStatus(active)
            suite.expect(service.awaitingSystemControl && !service.isWorking, "the card awaits confirmation with no work in flight")
            expectApply(enabled: false, "while system control is unconfirmed")
            _ = controller.performRestore(reason: nil)
            service.applyStatus(controller.statusResponse())
            expectApply(enabled: true, "after confirmed automatic control")
            service.isWorking = true
            expectApply(enabled: false, "while a request is in progress")
            service.isWorking = false
            service.snapshot.temperatures = []
            expectApply(enabled: manual, "without a curve sensor")
            return
        case .activeConnectionLost(let statusInFlight):
            checkActiveConnectionLoss(suite, statusInFlight: statusInFlight, expect: expectFeedback, poll: pollUntilStatusRead)
            return
        case .failedFirstApply:
            checkFailedFirstApply(suite, mode: mode, expect: expectFeedback, poll: pollUntilStatusRead)
            return
        case .acceptedApplyReplyLost(let sleepDuringApply):
            checkLostApplyReply(suite, sleepDuringApply: sleepDuringApply, expect: expectFeedback, poll: pollUntilStatusRead)
            return
        case .confirm(let source):
            checkConfirmation(suite, source: source, expect: expectFeedback, poll: pollUntilStatusRead)
            return
        case .sensorStop(let open):
            panelOpen = open
        }

        let controller = FanControlRecoveryContract.Controller()
        let curves = [FanControlConfiguration.defaultCurve]
        let curve = FanControlConfiguration.curve(curves)
        let manual = FanControlConfiguration.manual(level: 65)
        controller.activeConfiguration = curve
        controller.hardware?.restoreResults = [false, true]
        service.controller = controller
        let active = controller.statusResponse().snapshot
        defaults.set(FanControlConfiguration.encodeCurves(curves), forKey: DefaultsKey.fanControlCurves)
        defaults.set(65, forKey: DefaultsKey.fanControlCoolingLevel)
        mode.wrappedValue = .curve
        service.panelIsVisible = true
        service.proxy.holdNextApply = true
        service.applyConfiguration(curve)
        expectFeedback(status: strings.systemControl, message: nil,
                       "an initial Apply keeps the last status while waiting for the controller")
        let applied = service.proxy.heldApply
        service.proxy.heldApply = nil
        applied?()
        suite.expect(applied != nil && service.snapshot.isCooling && service.timer != nil,
                     "an accepted curve starts the scheduled heartbeat")
        service.panelIsVisible = panelOpen
        service.stopIdleWorkIfPossible()

        controller.hardware?.temperatures = []
        for _ in 0..<FanControlPolicy.temperatureFailureLimit { controller.watchdogTick() }
        service.timer?.fire()
        suite.expect(controller.isRecovering && controller.lastStopReason == .temperatureUnavailable
                        && service.proxy.heartbeats == 1 && service.awaitingSystemControl
                        && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                     "the watchdog's failed restore enters confirmation through the scheduled heartbeat")
        expectFeedback(status: strings.controlUnconfirmed, message: strings.awaitingSystemControl,
                       "a stopped sensor cannot announce system control before the helper confirms it")
        service.applyConfiguration(manual)
        suite.expect(service.proxy.writes == [curve] && service.scheduledResumes.isEmpty,
                     "a pending handoff allows neither a manual write nor a retry")
        service.controller = nil // A transport failure between two helper replies.
        pollUntilStatusRead()
        expectFeedback(status: strings.controlUnconfirmed, message: strings.helperUnavailable,
                       "losing the helper during recovery leaves the status unconfirmed")

        if panelOpen {
            service.controller = FanControlRecoveryContract.Controller() // Another active session.
            pollUntilStatusRead()
            expectFeedback(status: strings.controlUnconfirmed, message: strings.awaitingSystemControl,
                           "an unrelated active session does not confirm our handoff")
            Service.restoreBeforeTerminationIfNeeded()
            Service.shared = Service()
            service.panelIsVisible = true
            Service.recoverIfNeeded()
            expectFeedback(status: strings.controlUnconfirmed, message: strings.awaitingSystemControl,
                           "relaunching remembers the pending handoff before a new helper reply")
        }
        controller.watchdogTick()
        service.controller = controller
        pollUntilStatusRead()
        let stopped = controller.statusResponse().snapshot
        suite.expect(!controller.isRecovering && !controller.ownership.marker && !service.awaitingSystemControl
                        && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                        && service.snapshot == stopped && stopped.stopReason == .temperatureUnavailable,
                     "the timer observes the controller's successful restore with its original stop reason")
        expectFeedback(status: strings.systemControl, message: strings.temperatureUnavailable,
                       "the card explains the sensor stop once restoration succeeds")
        suite.expect(defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) == nil
                        && defaults.bool(forKey: DefaultsKey.fanControlResume) == panelOpen
                        && defaults.string(forKey: DefaultsKey.fanControlCurves) == FanControlConfiguration.encodeCurves(curves)
                        && defaults.values[DefaultsKey.fanControlCoolingLevel] as? Int == 65
                        && mode.wrappedValue == .curve && service.scheduledResumes.isEmpty,
                     "a failed session keeps the user's choices without authorizing another write")
        if !panelOpen {
            suite.expect(service.timer == nil && service.connection == nil && !service.observing,
                         "confirmation stops closed-panel polling when resume is off")
            service.panelIsVisible = true
            service.controller = nil
            var idle = stopped
            idle.stopReason = nil // A newly started helper has no prior stop.
            service.statusResponse = .success(idle)
            service.requestStatus()
            expectFeedback(status: strings.systemControl, message: strings.temperatureUnavailable,
                           "reopening after the helper exits preserves the sensor cause without a retry")
        }

        let rawSnapshot = service.snapshot
        mode.wrappedValue = .system
        expectFeedback(status: strings.systemControl, message: nil,
                       "selecting System immediately dismisses the confirmed stop")
        suite.expect(service.snapshot == rawSnapshot, "selecting System preserves the helper's actual snapshot")
        for _ in 0..<2 {
            service.requestStatus()
            expectFeedback(status: strings.systemControl, message: nil,
                           "idle replies after dismissal do not redisplay the old sensor stop")
            suite.expect(service.snapshot == rawSnapshot, "dismissing the diagnosis preserves the helper's snapshot")
        }
        Service.shared = Service() // Keep only the preferences after dismissing the confirmed handoff.
        service.panelIsVisible = true
        service.connection = Invalidating()
        Service.recoverIfNeeded()
        expectFeedback(status: strings.systemControl, message: nil,
                       "relaunching does not resurrect the dismissed diagnosis before the first status reply")
        service.controller = controller
        service.requestStatus()
        expectFeedback(status: strings.systemControl, message: nil,
                       "the helper's old sensor stop stays dismissed after relaunch")
        suite.expect(!service.awaitingSystemControl && service.proxy.writes.isEmpty && service.scheduledResumes.isEmpty
                        && service.applied.isEmpty && Service.resumableConfiguration == nil
                        && defaults.bool(forKey: DefaultsKey.fanControlResume) == panelOpen
                        && mode.wrappedValue == .system,
                     "relaunching preserves the user's choice without retrying control")
        service.controller = nil
        service.statusResponse = .failure(.controlFailed)
        service.requestStatus()
        service.statusResponse = .success(stopped)
        service.requestStatus()
        expectFeedback(status: strings.systemControl, message: nil,
                       "a failed read between idle replies does not turn the old reason into a new stop")

        if !panelOpen {
            var laterStop = stopped
            laterStop.stopReason = .hardwareChanged
            service.statusResponse = .success(laterStop)
            service.requestStatus()
            expectFeedback(status: strings.systemControl, message: strings.safetyStopped,
                           "a different reported cause retires the dismissed sensor diagnosis")
            Service.shared = Service()
            Service.recoverIfNeeded()
            expectFeedback(status: strings.systemControl, message: nil,
                           "relaunch does not resurrect the retired cause of the failed handoff")
            service.statusResponse = .success(laterStop)
            service.requestStatus()
            suite.expect(service.interruptedStop != nil && Service.resumableConfiguration == nil
                            && defaults.string(forKey: DefaultsKey.fanControlDismissedStop) == nil,
                         "retiring the old diagnosis preserves the requirement for a new manual Apply")
        }
        mode.wrappedValue = .manual
        var manuallyControlled = active
        manuallyControlled.configuration = manual
        manuallyControlled.coolingLevel = 65
        service.statusResponse = .success(manuallyControlled)
        let previousWrites = service.proxy.writes
        let pressed = button(labeled: strings.applyManual, in: renderCard())?.accessibilityPerformPress?() ?? false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        suite.expect(pressed && service.proxy.writes == previousWrites + [manual] && service.interruptedStop == nil
                        && FanControlConfiguration.decodeResume(defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) ?? "")
                            == (panelOpen ? manual : nil),
                     "an explicit manual Apply starts a fresh session and respects the resume preference")
        expectFeedback(status: "\(strings.manualControl) · 65%", message: nil,
                       "the card shows the newly accepted manual speed")
        guard panelOpen else { return }

        func runCurveUntilStop(_ reason: FanControlStopReason) {
            mode.wrappedValue = .curve
            service.statusResponse = .success(active)
            service.applyConfiguration(curve)
            var interrupted = stopped
            interrupted.stopReason = reason
            service.statusResponse = .success(interrupted)
            service.timer?.fire()
        }
        runCurveUntilStop(.temperatureUnavailable)
        expectFeedback(status: strings.systemControl, message: strings.temperatureUnavailable,
                       "a new curve session reports the same sensor stop again")
        mode.wrappedValue = .system
        let otherClient = UUID()
        let otherApply = controller.applyConfiguration(session: otherClient, configuration: manual, duration: nil)
        let interrupted = controller.performRestore(reason: .thermalPressure)
        suite.expect(otherApply.succeeded && interrupted && controller.lastStopReason == .thermalPressure,
                     "a later session genuinely stops for a different reason")
        service.controller = controller
        service.requestStatus()
        expectFeedback(status: strings.systemControl, message: strings.safetyStopped,
                       "an idle reply reporting a different cause still explains the stop")
        controller.hardware?.temperatures = [.init(source: .hottestSoC, celsius: 60)]
        let otherCurve = controller.applyConfiguration(session: otherClient, configuration: curve, duration: nil)
        controller.hardware?.temperatures = []
        for _ in 0..<FanControlPolicy.temperatureFailureLimit { controller.watchdogTick() }
        suite.expect(otherCurve.succeeded && controller.lastStopReason == .temperatureUnavailable,
                     "the watchdog detects a new loss of the same sensor")
        service.requestStatus()
        expectFeedback(status: strings.systemControl, message: strings.temperatureUnavailable,
                       "after a different stop, the same sensor can be reported again")
        Service.shared = Service()
        service.panelIsVisible = true
        Service.recoverIfNeeded()
        service.controller = controller
        service.requestStatus()
        expectFeedback(status: strings.systemControl, message: strings.temperatureUnavailable,
                       "relaunch does not dismiss the new sensor stop that followed a different diagnosis")
        service.controller = nil
        runCurveUntilStop(.hardwareChanged)
        expectFeedback(status: strings.systemControl, message: strings.safetyStopped,
                       "a safety stop also explains why a kept curve stopped")
        service.workspaceDidWake()
        for _ in 0...FanControlResumePolicy.retryDelays.count { service.resumeDidFail(.controlFailed) }
        service.statusResponse = .success(stopped)
        service.requestStatus()
        expectFeedback(status: strings.systemControl, message: strings.failed,
                       "a later exhausted resume takes precedence over the helper's last stop")
    }

    @MainActor private static func checkFailedFirstApply(_ suite: TestSuite, mode: Binding<FanControlMode>,
                                                         expect: (String, String?, String) -> Void,
                                                         poll: () -> Void) {
        let service = Service.shared
        let defaults = UserDefaults.standard
        let strings = FanControlFeatureStrings.enUS
        let manual = FanControlConfiguration.manual(level: 65)
        let controller = FanControlRecoveryContract.Controller()
        controller.isCooling = false
        controller.owner = nil
        controller.coolingLevel = nil
        controller.activeConfiguration = nil
        controller.ownership.marker = false
        controller.hardware?.isManual = false
        controller.hardware?.writeError = .unsafeControlState
        controller.hardware?.restoreResults = [false]
        let session = UUID()
        service.proxy.onApply = { [unowned service] configuration in
            service.statusResponse = controller.applyConfiguration(session: session, configuration: configuration, duration: nil)
        }
        service.proxy.onRestore = { [unowned service] in
            let restored = controller.performRestore(reason: nil)
            let snapshot = controller.currentSnapshot()
            service.statusResponse = restored ? .success(snapshot) : .failure(.controlFailed, snapshot: snapshot)
        }
        service.applyConfiguration(manual)
        suite.expect(controller.isRecovering && controller.hardware?.isManual == true && controller.ownership.marker
                        && controller.lastStopReason == .recovery && service.awaitingSystemControl && service.isWorking
                        && service.proxy.restores == 0
                        && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) && service.timer != nil,
                     "the first Apply can leave hardware changed and recovery pending without an earlier accepted session")
        expect(strings.controlUnconfirmed, strings.awaitingSystemControl,
               "a partial first Apply reports unconfirmed system control")
        service.applyConfiguration(manual)
        service.workspaceDidWake()
        suite.expect(service.proxy.writes == [manual] && service.applied.isEmpty && service.scheduledResumes.isEmpty,
                     "an unconfirmed first Apply blocks another write and an automatic resume")
        service.controller = controller
        poll()
        expect(strings.controlUnconfirmed, strings.awaitingSystemControl,
               "the timer keeps observing a failed first Apply while the controller is recovering")
        controller.hardware?.restoreResults = [true]
        controller.watchdogTick()
        poll()
        suite.expect(!controller.isRecovering && controller.hardware?.isManual == false
                        && !service.awaitingSystemControl && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                        && service.snapshot.stopReason == .recovery && service.proxy.writes == [manual],
                     "only a confirmed return to automatic control completes recovery after a failed first Apply")
        expect(strings.systemControl, strings.safetyStopped, "the confirmed first-Apply recovery keeps its diagnosis")

        // The helper can repeat .recovery from the previous stop even after this attempt restores successfully.
        let hardware = controller.hardware
        mode.wrappedValue = .system
        expect(strings.systemControl, nil, "selecting System dismisses the old recovery")
        mode.wrappedValue = .manual
        service.controller = nil
        service.applyConfiguration(manual)
        suite.expect(hardware?.isManual == false && !controller.isRecovering && service.awaitingSystemControl
                        && service.proxy.restores == 0,
                     "a refusal repeating recovery waits for a fresh status without requesting another restore")
        let reopened = Service()
        suite.expect(reopened.awaitingSystemControl && reopened.interruption == .applyFailed,
                     "relaunch during confirmation remembers the new refusal instead of the old dismissal")
        controller.hardware = hardware // The next RPM probe reads the same physical fans.
        service.controller = controller
        poll()
        suite.expect(!controller.isRecovering && !controller.ownership.marker && service.snapshot.stopReason == .recovery
                        && !service.awaitingSystemControl && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                        && service.proxy.restores == 0,
                     "current idle telemetry confirms a refusal that repeated the previous recovery")
        expect(strings.systemControl, strings.applyFailed, "a new refused Apply explains its own failure after confirmation")

        mode.wrappedValue = .system
        mode.wrappedValue = .manual
        hardware?.restoreResults = [false, true]
        hardware?.failNextRPMRead = true
        service.controller = nil
        service.applyConfiguration(manual)
        suite.expect(service.snapshot.fans.isEmpty && service.awaitingSystemControl,
                     "a failed RPM read leaves the repeated reason unverified until the next status")
        service.controller = controller
        poll()
        controller.watchdogTick()
        poll()
        service.requestStatus()
        expect(strings.systemControl, strings.applyFailed,
               "later recovery telemetry cannot revive the dismissed reason after the refused Apply returned no RPM")

        mode.wrappedValue = .system
        mode.wrappedValue = .manual
        hardware?.restoreResults = [false, true]
        service.controller = nil
        service.applyConfiguration(manual)
        suite.expect(service.snapshot.fans.contains(where: \.isManuallyControlled) && service.awaitingSystemControl,
                     "the refused Apply itself reports a manual fan during the new recovery")
        controller.watchdogTick()
        service.controller = controller
        poll()
        expect(strings.systemControl, strings.safetyStopped,
               "a new recovery identified by the refused Apply can report the same stop after confirmation")
    }

    @MainActor private static func checkActiveConnectionLoss(_ suite: TestSuite, statusInFlight: Bool,
                                                            expect: (String, String?, String) -> Void,
                                                            poll: () -> Void) {
        let service = Service.shared
        let defaults = UserDefaults.standard
        let strings = FanControlFeatureStrings.enUS
        let controller = FanControlRecoveryContract.Controller()
        controller.isCooling = false
        controller.owner = nil
        controller.activeConfiguration = nil
        controller.ownership.marker = false
        controller.hardware?.isManual = false
        controller.connectionCount = 2 // B is connected but has not requested control.
        let sessionA = UUID()
        let sessionB = UUID()
        var rule = FanControlConfiguration.defaultCurve
        rule.sensor = .hottestCPU
        controller.hardware?.temperatures = [.init(source: .hottestCPU, celsius: 60)]
        let curve = FanControlConfiguration.curve([rule])
        let storedCurves = FanControlConfiguration.encodeCurves([rule])
        defaults.set(storedCurves, forKey: DefaultsKey.fanControlCurves)
        defaults.set(FanControlMode.curve.rawValue, forKey: DefaultsKey.fanControlMode)
        defaults.set(65, forKey: DefaultsKey.fanControlCoolingLevel)

        let previous = service.connection
        let connection = Invalidating()
        service.connection = connection
        connection.onInvalidate = { [weak service, weak connection] in
            controller.connectionClosed(sessionA)
            if let connection { service?.connectionLost(connection) }
        }
        service.proxy.onApply = { [unowned service] choice in
            service.statusResponse = controller.applyConfiguration(session: sessionA, configuration: choice, duration: nil)
        }
        service.applyConfiguration(curve)
        let active = controller.statusResponse()
        if let previous { service.connectionLost(previous) } // A late notification from the previous connection.
        suite.expect(service.connection === connection && controller.owner == sessionA && active.succeeded
                        && active.snapshot.isCooling && service.snapshot == active.snapshot && !service.awaitingSystemControl
                        && Service.resumableConfiguration == curve && service.timer != nil,
                     "an acknowledged Apply owns the fans and carries resume consent until its own connection breaks")
        if statusInFlight {
            service.proxy.holdNextStatus = true
            service.requestStatus()
        }
        let lateReply = service.proxy.heldStatus
        service.proxy.heldStatus = nil
        suite.expect((lateReply != nil) == statusInFlight && service.requestInFlight == (statusInFlight ? .read : nil),
                     "the connection breaks with the requested status-read state")
        connection.invalidate()
        suite.expect(service.requestInFlight == nil && service.awaitingSystemControl && service.isWorking
                        && controller.lastStopReason == .appDisconnected && !controller.isCooling
                        && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                        && defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) == nil,
                     "losing an acknowledged session immediately revokes resume consent and waits for system control")
        expect(strings.controlUnconfirmed, strings.helperUnavailable, "the card reports loss of the active connection")

        let manual = FanControlConfiguration.manual(level: 65)
        let secondApply = controller.applyConfiguration(session: sessionB, configuration: manual, duration: nil)
        suite.expect(secondApply.succeeded && controller.owner == sessionB && service.proxy.writes == [curve]
                        && service.proxy.restores == 0,
                     "B takes control before A sends another request")
        controller.lastHeartbeatUptime -= FanControlPolicy.heartbeatLimit + 1
        controller.watchdogTick()
        let stopped = controller.statusResponse()
        suite.expect(stopped.succeeded && !stopped.snapshot.isCooling && stopped.snapshot.stopReason == .heartbeatLost
                        && service.proxy.statusReads == (statusInFlight ? 1 : 0) && service.proxy.heartbeats == 0,
                     "B loses its heartbeat before A next polls the same helper")

        service.connection = Invalidating()
        service.controller = controller
        service.proxy.holdNextStatus = true
        poll()
        let currentReply = service.proxy.heldStatus
        service.proxy.heldStatus = nil
        let pendingSnapshot = service.snapshot
        service.controller = nil
        service.statusResponse = active
        lateReply?()
        suite.expect(currentReply != nil && service.requestInFlight == .read && service.awaitingSystemControl
                        && service.snapshot == pendingSnapshot && service.error == .helperUnavailable,
                     "a late reply from A's lost connection cannot complete the current poll or change the diagnosis")
        service.controller = controller
        currentReply?()
        suite.expect(service.scheduledResumes.isEmpty,
                     "B's stop must leave A without a retry, got delays \(service.scheduledResumes)")
        expect(strings.systemControl, strings.failed, "confirmation does not attribute B's stop to A")
        service.requestStatus() // The idle helper still reports B's stop.
        service.workspaceDidWake()
        service.retryResume()
        suite.expect(!service.awaitingSystemControl && !service.isWorking && service.snapshot == stopped.snapshot
                        && service.interruption == .stopped(nil) && service.interruptedStop == ""
                        && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                        && defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) == nil
                        && defaults.bool(forKey: DefaultsKey.fanControlResume)
                        && defaults.string(forKey: DefaultsKey.fanControlMode) == FanControlMode.curve.rawValue
                        && defaults.string(forKey: DefaultsKey.fanControlCurves) == storedCurves
                        && defaults.values[DefaultsKey.fanControlCoolingLevel] as? Int == 65,
                     "confirming A's handoff keeps only B's raw telemetry and preserves the user's settings")
        suite.expect(service.proxy.writes == [curve] && service.proxy.restores == 0 && service.proxy.heartbeats == 0
                        && service.applied.isEmpty && service.scheduledResumes.isEmpty,
                     "later status and wake perform no restore, write, heartbeat, or resume on behalf of A")
        expect(strings.systemControl, strings.failed, "after wake the card still shows no cause attributable to A")
    }

    @MainActor private static func checkLostApplyReply(_ suite: TestSuite, sleepDuringApply: Bool,
                                                      expect: (String, String?, String) -> Void,
                                                      poll: () -> Void) {
        let service = Service.shared
        let defaults = UserDefaults.standard
        let strings = FanControlFeatureStrings.enUS
        let manual = FanControlConfiguration.manual(level: 65)
        let controller = FanControlRecoveryContract.Controller()
        controller.isCooling = false
        controller.owner = nil
        controller.coolingLevel = nil
        controller.activeConfiguration = nil
        controller.ownership.marker = false
        controller.hardware?.isManual = false
        controller.hardware?.restoreResults = [false, false, true]
        let session = UUID()
        let connection = service.connection
        connection?.onInvalidate = { [weak service, weak connection] in
            controller.connectionClosed(session)
            if let connection { service?.connectionLost(connection) }
        }
        var accepted: FanControlResponse?
        service.proxy.holdNextApply = true
        service.proxy.onApply = { [unowned service] configuration in
            accepted = controller.applyConfiguration(session: session, configuration: configuration, duration: nil)
            if !sleepDuringApply { connection?.invalidate() }
            service.statusResponse = nil
        }
        service.applyConfiguration(manual)
        if !sleepDuringApply {
            suite.expect(service.proxy.heldApply != nil && service.awaitingSystemControl && service.requestInFlight == nil,
                         "the closed connection starts confirmation even when the accepted Apply never replies")
            expect(strings.controlUnconfirmed, strings.helperUnavailable,
                   "connection loss immediately makes control unconfirmed before the Apply callback")
            service.proxy.heldApply = nil
        }
        if sleepDuringApply {
            service.applyConfiguration(manual)
            suite.expect(service.requestInFlight == .apply && controller.owner == session && !controller.isRecovering,
                         "the helper accepted the first Apply while the client still awaits its reply")
            suite.expect(service.proxy.writes == [manual], "a second Apply cannot supersede the unresolved write")
            service.workspaceWillSleep()
            let lateApply = service.proxy.heldApply
            service.proxy.heldApply = nil
            suite.expect(connection?.invalidated == true && service.connection == nil && lateApply != nil
                            && service.requestInFlight == nil && service.proxy.restores == 0 && controller.isRecovering,
                         "sleep closes only the pending Apply's connection and the helper restores its owner")
            service.statusResponse = accepted
            lateApply?()
            suite.expect(!service.snapshot.isCooling && service.requestInFlight == nil
                            && defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) == nil,
                         "the old accepted reply cannot reclaim the fans or grant resume consent after sleep")
            service.statusResponse = nil
        }
        suite.expect(accepted?.succeeded == true && accepted?.snapshot.configuration == manual
                        && accepted?.snapshot.isCooling == true && controller.isRecovering
                        && controller.hardware?.isManual == true && controller.lastStopReason == .appDisconnected
                        && service.awaitingSystemControl && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                        && service.timer != nil && service.proxy.restores == 0,
                     "losing an accepted Apply reply observes recovery without claiming or restoring the fans")
        poll() // Status is unavailable too.
        expect(strings.controlUnconfirmed, strings.helperUnavailable,
               "the card still awaits automatic control when neither Apply nor status replied")
        service.workspaceDidWake()
        service.retryResume()
        let writesBeforeRetry = service.proxy.writes
        service.proxy.onApply = nil
        service.applyConfiguration(manual)
        suite.expect(writesBeforeRetry == [manual] && service.proxy.writes == writesBeforeRetry
                        && service.proxy.restores == 0 && service.applied.isEmpty && service.scheduledResumes.isEmpty,
                     "no write, blind restore, or resume is allowed while the accepted request is unconfirmed")
        controller.watchdogTick()
        service.controller = controller
        poll()
        expect(strings.controlUnconfirmed, strings.awaitingSystemControl,
               "a failed watchdog restore still cannot confirm system control")
        controller.watchdogTick()
        poll()
        suite.expect(!controller.ownership.marker && controller.hardware?.isManual == false
                        && !service.awaitingSystemControl && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                        && service.snapshot.stopReason == .appDisconnected && service.proxy.restores == 0
                        && defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) == nil,
                     "automatic telemetry ends the wait while preserving the helper's raw snapshot")
        expect(strings.systemControl, strings.failed, "a later status cannot attribute the lost request's stop reason")
    }

    @MainActor private static func checkConfirmation(_ suite: TestSuite, source: Confirmation,
                                                    expect: (String, String?, String) -> Void,
                                                    poll: () -> Void) {
        let service = Service.shared
        let strings = FanControlFeatureStrings.enUS
        let controller = FanControlRecoveryContract.Controller()
        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        controller.activeConfiguration = curve
        controller.hardware?.restoreResults = source == .knownReason ? [false, true] : [true]
        service.controller = controller
        service.applyConfiguration(curve)
        controller.hardware?.temperatures = []
        for _ in 0..<FanControlPolicy.temperatureFailureLimit { controller.watchdogTick() }
        if source != .knownReason { controller.hardware?.failNextRPMRead = true }
        service.timer?.fire()
        suite.expect(service.awaitingSystemControl && controller.lastStopReason == .temperatureUnavailable
                        && service.snapshot.stopReason == (source == .knownReason ? .temperatureUnavailable : nil)
                        && service.error == .controlFailed,
                     "the first stopped heartbeat reports only the diagnosis available from hardware")
        expect(strings.controlUnconfirmed, strings.awaitingSystemControl,
               "the first failed reading waits for confirmation")

        switch source {
        case .missingReason:
            service.proxy.holdNextStatus = true
            service.requestStatus()
            let superseding = service.beginRequest()
            let obsolete = service.proxy.heldStatus
            service.proxy.heldStatus = nil
            obsolete?()
            suite.expect(obsolete != nil && service.awaitingSystemControl && service.interruptedStop == ""
                            && service.snapshot.stopReason == nil && service.requestInFlight != nil,
                         "a superseded status reply cannot add a cause to the pending handoff")
            _ = service.finishRequest(superseding, response: nil)
        case .unobservedSession:
            let otherClient = UUID()
            let accepted = controller.applyConfiguration(session: otherClient, configuration: .manual(level: 65), duration: nil)
            let owned = controller.owner == otherClient && controller.isCooling
            let restored = controller.performRestore(reason: .appDisconnected)
            suite.expect(accepted.succeeded && owned && restored && controller.lastStopReason == .appDisconnected
                            && service.proxy.statusReads == 0 && service.awaitingSystemControl,
                         "another client starts and stops on the same helper between our failed heartbeat and first status")
        case .knownReason:
            controller.watchdogTick()
            let later = FanControlRecoveryContract.Controller()
            _ = later.performRestore(reason: .thermalPressure)
            service.controller = later
        }
        poll()
        let expected: FanControlStopReason? = source == .knownReason ? .temperatureUnavailable : nil
        let reported = service.controller?.statusResponse().snapshot
        suite.expect(!service.awaitingSystemControl && reported == service.snapshot
                        && service.interruption == .stopped(expected) && service.interruptedStop == (expected?.rawValue ?? "")
                        && !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                     "confirmation (\(source)) keeps the raw reply and stores only a cause attributable to this handoff")
        let message = expected == nil ? strings.failed : strings.temperatureUnavailable
        expect(strings.systemControl, message, "the confirmed handoff (\(source)) shows its attributable diagnosis")
        Service.shared = Service()
        expect(strings.systemControl, message, "the confirmed diagnosis (\(source)) survives a relaunch")
    }
}
