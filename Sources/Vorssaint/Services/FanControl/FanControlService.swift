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
    // Only an accepted Apply on this connection establishes ownership.
    private var supportsOwnedRestore: Bool?
    private var activeConfiguration: FanControlConfiguration?
    private var workspaceIsSleeping = false
    private var hadActiveControl: Bool {
        supportsOwnedRestore != nil
    }
    private var recoveryPollInterval = 2
    private var checkingUnregister = false

    // Kept until the next accepted Apply. An empty reason means the client
    // could not identify why its own control ended.
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
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlUnregisterPending) {
            if !AppFeature.fanControl.isAvailable {
                shared.checkingUnregister = true
                if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded), shared.interruptedStop == nil {
                    shared.observeFailedHandoff(nil)
                }
                shared.startTimerIfNeeded()
                shared.restoreThenUnregister()
                return
            }
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlUnregisterPending)
        }
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            // A previous process cannot own this connection. Observe its helper's recovery.
            if shared.awaitingSystemControl { shared.startTimerIfNeeded() }
            else { shared.observeFailedHandoff(nil) }
        } else if let configuration = resumableConfiguration {
            _ = shared.beginResume(configuration)
        } else if let stored = UserDefaults.standard.string(forKey: DefaultsKey.fanControlResumeConfiguration),
                  !stored.isEmpty, FanControlConfiguration.decodeResume(stored) == nil {
            // Older builds saved an active curve before receiving a release acknowledgement.
            shared.recordInterruption(nil)
        }
    }

    func syncWithPreferences() {
        let available = AppFeature.fanControl.isAvailable
        if available, UserDefaults.standard.bool(forKey: DefaultsKey.fanControlUnregisterPending) {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlUnregisterPending)
            if checkingUnregister {
                cancelUnregisterCheck()
                return
            }
        }
        if awaitingSystemControl || checkingUnregister { startTimerIfNeeded(); return }
        // The Hub also syncs features that stayed installed in a preset.
        guard !available else { return }
        // A sleep release may still be waiting for its reply.
        activeConfiguration = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        cancelResumeRetry()
        restoreThenUnregister()
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
        guard !checkingUnregister, requestInFlight != .replaceRegistration else { return }
        refreshAccessState()
        if accessState == .enabled {
            requestStatus(checkRegistration: true)
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
        if !resuming {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        }
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
            if response.error == .controlFailed, !response.snapshot.isCooling,
               self.hadActiveControl || response.localStopReason != nil || (resuming && response.retryableApply != true) {
                // An automatic retry requires evidence from this Apply, including
                // when an older helper cannot say whether it rolled the write back.
                self.observeFailedHandoff(response.localStopReason, applyFailed: response.localStopReason == nil)
            }
            self.apply(response)
            if response.succeeded, response.snapshot.isCooling {
                self.supportsOwnedRestore = response.supportsOwnedRestore == true
                self.activeConfiguration = configuration
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlInterruptedStop)
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlDismissedStop)
                self.resumeFailures = 0
                self.interruption = nil
                if resuming, self.supportsOwnedRestore != true {
                    self.disconnectForRecovery()
                } else {
                    self.startTimerIfNeeded()
                }
            } else if response.error == .alreadyControlled {
                self.observeFailedHandoff(nil)
            } else {
                self.restoreAutomatic(supersedingCurrentRequest: false,
                                      preserving: response,
                                      retrySnapshot: retrySnapshot, resuming: resuming)
            }
        }
    }

    func forgetResume() {
        activeConfiguration = nil
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
        restoreAutomatic(supersedingCurrentRequest: false, explicit: true)
    }

    private func restoreAutomatic(supersedingCurrentRequest: Bool,
                                  explicit: Bool = false, resumeAfterRelease: Bool = false,
                                  preserving refusal: FanControlResponse? = nil,
                                  retrySnapshot: FanControlSnapshot? = nil,
                                  resuming: Bool = false) {
        if awaitingSystemControl { startTimerIfNeeded(); return }
        guard requestInFlight != .restore, supersedingCurrentRequest || !isWorking else { return }
        if requestInFlight == .apply || (!explicit && hadActiveControl && supportsOwnedRestore != true) {
            disconnectForRecovery()
            return
        }
        refreshAccessState()
        guard accessState == .enabled else {
            if hadActiveControl { disconnectForRecovery() }
            return
        }
        let owned = !explicit && supportsOwnedRestore == true && connection != nil
        let generation = beginRequest(.restore)
        isWorking = true
        startTimerIfNeeded()
        send { proxy, reply in
            if explicit { proxy.restoreAutomatic(withReply: reply) }
            else if owned { proxy.restoreOwnedControl(withReply: reply) }
            else { proxy.status(withReply: reply) }
        } completion: { response in
            guard self.finishRequest(generation, response: response) else { return }
            self.isWorking = false
            let configuration = self.activeConfiguration
            let failure = refusal.map { $0.error ?? .controlFailed }
            guard let response, response.succeeded, !response.snapshot.isCooling else {
                if let response { self.apply(response) }
                if !self.awaitingSystemControl {
                    let applyFailed = refusal != nil && (refusal?.retryableApply == true || self.interruptedStop == nil)
                    self.observeFailedHandoff(nil, applyFailed: applyFailed)
                }
                return
            }
            self.apply(response)
            if owned, resumeAfterRelease, let configuration {
                self.rememberForResume(configuration)
            }
            if self.snapshot.fans.isEmpty, let retrySnapshot {
                self.snapshot.fans = retrySnapshot.fans
            }
            if failure == .controlFailed, !resuming {
                self.interruption = .applyFailed
            } else if let failure {
                self.error = failure
            }
            self.finishSystemHandoff()
            guard !self.workspaceIsSleeping else { return }
            if resuming, let refusal {
                self.resumeDidFail(refusal)
            } else if resumeAfterRelease, let configuration = Self.resumableConfiguration {
                _ = self.beginResume(configuration)
            }
        }
    }

    private func disconnectForRecovery() {
        requestGeneration += 1
        requestInFlight = nil
        observeFailedHandoff(nil)
        connection?.invalidate()
        connection = nil
    }

    private func finishSystemHandoff() {
        awaitingSystemControl = false
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
        if !AppFeature.fanControl.isAvailable {
            // Releasing our session does not reserve the idle daemon for removal.
            restoreThenUnregister()
            return
        }
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlUnregisterPending)
        stopIdleWorkIfPossible()
    }

    static func restoreBeforeTerminationIfNeeded() {
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlUnregisterPending) {
            shared.releaseUnregisterConnection()
            shared.timer?.invalidate()
            shared.timer = nil
            return
        }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        shared.restoreBeforeTermination()
    }

    private func restoreBeforeTermination() {
        let canRelease = supportsOwnedRestore == true && !awaitingSystemControl
            && requestInFlight != .apply && requestInFlight != .restore
        let configuration = activeConfiguration
        timer?.invalidate()
        timer = nil
        requestGeneration += 1
        requestInFlight = nil
        // Persist uncertainty before sending. A later process can observe system
        // control, but only this process may consume this connection's release ACK.
        if !awaitingSystemControl { recordInterruption(nil) }
        if canRelease, let response = restoreOwnedBeforeExit(), response.succeeded, !response.snapshot.isCooling {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlInterruptedStop)
            if let configuration { rememberForResume(configuration) }
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
        }
        connection?.invalidate()
        connection = nil
    }

    private func restoreOwnedBeforeExit() -> FanControlResponse? {
        guard let connection else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var reply: FanControlResponse?
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in semaphore.signal() })
            as? FanControlXPCProtocol else { return nil }
        proxy.restoreOwnedControl { data in
            lock.withLock { reply = FanControlIPC.decode(data) }
            semaphore.signal()
        }
        // XPC delivers this reply off the main queue. Never hold up quit for
        // an unavailable helper or let a late callback change preferences.
        guard semaphore.wait(timeout: .now() + 1) == .success else { return nil }
        return lock.withLock { reply }
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

    func resumePreferenceDidChange() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        cancelResumeRetry(keepingInterruption: interruptedStop != nil)
    }

    /// The manual speed or curve to bring back when the app opens or the Mac
    /// wakes, while resume is on and the user has not returned to System.
    private static var resumableConfiguration: FanControlConfiguration? {
        // Picking System in the card is a return to System too, even when a
        // safety stop had already handed the fans back and left no button.
        guard !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
              UserDefaults.standard.string(forKey: DefaultsKey.fanControlInterruptedStop) == nil,
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
    private func resumeDidFail(_ refusal: FanControlResponse) {
        guard Self.resumableConfiguration != nil else { return }
        guard refusal.retryableApply == true, refusal.error == .controlFailed, refusal.localStopReason == nil else {
            interruption = .resumeFailed
            return
        }
        Self.log.error("Fan control resume attempt \(self.resumeFailures + 1) failed after a retryable refusal")
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
        guard !workspaceIsSleeping, let configuration = Self.resumableConfiguration else { return }
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
        if hadActiveControl, !response.snapshot.isCooling || response.error == .alreadyControlled {
            // Even on the same connection, an idle heartbeat returns global
            // status. Another client may have started and stopped between reads.
            if response.succeeded {
                recordInterruption(nil)
            } else {
                observeFailedHandoff(nil)
            }
        }
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
        guard AppFeature.fanControl.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.fanControlResume),
              UserDefaults.standard.string(forKey: DefaultsKey.fanControlMode) != FanControlMode.system.rawValue,
              let stored = FanControlConfiguration.encodeResume(configuration) else { return }
        UserDefaults.standard.set(stored, forKey: DefaultsKey.fanControlResumeConfiguration)
    }

    // MARK: - Requests

    private func requestStatus(checkRegistration: Bool = false) {
        guard accessState == .enabled, requestInFlight == nil else { return }
        let generation = beginRequest()
        send { proxy, reply in proxy.status(withReply: reply) } completion: { response in
            guard self.finishRequest(generation, response: response) else { return }
            if !AppFeature.fanControl.isAvailable || self.checkingUnregister {
                if self.hadActiveControl { self.restoreThenUnregister() }
                else { self.checkUnregisterStatus(response) }
                return
            }
            guard let response else { return }
            self.applyStatus(response)
            // Bootstrap unversioned registrations. A compatible reply can also
            // come from an older daemon awaiting replacement after recovery.
            let registered = UserDefaults.standard.string(forKey: DefaultsKey.fanControlHelperVersion) ?? ""
            if registered.isEmpty, AppFeature.fanControl.isAvailable {
                UserDefaults.standard.set(Self.helperVersion, forKey: DefaultsKey.fanControlHelperVersion)
            } else if checkRegistration {
                self.replaceRegistrationIfNeeded(after: response)
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
        if checkingUnregister { startTimerIfNeeded(); return }
        if request == .prepareUnregister { isWorking = false; return }
        if hadActiveControl || request == .apply || request == .restore {
            observeFailedHandoff(nil)
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

    private func apply(_ response: FanControlResponse) {
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
        if !response.snapshot.isCooling || response.error == .alreadyControlled {
            supportsOwnedRestore = nil
            activeConfiguration = nil
        }
        snapshot = response.snapshot
        error = response.error
    }

    private func recordInterruption(_ reason: FanControlStopReason?, applyFailed: Bool = false) {
        interruption = applyFailed ? .applyFailed : .stopped(reason)
        supportsOwnedRestore = nil
        activeConfiguration = nil
        let stored = applyFailed ? FanControlInterruption.refusedApply : reason.map { "local." + $0.rawValue } ?? ""
        UserDefaults.standard.set(stored, forKey: DefaultsKey.fanControlInterruptedStop)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlDismissedStop)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        cancelResumeAttempt()
    }

    private func observeFailedHandoff(_ reason: FanControlStopReason?, applyFailed: Bool = false) {
        recordInterruption(reason, applyFailed: applyFailed)
        awaitingSystemControl = true
        UserDefaults.standard.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)
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

    /// A compatible older daemon can still serve the panel. Replace it only
    /// when the running daemon can reserve itself against another client's Apply.
    private func replaceRegistrationIfNeeded(after response: FanControlResponse) {
        let current = Self.helperVersion
        guard panelIsVisible, Self.helperAwaitsRegistration, registrationAttemptedVersion != current,
              response.supportsUnregisterPreparation == true, !response.snapshot.isCooling,
              !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        prepareForUnregister { reserved in
            if self.checkingUnregister {
                if reserved { self.finishUnregisterCheck(reserved: true) }
                else { self.startTimerIfNeeded() }
                return
            }
            guard reserved else { return }
            guard self.panelIsVisible, AppFeature.fanControl.isAvailable,
                  let reservation = self.connection else {
                self.releaseUnregisterConnection()
                return
            }
            self.replaceReservedRegistration(using: reservation)
        }
    }

    private func replaceReservedRegistration(using reservation: NSXPCConnection) {
        let current = Self.helperVersion
        registrationAttemptedVersion = current
        // The reservation must outlive the panel and all its requests until
        // Service Management finishes terminating the old daemon.
        connection = nil
        let generation = beginRequest(.replaceRegistration)
        isWorking = true
        Self.appService.unregister { error in
            DispatchQueue.main.async {
                reservation.invalidate()
                guard generation == self.requestGeneration else { return }
                self.requestInFlight = nil
                self.isWorking = false
                if error == nil {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
                }
                self.refreshAccessState()
                guard AppFeature.fanControl.isAvailable else {
                    self.restoreThenUnregister()
                    return
                }
                guard error == nil else { self.error = .helperUnavailable; return }
                do {
                    try Self.appService.register()
                    UserDefaults.standard.set(current, forKey: DefaultsKey.fanControlHelperVersion)
                    self.refreshAccessState()
                    if self.panelIsVisible, self.accessState == .enabled { self.requestStatus() }
                } catch {
                    self.refreshAccessState()
                    self.error = .helperUnavailable
                }
            }
        }
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
        UserDefaults.standard.set(true, forKey: DefaultsKey.fanControlUnregisterPending)
        guard requestInFlight != .replaceRegistration else { return }
        refreshAccessState()
        guard accessState != .notRegistered else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
            finishUnregisterCheck(reserved: false, controlConfirmed: false)
            return
        }
        if accessState != .enabled {
            if hadActiveControl || requestInFlight == .apply { disconnectForRecovery() }
            error = accessState == .requiresApproval ? .authorizationRequired : .helperUnavailable
            if checkingUnregister || UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
                checkingUnregister = true
                startTimerIfNeeded()
            } else {
                finishUnregisterCheck(reserved: false, controlConfirmed: false)
            }
            return
        }
        if hadActiveControl || requestInFlight == .apply {
            restoreAutomatic(supersedingCurrentRequest: true)
        } else {
            // Keep this wait across a lost first status reply or process exit.
            checkingUnregister = true
            startTimerIfNeeded()
            requestStatus()
        }
    }

    private func checkUnregisterStatus(_ response: FanControlResponse?) {
        checkingUnregister = true
        UserDefaults.standard.set(true, forKey: DefaultsKey.fanControlUnregisterPending)
        guard let response else {
            startTimerIfNeeded()
            return
        }
        apply(response)
        guard response.supportsUnregisterPreparation == true else {
            // Legacy helpers have no atomic way to deny a new Apply before
            // removal. Only an outstanding control recovery still needs observation.
            let idle = !response.snapshot.isCooling && (response.succeeded || response.error == .noFans
                                                        || response.error == .unsupportedHardware)
            if idle || !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
                finishUnregisterCheck(reserved: false, controlConfirmed: idle)
            } else {
                startTimerIfNeeded()
            }
            return
        }
        guard !response.snapshot.isCooling else { startTimerIfNeeded(); return }
        prepareForUnregister { reserved in
            if reserved { self.finishUnregisterCheck(reserved: true) }
            else { self.startTimerIfNeeded() }
        }
    }

    private func prepareForUnregister(_ completion: @escaping (Bool) -> Void) {
        let generation = beginRequest(.prepareUnregister)
        isWorking = true
        send { proxy, reply in proxy.prepareForUnregister(withReply: reply) } completion: { response in
            guard self.finishRequest(generation, response: response) else { return }
            self.isWorking = false
            let reserved = response?.succeeded == true && response?.snapshot.isCooling == false
            if reserved { self.refreshAccessState() }
            // Approval can change while the ACK is in flight. A lost ACK may
            // also leave a reservation behind.
            if response == nil || (reserved && self.accessState != .enabled) {
                self.connection?.invalidate()
                self.connection = nil
                completion(false)
                return
            }
            completion(reserved)
        }
    }

    private func releaseUnregisterConnection() {
        requestGeneration += 1
        requestInFlight = nil
        checkingUnregister = false
        let releasedConnection = connection
        connection = nil
        releasedConnection?.invalidate()
    }

    private func cancelUnregisterCheck() {
        releaseUnregisterConnection()
        isWorking = awaitingSystemControl
        if awaitingSystemControl { startTimerIfNeeded() }
        else if !panelIsVisible {
            timer?.invalidate()
            timer = nil
            stopObservingSystemState()
        }
    }

    private func finishUnregisterCheck(reserved: Bool, controlConfirmed: Bool = true) {
        let disabled = !AppFeature.fanControl.isAvailable
        if controlConfirmed {
            awaitingSystemControl = false
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
        } else if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            if interruptedStop == nil { recordInterruption(nil) }
            awaitingSystemControl = true
        }
        if disabled, reserved {
            do {
                try Self.appService.unregister()
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
                refreshAccessState()
            } catch {
                self.error = .helperUnavailable
                // Release the reservation during backoff. Each retry must
                // establish that the daemon is still idle on a new connection.
                releaseUnregisterConnection()
                checkingUnregister = true
                startTimerIfNeeded()
                return
            }
        }
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlUnregisterPending)
        releaseUnregisterConnection()
        isWorking = false
        if disabled {
            timer?.invalidate()
            timer = nil
            stopObservingSystemState()
        } else {
            stopIdleWorkIfPossible()
        }
    }

    // MARK: - Timers and system state

    private func startTimerIfNeeded() {
        guard panelIsVisible || snapshot.isCooling || checkingUnregister
                || UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        startObservingSystemState()
        if awaitingSystemControl || checkingUnregister { isWorking = true }
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
        if awaitingSystemControl || checkingUnregister {
            guard requestInFlight == nil, tickCount.isMultiple(of: recoveryPollInterval) else { return }
            refreshAccessState()
            if accessState == .enabled { requestStatus() }
            else if accessState == .notRegistered, !AppFeature.fanControl.isAvailable {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
                finishUnregisterCheck(reserved: false, controlConfirmed: false)
            } else if !checkingUnregister, !AppFeature.fanControl.isAvailable,
                      !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
                finishUnregisterCheck(reserved: false, controlConfirmed: false)
            }
            recoveryPollInterval = min(recoveryPollInterval * 2, 60)
        } else if snapshot.isCooling {
            heartbeat()
        } else if panelIsVisible, error != .controlFailed, tickCount.isMultiple(of: 2) {
            refresh()
        }
    }

    private func stopIdleWorkIfPossible() {
        guard !checkingUnregister, !panelIsVisible, !snapshot.isCooling,
              !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        if requestInFlight == .prepareUnregister {
            releaseUnregisterConnection()
            isWorking = false
        }
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
        workspaceIsSleeping = false
    }

    @objc private func workspaceWillSleep() {
        // A retry must not re-apply control on the way into sleep; the wake
        // starts a fresh resume.
        cancelResumeAttempt()
        workspaceIsSleeping = true
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            restoreAutomatic(supersedingCurrentRequest: true, resumeAfterRelease: true)
        }
    }

    @objc private func workspaceDidWake() {
        guard workspaceIsSleeping else { return }
        workspaceIsSleeping = false
        guard !hadActiveControl, requestInFlight != .apply, requestInFlight != .restore else { return }
        if let configuration = Self.resumableConfiguration, beginResume(configuration) { return }
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            restoreAutomatic(supersedingCurrentRequest: true)
        } else if panelIsVisible {
            refresh()
        }
    }
}
