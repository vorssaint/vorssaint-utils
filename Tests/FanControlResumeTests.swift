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
    enum SMAppService {
        static func openSystemSettingsLoginItems() {}
    }
    enum ProcessInfo {
        static let processInfo = Thermal()
        final class Thermal { var thermalState = Foundation.ProcessInfo.ThermalState.nominal }
    }
    enum AppFeature: CaseIterable {
        case fanControl
        var isAvailable: Bool { Environment.available }
    }
    final class SystemMonitor {
        static let shared = SystemMonitor()
        var planChanges = 0
        func planDidChange() { planChanges += 1 }
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
    class Invalidating {
        var invalidated = false
        func invalidate() { invalidated = true }
    }
    final class Timer: Invalidating {
        var tolerance: TimeInterval = 0
        static func scheduledTimer(withTimeInterval: TimeInterval, repeats: Bool, block: (Timer) -> Void) -> Timer {
            Timer() // Tests advance the service with poll().
        }
    }
    final class RemovalProxy {
        let statusReply: Data
        let restoreReply: Data
        var calls: [String] = []

        init(status: Data, restore: Data) {
            statusReply = status
            restoreReply = restore
        }

        func status(withReply reply: @escaping (Data) -> Void) {
            calls.append("status")
            reply(statusReply)
        }

        func restoreForRemoval(withReply reply: @escaping (Data) -> Void) {
            calls.append("restoreForRemoval")
            reply(restoreReply)
        }

        func restoreAutomatic(withReply reply: @escaping (Data) -> Void) {
            calls.append("restoreAutomatic")
            reply(restoreReply)
        }
    }
    final class StatusProxy {
        var statusCalls = 0
        var heartbeats = 0
        var globalRestores = 0
        var sessionReleases = 0
        var restoreCalls: Int { globalRestores + sessionReleases }
        var issuingConnection: Invalidating?
        var lastReleaseConnection: Invalidating?
        var configurations: [FanControlConfiguration] = []
        var holdNextReply = false
        var heldReply: (() -> Void)?
        func status(withReply reply: @escaping () -> Void) {
            statusCalls += 1
            respond(reply)
        }
        func heartbeat(withReply reply: @escaping () -> Void) {
            heartbeats += 1
            respond(reply)
        }
        func applyConfiguration(_ data: Data, withReply reply: @escaping () -> Void) {
            if let configuration = FanControlIPC.decodeConfiguration(data) { configurations.append(configuration) }
            respond(reply)
        }
        func restoreAutomatic(withReply reply: @escaping () -> Void) {
            globalRestores += 1
            respond(reply)
        }
        func releaseControl(withReply reply: @escaping () -> Void) {
            sessionReleases += 1
            lastReleaseConnection = issuingConnection
            respond(reply)
        }
        private func respond(_ reply: @escaping () -> Void) {
            if holdNextReply {
                holdNextReply = false
                heldReply = reply
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
            func register() throws { status = .enabled }
            func unregister() throws {
                unregisterCalls += 1
                status = .notRegistered
            }
        }
        static var shared = Service()
        static var helperVersion = "bundled"
        static let appService = Registration()
        static let log = Logger(subsystem: "com.vorssaint.tests", category: "FanControlResume")
        var accessState = AccessState.enabled
        var snapshot = FanControlSnapshot.empty
        var error: FanControlErrorCode?
        var statusResponse: FanControlResponse?
        var followingResponse: FanControlResponse?
        let proxy = StatusProxy()
        var requestGeneration = 0
        var requestInFlight = false
        var panelIsVisible = false
        var tickCount = 0
        var pendingStop: StopConfirmation?
        var pendingApply: PendingApply?
        var ownedSession: (connection: Invalidating, configuration: FanControlConfiguration, supportsSessionRelease: Bool)?
        var isSleeping = false
        var resumeBlocked = false
        var unregisterAfterRestore = false
        var timer: Timer?
        var connection: Invalidating?
        var observing = true
        var isWorking = false
        var resumeFailures = 0
        var resumeFailed = false
        var scheduledResumes: [TimeInterval] = []
        var applied: [FanControlConfiguration] = []
        var onApply: ((FanControlConfiguration, Bool) -> Void)?
        func send(_ operation: (StatusProxy, @escaping () -> Void) -> Void,
                  completion: @escaping (FanControlResponse?, Invalidating?) -> Void) {
            let requestConnection = connection ?? Invalidating()
            connection = requestConnection
            proxy.issuingConnection = requestConnection
            operation(proxy) {
                let response = self.statusResponse
                if let following = self.followingResponse {
                    self.statusResponse = following
                    self.followingResponse = nil
                }
                completion(response, requestConnection)
            }
        }
        func finishHeldRequest(_ response: FanControlResponse?, followedBy following: FanControlResponse? = nil) {
            statusResponse = response
            followingResponse = following
            let reply = proxy.heldReply
            proxy.heldReply = nil
            reply?()
        }
        func refreshAccessState() { accessState = Self.appService.status }
        func replaceRegistrationIfNeeded() -> Bool { false }
        func refreshLocalProbe() {}
        func applyConfiguration(_ configuration: FanControlConfiguration, resuming: Bool) {
            applied.append(configuration)
            onApply?(configuration, resuming)
        }
        func scheduleResumeAttempt(after delay: TimeInterval) { scheduledResumes.append(delay) }
        func cancelResumeAttempt() { scheduledResumes.removeAll() }
        func startObservingSystemState() { observing = true }
        func stopObservingSystemState() {
            observing = false
            isSleeping = false
        }
    }

    private static func removalRestore(_ suite: TestSuite) {
        var active = FanControlSnapshot.empty
        active.isCooling = true
        let modern = FanControlIPC.encode(.success(active))
        let legacy = FanControlIPC.encode(FanControlResponse(succeeded: true, snapshot: active,
                                                             error: nil, supportsSessionRelease: nil))
        let replies: [(String, FanControlResponse?, Bool)] = [
            ("automatic", .success(.empty), true), ("still cooling", .success(active), false),
            ("refused", .failure(.alreadyControlled, snapshot: active), false),
            ("failed", .failure(.controlFailed), false), ("unreadable", nil, false),
        ]
        for (status, selector) in [(modern, "restoreForRemoval"), (legacy, "restoreAutomatic")] {
            for (description, response, canUnregister) in replies {
                let proxy = RemovalProxy(status: status, restore: response.map(FanControlIPC.encode) ?? Data())
                var confirmations: [Bool] = []
                Service.requestRemovalRestore(using: proxy) { confirmations.append($0) }
                suite.expect(proxy.calls == ["status", selector] && confirmations == [canUnregister],
                             "\(selector) reports whether uninstall can unregister after a \(description) reply")
            }
        }
        let unknown = RemovalProxy(status: Data(), restore: FanControlIPC.encode(.success(.empty)))
        var confirmations: [Bool] = []
        Service.requestRemovalRestore(using: unknown) { confirmations.append($0) }
        suite.expect(unknown.calls == ["status"] && confirmations == [false],
                     "an unreadable capability reply cannot trigger a restore or authorize unregistration")
    }

    static func run(_ suite: TestSuite) {
        removalRestore(suite)
        var service: Service { Service.shared }
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
            Service.appService.status = .enabled
            Service.appService.unregisterCalls = 0
            Service.shared = Service()
            service.timer = Timer()
            service.connection = Invalidating()
            ProcessInfo.processInfo.thermalState = .nominal
        }
        func startControl(_ configuration: FanControlConfiguration, supportsRelease: Bool? = true, hasReceipts: Bool = true) {
            var active = FanControlSnapshot.empty
            active.isCooling = true
            active.configuration = configuration
            service.statusResponse = FanControlResponse(succeeded: true, snapshot: active, error: nil,
                                                        supportsSessionRelease: supportsRelease, isRecovering: hasReceipts ? false : nil)
            service.sendConfiguration(configuration, resuming: false)
        }
        var storedResume: String? { defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) }

        for delayedReply in [false, true] {
            reset()
            service.onApply = { Service.shared.sendConfiguration($0, resuming: $1) }
            var active = FanControlSnapshot.empty
            active.isCooling = true
            active.configuration = manual
            service.statusResponse = .success(active)
            service.proxy.holdNextReply = delayedReply
            let previousChanges = SystemMonitor.shared.planChanges
            launch()
            if delayedReply { service.finishHeldRequest(.success(active)) }
            service.poll()
            suite.expect(SystemMonitor.shared.planChanges == previousChanges + 1
                            && service.proxy.configurations == [manual] && service.proxy.restoreCalls == 0
                            && service.ownsSession && service.proxy.heartbeats == 1
                            && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                         "launch synchronization keeps the saved control whether its application replies before or after the binding")
        }
        reset(stored: nil, recovery: true)
        service.statusResponse = .success(.empty)
        service.proxy.holdNextReply = true
        launch()
        service.finishHeldRequest(.success(.empty))
        suite.expect(service.applied.isEmpty && service.proxy.statusCalls == 1 && service.proxy.restoreCalls == 0
                        && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                     "launch without a saved control checks the previous recovery once and clears the confirmed marker")

        func launchDuringRecovery(_ reason: FanControlStopReason) {
            reset(recovery: true)
            service.onApply = { Service.shared.sendConfiguration($0, resuming: $1) }
            service.proxy.holdNextReply = true
            launch()
            var stopped = FanControlSnapshot.empty
            stopped.stopReason = reason
            var recovering = FanControlResponse.failure(.controlFailed, snapshot: stopped)
            recovering.isRecovering = true
            service.finishHeldRequest(recovering)
            service.workspaceDidWake()
            service.retryResume()
            service.poll()
            service.poll()
            suite.expect(service.proxy.statusCalls == 2 && service.proxy.configurations.isEmpty
                            && service.scheduledResumes.isEmpty && service.resumeFailures == 0,
                         "a new client waits for the previous recovery without applying or spending a retry")
        }
        func confirmAtLaunch(_ reason: FanControlStopReason?, then reply: FanControlResponse? = nil) {
            var stopped = FanControlSnapshot.empty
            stopped.stopReason = reason
            service.proxy.holdNextReply = true
            service.requestStatus()
            service.finishHeldRequest(.success(stopped), followedBy: reply)
        }

        launchDuringRecovery(.appDisconnected)
        var resumed = FanControlSnapshot.empty
        resumed.isCooling = true
        resumed.configuration = manual
        confirmAtLaunch(.appDisconnected, then: .success(resumed))
        service.poll()
        suite.expect(service.proxy.configurations == [manual] && service.ownsSession
                        && service.proxy.heartbeats == 1 && service.resumeFailures == 0,
                     "confirmation of the previous disconnect permits the saved configuration to start once")

        for reason: FanControlStopReason in [.hardwareChanged, .thermalPressure, .temperatureUnavailable] {
            reset(recovery: true)
            var protected = FanControlSnapshot.empty
            protected.stopReason = reason
            service.statusResponse = .success(protected)
            launch()
            service.workspaceDidWake()
            suite.expect(service.resumeFailed && service.applied.isEmpty && service.scheduledResumes.isEmpty,
                         "a protection stop in the first launch status vetoes the saved curve")
        }
        for activate in [{ service.panelDidAppear() }, { service.authorize() }, { service.workspaceDidWake() }] {
            reset(recovery: true)
            service.timer = nil
            service.observing = false
            Service.appService.status = .requiresApproval
            launch()
            service.workspaceDidWake()
            suite.expect(service.observing && service.timer == nil && service.proxy.statusCalls == 0
                            && service.applied.isEmpty && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                         "without approval the launch check waits for user action or a wake without polling")
            Service.appService.status = .enabled
            var stopped = FanControlSnapshot.empty
            stopped.stopReason = .hardwareChanged
            service.proxy.holdNextReply = true
            activate()
            service.workspaceWillSleep()
            service.workspaceDidWake()
            service.finishHeldRequest(.success(stopped))
            service.workspaceDidWake()
            suite.expect(service.proxy.statusCalls == 1 && service.resumeFailed && service.applied.isEmpty
                            && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                         "the first check after approval preserves a protection stop through later wakes")
        }
        for needsReplacement in [false, true] {
            reset(recovery: true)
            Service.appService.status = .requiresApproval
            defaults.values[DefaultsKey.fanControlHelperVersion] = needsReplacement ? "previous" : Service.helperVersion
            launch()
            service.workspaceWillSleep()
            Service.appService.status = .enabled
            service.statusResponse = .success(.empty)
            service.workspaceDidWake()
            suite.expect(service.proxy.statusCalls == 1 && service.applied == (needsReplacement ? [] : [manual])
                            && service.pendingStop == nil && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                            && Service.helperAwaitsRegistration == needsReplacement,
                         "after late approval a wake confirms automatic mode before resuming or allowing helper replacement")
        }
        reset(recovery: true)
        service.timer = nil
        service.proxy.holdNextReply = true
        launch()
        service.finishHeldRequest(nil)
        suite.expect(service.timer != nil && service.applied.isEmpty
                        && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                     "an interrupted launch status keeps polling without issuing a write")
        service.statusResponse = .success(.empty)
        service.poll()
        service.poll()
        suite.expect(service.proxy.statusCalls == 2 && service.applied == [manual],
                     "a later automatic reading finishes the interrupted launch check")

        for (recovering, confirmed): (FanControlStopReason, FanControlStopReason?) in [
            (.hardwareChanged, .appDisconnected), (.appDisconnected, .thermalPressure), (.appDisconnected, nil),
        ] {
            launchDuringRecovery(recovering)
            confirmAtLaunch(confirmed)
            service.workspaceDidWake()
            service.retryResume()
            suite.expect(service.proxy.configurations.isEmpty && service.scheduledResumes.isEmpty
                            && service.resumeFailed && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                         "a protection stop or lost recovery history at relaunch keeps the fans on automatic")
        }

        for recoveringAgain in [false, true] {
            launchDuringRecovery(.appDisconnected)
            var prior = FanControlSnapshot.empty
            prior.stopReason = .appDisconnected
            var refused = FanControlResponse.failure(.controlFailed, snapshot: prior)
            refused.isRecovering = recoveringAgain
            service.onApply = { configuration, resuming in
                Service.shared.statusResponse = refused
                Service.shared.followingResponse = recoveringAgain ? refused : .success(prior)
                Service.shared.sendConfiguration(configuration, resuming: resuming)
            }
            confirmAtLaunch(.appDisconnected)
            for _ in FanControlResumePolicy.retryDelays {
                if recoveringAgain {
                    let before = service.proxy.configurations.count
                    service.retryResume()
                    suite.expect(service.proxy.configurations.count == before,
                                 "a refused resume waits for the new recovery confirmation before retrying")
                    confirmAtLaunch(.appDisconnected)
                }
                service.retryResume()
            }
            if recoveringAgain { confirmAtLaunch(.appDisconnected) }
            service.retryResume()
            suite.expect(service.proxy.configurations.count == 1 + FanControlResumePolicy.retryDelays.count
                            && service.scheduledResumes == FanControlResumePolicy.retryDelays && service.resumeFailed,
                         "resumes refused with a previous disconnect consume exactly the normal retry budget")
        }

        reset(resume: false, recovery: true)
        service.statusResponse = .success(.empty)
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.proxy.restoreCalls == 0 && service.proxy.statusCalls == 1
                        && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                     "launch confirms automatic control for an earlier session without writing to its fans")
        reset(recovery: true)
        service.statusResponse = .success(.empty)
        Service.recoverIfNeeded()
        suite.expect(service.applied == [manual] && service.proxy.restoreCalls == 0 && service.proxy.statusCalls == 1,
                     "a first automatic reading with no stop history permits the requested launch resume")
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
        idle.configuration = manual
        idle.fans = [.init(index: 0, actualRPM: 2_000, minimumRPM: 1_200, maximumRPM: 5_800,
                           targetRPM: 2_000, isManuallyControlled: true)]
        idle.temperatures = [.init(source: .hottestCPU, celsius: 45)]
        idle.gpuPoweredDown = true
        service.statusResponse = .success(idle)
        service.sendConfiguration(manual, resuming: false)
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

        reset(resume: false, stored: nil)
        startControl(manual)
        var unversioned = FanControlSnapshot.empty
        unversioned.isCooling = true
        service.statusResponse = .success(unversioned)
        service.requestStatus()
        service.poll()
        defaults.values[DefaultsKey.fanControlResume] = true
        service.resumePreferenceDidChange()
        suite.expect(service.proxy.heartbeats == 1 && FanControlConfiguration.decodeResume(storedResume ?? "") == manual,
                     "older telemetry can omit the configuration while the client keeps its heartbeat and saves its accepted speed")
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
        startControl(manual)
        service.statusResponse = .success(.empty)
        service.returnToSystem()
        suite.expect(storedResume == nil && service.proxy.sessionReleases == 1 && service.proxy.globalRestores == 0
                        && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
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
        service.statusResponse = .success(.empty)
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.proxy.restoreCalls == 0 && service.proxy.statusCalls == 1
                        && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                     "without resume, waking confirms the end of the interrupted session")
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
        startControl(manual)
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

        func stoppedSession(_ reason: FanControlStopReason?, restored: Bool = true,
                            telemetry: FanControlSnapshot? = nil) -> FanControlResponse {
            var stopped = FanControlSnapshot.empty
            stopped.stopReason = reason
            return FanControlResponse(succeeded: restored, snapshot: telemetry ?? stopped,
                                      error: restored ? nil : .controlFailed, supportsSessionRelease: true,
                                      sessionStop: .init(reason: reason, restored: restored), isRecovering: !restored)
        }

        for reason: FanControlStopReason? in [.hardwareChanged, .temperatureUnavailable, .thermalPressure,
                                               .recovery, .appDisconnected, .timeLimit, nil, .heartbeatLost] {
            reset()
            startControl(manual)
            var stopped = FanControlSnapshot.empty
            stopped.stopReason = reason
            service.applyStatus(stoppedSession(reason))
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
        startControl(manual)
        var stopped = FanControlSnapshot.empty
        stopped.stopReason = .heartbeatLost
        service.applyStatus(stoppedSession(.heartbeatLost))
        suite.expect(service.scheduledResumes.isEmpty, "a heartbeat loss only resumes opted-in control")

        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        func readStatus(_ response: FanControlResponse) {
            service.statusResponse = response
            service.requestStatus()
        }
        func startCurve(panelVisible: Bool = false) {
            reset(stored: nil)
            defaults.values[DefaultsKey.fanControlMode] = FanControlMode.curve.rawValue
            service.panelIsVisible = panelVisible
            startControl(curve)
        }

        reset(resume: false, stored: nil)
        startControl(curve)
        let sameCurve = service.snapshot
        readStatus(stoppedSession(.hardwareChanged, telemetry: sameCurve))
        service.heartbeat()
        service.poll()
        defaults.values[DefaultsKey.fanControlResume] = true
        service.resumePreferenceDidChange()
        suite.expect(service.snapshot == sameCurve && !service.ownsSession && service.proxy.heartbeats == 0
                        && storedResume == nil && service.proxy.restoreCalls == 0,
                     "a local stop receipt revokes ownership even while the panel shows another client's identical active curve")

        // A stopped for hardware protection; B subsequently ran the same curve and lost its heartbeat.
        for readsStatus in [false, true] {
            for hasOwnReceipt in [false, true] {
                startCurve(panelVisible: readsStatus)
                var latest = FanControlResponse.success(stopped)
                latest.isRecovering = false
                service.statusResponse = hasOwnReceipt
                    ? stoppedSession(.hardwareChanged, telemetry: stopped) : latest
                if readsStatus { service.requestStatus() } else { service.heartbeat() }
                readStatus(latest)
                service.workspaceDidWake()
                service.retryResume()
                suite.expect(service.snapshot.stopReason == .heartbeatLost && service.applied.isEmpty
                                && service.scheduledResumes.isEmpty && service.proxy.configurations == [curve],
                             "the panel may show B's heartbeat loss but neither status nor heartbeat can resume A's curve")
            }
            for supportsRelease: Bool? in [nil, true] {
                reset(stored: nil)
                startControl(curve, supportsRelease: supportsRelease, hasReceipts: false)
                service.statusResponse = FanControlResponse(succeeded: true, snapshot: stopped, error: nil,
                                                            supportsSessionRelease: supportsRelease)
                if readsStatus { service.requestStatus() } else { service.heartbeat() }
                service.workspaceDidWake()
                service.retryResume()
                suite.expect(service.applied.isEmpty && service.scheduledResumes.isEmpty,
                             "an older helper's ordinary status and heartbeat cannot attribute the global stop to this curve")
            }
        }

        func startRecovery(panelVisible: Bool = false, reason: FanControlStopReason = .heartbeatLost) {
            startCurve(panelVisible: panelVisible)
            var recovering = FanControlSnapshot.empty
            recovering.stopReason = reason
            service.statusResponse = stoppedSession(reason, restored: false)
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

        func confirmRecovery(_ reason: FanControlStopReason?, hasReceipt: Bool = true) {
            var restored = FanControlSnapshot.empty
            restored.stopReason = reason
            service.statusResponse = hasReceipt ? stoppedSession(reason) : .success(restored)
            service.poll()
            service.poll()
            suite.expect(service.snapshot == restored && service.error == nil
                            && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                            && (service.timer != nil) == service.panelIsVisible,
                         "the timer observes automatic control and finishes recovery even with the panel closed")
            readStatus(.success(restored)) // A repeated observation after the receipt was consumed.
        }

        func interruptApply(accepted: Bool, eventBeforeReply: Bool, removing: Bool = false, anotherOwner: Bool = false,
                            legacy: Bool = false, disconnectReason: FanControlStopReason? = .appDisconnected,
                            event: () -> Void) {
            reset(stored: removing ? manual : nil)
            defaults.values[DefaultsKey.fanControlMode] = FanControlMode.curve.rawValue
            var active = FanControlSnapshot.empty
            active.isCooling = true
            active.configuration = curve
            let reply = FanControlResponse(succeeded: accepted, snapshot: active, error: accepted ? nil : .alreadyControlled,
                                           supportsSessionRelease: legacy ? nil : true)
            service.proxy.holdNextReply = eventBeforeReply
            service.statusResponse = reply
            service.sendConfiguration(curve, resuming: false)
            let issuingConnection = service.proxy.issuingConnection
            if accepted && !legacy && !eventBeforeReply { service.proxy.holdNextReply = true }
            event()
            let replacementConnection = legacy && anotherOwner && removing ? Invalidating() : nil
            if let replacementConnection { service.connection = replacementConnection }
            if eventBeforeReply {
                suite.expect(service.isWorking && service.proxy.heldReply != nil && service.proxy.restoreCalls == 0
                                && Service.appService.unregisterCalls == 0 && service.applied.isEmpty,
                             "the lifecycle event waits for the outstanding application to establish ownership")
                if accepted && !legacy { service.proxy.holdNextReply = true }
                service.finishHeldRequest(reply)
            }
            if removing {
                suite.expect(storedResume == nil, "the discarded curve stays forgotten while removal awaits a handoff")
            }
            if accepted && legacy {
                suite.expect(issuingConnection?.invalidated == true && service.connection !== issuingConnection
                                && (replacementConnection == nil || service.connection === replacementConnection)
                                && replacementConnection?.invalidated != true && service.proxy.restoreCalls == 0
                                && service.timer != nil && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                             "a legacy session closes exactly its issuing connection and waits for a status confirmation")
                var disconnected = FanControlSnapshot.empty
                disconnected.stopReason = disconnectReason
                service.statusResponse = FanControlResponse(succeeded: anotherOwner, snapshot: anotherOwner ? active : disconnected,
                                                            error: anotherOwner ? nil : .controlFailed, supportsSessionRelease: nil)
                let reads = service.proxy.statusCalls
                service.poll()
                service.poll()
                service.heartbeat()
                service.retryResume()
                suite.expect(service.proxy.statusCalls > reads && service.proxy.issuingConnection !== issuingConnection
                                && service.proxy.heartbeats == 0 && service.proxy.restoreCalls == 0
                                && service.applied.isEmpty && service.scheduledResumes.isEmpty
                                && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) && Service.appService.unregisterCalls == 0,
                             "checking the closed session sends only status requests until the helper confirms automatic control")
                service.statusResponse = FanControlResponse(succeeded: true, snapshot: disconnected, error: nil, supportsSessionRelease: nil)
                for _ in 0..<(anotherOwner ? 60 : 2) { service.poll() }
                suite.expect(service.snapshot == disconnected && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                             "the status timer observes the confirmed disconnect before ending recovery")
                service.requestStatus()
            } else if accepted {
                suite.expect(service.proxy.globalRestores == 0 && service.proxy.sessionReleases == 1
                                && service.proxy.lastReleaseConnection === issuingConnection
                                && service.proxy.heldReply != nil && Service.appService.unregisterCalls == 0
                                && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                             "the current helper receives one scoped release on the connection that applied the curve")
                if anotherOwner {
                    service.finishHeldRequest(.failure(.alreadyControlled, snapshot: active))
                    service.heartbeat()
                    service.retryResume()
                    suite.expect(service.proxy.heartbeats == 0 && service.proxy.restoreCalls == 1 && service.applied.isEmpty
                                    && Service.appService.unregisterCalls == 0,
                                 "a refused scoped release cannot disturb the identical curve held by another owner")
                    readStatus(.success(.empty))
                } else {
                    service.finishHeldRequest(.success(.empty))
                }
            } else {
                readStatus(.success(active))
                service.heartbeat()
                suite.expect(service.proxy.restoreCalls == 0 && service.proxy.heartbeats == 0
                                && Service.appService.unregisterCalls == 0
                                && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                             "an identical active curve after a refused application remains with its external owner")
            }
        }

        for (eventBeforeReply, wakeEarly) in [(false, false), (true, false), (true, true)] {
            for accepted in [false, true] {
                interruptApply(accepted: accepted, eventBeforeReply: eventBeforeReply) {
                    service.workspaceWillSleep()
                    if wakeEarly { service.workspaceDidWake() }
                }
                if !wakeEarly { service.workspaceDidWake() }
                if !service.scheduledResumes.isEmpty { service.retryResume() }
                suite.expect(service.proxy.configurations == [curve] && service.applied == (accepted ? [curve] : [])
                                && FanControlConfiguration.decodeResume(storedResume ?? "") == (accepted ? curve : nil),
                             "wake resumes the accepted curve once and never adopts a refused one")
            }
        }

        for legacy in [false, true] {
            for (removing, eventBeforeReply) in [(false, false), (false, true), (true, false), (true, true)] {
                interruptApply(accepted: true, eventBeforeReply: eventBeforeReply, removing: removing, anotherOwner: true, legacy: legacy) {
                    if removing {
                        Environment.available = false
                        service.syncWithPreferences()
                    } else {
                        service.workspaceWillSleep()
                    }
                }
                service.workspaceDidWake()
                suite.expect(service.proxy.configurations == [curve] && service.proxy.globalRestores == 0
                                && service.proxy.heartbeats == 0 && service.applied.isEmpty && service.scheduledResumes.isEmpty
                                && Service.appService.unregisterCalls == (removing ? 1 : 0),
                             "another owner's identical curve never receives a global restore, heartbeat or saved-curve retry")
            }
        }
        for (eventBeforeReply, earlyWake) in [(false, false), (false, true), (true, false), (true, true)] {
            for reason: FanControlStopReason? in [nil, .appDisconnected, .heartbeatLost, .hardwareChanged,
                                                   .timeLimit, .thermalPressure, .temperatureUnavailable, .recovery] {
                interruptApply(accepted: true, eventBeforeReply: eventBeforeReply, legacy: true, disconnectReason: reason) {
                    service.workspaceWillSleep()
                    if earlyWake { service.workspaceDidWake() }
                }
                if !earlyWake { service.workspaceDidWake() }
                service.retryResume()
                suite.expect(service.applied.isEmpty && service.scheduledResumes.isEmpty && service.proxy.configurations == [curve]
                                && service.proxy.restoreCalls == 0 && !defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                             "an idle legacy status confirms automatic control after disconnect but cannot attribute a stop to the sleeping client")
            }
        }

        reset(stored: nil)
        startControl(curve, hasReceipts: false)
        service.proxy.holdNextReply = true
        service.workspaceWillSleep()
        service.finishHeldRequest(nil)
        service.statusResponse = .success(stopped)
        service.poll()
        service.poll()
        service.workspaceDidWake()
        service.retryResume()
        suite.expect(service.proxy.sessionReleases == 1 && service.proxy.statusCalls > 0
                        && service.scheduledResumes.isEmpty && service.applied.isEmpty,
                     "losing an older helper's scoped release reply cannot turn a later global heartbeat reason into the owner's receipt")

        startCurve()
        service.proxy.holdNextReply = true
        service.workspaceWillSleep()
        service.workspaceWillSleep()
        service.workspaceDidWake()
        suite.expect(service.proxy.sessionReleases == 1 && service.proxy.heldReply != nil
                        && service.applied.isEmpty && service.scheduledResumes.isEmpty,
                     "duplicate sleep notifications leave one scoped release pending across wake")
        service.finishHeldRequest(stoppedSession(nil))
        suite.expect(service.scheduledResumes == [FanControlResumePolicy.retryDelays[0]],
                     "the first release acknowledgement schedules exactly one wake resume")
        service.retryResume()
        suite.expect(service.applied == [curve] && service.proxy.globalRestores == 0,
                     "the acknowledged release resumes only the accepted local curve")

        for removing in [false, true] {
            startCurve()
            service.proxy.holdNextReply = true
            if removing {
                Environment.available = false
                service.syncWithPreferences()
            } else {
                service.workspaceWillSleep()
                service.workspaceDidWake()
            }
            let replacement = Invalidating()
            service.connection = replacement
            service.proxy.holdNextReply = true
            service.finishHeldRequest(.success(.empty))
            service.poll()
            service.poll()
            suite.expect(service.proxy.statusCalls > 0 && service.proxy.issuingConnection === replacement
                            && service.proxy.heldReply != nil && Service.appService.unregisterCalls == 0
                            && service.scheduledResumes.isEmpty && service.applied.isEmpty,
                         "a release acknowledgement from the old connection waits for status on its replacement")
            service.connection = Invalidating()
            service.finishHeldRequest(.success(.empty))
            suite.expect(defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                            && Service.appService.unregisterCalls == 0 && service.scheduledResumes.isEmpty,
                         "an obsolete status reply also leaves the handoff pending")
            service.requestStatus()
            service.workspaceDidWake()
            service.retryResume()
            suite.expect(Service.appService.unregisterCalls == (removing ? 1 : 0) && service.applied.isEmpty
                            && service.scheduledResumes.isEmpty && service.proxy.sessionReleases == 1
                            && service.proxy.globalRestores == 0,
                         "the replacement's idle status confirms removal once and cannot authorize a wake resume")
        }

        reset(stored: manual)
        service.proxy.holdNextReply = true
        service.sendConfiguration(curve, resuming: false)
        let lostReplyConnection = service.proxy.issuingConnection
        service.workspaceWillSleep()
        service.finishHeldRequest(nil)
        suite.expect(lostReplyConnection?.invalidated == true && service.proxy.restoreCalls == 0
                        && service.applied.isEmpty && service.scheduledResumes.isEmpty,
                     "an unreadable apply reply releases the issuing client without assuming ownership")
        confirmRecovery(.appDisconnected, hasReceipt: false)
        service.workspaceDidWake()
        suite.expect(service.proxy.configurations == [curve] && service.applied.isEmpty && service.scheduledResumes.isEmpty
                        && FanControlConfiguration.decodeResume(storedResume ?? "") == manual,
                     "a confirmed disconnect after an unreadable reply cannot authorize a wake resume")

        for legacy in [false, true] {
            reset(stored: nil)
            var active = FanControlSnapshot.empty
            active.isCooling = true
            active.configuration = curve
            service.statusResponse = FanControlResponse(succeeded: true, snapshot: active, error: nil,
                                                        supportsSessionRelease: legacy ? nil : true)
            service.sendConfiguration(curve, resuming: false)
            let owner = service.proxy.issuingConnection
            Service.restoreBeforeTerminationIfNeeded()
            suite.expect(owner?.invalidated == true && service.proxy.restoreCalls == 0,
                         "quitting closes the owned connection without waiting for a release reply on either helper")
        }

        let removals: [(beforeReply: Bool, registration: Fixture.AccessState)] = [
            (false, .enabled), (true, .enabled), (true, .requiresApproval), (true, .notRegistered),
        ]
        for (eventBeforeReply, registration) in removals {
            for accepted in [false, true] {
                for reenable in [false, true] {
                    interruptApply(accepted: accepted, eventBeforeReply: eventBeforeReply, removing: true) {
                        Service.appService.status = registration
                        Environment.available = false
                        service.syncWithPreferences()
                        if reenable {
                            Environment.available = true
                            service.syncWithPreferences()
                        }
                    }
                    readStatus(.success(.empty))
                    readStatus(.success(.empty))
                    service.workspaceDidWake()
                    service.retryResume()
                    let shouldUnregister = !reenable && registration != .notRegistered
                    suite.expect(Service.appService.unregisterCalls == (shouldUnregister ? 1 : 0) && storedResume == nil
                                    && service.applied.isEmpty && service.scheduledResumes.isEmpty
                                    && service.proxy.configurations == [curve],
                                 "confirmed idle unregisters a removed feature once and never saves or resumes its discarded curve")
                }
            }
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

        startCurve()
        service.proxy.holdNextReply = true
        service.returnToSystem()
        service.poll()
        suite.expect(service.proxy.heldReply != nil && service.isWorking && storedResume == nil,
                     "returning to System forgets the saved curve while the restore reply is pending")
        service.finishHeldRequest(.failure(.controlFailed, snapshot: stopped))
        let beforeRestorePolls = service.proxy.statusCalls
        service.poll()
        service.poll()
        suite.expect(service.snapshot == stopped && service.error == .controlFailed
                        && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
                        && service.proxy.statusCalls > beforeRestorePolls && service.timer != nil,
                     "a failed explicit restore keeps checking for confirmation with the panel closed")
        confirmRecovery(.heartbeatLost)
        service.workspaceDidWake()
        service.retryResume()
        suite.expect(storedResume == nil && service.applied.isEmpty && service.scheduledResumes.isEmpty
                        && service.proxy.configurations == [curve] && service.proxy.sessionReleases == 1
                        && service.proxy.globalRestores == 0,
                     "confirming the explicit restore twice leaves the fans with the system through the next wake")

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
            service.proxy.holdNextReply = true
            let beforeSleepCheck = service.proxy.statusCalls
            service.workspaceWillSleep()
            suite.expect(service.proxy.heldReply != nil && service.proxy.statusCalls == beforeSleepCheck + 1
                            && service.proxy.restoreCalls == 0,
                         "sleep checks an already stopped session without another restore command")
            if wakesBeforeReply { service.workspaceDidWake() }
            service.finishHeldRequest(stoppedSession(.heartbeatLost))
            suite.expect(service.applied.isEmpty && service.scheduledResumes.count == (wakesBeforeReply ? 1 : 0),
                         "the sleep restore can confirm the stop and only schedule a retry after wake")
            if wakesBeforeReply { service.retryResume() } else { service.workspaceDidWake() }
            suite.expect(service.applied == [curve], "a wake on either side of the restore reply resumes once")

            startCurve()
            service.proxy.holdNextReply = true
            service.workspaceWillSleep()
            if wakesBeforeReply { service.workspaceDidWake() }
            service.finishHeldRequest(stoppedSession(nil))
            if !wakesBeforeReply { service.workspaceDidWake() }
            if !service.scheduledResumes.isEmpty { service.retryResume() }
            suite.expect(service.applied == [curve], "an ordinary sleep restore permits the next wake to resume once")

            startCurve()
            service.statusResponse = stoppedSession(nil, restored: false)
            service.workspaceWillSleep()
            if wakesBeforeReply { service.workspaceDidWake() }
            service.retryResume()
            suite.expect(service.proxy.sessionReleases == 1 && service.scheduledResumes.isEmpty && service.applied.isEmpty
                            && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
                         "a failed voluntary sleep release waits for its owner's completed receipt")
            confirmRecovery(nil)
            if wakesBeforeReply { service.retryResume() } else { service.workspaceDidWake() }
            suite.expect(service.applied == [curve] && service.proxy.sessionReleases == 1 && service.proxy.globalRestores == 0,
                         "the watchdog's confirmed voluntary release resumes the same curve once on either side of wake")

            for releaseReply: FanControlResponse? in [nil, .failure(.controlFailed)] {
                startCurve()
                service.proxy.holdNextReply = true
                service.workspaceWillSleep()
                if wakesBeforeReply { service.workspaceDidWake() }
                service.finishHeldRequest(releaseReply)
                // The replacement helper has no record of the previous stop.
                service.connection = Invalidating()
                confirmRecovery(nil, hasReceipt: false)
                if !wakesBeforeReply { service.workspaceDidWake() }
                service.retryResume()
                suite.expect(service.proxy.sessionReleases == 1 && service.proxy.globalRestores == 0
                                && service.applied.isEmpty && service.scheduledResumes.isEmpty,
                             "an idle status without a reason after an inconclusive scoped release cannot resume the curve")
            }

            for confirmation: FanControlStopReason? in [.hardwareChanged, nil] {
                startCurve()
                service.proxy.holdNextReply = true
                service.sendConfiguration(manual, resuming: false)
                service.workspaceWillSleep()
                if wakesBeforeReply { service.workspaceDidWake() }
                var refused = FanControlSnapshot.empty
                refused.stopReason = .hardwareChanged
                var idle = FanControlSnapshot.empty
                idle.stopReason = confirmation
                service.finishHeldRequest(stoppedSession(.hardwareChanged, restored: false, telemetry: refused),
                                          followedBy: .success(idle))
                readStatus(.success(idle))
                if !wakesBeforeReply { service.workspaceDidWake() }
                service.workspaceWillSleep()
                service.workspaceDidWake()
                service.retryResume()
                suite.expect(service.proxy.configurations == [curve, manual] && service.applied.isEmpty
                                && service.scheduledResumes.isEmpty && service.proxy.globalRestores == 0,
                             "a hardware stop in a refused reconfiguration vetoes the saved curve across subsequent wakes")
                startControl(manual)
                service.statusResponse = stoppedSession(nil)
                service.workspaceWillSleep()
                service.workspaceDidWake()
                if !service.scheduledResumes.isEmpty { service.retryResume() }
                suite.expect(service.applied == [manual], "a newly accepted local configuration clears the previous protection veto")
            }

            for restoreFailed in [false, true] {
                startCurve()
                service.proxy.holdNextReply = true
                service.workspaceWillSleep()
                suite.expect(service.proxy.heldReply != nil && service.isWorking,
                             "sleep leaves the requested restore in flight until the helper replies")
                if wakesBeforeReply {
                    service.workspaceDidWake()
                    suite.expect(service.applied.isEmpty && service.scheduledResumes.isEmpty,
                                 "wake waits for the scoped release reply before scheduling an application")
                }
                var unsafeStop = FanControlSnapshot.empty
                unsafeStop.stopReason = .hardwareChanged
                let reply = stoppedSession(.hardwareChanged, restored: !restoreFailed, telemetry: unsafeStop)
                service.finishHeldRequest(reply)
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
        service.proxy.holdNextReply = true
        service.workspaceWillSleep()
        suite.expect(service.proxy.statusCalls == 1 && service.proxy.restoreCalls == 0 && service.proxy.heldReply != nil,
                     "sleep reads the helper status when only an earlier recovery marker remains")
        var historicalStop = FanControlSnapshot.empty
        historicalStop.stopReason = .hardwareChanged
        service.finishHeldRequest(.success(historicalStop))
        service.workspaceDidWake()
        suite.expect(service.applied == [curve] && service.scheduledResumes.isEmpty,
                     "a historical protection reason from a helper already idle at sleep cannot veto the next wake")

        for interveningProtection in [false, true] {
            startRecovery()
            readStatus(.failure(.controlFailed))
            if interveningProtection {
                var unsafeStop = FanControlSnapshot.empty
                unsafeStop.stopReason = .thermalPressure
                readStatus(stoppedSession(.thermalPressure, restored: false, telemetry: unsafeStop))
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

        var foreign = FanControlSnapshot.empty
        foreign.isCooling = true
        foreign.configuration = .manual(level: 40)
        for hadSession in [false, true] {
            if hadSession {
                startRecovery()
            } else {
                reset(resume: false, stored: nil)
                service.timer = nil
            }
            let beforeHeartbeats = service.proxy.heartbeats
            service.statusResponse = .success(foreign)
            service.panelDidAppear()
            service.heartbeat()
            for _ in 0..<4 { service.poll() }
            if hadSession {
                readStatus(.success(stopped))
                service.retryResume()
                suite.expect(service.applied.isEmpty && service.scheduledResumes.isEmpty,
                             "the end of an observed foreign session cannot restart the previously owned curve")
                readStatus(.success(foreign))
                defaults.values[DefaultsKey.fanControlResume] = false
                service.resumePreferenceDidChange()
            }
            defaults.values[DefaultsKey.fanControlResume] = true
            service.resumePreferenceDidChange()
            suite.expect(service.snapshot == foreign && service.proxy.heartbeats == beforeHeartbeats && storedResume == nil,
                         "enabling resume while observing another controller cannot adopt or heartbeat its configuration")
            if !hadSession {
                let timer = service.timer
                let connection = service.connection
                service.panelDidDisappear()
                suite.expect(timer?.invalidated == true && connection?.invalidated == true
                                && service.timer == nil && service.connection == nil,
                             "closing a panel that only observed a foreign session stops the timer and disconnects")
            }
            readStatus(.success(stopped))
            service.workspaceDidWake()
            suite.expect(service.applied.isEmpty && service.scheduledResumes.isEmpty && service.proxy.restoreCalls == 0,
                         "a wake leaves an observed configuration with its owner")
        }

        for replacesBeforeReply in [false, true] {
            reset(resume: false, stored: nil)
            service.proxy.holdNextReply = replacesBeforeReply
            startControl(curve)
            var matching = FanControlSnapshot.empty
            matching.isCooling = true
            matching.configuration = curve
            service.connection = Invalidating()
            if replacesBeforeReply { service.finishHeldRequest(.success(matching)) }
            readStatus(.success(matching))
            service.heartbeat()
            defaults.values[DefaultsKey.fanControlResume] = true
            service.resumePreferenceDidChange()
            suite.expect(service.proxy.heartbeats == 0 && storedResume == nil,
                         "a replacement connection cannot claim even an identical curve from the previous connection")
            startControl(curve)
            service.heartbeat()
            suite.expect(service.proxy.heartbeats == 1 && FanControlConfiguration.decodeResume(storedResume ?? "") == curve,
                         "a new accepted apply establishes ownership on the replacement connection")
        }

        for stoppedBeforeReconnect in [false, true] {
            if stoppedBeforeReconnect { startRecovery() } else { startCurve() }
            service.connection = Invalidating()
            readStatus(.success(stopped))
            service.requestStatus()
            service.workspaceDidWake()
            service.retryResume()
            suite.expect(service.scheduledResumes.isEmpty && service.applied.isEmpty,
                         "global telemetry on a replacement connection cannot confirm even an earlier pending local receipt")
        }

        reset(resume: false, stored: nil)
        startControl(curve)
        readStatus(.success(foreign))
        service.poll()
        defaults.values[DefaultsKey.fanControlResume] = true
        service.resumePreferenceDidChange()
        suite.expect(service.proxy.heartbeats == 0 && storedResume == nil,
                     "a different active configuration is foreign even on the same connection")

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

        for previousRecovery in [false, true] {
            reset(resume: false, stored: nil, recovery: previousRecovery)
            service.statusResponse = .failure(.alreadyControlled)
            service.sendConfiguration(curve, resuming: false)
            Service.restoreBeforeTerminationIfNeeded()
            suite.expect(service.proxy.configurations == [curve] && service.proxy.restoreCalls == 0
                            && defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) == previousRecovery,
                         "a refused application leaves only preexisting recovery work and never restores on quit")
            Service.shared = Service() // A new process reads the same preferences.
            service.statusResponse = .success(foreign)
            Service.recoverIfNeeded()
            suite.expect(service.proxy.restoreCalls == 0 && service.applied.isEmpty
                            && service.proxy.statusCalls == (previousRecovery ? 1 : 0),
                         "on relaunch only earlier recovery work checks the external session without restoring it")
        }

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
            let checks = service.proxy.statusCalls
            service.syncWithPreferences()
            suite.expect(service.proxy.statusCalls == checks + 1 && service.proxy.restoreCalls == 0
                            && Service.appService.unregisterCalls == 0
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
        startControl(manual)
        Environment.available = false
        service.statusResponse = .success(.empty)
        service.syncWithPreferences()
        suite.expect(storedResume == nil && service.proxy.sessionReleases == 1 && service.proxy.globalRestores == 0
                        && Service.appService.unregisterCalls == 1,
                     "removing the feature forgets the kept control before unregistering the helper")
        reset()
    }
}
