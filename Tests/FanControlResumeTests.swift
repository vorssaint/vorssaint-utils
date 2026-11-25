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
        weak var client: Fixture?
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
        func remoteObjectProxyWithErrorHandler(_ handler: @escaping (Error) -> Void) -> Any? {
            client.map(ExitProxy.init)
        }
    }
    typealias Timer = Invalidating
    typealias NSXPCConnection = Invalidating
    typealias FanControlXPCProtocol = ExitProxy
    struct ExitProxy {
        unowned let client: Fixture
        func restoreOwnedControl(_ reply: @escaping (Data) -> Void) {
            client.send({ proxy, complete in proxy.restoreOwnedControl(withReply: complete) }) { response in
                if let response { reply(FanControlIPC.encode(response)) }
            }
        }
    }
    final class StatusProxy {
        var statusReads = 0
        var heartbeats = 0
        var restores = 0
        var ownedRestores = 0
        var holdRestore = false
        var heldRestore: (() -> Void)?
        var holdNextStatus = false
        var heldStatus: (() -> Void)?
        var holdNextApply = false
        var heldApply: (() -> Void)?
        var onApply: ((FanControlConfiguration) -> Void)?
        var onHeartbeat: (() -> Void)?
        var onStatus: (() -> Void)?
        var onRestore: (() -> Void)?
        var onOwnedRestore: (() -> Void)?
        var onPrepareForUnregister: (() -> Void)?
        var heldPreparation: (() -> Void)?
        var holdPreparation = false
        var preparationCount = 0
        var writes: [FanControlConfiguration] = []
        func status(withReply reply: @escaping () -> Void) {
            statusReads += 1
            onStatus?()
            if holdNextStatus {
                holdNextStatus = false
                heldStatus = reply
            } else { reply() }
        }
        func heartbeat(withReply reply: () -> Void) { heartbeats += 1; onHeartbeat?(); reply() }
        func restoreAutomatic(withReply reply: @escaping () -> Void) {
            restores += 1
            onRestore?()
            if holdRestore { heldRestore = reply } else { reply() }
        }
        func restoreOwnedControl(withReply reply: @escaping () -> Void) {
            ownedRestores += 1
            onOwnedRestore?()
            if holdRestore { heldRestore = reply } else { reply() }
        }
        func prepareForUnregister(withReply reply: @escaping () -> Void) {
            preparationCount += 1
            onPrepareForUnregister?()
            if holdPreparation { heldPreparation = reply } else { reply() }
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
            var registerCalls = 0
            var unregisterAttempts = 0
            var registerAttempts = 0
            var fails = false
            var registerFails = false
            var status: AccessState?
            var onUnregister: (() -> Void)?
            var holdUnregister = false
            var heldUnregister: (() -> Void)?
            func unregister() throws {
                unregisterAttempts += 1
                if fails { throw FanControlErrorCode.helperUnavailable }
                unregisterCalls += 1
                status = .notRegistered
                onUnregister?()
            }
            func unregister(completionHandler reply: @escaping (Error?) -> Void) {
                let error: Error?
                do { try unregister(); error = nil }
                catch let failure { error = failure }
                if holdUnregister { heldUnregister = { reply(error) } }
                else { reply(error) }
            }
            func register() throws {
                registerAttempts += 1
                if registerFails { throw FanControlErrorCode.helperUnavailable }
                registerCalls += 1
                status = .enabled
            }
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
        var activeConfiguration: FanControlConfiguration?
        var supportsOwnedRestore: Bool?
        var workspaceIsSleeping = false
        var recoveryPollInterval = 2
        var checkingUnregister = false
        var registrationAttemptedVersion: String?
        var requestGeneration = 0
        var requestInFlight: FanControlRequest?
        var panelIsVisible = false
        var timer: Invalidating?
        var connection: Invalidating? {
            didSet { connection?.client = self }
        }
        var observing = true
        var isWorking = false
        var resumeFailures = 0
        var scheduledResumes: [TimeInterval] = []
        var applied: [FanControlConfiguration] = []
        var onResume: ((FanControlConfiguration) -> Void)?
        var events: [String] = []
        func send(_ operation: (StatusProxy, @escaping () -> Void) -> Void,
                  completion: @escaping (FanControlResponse?) -> Void) {
            operation(proxy) { completion(self.controller?.statusResponse() ?? self.statusResponse) }
        }
        func refreshAccessState() {
            if let status = Self.appService.status { accessState = status }
        }
        func applyConfiguration(_ configuration: FanControlConfiguration, resuming: Bool) {
            applied.append(configuration)
            onResume?(configuration)
        }
        func scheduleResumeAttempt(after delay: TimeInterval) { scheduledResumes.append(delay) }
        func cancelResumeAttempt() { scheduledResumes.removeAll() }
        func authorize() { events.append("authorize") }
        func refreshLocalProbe() { events.append("probe") }
        func startObservingSystemState() { observing = true }
        func stopObservingSystemState() {
            guard observing else { return }
            observing = false
            workspaceIsSleeping = false
        }
    }

    static func run(_ suite: TestSuite) {
        var service: Service { Service.shared }
        let defaults = UserDefaults.standard
        let manual = FanControlConfiguration.manual(level: 100)
        func reset(resume: Bool = true, stored: FanControlConfiguration? = manual,
                   recovery: Bool = false) {
            Environment.available = true
            Service.appService.unregisterCalls = 0
            Service.appService.registerCalls = 0
            Service.appService.unregisterAttempts = 0
            Service.appService.registerAttempts = 0
            Service.appService.fails = false
            Service.appService.registerFails = false
            Service.appService.status = nil
            Service.appService.onUnregister = nil
            Service.appService.holdUnregister = false
            Service.appService.heldUnregister = nil
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
        suite.expect(service.applied.isEmpty && service.proxy.restores == 0 && service.proxy.ownedRestores == 0,
                     "launch without a known owner observes recovery without changing any session")
        reset(recovery: true)
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.events.isEmpty && service.proxy.restores == 0,
                     "even valid prior consent cannot override an unfinished recovery")
        reset()
        defaults.values[DefaultsKey.fanControlResumeConfiguration] = #"{"curves":[],"manualLevel":100,"mode":"manual"}"#
        Service.recoverIfNeeded()
        service.workspaceDidWake()
        suite.expect(Service.resumableConfiguration == nil && service.applied.isEmpty && service.proxy.restores == 0,
                     "an older valid stored configuration without an owned-release acknowledgment never reapplies")
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
        suite.expect(storedResume == nil,
                     "turning resume on cannot turn an active snapshot into permission to resume")
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
        service.workspaceWillSleep()
        service.workspaceDidWake()
        suite.expect(service.applied == [manual] && service.events.isEmpty && service.proxy.restores == 0,
                     "waking re-applies the kept control")
        reset(resume: false, recovery: true)
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.proxy.restores == 0,
                     "wake without an acknowledged owner leaves a possibly unrelated session alone")
        reset(resume: false)
        service.panelIsVisible = true
        service.workspaceWillSleep()
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.proxy.statusReads == 1 && service.proxy.restores == 0,
                     "without resume, waking only refreshes a visible panel")


        let retryableRefusal = FanControlResponse.failure(.controlFailed, retryableApply: true)
        // A resume can fail for a moment right after a wake, before the fans and
        // sensors answer again. One refusal must not leave the fans on System
        // while the card still shows the curve as chosen.
        reset()
        service.workspaceWillSleep()
        service.workspaceDidWake()
        service.resumeDidFail(retryableRefusal)
        suite.expect(service.scheduledResumes == [FanControlResumePolicy.retryDelays[0]],
                     "a resume refused right after a wake is tried again shortly")
        service.retryResume()
        suite.expect(service.applied == [manual, manual],
                     "the retry re-applies the kept control")
        reset()
        for _ in FanControlResumePolicy.retryDelays { service.resumeDidFail(retryableRefusal) }
        suite.expect(service.scheduledResumes == FanControlResumePolicy.retryDelays && service.interruption == nil,
                     "failed resumes back off through every planned retry")
        service.resumeDidFail(retryableRefusal)
        suite.expect(service.scheduledResumes == FanControlResumePolicy.retryDelays && service.interruption == .resumeFailed,
                     "resuming gives up after the last retry and says so instead of looking active")
        service.workspaceWillSleep()
        service.workspaceDidWake()
        suite.expect(service.resumeFailures == 0 && service.interruption == nil
                        && service.applied == [manual],
                     "a later wake starts a fresh resume with the full retry budget")
        reset(resume: false, stored: nil)
        service.resumeDidFail(retryableRefusal)
        suite.expect(service.scheduledResumes.isEmpty && service.interruption == nil,
                     "without resume a failed apply is never retried")
        reset()
        service.resumeDidFail(retryableRefusal)
        service.returnToSystem()
        service.retryResume()
        suite.expect(service.scheduledResumes.isEmpty && service.applied.isEmpty,
                     "returning to System cancels a pending resume retry")
        reset()
        service.resumeDidFail(retryableRefusal)
        defaults.values[DefaultsKey.fanControlResume] = false
        service.resumePreferenceDidChange()
        suite.expect(service.scheduledResumes.isEmpty, "turning resume off cancels a pending retry")
        reset()
        service.resumeDidFail(retryableRefusal)
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
        service.workspaceWillSleep()
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.scheduledResumes.count == 1,
                     "a wake under thermal pressure defers even its initial application")
        ProcessInfo.processInfo.thermalState = .fair
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.scheduledResumes.count == 1,
                     "a duplicate wake cannot skip the pending thermal delay")
        service.retryResume()
        suite.expect(service.applied == [manual], "the deferred retry can apply when thermal pressure has eased")
        reset()
        service.resumeDidFail(retryableRefusal)
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
            suite.expect(service.proxy.heartbeats == 1 && service.scheduledResumes.isEmpty
                            && service.snapshot.stopReason == reason && service.interruption == .stopped(nil)
                            && service.interruptedStop == "" && storedResume == nil,
                         "duplicate idle reports preserve the global reason without attributing it or scheduling a retry")
        }
        reset()
        service.resumeDidFail(.failure(.controlFailed, localStopReason: .hardwareChanged))
        suite.expect(service.interruption == .resumeFailed && service.scheduledResumes.isEmpty,
                     "a refused application that lost hardware ownership leaves control with the system")
        for keepControl in [false, true] {
            var idleReplies: [FanControlSnapshot] = []
            for restoreResults in [[true], [false, true]] {
                reset(resume: keepControl, stored: nil)
                let controller = FanControlRecoveryContract.Controller()
                controller.activeConfiguration = manual
                controller.hardware?.restoreResults = restoreResults
                service.controller = controller
                service.applyConfiguration(manual)
                controller.lastHeartbeatUptime -= FanControlPolicy.heartbeatLimit + 1
                for _ in restoreResults { controller.watchdogTick() }
                service.timer?.fire()
                idleReplies.append(service.snapshot)
                suite.expect(controller.hardware?.restores == restoreResults.count && !controller.isRecovering
                                && service.snapshot.stopReason == .heartbeatLost && service.interruptedStop == ""
                                && !service.awaitingSystemControl && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                             "a completed watchdog restore needs no further confirmation, including after a failed attempt between reads")
                service.retryResume()
                service.workspaceWillSleep()
                service.workspaceDidWake()
                suite.expect(service.scheduledResumes.isEmpty && service.applied.isEmpty && service.interruption == .stopped(nil)
                                && storedResume == nil && defaults.bool(forKey: DefaultsKey.fanControlResume) == keepControl,
                             "an idle heartbeat requires a new Apply with either resume preference")
            }
            suite.expect(idleReplies[0] == idleReplies[1], "the same idle reply covers both single-client restore histories")
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
                                && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) && service.interruptedStop == "",
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
            service.workspaceWillSleep()
            service.workspaceDidWake()
            service.retryResume()
            suite.expect(service.snapshot == .empty && service.interruption == .stopped(nil)
                            && !service.isWorking && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                            && service.proxy.writes == priorWrites && service.scheduledResumes.isEmpty && service.applied.isEmpty,
                         "confirmed automatic control ends the wait without reapplying the failed curve on a later wake")
            suite.expect(storedResume == nil && defaults.bool(forKey: DefaultsKey.fanControlResume)
                            && defaults.string(forKey: DefaultsKey.fanControlMode) == FanControlMode.curve.rawValue
                            && defaults.string(forKey: DefaultsKey.fanControlCurves) == storedCurves
                            && defaults.values[DefaultsKey.fanControlCoolingLevel] as? Int == 65,
                         "loss of session consent preserves the user's selected mode, curves, manual speed and resume setting")
            service.statusResponse = .failure(.controlFailed)
            let readsBeforeRefusal = service.proxy.statusReads
            service.applyConfiguration(selection)
            suite.expect(service.proxy.restores == 0 && service.proxy.statusReads == readsBeforeRefusal + 1
                            && service.awaitingSystemControl && storedResume == nil
                            && service.interruptedStop == "" && service.interruption == .stopped(nil),
                         "a refused explicit application with no owner waits for an idle status without a global restore")
            service.statusResponse = .success(.empty)
            service.requestStatus()
            service.statusResponse = .success(running)
            service.applyConfiguration(selection)
            suite.expect(service.proxy.writes == priorWrites + [selection, selection] && service.snapshot.isCooling && service.interruptedStop == nil
                            && service.activeConfiguration == selection && storedResume == nil,
                         "a new explicit application works once the system handoff has been confirmed")
        }
        for restored in [true, false] {
            reset(stored: nil)
            service.statusResponse = .success(active, supportsOwnedRestore: true)
            service.applyConfiguration(manual)
            service.proxy.holdRestore = true
            service.workspaceWillSleep()
            service.workspaceWillSleep()
            let reply = service.proxy.heldRestore
            service.proxy.heldRestore = nil
            service.statusResponse = restored ? .success(.empty) : .failure(.controlFailed, snapshot: stopped)
            reply?()
            service.workspaceDidWake()
            suite.expect(reply != nil && service.proxy.restores == 0 && service.proxy.ownedRestores == 1
                            && service.isWorking == !restored && (storedResume != nil) == restored
                            && service.scheduledResumes.isEmpty && service.applied == (restored ? [manual] : []) && service.proxy.writes == [manual],
                         "duplicate sleep notifications preserve the first restore reply and only a successful handoff resumes on wake")
        }
        for confirmed in [false, true] {
            reset(stored: nil)
            service.statusResponse = .success(active, supportsOwnedRestore: true)
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
            service.statusResponse = confirmed ? .success(.empty) : .failure(.controlFailed, snapshot: stopped)
            Service.restoreBeforeTerminationIfNeeded()
            service.statusResponse = .success(stopped) // The late status must not change the exit decision.
            lateReadAtExit?()
            ownedTimer?.fire()
            suite.expect(lateReadAtExit != nil && service.proxy.restores == 0 && service.proxy.ownedRestores == 1
                            && ownedConnection?.invalidated == true && ownedTimer?.invalidated == true && service.requestInFlight == nil
                            && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) == !confirmed
                            && FanControlConfiguration.decodeResume(storedResume ?? "") == (confirmed ? manual : nil)
                            && service.scheduledResumes.isEmpty && service.proxy.heartbeats == 0 && service.proxy.writes == [manual],
                         "intentional termination restores once, ignores a late status, and retains consent only after a local handoff")
            Service.shared = Service()
            Service.recoverIfNeeded()
            suite.expect(service.applied == (confirmed ? [manual] : []) && service.interruption == (confirmed ? nil : .stopped(nil)),
                         "relaunch honors the stop evidence received during termination")
        }
        reset()
        Environment.available = false
        service.statusResponse = .success(.empty)
        service.statusResponse?.supportsUnregisterPreparation = true
        service.syncWithPreferences()
        suite.expect(storedResume == nil && service.proxy.statusReads == 1 && service.proxy.restores == 0
                        && service.proxy.preparationCount == 1 && Service.appService.unregisterCalls == 1,
                     "removing the feature confirms idle status without a global restore before unregistering the helper")
        for failureDuringRemoval in [false, true] {
            for reenable in [false, true] {
                reset(stored: nil)
                defaults.values[DefaultsKey.fanControlHelperVersion] = Service.helperVersion
                service.statusResponse = .success(active, supportsOwnedRestore: true)
                service.applyConfiguration(manual)
                service.statusResponse = .failure(.controlFailed, snapshot: stopped)
                if !failureDuringRemoval { service.heartbeat() }
                Environment.available = false
                service.syncWithPreferences()
                suite.expect(service.awaitingSystemControl && storedResume == nil && Service.appService.unregisterCalls == 0
                                && service.interruptedStop == "" && service.timer != nil && service.isWorking,
                             "removing the feature waits for confirmed automatic control even when its own restore first fails")
                if reenable {
                    Environment.available = true
                    service.syncWithPreferences()
                }
                service.statusResponse = .success(.empty)
                service.statusResponse?.supportsUnregisterPreparation = true
                service.requestStatus()
                service.requestStatus()
                suite.expect(!service.awaitingSystemControl && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                                && Service.appService.unregisterCalls == (reenable ? 0 : 1) && service.proxy.restores == 0
                                && service.proxy.ownedRestores == (failureDuringRemoval ? 1 : 0)
                                && defaults.string(forKey: DefaultsKey.fanControlHelperVersion) == (reenable ? Service.helperVersion : nil),
                             "duplicate status confirmations preserve the registration only when the feature was reenabled")
            }
        }
        for legacy in [false, true] {
            for telemetryError: FanControlRecoveryContract.FanControlHardwareError in [.noFans, .unsupported] {
                reset(stored: nil)
                let helper = idleHelper()
                helper.hardware?.snapshotError = telemetryError
                connect(service, to: helper, session: UUID(), legacy: legacy)
                Environment.available = false
                service.syncWithPreferences()
                suite.expect(Service.appService.unregisterCalls == (legacy ? 0 : 1)
                                && service.proxy.preparationCount == (legacy ? 0 : 1)
                                && service.connection == nil && service.timer == nil && !service.awaitingSystemControl
                                && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) && helper.hardware?.restores == 0,
                             "disabling ends idle polling even without RPM data, reserving only a modern daemon")
                reset(stored: nil)
                checkReenabledWithOtherOwner(suite, telemetryError: telemetryError, legacy: legacy)
            }
            reset(stored: nil)
            checkDisableWithOtherOwner(suite, legacy: legacy)
            reset(stored: nil)
            checkDisableDuringRecovery(suite, legacy: legacy)
        }
        reset(stored: nil)
        Environment.available = false
        service.accessState = .requiresApproval
        service.syncWithPreferences()
        suite.expect(service.proxy.statusReads == 0 && service.connection == nil && service.timer == nil
                        && Service.appService.unregisterCalls == 0 && !defaults.bool(forKey: DefaultsKey.fanControlUnregisterPending),
                     "without approval the client cannot reserve the daemon and leaves its registration without polling")
        reset(stored: nil)
        let unapprovedHelper = idleHelper()
        connect(service, to: unapprovedHelper, session: UUID(), legacy: true)
        service.applyConfiguration(manual)
        service.accessState = .requiresApproval
        Environment.available = false
        service.syncWithPreferences()
        suite.expect(service.connection == nil && service.proxy.restores == 0 && service.proxy.ownedRestores == 0
                        && unapprovedHelper.owner == nil && service.awaitingSystemControl && Service.appService.unregisterCalls == 0,
                     "disabling after approval is lost closes only the old helper's owning connection and preserves recovery")
        for reenable in [false, true] {
            reset(stored: nil)
            checkUnregisterReservation(suite, reenable: reenable)
        }
        for outcome in [UnregisterRetry.succeeds, .relaunched, .approvalRestored, .reenabled, .persistent] {
            reset(stored: nil)
            checkUnregisterRetry(suite, outcome: outcome)
        }
        reset(stored: nil)
        checkReenabledBeforeRelease(suite)
        for lost in [LostDisableRead.disconnected, .relaunched, .unregistered] {
            reset(stored: nil)
            checkLostDisableRead(suite, lost: lost)
        }
        for legacy in [false, true] {
            reset(stored: nil)
            checkSwapWithOwner(suite, legacy: legacy)
        }
        for event in [SwapInterleaving.takeover, .panelCloses, .connectionLost, .approvalLost] {
            reset(stored: nil)
            checkSwapInterleaving(suite, event: event)
        }
        for outcome in [SwapOutcome.success, .unregisterFailed, .registerFailed, .panelClosed, .featureDisabled, .reenabled] {
            reset(stored: nil)
            checkIdleSwap(suite, outcome: outcome)
        }
        for panelOpen in [false, true] {
            reset(resume: panelOpen, stored: nil)
            MainActor.assumeIsolated { checkCardFeedback(suite, scenario: .sensorStop(panelOpen: panelOpen)) }
        }
        for scenario: CardScenario in [.applyAvailability(.manual), .applyAvailability(.curve),
                                       .otherClientStop(.heartbeat), .otherClientStop(.sleep), .otherClientStop(.otherOwnerActive),
                                       .activeConnectionLost(statusInFlight: false), .activeConnectionLost(statusInFlight: true),
                                       .failedFirstApply, .acceptedApplyReplyLost(sleepDuringApply: false),
                                       .acceptedApplyReplyLost(sleepDuringApply: true), .confirm(.missingReason),
                                       .confirm(.unobservedSession), .confirm(.knownReason)] {
            reset(stored: nil)
            MainActor.assumeIsolated { checkCardFeedback(suite, scenario: scenario) }
        }
        for legacy in [false, true] {
            for exiting in [false, true] {
                for owner in [HandoffOwner.local, .otherActive, .otherReturnedToSystem] {
                    reset(stored: nil)
                    checkHandoff(suite, owner: owner, exiting: exiting, legacy: legacy)
                }
            }
        }
        for result in [ExitReply.lost, .late, .failed] {
            reset(stored: nil)
            checkUnconfirmedExit(suite, reply: result)
        }
        for choice in [SleepResumeChoice.keep, .forget, .removeAndReinstall] {
            reset(stored: nil)
            checkWakeBeforeReply(suite, choice: choice)
        }
        reset(stored: nil)
        checkContestedWake(suite)
        reset(stored: nil)
        checkSleepDuringResumeRetry(suite)
        for stop: FanControlStopReason in [.heartbeatLost, .temperatureUnavailable, .recovery] {
            reset(stored: nil)
            checkRefusedRelaunch(suite, earlierStop: stop)
        }
        reset(stored: nil)
        checkRefusedRelaunch(suite, earlierStop: .heartbeatLost, legacy: true)
        for event in [RepeatedFanEvent.wakeDuringLaunch, .duplicateWake, .hubSync] {
            for beforeReply in [false, true] {
                reset(stored: nil)
                checkRepeatedEvent(suite, event: event, beforeReply: beforeReply)
            }
        }
        reset()
    }

    private enum Confirmation { case missingReason, unobservedSession, knownReason }
    private enum FirstObservation { case heartbeat, sleep, otherOwnerActive }
    private enum CardScenario {
        case sensorStop(panelOpen: Bool), failedFirstApply, acceptedApplyReplyLost(sleepDuringApply: Bool), confirm(Confirmation)
        case activeConnectionLost(statusInFlight: Bool), applyAvailability(FanControlMode), otherClientStop(FirstObservation)
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
            let warnings = [strings.temperatureUnavailable, strings.safetyStopped, strings.failed, strings.controlStopped, strings.applyFailed,
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
        case .otherClientStop(let observation):
            checkOtherClientStop(suite, observation: observation, expect: expectFeedback)
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
        expectFeedback(status: strings.systemControl, message: strings.controlStopped,
                       "the card reports an unattributed stop once restoration succeeds")
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
            expectFeedback(status: strings.systemControl, message: strings.controlStopped,
                           "reopening after the helper exits preserves the generic diagnosis without a retry")
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
            expectFeedback(status: strings.systemControl, message: strings.controlStopped,
                           "a different global stop retires the dismissal and shows a neutral message")
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
                        && defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) == nil,
                     "an explicit manual Apply starts a fresh session without granting consent before a verified release")
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
        expectFeedback(status: strings.systemControl, message: strings.controlStopped,
                       "a new curve ending between reads also has no attributable cause")
        mode.wrappedValue = .system
        let otherClient = UUID()
        let otherApply = controller.applyConfiguration(session: otherClient, configuration: manual, duration: nil)
        let interrupted = controller.performRestore(reason: .thermalPressure)
        suite.expect(otherApply.succeeded && interrupted && controller.lastStopReason == .thermalPressure,
                     "a later session genuinely stops for a different reason")
        service.controller = controller
        service.requestStatus()
        expectFeedback(status: strings.systemControl, message: strings.controlStopped,
                       "a different global stop shows a neutral message after dismissal")
        controller.hardware?.temperatures = [.init(source: .hottestSoC, celsius: 60)]
        let otherCurve = controller.applyConfiguration(session: otherClient, configuration: curve, duration: nil)
        controller.hardware?.temperatures = []
        for _ in 0..<FanControlPolicy.temperatureFailureLimit { controller.watchdogTick() }
        suite.expect(otherCurve.succeeded && controller.lastStopReason == .temperatureUnavailable,
                     "the watchdog detects a new loss of the same sensor")
        service.requestStatus()
        expectFeedback(status: strings.systemControl, message: strings.controlStopped,
                       "a subsequent global sensor stop does not identify the cause for this client")
        Service.shared = Service()
        service.panelIsVisible = true
        Service.recoverIfNeeded()
        service.controller = controller
        service.requestStatus()
        expectFeedback(status: strings.systemControl, message: strings.controlStopped,
                       "after relaunch the global stop still shows a neutral message")
        service.controller = nil
        runCurveUntilStop(.hardwareChanged)
        expectFeedback(status: strings.systemControl, message: strings.controlStopped,
                       "a global safety stop does not identify why the kept curve stopped")
        service.workspaceWillSleep()
        service.workspaceDidWake()
        service.statusResponse = .success(stopped)
        service.requestStatus()
        expectFeedback(status: strings.systemControl, message: strings.controlStopped,
                       "wake and idle telemetry preserve the generic diagnosis")
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
        service.workspaceWillSleep()
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
        let readsBeforeRefusal = service.proxy.statusReads
        service.proxy.onStatus = { [unowned service] in
            service.proxy.onStatus = nil
            controller.hardware = hardware
            hardware?.failNextRPMRead = true
            service.statusResponse = controller.statusResponse()
        }
        service.applyConfiguration(manual)
        suite.expect(hardware?.isManual == false && !controller.isRecovering && service.awaitingSystemControl
                        && service.proxy.statusReads == readsBeforeRefusal + 1 && service.proxy.restores == 0,
                     "a refusal repeating recovery waits for a fresh status without requesting another restore")
        let reopened = Service()
        suite.expect(reopened.awaitingSystemControl && reopened.interruption == .applyFailed,
                     "relaunch during confirmation remembers the new refusal instead of the old dismissal")
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
        expect(strings.systemControl, strings.safetyStopped,
               "the refused Apply identifies its own recovery even when it cannot read RPM")

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
        Service.shared = Service()
        expect(strings.systemControl, strings.safetyStopped,
               "the stop confirmed by this Apply retains its diagnosis after relaunch")
    }

    private static func idleHelper() -> FanControlRecoveryContract.Controller {
        let helper = FanControlRecoveryContract.Controller()
        helper.isCooling = false
        helper.owner = nil
        helper.activeConfiguration = nil
        helper.ownership.marker = false
        helper.hardware?.isManual = false
        helper.connectionCount = 2
        return helper
    }

    private static func connect(_ client: Service, to helper: FanControlRecoveryContract.Controller,
                                session: UUID, legacy: Bool = false) {
        client.panelIsVisible = true
        let connection = Invalidating()
        client.connection = connection
        connection.onInvalidate = { [weak client, weak connection] in
            helper.connectionClosed(session)
            if let connection { client?.connectionLost(connection) }
        }
        client.proxy.onStatus = { [unowned client] in
            if legacy { client.statusResponse = helper.statusResponse() }
            else { helper.status { client.statusResponse = FanControlIPC.decode($0) } }
        }
        client.proxy.onPrepareForUnregister = { [unowned client] in
            helper.prepareForUnregister(session: session) { client.statusResponse = FanControlIPC.decode($0) }
        }
        client.proxy.onApply = { [unowned client] choice in
            let response = helper.applyConfiguration(session: session, configuration: choice, duration: nil)
            if legacy, let error = response.error {
                client.statusResponse = .failure(error, snapshot: response.snapshot)
            } else {
                client.statusResponse = legacy ? .success(response.snapshot) : response
            }
        }
        client.proxy.onHeartbeat = { [unowned client] in
            helper.heartbeat(session: session) { client.statusResponse = FanControlIPC.decode($0) }
        }
        client.proxy.onRestore = { [unowned client] in
            helper.restore { client.statusResponse = FanControlIPC.decode($0) }
        }
        client.proxy.onOwnedRestore = { [unowned client] in
            helper.restore(session: session) { client.statusResponse = FanControlIPC.decode($0) }
        }
        client.onResume = { [unowned client] in client.sendConfiguration($0, resuming: true) }
    }

    private static func deliverRegistrationCallbacks() {
        // SMAppService's completion returns to the service through the main queue.
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    private static func checkSwapWithOwner(_ suite: TestSuite, legacy: Bool) {
        let helper = idleHelper()
        let client = Service.shared
        let requester = UUID(), other = UUID()
        let registration = Service.appService
        let defaults = UserDefaults.standard
        defaults.set("previous", forKey: DefaultsKey.fanControlHelperVersion)
        connect(client, to: helper, session: requester, legacy: legacy)
        let manual = FanControlConfiguration.manual(level: 65)
        let started = helper.applyConfiguration(session: other, configuration: manual, duration: nil)
        var shutdowns = 0
        registration.onUnregister = {
            // Model unloading the daemon by delivering its termination and connection-close events.
            helper.shutdown { _ in shutdowns += 1 }
            helper.connectionClosed(other)
        }
        client.panelDidAppear()
        deliverRegistrationCallbacks()
        var heartbeat: FanControlResponse?
        helper.heartbeat(session: other) { heartbeat = FanControlIPC.decode($0) }
        let restored = helper.hardware?.restores ?? 0
        let writes = helper.hardware?.updates ?? []
        suite.expect(started.succeeded && helper.owner == other && heartbeat?.snapshot.configuration == manual
                        && heartbeat?.succeeded == true && registration.unregisterAttempts == 0
                        && shutdowns == 0 && restored == 0 && writes == [65]
                        && defaults.string(forKey: DefaultsKey.fanControlHelperVersion) == "previous",
                     "opening A's panel keeps B running: legacy=\(legacy), unregister=\(registration.unregisterCalls), shutdown=\(shutdowns), owns=\(helper.owner == other), writes=\(writes), restores=\(restored), stop=\(String(describing: helper.lastStopReason))")
        helper.restore { _ in } // B chooses System before A next refreshes.
        client.refresh()
        deliverRegistrationCallbacks()
        if legacy {
            suite.expect(registration.unregisterAttempts == 0 && client.proxy.preparationCount == 0
                            && !client.isWorking && !client.snapshot.isCooling
                            && defaults.string(forKey: DefaultsKey.fanControlHelperVersion) == "previous",
                         "an idle compatible legacy helper stays registered without claiming the bundled version")
            client.applyConfiguration(manual)
            suite.expect(helper.owner == requester && client.snapshot.isCooling && client.proxy.writes == [manual],
                         "A can still use explicit Apply with the compatible legacy registration")
        }
    }

    private enum SwapInterleaving { case takeover, panelCloses, connectionLost, approvalLost }

    private static func checkSwapInterleaving(_ suite: TestSuite, event: SwapInterleaving) {
        let helper = idleHelper()
        let client = Service.shared
        let requester = UUID(), other = UUID()
        let registration = Service.appService
        let key = DefaultsKey.fanControlHelperVersion
        UserDefaults.standard.set("previous", forKey: key)
        connect(client, to: helper, session: requester)
        client.panelIsVisible = false
        client.refresh()
        deliverRegistrationCallbacks()
        suite.expect(registration.unregisterAttempts == 0 && client.proxy.preparationCount == 0,
                     "a refresh outside the panel cannot start a registration swap")
        connect(client, to: helper, session: requester)
        client.proxy.holdNextStatus = event == .takeover
        client.proxy.holdPreparation = event != .takeover
        client.panelDidAppear()
        deliverRegistrationCallbacks()
        if event == .takeover {
            let held = client.proxy.heldStatus
            client.proxy.heldStatus = nil
            let accepted = helper.applyConfiguration(session: other, configuration: .manual(level: 45), duration: nil)
            held?()
            suite.expect(held != nil && accepted.succeeded && helper.owner == other && client.proxy.preparationCount == 1
                            && registration.unregisterAttempts == 0 && helper.hardware?.restores == 0,
                         "B taking over after A's idle status makes the daemon refuse the swap reservation")
            helper.restore { _ in }
            client.refresh()
            deliverRegistrationCallbacks()
            suite.expect(registration.unregisterCalls == 1 && registration.registerCalls == 1
                            && UserDefaults.standard.string(forKey: key) == Service.helperVersion,
                         "a later visible idle refresh can safely complete the previously contested swap")
        } else {
            let held = client.proxy.heldPreparation
            client.proxy.heldPreparation = nil
            suite.expect(held != nil && helper.unregisterSession == requester, "the idle reservation reply is in flight")
            if event == .approvalLost {
                client.accessState = .requiresApproval
                held?() // The callback must recheck authorization before unregistering.
            } else if event == .panelCloses {
                client.panelDidDisappear()
            } else {
                client.connection?.invalidate()
            }
            let accepted = helper.applyConfiguration(session: other, configuration: .manual(level: 45), duration: nil)
            if event != .approvalLost { held?() }
            suite.expect(accepted.succeeded && helper.owner == other && helper.unregisterSession == nil
                            && registration.unregisterAttempts == 0 && !client.awaitingSystemControl && !client.isWorking
                            && UserDefaults.standard.string(forKey: key) == "previous",
                         "a stale reservation reply after \(event) cannot remove B's helper or claim a swap")
        }
    }

    private enum SwapOutcome { case success, unregisterFailed, registerFailed, panelClosed, featureDisabled, reenabled }

    private static func checkIdleSwap(_ suite: TestSuite, outcome: SwapOutcome) {
        let helper = idleHelper()
        let client = Service.shared
        let requester = UUID(), other = UUID()
        let registration = Service.appService
        let key = DefaultsKey.fanControlHelperVersion
        UserDefaults.standard.set("previous", forKey: key)
        connect(client, to: helper, session: requester)
        registration.fails = outcome == .unregisterFailed
        registration.registerFails = outcome == .registerFailed
        registration.holdUnregister = true
        var reservedWhenUnregistered = false
        registration.onUnregister = {
            let denied = helper.applyConfiguration(session: other, configuration: .manual(level: 45), duration: nil)
            reservedWhenUnregistered = helper.unregisterSession == requester && denied.error == .alreadyControlled
            helper.shutdown { _ in }
        }
        client.panelDidAppear()
        if outcome == .panelClosed { client.panelDidDisappear() }
        if outcome == .featureDisabled || outcome == .reenabled {
            Environment.available = false
            client.syncWithPreferences()
            if outcome == .reenabled {
                Environment.available = true
                client.syncWithPreferences()
            }
        }
        suite.expect(registration.heldUnregister != nil && registration.registerAttempts == 0
                        && helper.unregisterSession == requester,
                     "registration waits for the OS to finish unregistering the reserved daemon (\(outcome))")
        registration.heldUnregister?()
        registration.heldUnregister = nil
        deliverRegistrationCallbacks()
        let shouldRegister = outcome != .unregisterFailed && outcome != .featureDisabled
        let registered = shouldRegister && outcome != .registerFailed
        suite.expect(client.proxy.preparationCount == 1 && registration.unregisterAttempts == 1
                        && registration.registerAttempts == (shouldRegister ? 1 : 0)
                        && registration.registerCalls == (registered ? 1 : 0)
                        && reservedWhenUnregistered == (outcome != .unregisterFailed) && helper.unregisterSession == nil
                        && helper.hardware?.updates.isEmpty == true && !client.isWorking,
                     "swap with \(outcome) keeps B out until unregister and releases the reservation afterwards")
        let recorded = UserDefaults.standard.string(forKey: key)
        suite.expect((recorded == Service.helperVersion) == registered
                        && (outcome != .unregisterFailed || recorded == "previous")
                        && client.accessState == (registered || outcome == .unregisterFailed ? .enabled : .notRegistered),
                     "the recorded version and access state reflect the actual registration outcome (\(outcome))")
    }

    private static func checkDisableWithOtherOwner(_ suite: TestSuite, legacy: Bool) {
        let client = Service.shared
        let helper = idleHelper()
        connect(client, to: helper, session: UUID(), legacy: legacy)
        client.proxy.holdNextStatus = true
        Environment.available = false
        client.syncWithPreferences()
        let other = UUID()
        let started = helper.applyConfiguration(session: other, configuration: .manual(level: 65), duration: nil)
        client.proxy.heldStatus?()
        client.proxy.heldStatus = nil
        suite.expect(started.succeeded && helper.owner == other && helper.hardware?.restores == 0
                        && Service.appService.unregisterCalls == 0,
                     "a client taking over after the idle read survives another client's removal request")
        guard !legacy else { return } // Legacy disable keeps the registration after the old idle reply.

        helper.hardware?.restoreResults = [false, true]
        _ = helper.performRestore(reason: .hardwareChanged)
        client.requestStatus()
        suite.expect(helper.isRecovering && helper.ownership.marker && client.checkingUnregister
                        && Service.appService.unregisterCalls == 0 && helper.hardware?.restores == 1,
                     "unregistration waits for recovery without attempting an extra restore")
        helper.watchdogTick()
        helper.hardware?.snapshotError = .noFans
        client.requestStatus()
        suite.expect(!helper.isRecovering && !helper.ownership.marker && !client.awaitingSystemControl
                        && Service.appService.unregisterCalls == 1 && helper.hardware?.restores == 2,
                     "the daemon can be removed after recovery even when RPM cannot be read")
    }

    private static func checkDisableDuringRecovery(_ suite: TestSuite, legacy: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)
        defaults.set("", forKey: DefaultsKey.fanControlInterruptedStop)
        defaults.set(true, forKey: DefaultsKey.fanControlUnregisterPending)
        Environment.available = false
        Service.shared = Service()
        let client = Service.shared
        let helper = idleHelper()
        helper.isRecovering = true
        helper.ownership.marker = true
        connect(client, to: helper, session: UUID(), legacy: legacy)
        client.panelIsVisible = false
        Service.recoverIfNeeded()
        suite.expect(client.awaitingSystemControl && client.checkingUnregister && client.timer != nil
                        && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                        && defaults.bool(forKey: DefaultsKey.fanControlUnregisterPending)
                        && Service.appService.unregisterCalls == 0 && helper.hardware?.restores == 0,
                     "a relaunch preserves both a real recovery and a pending disable on modern and older helpers")
        helper.watchdogTick()
        client.timer?.fire()
        client.timer?.fire()
        suite.expect(!client.awaitingSystemControl && !client.checkingUnregister && client.timer == nil
                        && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                        && !defaults.bool(forKey: DefaultsKey.fanControlUnregisterPending)
                        && Service.appService.unregisterCalls == (legacy ? 0 : 1) && client.interruptedStop == "",
                     "only confirmed idle clears the two pending operations while the original interruption is retained")
    }

    private static func checkUnregisterReservation(_ suite: TestSuite, reenable: Bool) {
        let client = Service.shared
        let helper = idleHelper()
        let requester = UUID(), other = UUID()
        connect(client, to: helper, session: requester)
        client.proxy.holdPreparation = true
        Environment.available = false
        client.syncWithPreferences()
        let denied = helper.applyConfiguration(session: other, configuration: .manual(level: 65), duration: nil)
        var legacyError: FanControlErrorCode?
        helper.startLegacySession(other) { legacyError = FanControlIPC.decode($0)?.error }
        suite.expect(helper.unregisterSession == requester && denied.error == .alreadyControlled && helper.owner == nil
                        && legacyError == .alreadyControlled && helper.hardware?.updates.isEmpty == true
                        && Service.appService.unregisterCalls == 0,
                     "modern and legacy clients cannot start a session between the removal reservation and unregister")
        Service.appService.fails = !reenable
        Environment.available = reenable
        if reenable {
            client.syncWithPreferences()
            let accepted = helper.applyConfiguration(session: other, configuration: .manual(level: 65), duration: nil)
            suite.expect(helper.unregisterSession == nil && accepted.succeeded && helper.owner == other && !client.isWorking,
                         "reenabling releases an in-flight reservation to a new owner before its delayed reply")
        }
        client.proxy.heldPreparation?()
        client.proxy.heldPreparation = nil
        let accepted = helper.applyConfiguration(session: other, configuration: .manual(level: 65), duration: nil)
        suite.expect(Service.appService.unregisterCalls == 0 && helper.unregisterSession == nil && accepted.succeeded
                        && helper.owner == other && !client.awaitingSystemControl && client.connection == nil,
                     "reenabling or a failed unregister releases the idle daemon to a subsequent owner")
    }

    private enum UnregisterRetry { case succeeds, relaunched, approvalRestored, reenabled, persistent }

    private static func checkUnregisterRetry(_ suite: TestSuite, outcome: UnregisterRetry) {
        let defaults = UserDefaults.standard
        let helper = idleHelper()
        let initial = Service.shared
        defaults.set(Service.helperVersion, forKey: DefaultsKey.fanControlHelperVersion)
        connect(initial, to: helper, session: UUID())
        initial.panelIsVisible = false
        Environment.available = false
        Service.appService.fails = true
        initial.syncWithPreferences()
        suite.expect(defaults.bool(forKey: DefaultsKey.fanControlUnregisterPending) && initial.checkingUnregister
                        && defaults.string(forKey: DefaultsKey.fanControlHelperVersion) == Service.helperVersion
                        && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) && initial.interruption == nil
                        && helper.unregisterSession == nil && initial.connection == nil && initial.timer != nil,
                     "a failed unregister releases the daemon while retaining removal intent and its registered version")
        for _ in 0..<5 { initial.syncWithPreferences() }
        suite.expect(initial.proxy.statusReads == 1 && initial.proxy.preparationCount == 1,
                     "repeat preference notifications cannot bypass the unregister retry delay")

        let other = UUID()
        let otherApply = helper.applyConfiguration(session: other, configuration: .manual(level: 65), duration: nil)
        suite.expect(otherApply.succeeded && helper.owner == other,
                     "another client can acquire the daemon during the removal backoff")
        if outcome == .reenabled {
            let timer = initial.timer
            Environment.available = true
            initial.syncWithPreferences()
            for _ in 0..<65 { timer?.fire() }
            suite.expect(!defaults.bool(forKey: DefaultsKey.fanControlUnregisterPending) && initial.timer == nil
                            && initial.proxy.statusReads == 1 && initial.proxy.preparationCount == 1
                            && helper.owner == other && Service.appService.unregisterCalls == 0,
                         "reenabling during removal backoff cancels every later attempt and preserves the new owner")
            return
        }
        let relaunch = outcome == .relaunched || outcome == .approvalRestored
        if outcome == .approvalRestored {
            initial.accessState = .requiresApproval
            for _ in 0..<65 { initial.timer?.fire() }
            suite.expect(initial.proxy.statusReads == 1 && initial.events.isEmpty && initial.timer != nil
                            && defaults.bool(forKey: DefaultsKey.fanControlUnregisterPending),
                         "a failed removal retains its intent without contacting the daemon or prompting while approval is unavailable")
        }
        if relaunch {
            Service.restoreBeforeTerminationIfNeeded()
            Service.shared = Service()
        }
        let client = Service.shared
        connect(client, to: helper, session: UUID())
        client.panelIsVisible = false
        if relaunch {
            if outcome == .approvalRestored { client.accessState = .requiresApproval }
            Service.recoverIfNeeded()
            if outcome == .approvalRestored {
                suite.expect(client.proxy.statusReads == 0 && client.timer != nil && client.events.isEmpty
                                && defaults.bool(forKey: DefaultsKey.fanControlUnregisterPending),
                             "launch with a pending unregister error preserves it while awaiting approval")
                client.accessState = .enabled
                client.timer?.fire()
                client.timer?.fire()
            }
        }
        else {
            client.timer?.fire()
            client.timer?.fire()
        }
        suite.expect(defaults.bool(forKey: DefaultsKey.fanControlUnregisterPending) && helper.owner == other
                        && helper.hardware?.restores == 0 && Service.appService.unregisterCalls == 0,
                     "a retried removal checks the current owner again, including after relaunch")
        helper.restore(session: other) { _ in }
        Service.appService.fails = outcome == .persistent
        let before = client.proxy.preparationCount
        for _ in 0..<180 {
            guard let timer = client.timer else { break }
            if client.connection == nil {
                connect(client, to: helper, session: UUID())
                client.panelIsVisible = false
            }
            timer.fire()
        }
        if outcome == .persistent {
            suite.expect(client.proxy.preparationCount - before > 0 && client.proxy.preparationCount - before < 10
                            && defaults.bool(forKey: DefaultsKey.fanControlUnregisterPending) && client.timer != nil
                            && Service.appService.unregisterCalls == 0 && helper.owner == nil && helper.unregisterSession == nil,
                         "persistent unregister failures back off without losing intent or holding the helper reservation")
        } else {
            suite.expect(Service.appService.unregisterCalls == 1 && client.proxy.preparationCount == before + 1
                            && !defaults.bool(forKey: DefaultsKey.fanControlUnregisterPending) && client.timer == nil
                            && defaults.string(forKey: DefaultsKey.fanControlHelperVersion) == nil,
                         "a transient unregister error is retried under a fresh reservation and completes once")
        }
    }

    private enum LostDisableRead { case disconnected, relaunched, unregistered }

    private static func checkReenabledBeforeRelease(_ suite: TestSuite) {
        let client = Service.shared
        let helper = idleHelper()
        let manual = FanControlConfiguration.manual(level: 65)
        connect(client, to: helper, session: UUID())
        client.applyConfiguration(manual)
        client.proxy.holdRestore = true
        Environment.available = false
        client.syncWithPreferences()
        Environment.available = true
        client.syncWithPreferences()
        suite.expect(client.requestInFlight == .restore && !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlUnregisterPending),
                     "reenabling cancels removal while preserving the pending owner-checked release")
        client.proxy.heldRestore?()
        client.proxy.heldRestore = nil
        client.proxy.holdRestore = false
        client.applyConfiguration(manual)
        Service.restoreBeforeTerminationIfNeeded()
        suite.expect(Service.appService.unregisterCalls == 0 && client.proxy.ownedRestores == 2
                        && Service.resumableConfiguration == manual && helper.owner == nil,
                     "a new Apply and acknowledged quit after reenabling can still arm its own resume")
    }

    private static func checkReenabledWithOtherOwner(_ suite: TestSuite, telemetryError: FanControlRecoveryContract.FanControlHardwareError,
                                                     legacy: Bool) {
        let client = Service.shared
        let helper = idleHelper()
        let other = UUID()
        _ = helper.applyConfiguration(session: other, configuration: .manual(level: 65), duration: nil)
        helper.hardware?.snapshotError = telemetryError
        connect(client, to: helper, session: UUID(), legacy: legacy)
        client.panelIsVisible = false
        Environment.available = false
        client.syncWithPreferences()
        let timer = client.timer
        suite.expect(client.snapshot.isCooling && client.snapshot.fans.isEmpty && helper.owner == other
                        && helper.hardware?.restores == 0 && Service.appService.unregisterCalls == 0
                        && (timer != nil) == !legacy,
                     "unreadable fan telemetry during disable does not affect another owner's active control")
        Environment.available = true
        client.syncWithPreferences()
        timer?.fire()
        suite.expect(timer?.invalidated != false && client.timer == nil && client.connection == nil
                        && helper.owner == other && client.proxy.heartbeats == 0 && client.interruptedStop == nil,
                     "reenabling in the background drops removal polling without sending a heartbeat to the other owner")
    }

    private static func checkLostDisableRead(_ suite: TestSuite, lost: LostDisableRead) {
        let original = Service.shared
        let helper = idleHelper()
        connect(original, to: helper, session: UUID())
        original.proxy.holdNextStatus = true
        Environment.available = false
        original.syncWithPreferences()
        original.panelIsVisible = false
        original.stopIdleWorkIfPossible()
        let late = original.proxy.heldStatus
        original.proxy.heldStatus = nil
        suite.expect(late != nil && original.timer != nil
                        && UserDefaults.standard.bool(forKey: DefaultsKey.fanControlUnregisterPending)
                        && !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                     "a removal requested from idle persists the wait before the first reply")
        if lost == .relaunched {
            Service.restoreBeforeTerminationIfNeeded()
            Service.shared = Service()
            Service.recoverIfNeeded()
        } else {
            original.connection?.invalidate()
        }
        late?()
        let client = Service.shared
        if lost == .unregistered {
            client.accessState = .notRegistered
        } else {
            connect(client, to: helper, session: UUID())
        }
        for _ in 0..<4 { client.timer?.fire() }
        suite.expect(client.timer == nil && client.connection == nil && !client.awaitingSystemControl
                        && !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                        && !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlUnregisterPending)
                        && client.interruptedStop == nil && client.interruption == nil
                        && Service.appService.unregisterCalls == (lost == .unregistered ? 0 : 1),
                     "a lost initial disable read ends through a new reservation or a removed registration (\(lost))")
    }

    private enum HandoffOwner { case local, otherActive, otherReturnedToSystem }

    private static func checkHandoff(_ suite: TestSuite, owner: HandoffOwner, exiting: Bool, legacy: Bool) {
        let original = Service.shared
        let helper = idleHelper()
        let sessionA = UUID(), sessionB = UUID()
        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        let manual = FanControlConfiguration.manual(level: 65)
        connect(original, to: helper, session: sessionA, legacy: legacy)
        let connection = original.connection
        original.applyConfiguration(curve)
        suite.expect(helper.owner == sessionA && Service.resumableConfiguration == nil,
                     "an active curve grants no persisted resume permission")
        if owner != .local {
            helper.hardware?.temperatures = []
            for _ in 0..<FanControlPolicy.temperatureFailureLimit { helper.watchdogTick() }
            let accepted = helper.applyConfiguration(session: sessionB, configuration: manual, duration: nil)
            suite.expect(accepted.succeeded && helper.owner == sessionB, "B takes over after A's sensor stop")
            if owner == .otherReturnedToSystem {
                helper.restore { data in
                    suite.expect(FanControlIPC.decode(data)?.succeeded == true && helper.lastStopReason == nil,
                                 "B explicitly returns to System, leaving an idle reply without a stop reason")
                }
            }
            helper.hardware?.temperatures = [.init(source: .hottestSoC, celsius: 60)]
        }
        let restores = helper.hardware?.restores ?? 0
        if exiting { Service.restoreBeforeTerminationIfNeeded() } else { original.workspaceWillSleep() }
        let verified = !legacy && owner == .local
        let context = "owner=\(owner), exiting=\(exiting), legacy=\(legacy)"
        suite.expect(original.proxy.heartbeats == 0 && original.proxy.statusReads == 0
                        && original.proxy.restores == 0 && original.proxy.ownedRestores == (legacy ? 0 : 1)
                        && (!legacy || connection?.invalidated == true),
                     "without a prior read, sleep or exit can request only its own verified handoff (\(context))")
        suite.expect(Service.resumableConfiguration == (verified ? curve : nil)
                        && helper.owner == (owner == .otherActive ? sessionB : nil)
                        && helper.hardware?.restores == restores + (owner == .local ? 1 : 0),
                     "a handoff preserves the other owner and authorizes resume only for its own confirmed release (\(context))")
        if exiting {
            Service.shared = Service()
            connect(Service.shared, to: helper, session: UUID(), legacy: legacy)
            Service.recoverIfNeeded()
        } else {
            original.requestStatus()
            original.workspaceDidWake()
        }
        let current = Service.shared
        current.retryResume()
        let writes = (exiting ? original.proxy.writes : []) + current.proxy.writes
        suite.expect(writes == (verified ? [curve, curve] : [curve]) && current.proxy.restores == 0
                        && (owner != .otherActive || (helper.owner == sessionB && helper.activeConfiguration == manual)),
                     "wake and relaunch preserve the other client's session and apply only a confirmed curve (\(context))")
    }

    private enum ExitReply { case lost, late, failed }

    private static func checkUnconfirmedExit(_ suite: TestSuite, reply: ExitReply) {
        let helper = idleHelper()
        let original = Service.shared
        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        connect(original, to: helper, session: UUID())
        original.applyConfiguration(curve)
        var recordedBeforeSend = false
        let restore = original.proxy.onOwnedRestore
        original.proxy.onOwnedRestore = {
            recordedBeforeSend = UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                && UserDefaults.standard.string(forKey: DefaultsKey.fanControlInterruptedStop) == ""
                && UserDefaults.standard.string(forKey: DefaultsKey.fanControlResumeConfiguration) == nil
            restore?()
        }
        original.proxy.holdRestore = reply != .failed
        if reply == .failed { helper.hardware?.restoreResults = [false, true] }
        Service.restoreBeforeTerminationIfNeeded()
        let response = original.statusResponse
        let lateAck = original.proxy.heldRestore
        original.proxy.heldRestore = nil
        suite.expect(recordedBeforeSend && original.proxy.ownedRestores == 1 && original.proxy.restores == 0
                        && response?.succeeded == (reply != .failed) && response?.snapshot.stopReason == nil
                        && (lateAck != nil) == (reply != .failed) && Service.resumableConfiguration == nil,
                     "exit without a timely success cannot persist resume consent (\(reply))")
        Service.shared = Service()
        let relaunched = Service.shared
        connect(relaunched, to: helper, session: UUID())
        Service.recoverIfNeeded()
        if reply == .late { lateAck?() }
        if reply == .failed { helper.watchdogTick() }
        relaunched.requestStatus()
        relaunched.workspaceWillSleep()
        relaunched.workspaceDidWake()
        relaunched.retryResume()
        suite.expect(original.proxy.writes == [curve] && relaunched.proxy.writes.isEmpty
                        && relaunched.proxy.restores == 0 && helper.owner == nil
                        && Service.resumableConfiguration == nil && relaunched.interruption == .stopped(nil),
                     "relaunch, wake and a late ACK require Apply after an unconfirmed exit (\(reply))")
    }

    private enum SleepResumeChoice { case keep, forget, removeAndReinstall }

    private static func checkWakeBeforeReply(_ suite: TestSuite, choice: SleepResumeChoice) {
        let helper = idleHelper()
        let service = Service.shared
        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        let session = UUID()
        connect(service, to: helper, session: session)
        service.applyConfiguration(curve)
        service.proxy.holdRestore = true
        service.workspaceWillSleep()
        guard let reply = service.proxy.heldRestore else {
            suite.expect(false, "sleep must await its own helper reply")
            return
        }
        service.proxy.heldRestore = nil
        service.workspaceDidWake()
        suite.expect(service.proxy.writes == [curve] && Service.resumableConfiguration == nil && helper.owner == nil,
                     "wake before the owned release reply waits without writing")
        switch choice {
        case .keep: break
        case .forget: service.forgetResume()
        case .removeAndReinstall:
            Environment.available = false
            service.syncWithPreferences()
            Environment.available = true
            service.syncWithPreferences()
        }
        reply()
        suite.expect(service.proxy.ownedRestores == 1 && service.proxy.restores == 0
                        && service.proxy.writes == (choice == .keep ? [curve, curve] : [curve])
                        && helper.owner == (choice == .keep ? session : nil) && Service.resumableConfiguration == nil,
                     "a late sleep ACK resumes only consent retained across wake (\(choice))")
    }

    private static func checkContestedWake(_ suite: TestSuite) {
        let helper = idleHelper()
        let client = Service.shared
        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        let sessionB = UUID(), manual = FanControlConfiguration.manual(level: 65)
        connect(client, to: helper, session: UUID())
        client.applyConfiguration(curve)
        client.workspaceWillSleep()
        suite.expect(Service.resumableConfiguration == curve && client.proxy.ownedRestores == 1,
                     "the local sleep handoff confirms A's curve before B starts")
        let accepted = helper.applyConfiguration(session: sessionB, configuration: manual, duration: nil)
        let restores = helper.hardware?.restores
        client.workspaceDidWake()
        client.retryResume()
        suite.expect(accepted.succeeded && client.proxy.writes == [curve, curve] && client.proxy.restores == 0
                        && helper.owner == sessionB && helper.activeConfiguration == manual && helper.hardware?.restores == restores
                        && Service.resumableConfiguration == nil && client.scheduledResumes.isEmpty,
                     "B refusing A's actual automatic Apply on wake leaves B in control and revokes further retries")
    }

    private static func checkSleepDuringResumeRetry(_ suite: TestSuite) {
        let helper = idleHelper()
        let service = Service.shared
        let session = UUID()
        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        connect(service, to: helper, session: session)
        service.applyConfiguration(curve)
        service.workspaceWillSleep()
        let hardware = helper.hardware
        hardware?.temperatures = [] // The first wake cannot start the curve yet.
        service.proxy.onStatus = { [unowned service] in
            // A failed start closes the handle. The following probe still reads the same fans.
            helper.hardware = hardware
            service.statusResponse = helper.statusResponse()
        }
        service.proxy.holdNextStatus = true
        service.workspaceDidWake()
        guard let reply = service.proxy.heldStatus else {
            suite.expect(false, "a refused automatic Apply must observe system control")
            return
        }
        service.proxy.heldStatus = nil
        suite.expect(helper.owner == nil && service.proxy.writes == [curve, curve] && service.proxy.restores == 0,
                     "a clean refusal at wake reads status without changing fan control")
        service.workspaceWillSleep()
        reply()
        hardware?.temperatures = [.init(source: .hottestSoC, celsius: 60)]
        service.retryResume()
        suite.expect(helper.owner == nil && service.scheduledResumes.isEmpty && service.proxy.writes == [curve, curve],
                     "an idle status arriving during sleep can neither schedule nor execute a resume retry")
        service.workspaceDidWake()
        suite.expect(helper.owner == session && service.proxy.writes == [curve, curve, curve] && service.proxy.ownedRestores == 1,
                     "the following wake can retry the earlier verified handoff once the sensor returns")
    }

    private static func checkRefusedRelaunch(_ suite: TestSuite, earlierStop: FanControlStopReason, legacy: Bool = false) {
        let helper = idleHelper()
        let original = Service.shared
        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        connect(original, to: helper, session: UUID())
        original.applyConfiguration(curve)
        Service.restoreBeforeTerminationIfNeeded()
        suite.expect(Service.resumableConfiguration == curve && helper.owner == nil,
                     "A's confirmed exit grants exactly its locally released curve")

        let sessionB = UUID()
        let accepted = helper.applyConfiguration(session: sessionB, configuration: curve, duration: nil)
        suite.expect(accepted.succeeded && helper.owner == sessionB, "B takes control after A has quit")
        let device = helper.hardware
        switch earlierStop {
        case .heartbeatLost:
            helper.lastHeartbeatUptime -= FanControlPolicy.heartbeatLimit + 1
            helper.watchdogTick()
        case .temperatureUnavailable:
            device?.temperatures = []
            for _ in 0..<FanControlPolicy.temperatureFailureLimit { helper.watchdogTick() }
        case .recovery:
            helper.restore(session: sessionB) { _ in }
            device?.writeError = .unsafeControlState
            device?.restoreResults = [false, true]
            _ = helper.applyConfiguration(session: sessionB, configuration: curve, duration: nil)
            helper.watchdogTick()
        default:
            preconditionFailure("unexpected stop in the relaunch contract")
        }
        suite.expect(helper.owner == nil && !helper.isRecovering && helper.lastStopReason == earlierStop,
                     "B's completed stop is still the helper's global history (\(earlierStop))")

        Service.shared = Service()
        let client = Service.shared
        let newSession = UUID()
        connect(client, to: helper, session: newSession, legacy: legacy)
        let restores = device?.restores ?? 0
        device?.temperatures = [.init(source: .hottestSoC, celsius: 60)]
        device?.writeError = .operationFailed
        var refusal: FanControlResponse?
        let write = client.proxy.onApply
        client.proxy.onApply = { [unowned client] choice in
            write?(choice)
            refusal = client.statusResponse
        }
        client.proxy.onStatus = { [unowned client] in
            // A rolled-back start closes the device. The new status handle reads the same fans.
            helper.hardware = device
            client.statusResponse = helper.statusResponse()
        }
        Service.recoverIfNeeded()
        suite.expect(refusal?.error == .controlFailed && refusal?.snapshot.stopReason == earlierStop
                        && refusal?.localStopReason == nil && refusal?.retryableApply == (legacy ? nil : true)
                        && device?.restores == restores + 1 && device?.isManual == false,
                     "A's own refused write rolls back successfully while echoing B's stop (\(earlierStop))")
        if legacy {
            client.requestStatus()
            client.retryResume()
            client.workspaceWillSleep()
            client.workspaceDidWake()
            suite.expect(client.proxy.writes == [curve] && client.scheduledResumes.isEmpty
                            && client.proxy.restores == 0 && helper.owner == nil && Service.resumableConfiguration == nil,
                         "without local proof from an older helper, neither idle confirmation nor wake retries the refused write")
            return
        }
        suite.expect(client.proxy.writes == [curve] && client.scheduledResumes == [FanControlResumePolicy.retryDelays[0]]
                        && client.interruption == nil && !client.awaitingSystemControl && Service.resumableConfiguration == curve,
                     "identical local refusals schedule the same retry for every global reason (\(earlierStop))")
        let connection = client.connection
        client.workspaceDidWake()
        suite.expect(client.proxy.writes == [curve] && client.resumeFailures == 1 && client.connection === connection
                        && client.scheduledResumes == [FanControlResumePolicy.retryDelays[0]],
                     "a wake with no preceding sleep cannot bypass the pending retry or reset its budget")
        device?.writeError = nil
        helper.hardware = device
        client.retryResume()
        suite.expect(helper.owner == newSession && client.proxy.writes == [curve, curve]
                        && client.proxy.ownedRestores == 0 && client.proxy.restores == 0,
                     "the authorized retry can start A's curve when the local write recovers (\(earlierStop))")
    }

    private enum RepeatedFanEvent { case wakeDuringLaunch, duplicateWake, hubSync }

    private static func checkRepeatedEvent(_ suite: TestSuite, event: RepeatedFanEvent, beforeReply: Bool) {
        let helper = idleHelper()
        var client = Service.shared
        var session = UUID()
        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        connect(client, to: helper, session: session)
        if event != .hubSync {
            client.applyConfiguration(curve)
            if event == .wakeDuringLaunch {
                Service.restoreBeforeTerminationIfNeeded()
                Service.shared = Service()
                client = Service.shared
                session = UUID()
                connect(client, to: helper, session: session)
            } else {
                client.workspaceWillSleep()
            }
        }
        let previousWrites = client.proxy.writes
        let previousRestores = client.proxy.ownedRestores
        let connection = client.connection
        client.proxy.holdNextApply = true
        switch event {
        case .wakeDuringLaunch: Service.recoverIfNeeded()
        case .duplicateWake: client.workspaceDidWake()
        case .hubSync: client.applyConfiguration(curve)
        }
        guard let reply = client.proxy.heldApply else {
            suite.expect(false, "the original Apply must reach the helper (\(event))")
            return
        }
        client.proxy.heldApply = nil
        if !beforeReply { reply() }
        for _ in 0..<2 {
            // The installed Fan Control binding calls this same sync when the Hub keeps the selection.
            if event == .hubSync { client.syncWithPreferences() }
            else { client.workspaceDidWake() }
        }
        if beforeReply { reply() }
        let context = "\(event), beforeReply=\(beforeReply)"
        suite.expect(helper.owner == session && helper.activeConfiguration == curve && client.activeConfiguration == curve
                        && client.connection === connection && connection?.invalidated == false && !client.awaitingSystemControl
                        && client.proxy.writes == previousWrites + [curve] && client.proxy.ownedRestores == previousRestores
                        && client.proxy.restores == 0 && client.scheduledResumes.isEmpty,
                     "repeated notifications preserve A's original Apply, connection and active session (\(context))")
        client.workspaceWillSleep()
        suite.expect(helper.owner == nil && Service.resumableConfiguration == curve,
                     "the next real sleep can still confirm the same local release (\(context))")
        client.workspaceDidWake()
        suite.expect(helper.owner == session && client.proxy.writes == previousWrites + [curve, curve]
                        && client.proxy.ownedRestores == previousRestores + 1 && client.proxy.restores == 0,
                     "one real sleep/wake resumes exactly once after the repeated notification (\(context))")
    }

    @MainActor private static func checkOtherClientStop(_ suite: TestSuite, observation: FirstObservation,
                                                       expect: (String, String?, String) -> Void) {
        var service: Service { Service.shared }
        let helper = idleHelper()
        let sessionA = UUID()
        let sessionB = UUID()
        connect(service, to: helper, session: sessionA)
        let connection = service.connection
        let reading = FanControlTemperatureReading(source: .hottestSoC, celsius: 60)
        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        let strings = FanControlFeatureStrings.enUS
        let defaults = UserDefaults.standard
        defaults.set(FanControlMode.curve.rawValue, forKey: DefaultsKey.fanControlMode)
        helper.hardware?.temperatures = [reading]
        service.applyConfiguration(curve)
        suite.expect(helper.owner == sessionA && service.activeConfiguration == curve && Service.resumableConfiguration == nil,
                     "an accepted Apply belongs to A and cannot authorize a later launch before its release")
        helper.hardware?.temperatures = []
        for _ in 0..<FanControlPolicy.temperatureFailureLimit { helper.watchdogTick() }
        suite.expect(!helper.isCooling && helper.lastStopReason == .temperatureUnavailable,
                     "A's curve stopped for missing temperature before its next heartbeat")
        let second = helper.applyConfiguration(session: sessionB, configuration: .manual(level: 65), duration: nil)
        suite.expect(second.succeeded && helper.owner == sessionB, "B starts a separate manual session")
        if observation == .otherOwnerActive {
            service.timer?.fire()
            suite.expect(service.error == .alreadyControlled && helper.owner == sessionB
                            && service.awaitingSystemControl && Service.resumableConfiguration == nil,
                         "a heartbeat refused by B's active session immediately revokes A's resume consent")
        }
        helper.lastHeartbeatUptime -= FanControlPolicy.heartbeatLimit + 1
        helper.watchdogTick()
        helper.hardware?.temperatures = [reading]
        suite.expect(helper.lastStopReason == .heartbeatLost && helper.owner == nil
                        && service.proxy.heartbeats == (observation == .otherOwnerActive ? 1 : 0) && service.proxy.statusReads == 0,
                     "B's watchdog stop replaces A's before A reads either stop")
        switch observation {
        case .heartbeat: service.timer?.fire()
        case .sleep:
            service.workspaceWillSleep()
            service.requestStatus()
        case .otherOwnerActive:
            service.statusResponse = helper.statusResponse()
            service.requestStatus()
        }
        suite.expect(service.connection === connection && connection?.invalidated == false
                        && service.proxy.heartbeats == (observation == .sleep ? 0 : 1)
                        && service.proxy.restores == 0 && service.proxy.ownedRestores == (observation == .sleep ? 1 : 0)
                        && service.snapshot.stopReason == .heartbeatLost
                        && service.interruption == .stopped(nil) && service.scheduledResumes.isEmpty,
                     "on A's original connection the global idle reply gives no cause or retry for A")
        expect(strings.systemControl, strings.controlStopped, "B's stop cannot explain why A's curve ended")
        service.retryResume()
        service.workspaceWillSleep()
        service.workspaceDidWake()
        suite.expect(service.proxy.writes == [curve] && helper.owner == nil && Service.resumableConfiguration == nil,
                     "neither a retry nor a wake can write A's previous curve")
        guard observation == .heartbeat else { return }

        Service.shared = Service()
        let relaunched = UUID()
        connect(service, to: helper, session: relaunched)
        Service.recoverIfNeeded()
        service.statusResponse = helper.statusResponse()
        service.requestStatus()
        suite.expect(!service.awaitingSystemControl && !service.isWorking && service.proxy.writes.isEmpty
                        && service.proxy.restores == 0 && service.interruptedStop == "",
                     "relaunch and another idle status preserve the requirement for an explicit Apply")
        expect(strings.systemControl, strings.controlStopped, "relaunch preserves the generic diagnosis")
        service.applyConfiguration(curve)
        suite.expect(service.interruption == nil && helper.owner == relaunched && Service.resumableConfiguration == nil,
                     "a fresh Apply accepts the selected curve again")
        service.workspaceWillSleep()
        suite.expect(helper.owner == nil && !helper.isCooling && service.proxy.ownedRestores == 1 && service.proxy.restores == 0,
                     "local sleep returns the newly applied curve to system control")
        service.workspaceDidWake()
        suite.expect(helper.owner == relaunched && service.proxy.writes == [curve, curve]
                        && service.scheduledResumes.isEmpty && service.interruption == nil,
                     "after its confirmed local handoff, wake writes the kept curve once")
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
                        && service.activeConfiguration == curve && Service.resumableConfiguration == nil && service.timer != nil,
                     "an acknowledged Apply owns the fans without authorizing relaunch before its own release")
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
        expect(strings.systemControl, strings.controlStopped, "confirmation does not attribute B's stop to A")
        service.requestStatus() // The idle helper still reports B's stop.
        service.workspaceWillSleep()
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
        expect(strings.systemControl, strings.controlStopped, "after wake the card still shows no cause attributable to A")
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
        expect(strings.systemControl, strings.controlStopped, "a later status cannot attribute the lost request's stop reason")
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
        let reported = service.controller?.statusResponse().snapshot
        suite.expect(!service.awaitingSystemControl && reported == service.snapshot
                        && service.interruption == .stopped(nil) && service.interruptedStop == ""
                        && !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                     "confirmation (\(source)) keeps the raw reply and stores only a cause attributable to this handoff")
        expect(strings.systemControl, strings.controlStopped, "the confirmed handoff (\(source)) has no attributable cause")
        Service.shared = Service()
        expect(strings.systemControl, strings.controlStopped, "the confirmed diagnosis (\(source)) survives a relaunch")
        if source == .knownReason {
            UserDefaults.standard.set(FanControlStopReason.temperatureUnavailable.rawValue,
                                      forKey: DefaultsKey.fanControlInterruptedStop)
            Service.shared = Service()
            expect(strings.systemControl, strings.controlStopped,
                   "a sensor stop saved by an older client carries no proof of local ownership")
        }
    }
}
