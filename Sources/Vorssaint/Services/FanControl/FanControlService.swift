// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import os
import ServiceManagement

final class FanControlService: ObservableObject {
    enum AccessState: Equatable {
        case notRegistered
        case requiresApproval
        case enabled
        case unavailable
    }

    static let shared = FanControlService()

    @Published private(set) var accessState: AccessState = .notRegistered
    @Published private(set) var snapshot: FanControlSnapshot = .empty
    @Published private(set) var error: FanControlErrorCode?
    @Published private(set) var isWorking = false
    @Published private(set) var interruption: FanControlInterruption? = {
        if let dismissed = UserDefaults.standard.string(forKey: DefaultsKey.fanControlDismissedStop) {
            return .dismissed(FanControlStopReason(rawValue: dismissed))
        }
        return UserDefaults.standard.string(forKey: DefaultsKey.fanControlInterruptedStop)
            .flatMap(FanControlInterruption.init(storedStop:))
    }()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "FanControl")
    private let probeQueue = DispatchQueue(label: "com.vorssaint.fan-control.probe",
                                           qos: .utility)
    private var probeHardware: FanControlHardware?
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var panelIsVisible = false
    private var requestInFlight: FanControlRequest?
    private var requestGeneration = 0
    private var tickCount = 0
    private var registrationAttemptedVersion: String?
    private var observingWorkspace = false
    private var resumeAttempt: DispatchWorkItem?
    private var resumeFailures = 0
    private var hadActiveControl = false
    private var recoveryPollInterval = 2

    // Kept until the next accepted Apply. An empty reason means the handoff
    // failed before the helper could report why.
    private var interruptedStop: String? {
        UserDefaults.standard.string(forKey: DefaultsKey.fanControlInterruptedStop)
    }

    // Reconstruct the pending handoff once at launch. A later manual Apply
    // sets the normal recovery marker for its own, separate request.
    @Published private(set) var awaitingSystemControl: Bool = {
        UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
            && UserDefaults.standard.string(forKey: DefaultsKey.fanControlInterruptedStop) != nil
    }()

    private static var appService: SMAppService {
        SMAppService.daemon(plistName: FanControlIdentifiers.plistName)
    }

    private static var helperVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "VorssaintFanControlHelperVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? AppInfo.version
    }

    private init() {
        refreshAccessState()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        connection?.invalidate()
        timer?.invalidate()
    }

    static func recoverIfNeeded() {
        // Re-applying supersedes the recovery: a start that fails restores too.
        if let configuration = resumableConfiguration, shared.beginResume(configuration) { return }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        shared.restoreAutomatic()
    }

    func syncWithPreferences() {
        if awaitingSystemControl { startTimerIfNeeded(); return }
        if AppFeature.fanControl.isAvailable {
            if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
                restoreAutomatic()
            }
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
            cancelResumeRetry()
            restoreThenUnregister()
        }
    }

    func panelDidAppear() {
        panelIsVisible = true
        startObservingSystemState()
        refresh()
        startTimerIfNeeded()
    }

    func panelDidDisappear() {
        panelIsVisible = false
        stopIdleWorkIfPossible()
    }

    func refresh() {
        refreshAccessState()
        if accessState == .enabled {
            guard !replaceRegistrationIfNeeded() else { return }
            requestStatus()
        } else {
            refreshLocalProbe()
        }
    }

    func authorize() {
        refreshAccessState()
        switch accessState {
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        case .enabled:
            requestStatus()
        case .unavailable:
            error = .helperUnavailable
        case .notRegistered:
            isWorking = true
            do {
                try Self.appService.register()
                UserDefaults.standard.set(Self.helperVersion,
                                          forKey: DefaultsKey.fanControlHelperVersion)
                refreshAccessState()
                isWorking = false
                if accessState == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else if accessState == .enabled {
                    requestStatus()
                }
            } catch {
                isWorking = false
                refreshAccessState()
                if accessState == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else {
                    self.error = .helperUnavailable
                }
            }
        }
        startTimerIfNeeded()
    }

    func applyConfiguration(_ configuration: FanControlConfiguration) {
        guard !isWorking, !awaitingSystemControl else { return }
        // The user's own choice replaces any resume still waiting to retry.
        cancelResumeRetry(keepingInterruption: interruptedStop != nil)
        applyConfiguration(configuration, resuming: false)
    }

    private func applyConfiguration(_ configuration: FanControlConfiguration, resuming: Bool) {
        guard FanControlPolicy.validConfiguration(configuration) else {
            error = .controlFailed
            return
        }
        if configuration.mode == .system {
            returnToSystem()
            return
        }
        guard accessState == .enabled else { authorize(); return }
        guard let encodedConfiguration = FanControlIPC.encode(configuration) else {
            error = .controlFailed
            return
        }
        error = nil
        let retrySnapshot = snapshot
        startObservingSystemState()
        let generation = beginRequest(.apply)
        UserDefaults.standard.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)
        isWorking = true
        send({ proxy, reply in
            proxy.applyConfiguration(encodedConfiguration, withReply: reply)
        }) { response in
            guard self.finishRequest(generation, response: response) else { return }
            self.isWorking = false
            guard let response else {
                // The helper may already have applied the setting. Its watchdog
                // owns recovery, including when a different client connects.
                self.observeFailedHandoff(nil)
                return
            }
            self.apply(response, request: .apply)
            if response.succeeded, response.snapshot.isCooling {
                self.hadActiveControl = true
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlInterruptedStop)
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlDismissedStop)
                self.resumeFailures = 0
                self.interruption = nil
                self.rememberForResume(configuration)
                self.startTimerIfNeeded()
            } else {
                self.restoreAutomatic(supersedingCurrentRequest: false,
                                      preserving: response.error ?? .controlFailed,
                                      retrySnapshot: retrySnapshot, resuming: resuming)
                if resuming { self.resumeDidFail(response.error ?? .controlFailed, stopReason: response.snapshot.stopReason) }
            }
        }
    }

    func restoreAutomatic() {
        restoreAutomatic(supersedingCurrentRequest: false)
    }

    func forgetResume() {
        if let reason = snapshot.stopReason {
            dismissStop(reason)
        } else if case .stopped(let reason) = interruption {
            dismissStop(reason)
        } else if interruption == .applyFailed {
            dismissStop(nil)
        }
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        cancelResumeRetry()
    }

    private func dismissStop(_ reason: FanControlStopReason?) {
        interruption = .dismissed(reason)
        UserDefaults.standard.set(reason?.rawValue ?? "", forKey: DefaultsKey.fanControlDismissedStop)
    }

    func returnToSystem() {
        forgetResume()
        restoreAutomatic()
    }

    private func restoreAutomatic(supersedingCurrentRequest: Bool,
                                  preserving failure: FanControlErrorCode? = nil,
                                  retrySnapshot: FanControlSnapshot? = nil,
                                  resuming: Bool = false) {
        if awaitingSystemControl { startTimerIfNeeded(); return }
        guard requestInFlight != .restore, supersedingCurrentRequest || !isWorking else { return }
        if requestInFlight == .apply {
            // Disconnect only our session when sleep or disabling the feature
            // supersedes an Apply whose result is still unknown.
            requestGeneration += 1
            requestInFlight = nil
            observeFailedHandoff(nil)
            connection?.invalidate()
            connection = nil
            return
        }
        refreshAccessState()
        guard accessState == .enabled else { return }
        let generation = beginRequest(.restore)
        isWorking = true
        startTimerIfNeeded()
        send { proxy, reply in proxy.restoreAutomatic(withReply: reply) } completion: { response in
            guard self.finishRequest(generation, response: response) else { return }
            self.isWorking = false
            if self.hadActiveControl, response?.succeeded != true || response?.snapshot.isCooling == true {
                self.observeFailedHandoff(response?.snapshot.stopReason)
            }
            guard let response else { return }
            self.apply(response, request: .restore)
            if response.succeeded, !response.snapshot.isCooling {
                if self.snapshot.fans.isEmpty, let retrySnapshot {
                    self.snapshot.fans = retrySnapshot.fans
                }
                if failure == .controlFailed, !resuming {
                    self.interruption = .applyFailed
                } else if let failure {
                    self.error = failure
                }
                self.finishSystemHandoff()
            }
        }
    }

    private func finishSystemHandoff() {
        awaitingSystemControl = false
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
        if !AppFeature.fanControl.isAvailable {
            do {
                try Self.appService.unregister()
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
                refreshAccessState()
            } catch {
                self.error = .helperUnavailable
            }
        }
        stopIdleWorkIfPossible()
    }

    static func restoreBeforeTerminationIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        shared.restoreBeforeTermination()
    }

    private func restoreBeforeTermination() {
        if requestInFlight == .apply { observeFailedHandoff(nil) }
        // Stop monitoring before intentionally closing our own session.
        timer?.invalidate()
        timer = nil
        requestGeneration += 1
        requestInFlight = nil
        hadActiveControl = false
        if !awaitingSystemControl {
            send { proxy, reply in proxy.restoreAutomatic(withReply: reply) } completion: { response in
                if let response, response.succeeded, !response.snapshot.isCooling {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
                }
            }
        }
        // On disconnect the helper restores only its owning connection's session.
        connection?.invalidate()
        connection = nil
    }

    /// Remember whether the attempted uninstall is removing a registration
    /// that must be restored if the app remains installed.
    static var hasRegisteredHelperForRemoval: Bool {
        switch appService.status {
        case .notRegistered, .notFound: return false
        case .enabled, .requiresApproval: return true
        @unknown default: return true
        }
    }

    /// A failed permission reset leaves the app installed after the helper was
    /// removed. Try to restore its registration and report whether it can run;
    /// macOS may require approval again even when registration succeeds.
    static func restoreRegistrationAfterFailedRemoval() -> Bool {
        let service = appService
        if service.status == .notRegistered || service.status == .notFound {
            try? service.register()
        }
        let status = service.status
        if status == .enabled || status == .requiresApproval {
            UserDefaults.standard.set(helperVersion, forKey: DefaultsKey.fanControlHelperVersion)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
        }
        DispatchQueue.main.async { shared.refresh() }
        return status == .enabled
    }

    /// Used by the complete-uninstall path from its background queue. The
    /// daemon is removed only after it confirms automatic control, so teardown
    /// can never kill the recovery mechanism while a manual session remains.
    ///
    /// Reports whether the daemon is actually gone. A caller that tells someone
    /// the app was fully removed has no other way to know: the registration
    /// outlives the bundle, so a silent failure here reads as success forever.
    @discardableResult
    static func restoreAndUnregisterForRemoval() -> Bool {
        let service = appService
        guard service.status == .enabled else {
            guard service.status != .notRegistered else { return true }
            // A pending recovery keeps the daemon deliberately: it is the only
            // thing that can put the fans back. Still not a clean detach.
            guard !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
            else { return false }
            return unregisterForRemoval(service)
        }
        let connection = NSXPCConnection(machServiceName: FanControlIdentifiers.helperID,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
        connection.setCodeSigningRequirement(FanControlIdentifiers.helperCodeRequirement)
        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var restored = false
        connection.activate()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in semaphore.signal() }
            as? FanControlXPCProtocol
        guard let proxy else {
            connection.invalidate()
            return false
        }
        proxy.restoreAutomatic { data in
            if let response = FanControlIPC.decode(data) {
                resultLock.withLock {
                    restored = response.succeeded && !response.snapshot.isCooling
                }
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 20)
        connection.invalidate()
        guard resultLock.withLock({ restored }) else { return false }
        return unregisterForRemoval(service)
    }

    private static func unregisterForRemoval(_ service: SMAppService) -> Bool {
        do {
            try service.unregister()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Resume

    /// Turning resume on keeps the control already running; turning it off
    /// forgets it, so no later restart brings back an old choice.
    func resumePreferenceDidChange() {
        guard interruptedStop == nil else { return }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlResume) else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
            cancelResumeRetry()
            return
        }
        // Only the control running now is kept, never an older one left
        // behind, for example by a restored backup.
        if snapshot.isCooling, let configuration = snapshot.configuration {
            rememberForResume(configuration)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        }
    }

    /// The manual speed or curve to bring back when the app opens or the Mac
    /// wakes, while resume is on and the user has not returned to System.
    private static var resumableConfiguration: FanControlConfiguration? {
        // Picking System in the card is a return to System too, even when a
        // safety stop had already handed the fans back and left no button.
        guard UserDefaults.standard.string(forKey: DefaultsKey.fanControlInterruptedStop) == nil,
              AppFeature.fanControl.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.fanControlResume),
              UserDefaults.standard.string(forKey: DefaultsKey.fanControlMode)
                != FanControlMode.system.rawValue else { return nil }
        return FanControlConfiguration.decodeResume(
            UserDefaults.standard.string(forKey: DefaultsKey.fanControlResumeConfiguration) ?? "")
    }

    /// A resume never asks for approval or opens System Settings: without an
    /// enabled helper the fans stay with the system until the user acts.
    private func resume(_ configuration: FanControlConfiguration) -> Bool {
        refreshAccessState()
        guard accessState == .enabled, !Self.helperAwaitsRegistration else { return false }
        applyConfiguration(configuration, resuming: true)
        return true
    }

    /// A launch or wake starts over with the full retry budget.
    private func beginResume(_ configuration: FanControlConfiguration) -> Bool {
        cancelResumeRetry()
        guard !isWorking, !FanControlResumePolicy.defersResume(thermalState: ProcessInfo.processInfo.thermalState) else {
            startObservingSystemState()
            scheduleResumeAttempt(after: FanControlResumePolicy.retryDelays[0])
            return true
        }
        return resume(configuration)
    }

    private func cancelResumeRetry(keepingInterruption: Bool = false) {
        cancelResumeAttempt()
        resumeFailures = 0
        if case .dismissed = interruption { return }
        if !keepingInterruption { interruption = nil }
    }

    /// One refused resume used to leave the fans on System for good while the
    /// card still showed the curve, so a hot Mac kept its fans at idle speed.
    private func resumeDidFail(_ failure: FanControlErrorCode, stopReason: FanControlStopReason? = nil) {
        guard Self.resumableConfiguration != nil else { return }
        guard (failure == .controlFailed || failure == .helperUnavailable),
              stopReason != .hardwareChanged, stopReason != .temperatureUnavailable,
              stopReason != .thermalPressure else {
            interruption = .resumeFailed
            return
        }
        Self.log.error("Fan control resume attempt \(self.resumeFailures + 1) failed: \(failure.rawValue, privacy: .public)")
        scheduleResumeRetry()
    }

    private func scheduleResumeRetry() {
        guard let delay = FanControlResumePolicy.retryDelay(afterFailures: resumeFailures) else {
            interruption = .resumeFailed
            Self.log.error("Fan control resume gave up; the fans stay with the system")
            return
        }
        resumeFailures += 1
        scheduleResumeAttempt(after: delay)
    }

    private func retryResume() {
        guard let configuration = Self.resumableConfiguration else { return }
        guard !isWorking,
              !FanControlResumePolicy.defersResume(thermalState: ProcessInfo.processInfo.thermalState) else {
            scheduleResumeAttempt(after: FanControlResumePolicy.retryDelays[0])
            return
        }
        guard !snapshot.isCooling else { return }
        if !resume(configuration) { interruption = .resumeFailed }
    }

    /// Both panel refreshes and heartbeats can be the first to see a stopped session.
    private func applyStatus(_ response: FanControlResponse) {
        let wasControlling = hadActiveControl
        apply(response)
        guard response.succeeded, !response.snapshot.isCooling else { return }
        if awaitingSystemControl {
            // Status confirms automatic control. Its last stop is global to all clients.
            isWorking = false
            finishSystemHandoff()
            return
        }
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
        stopIdleWorkIfPossible()
        guard wasControlling else { return }
        guard Self.resumableConfiguration != nil else {
            interruption = snapshot.stopReason.map(FanControlInterruption.stopped)
            return
        }
        if snapshot.stopReason == .heartbeatLost {
            scheduleResumeRetry()
        } else {
            cancelResumeAttempt()
            interruption = .stopped(snapshot.stopReason)
        }
    }

    private func scheduleResumeAttempt(after delay: TimeInterval) {
        resumeAttempt?.cancel()
        let attempt = DispatchWorkItem { [weak self] in
            self?.resumeAttempt = nil
            self?.retryResume()
        }
        resumeAttempt = attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: attempt)
    }

    private func cancelResumeAttempt() {
        resumeAttempt?.cancel()
        resumeAttempt = nil
    }

    /// An update brought a helper other than the registered one. Kept control
    /// would hold the recovery flag that blocks its registration swap, so a
    /// resume waits for Fan Control to open and register it first.
    private static var helperAwaitsRegistration: Bool {
        let installed = UserDefaults.standard.string(forKey: DefaultsKey.fanControlHelperVersion) ?? ""
        return !installed.isEmpty && installed != helperVersion
    }

    private func rememberForResume(_ configuration: FanControlConfiguration) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlResume),
              let stored = FanControlConfiguration.encodeResume(configuration) else { return }
        UserDefaults.standard.set(stored, forKey: DefaultsKey.fanControlResumeConfiguration)
    }

    // MARK: - Requests

    private func requestStatus() {
        guard requestInFlight == nil else { return }
        let generation = beginRequest()
        send { proxy, reply in proxy.status(withReply: reply) } completion: { response in
            guard self.finishRequest(generation, response: response), let response else { return }
            self.applyStatus(response)
            // Bootstrap unversioned registrations. A compatible reply can also
            // come from an older daemon awaiting replacement after recovery.
            let registered = UserDefaults.standard.string(forKey: DefaultsKey.fanControlHelperVersion) ?? ""
            if registered.isEmpty, AppFeature.fanControl.isAvailable {
                UserDefaults.standard.set(Self.helperVersion, forKey: DefaultsKey.fanControlHelperVersion)
            }
        }
    }

    private func send(_ operation: @escaping (FanControlXPCProtocol, @escaping (Data) -> Void) -> Void,
                      completion: @escaping (FanControlResponse?) -> Void) {
        var finished = false
        let finish: (FanControlResponse?) -> Void = { response in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(response)
            }
        }
        guard let proxy = proxy(errorHandler: { [weak self] failedConnection in
            DispatchQueue.main.async {
                if self?.connection === failedConnection {
                    failedConnection.invalidate()
                    self?.connectionLost(failedConnection)
                }
                finish(nil)
            }
        }) else {
            finish(nil)
            return
        }
        operation(proxy) { data in
            finish(FanControlIPC.decode(data))
        }
    }

    private func proxy(errorHandler: @escaping (NSXPCConnection) -> Void) -> FanControlXPCProtocol? {
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: FanControlIdentifiers.helperID,
                                             options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
            connection.setCodeSigningRequirement(FanControlIdentifiers.helperCodeRequirement)
            connection.interruptionHandler = { [weak self, weak connection] in
                DispatchQueue.main.async {
                    guard let connection, self?.connection === connection else { return }
                    connection.invalidate()
                    self?.connectionLost(connection)
                }
            }
            connection.invalidationHandler = { [weak self, weak connection] in
                DispatchQueue.main.async {
                    guard let connection else { return }
                    self?.connectionLost(connection)
                }
            }
            connection.activate()
            self.connection = connection
        }
        guard let connection else { return nil }
        return connection.remoteObjectProxyWithErrorHandler { _ in errorHandler(connection) }
            as? FanControlXPCProtocol
    }

    private func connectionLost(_ lost: NSXPCConnection) {
        guard connection === lost else { return }
        connection = nil
        let request = requestInFlight
        guard hadActiveControl || request != nil else { return }
        // The helper ties ownership to the connection, even between requests.
        // A replacement can confirm automatic control but cannot identify our stop.
        _ = finishRequest(requestGeneration, response: nil)
        requestGeneration += 1
        if hadActiveControl || request == .apply {
            observeFailedHandoff(nil)
        } else if request == .restore {
            isWorking = false
        }
    }

    private func heartbeat() {
        guard snapshot.isCooling, requestInFlight == nil, !isWorking else { return }
        let generation = beginRequest()
        send { proxy, reply in proxy.heartbeat(withReply: reply) } completion: { response in
            guard self.finishRequest(generation, response: response), let response else { return }
            self.applyStatus(response)
        }
    }

    private func apply(_ response: FanControlResponse, request: FanControlRequest = .read) {
        // An idle helper may have lost its history. Rearm the notice only
        // when a new session or a different reported stop is observed.
        let reason = response.snapshot.stopReason
        if !awaitingSystemControl, response.succeeded, case .dismissed(let dismissed) = interruption {
            if response.snapshot.isCooling || (dismissed != nil && reason != nil && reason != dismissed) {
                if interruptedStop != nil {
                    UserDefaults.standard.set(FanControlInterruption.acknowledgedStop,
                                              forKey: DefaultsKey.fanControlInterruptedStop)
                }
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlDismissedStop)
                interruption = nil
            } else if dismissed == nil, let reason {
                dismissStop(reason)
            }
        }
        // A first Apply can also leave partially changed hardware with the watchdog.
        if !awaitingSystemControl, response.error == .controlFailed, !response.snapshot.isCooling,
           hadActiveControl || (request != .read && reason == .recovery) {
            // A refused first Apply can echo an old .recovery after rolling back.
            let manual = response.snapshot.fans.contains(where: \.isManuallyControlled)
            if hadActiveControl || manual {
                observeFailedHandoff(reason)
            } else {
                observeFailedHandoff(nil, applyFailed: request == .apply)
            }
        }
        if !response.snapshot.isCooling || response.error == .alreadyControlled { hadActiveControl = false }
        snapshot = response.snapshot
        error = response.error
    }

    private func observeFailedHandoff(_ reason: FanControlStopReason?, applyFailed: Bool = false) {
        awaitingSystemControl = true
        interruption = applyFailed ? .applyFailed : .stopped(reason)
        hadActiveControl = false
        let stored = applyFailed ? FanControlInterruption.refusedApply : reason?.rawValue ?? ""
        UserDefaults.standard.set(stored, forKey: DefaultsKey.fanControlInterruptedStop)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlDismissedStop)
        UserDefaults.standard.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        cancelResumeAttempt()
        tickCount = 0
        recoveryPollInterval = 2
        startTimerIfNeeded()
    }

    private func beginRequest(_ request: FanControlRequest = .read) -> Int {
        requestGeneration += 1
        requestInFlight = request
        return requestGeneration
    }

    private func finishRequest(_ generation: Int, response: FanControlResponse?) -> Bool {
        guard generation == requestGeneration else { return false }
        requestInFlight = nil
        if response == nil {
            var last = snapshot
            last.temperatures = nil
            last.gpuPoweredDown = nil
            snapshot = last
            error = .helperUnavailable
        }
        return true
    }

    // MARK: - Registration and local reads

    private func refreshAccessState() {
        switch Self.appService.status {
        case .notRegistered: accessState = .notRegistered
        case .enabled: accessState = .enabled
        case .requiresApproval: accessState = .requiresApproval
        // A bundled daemon can report notFound before its first registration.
        // register() then moves it to the user-approval state.
        case .notFound: accessState = .notRegistered
        @unknown default: accessState = .unavailable
        }
    }

    /// Apple requires a changed embedded daemon to be unregistered before it
    /// is registered again. This runs once per app build and only when the user
    /// opens an already-authorized Fan Control surface.
    private func replaceRegistrationIfNeeded() -> Bool {
        let installed = UserDefaults.standard.string(forKey: DefaultsKey.fanControlHelperVersion) ?? ""
        let current = Self.helperVersion
        guard !installed.isEmpty, installed != current,
              registrationAttemptedVersion != current,
              !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return false }
        registrationAttemptedVersion = current
        isWorking = true
        Self.appService.unregister { error in
            DispatchQueue.main.async {
                guard error == nil else {
                    self.isWorking = false
                    self.error = .helperUnavailable
                    return
                }
                do {
                    try Self.appService.register()
                    UserDefaults.standard.set(current, forKey: DefaultsKey.fanControlHelperVersion)
                    self.isWorking = false
                    self.refreshAccessState()
                    if self.accessState == .enabled { self.requestStatus() }
                } catch {
                    self.isWorking = false
                    self.refreshAccessState()
                    self.error = .helperUnavailable
                }
            }
        }
        return true
    }

    private func refreshLocalProbe() {
        probeQueue.async {
            if self.probeHardware == nil { self.probeHardware = FanControlHardware() }
            let result: Result<FanControlSnapshot, FanControlErrorCode>
            guard let probe = self.probeHardware else {
                result = .failure(.unsupportedHardware)
                DispatchQueue.main.async { self.applyProbe(result) }
                return
            }
            do {
                result = .success(try probe.readOnlySnapshot())
            } catch FanControlHardwareError.noFans {
                result = .failure(.noFans)
            } catch FanControlHardwareError.alreadyControlled {
                if let snapshot = try? probe.telemetrySnapshot() {
                    DispatchQueue.main.async {
                        self.applyProbeSnapshot(snapshot, error: .alreadyControlled)
                    }
                    return
                }
                result = .failure(.alreadyControlled)
            } catch {
                if let snapshot = try? probe.telemetrySnapshot() {
                    DispatchQueue.main.async {
                        self.applyProbeSnapshot(snapshot, error: .unsupportedHardware)
                    }
                    return
                }
                result = .failure(.unsupportedHardware)
            }
            DispatchQueue.main.async { self.applyProbe(result) }
        }
    }

    private func applyProbe(_ result: Result<FanControlSnapshot, FanControlErrorCode>) {
        guard accessState != .enabled else { return }
        switch result {
        case .success(let snapshot):
            applyProbeSnapshot(snapshot,
                               error: snapshot.fans.contains(where: \.isManuallyControlled)
                                   ? .alreadyControlled : nil)
        case .failure(let error):
            snapshot = .empty
            self.error = error
        }
    }

    private func applyProbeSnapshot(_ snapshot: FanControlSnapshot,
                                    error: FanControlErrorCode?) {
        guard accessState != .enabled else { return }
        self.snapshot = snapshot
        self.error = error
    }

    private func restoreThenUnregister() {
        refreshAccessState()
        guard accessState != .notRegistered else { return }
        if accessState != .enabled {
            guard !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else {
                error = .authorizationRequired
                return
            }
            do {
                try Self.appService.unregister()
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
                refreshAccessState()
            } catch {
                self.error = .helperUnavailable
            }
            return
        }
        restoreAutomatic(supersedingCurrentRequest: true)
    }

    // MARK: - Timers and system state

    private func startTimerIfNeeded() {
        guard panelIsVisible || snapshot.isCooling
                || UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        startObservingSystemState()
        if awaitingSystemControl { isWorking = true }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // The helper drops cooling once a heartbeat is `heartbeatLimit` seconds
        // old, so a second's cadence has six to spare; matching the leeway the
        // helper's own watchdog already takes lets these wakes coalesce with
        // everything else on the run loop instead of standing alone.
        timer?.tolerance = 0.1
    }

    private func poll() {
        tickCount += 1
        if awaitingSystemControl {
            guard requestInFlight == nil, tickCount.isMultiple(of: recoveryPollInterval) else { return }
            refreshAccessState()
            if accessState == .enabled { requestStatus() }
            recoveryPollInterval = min(recoveryPollInterval * 2, 60)
        } else if snapshot.isCooling {
            heartbeat()
        } else if panelIsVisible, error != .controlFailed, tickCount.isMultiple(of: 2) {
            refresh()
        }
    }

    private func stopIdleWorkIfPossible() {
        guard !panelIsVisible, !snapshot.isCooling,
              !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        timer?.invalidate()
        timer = nil
        connection?.invalidate()
        connection = nil
        // A resume waits for the next wake, which only these observers see.
        guard Self.resumableConfiguration == nil else { return }
        stopObservingSystemState()
    }

    private func startObservingSystemState() {
        guard !observingWorkspace else { return }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(workspaceWillSleep),
                           name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(workspaceDidWake),
                           name: NSWorkspace.didWakeNotification, object: nil)
        observingWorkspace = true
    }

    private func stopObservingSystemState() {
        guard observingWorkspace else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        observingWorkspace = false
    }

    @objc private func workspaceWillSleep() {
        // A retry must not re-apply control on the way into sleep; the wake
        // starts a fresh resume.
        cancelResumeAttempt()
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            restoreAutomatic(supersedingCurrentRequest: true)
        }
    }

    @objc private func workspaceDidWake() {
        if let configuration = Self.resumableConfiguration, beginResume(configuration) { return }
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            restoreAutomatic(supersedingCurrentRequest: true)
        } else if panelIsVisible {
            refresh()
        }
    }
}
