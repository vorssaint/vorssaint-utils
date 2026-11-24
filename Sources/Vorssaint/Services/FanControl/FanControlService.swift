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
    /// Every retry of a kept control failed, so the fans stayed with the
    /// system even though the card still shows the chosen manual speed or curve.
    @Published private(set) var resumeFailed = false

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "FanControl")
    private let probeQueue = DispatchQueue(label: "com.vorssaint.fan-control.probe",
                                           qos: .utility)
    private var probeHardware: FanControlHardware?
    private var connection: NSXPCConnection?
    // The helper grants control to the connection that applied the configuration.
    // Status describes the fans for all clients, including after a reconnect.
    private var ownedSession: (connection: NSXPCConnection, configuration: FanControlConfiguration,
                               supportsSessionRelease: Bool)?
    private var ownsSession: Bool {
        guard let ownedSession, ownedSession.connection === connection, snapshot.isCooling else { return false }
        // Older helpers can omit the configuration from a status reply.
        return snapshot.configuration == nil || snapshot.configuration == ownedSession.configuration
    }
    private var timer: Timer?
    private var panelIsVisible = false
    private var requestInFlight = false
    private var requestGeneration = 0
    private var tickCount = 0
    private var registrationAttemptedVersion: String?
    private var observingWorkspace = false
    private var resumeAttempt: DispatchWorkItem?
    private var resumeFailures = 0

    private enum PendingApply {
        case keepRunning, restoreForSleep, returnToSystem
    }
    private var pendingApply: PendingApply?

    private enum StopConfirmation: Equatable {
        enum RecoveryPhase: Equatable {
            case checkingAtLaunch, recoveringAtLaunch, beforeRetry

            func allowsResume(after reason: FanControlStopReason?) -> Bool {
                reason == .appDisconnected || reason == .heartbeatLost || (self == .checkingAtLaunch && reason == nil)
            }
        }
        case resumeAfterHeartbeatLoss, resumeAfterSleep, keepSystem, otherController
        case previousSession(RecoveryPhase)

        func allowsSessionResume(_ response: FanControlResponse, isReleaseReply: Bool) -> Bool {
            if let receipt = response.sessionStop {
                guard !response.succeeded || receipt.restored else { return false }
                return allowsResume(after: receipt.reason, confirmedRelease: true)
            }
            // A previous helper can acknowledge its owner-scoped release directly.
            // Its ordinary status and heartbeat replies describe all clients.
            guard response.isRecovering == nil, isReleaseReply else { return false }
            return allowsResume(after: response.snapshot.stopReason, confirmedRelease: response.succeeded)
        }

        func allowsResume(after reason: FanControlStopReason?, confirmedRelease: Bool = false) -> Bool {
            switch self {
            case .resumeAfterHeartbeatLoss: return reason == .heartbeatLost
            case .resumeAfterSleep: return (reason == nil && confirmedRelease) || reason == .heartbeatLost
            case .keepSystem, .otherController, .previousSession: return false
            }
        }
    }
    private var pendingStop: StopConfirmation?
    private var isSleeping = false
    // A new accepted configuration can clear a safety veto. Another wake cannot.
    private var resumeBlocked = false
    private var unregisterAfterRestore = false

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
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            // A previous process may still be handing the fans back. A new
            // connection can check automatic mode before attempting any apply.
            if resumableConfiguration != nil {
                shared.pendingStop = .previousSession(.checkingAtLaunch)
                shared.checkLaunchRecovery()
            } else {
                shared.restoreAutomatic()
            }
        } else if let configuration = resumableConfiguration {
            _ = shared.beginResume(configuration)
        }
    }

    private func checkLaunchRecovery() {
        startObservingSystemState()
        refreshAccessState()
        guard accessState == .enabled else { return }
        startTimerIfNeeded()
        requestStatus()
    }

    func syncWithPreferences() {
        if AppFeature.fanControl.isAvailable {
            unregisterAfterRestore = false
            // The launch binding also runs after recoverIfNeeded starts the
            // saved configuration. Its recovery marker belongs to that apply.
            if pendingApply == nil, !ownsSession, pendingStop == nil,
               UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
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
        // The user's own choice replaces any resume still waiting to retry.
        cancelResumeRetry()
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
        guard pendingApply == nil else { return }
        guard accessState == .enabled else { authorize(); return }
        guard let encodedConfiguration = FanControlIPC.encode(configuration) else {
            error = .controlFailed
            return
        }
        error = nil
        let retrySnapshot = snapshot
        startObservingSystemState()
        let generation = beginRequest()
        let neededRecovery = UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
        UserDefaults.standard.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)
        pendingApply = .keepRunning
        isWorking = true
        send({ proxy, reply in
            proxy.applyConfiguration(encodedConfiguration, withReply: reply)
        }) { response, issuingConnection in
            guard self.finishRequest(generation, response: response), let action = self.pendingApply else { return }
            self.pendingApply = nil
            self.isWorking = false
            guard let response else {
                if action != .keepRunning, let issuingConnection {
                    self.disconnectSession(on: issuingConnection)
                } else {
                    self.restoreAutomatic()
                }
                if resuming, action == .keepRunning { self.resumeDidFail(.helperUnavailable) }
                return
            }
            if response.error == .alreadyControlled {
                // Another owner can acquire the fans between the status
                // confirmation and this write. The refusal made no changes.
                if !neededRecovery {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
                }
                self.applySessionResponse(response, observed: .keepSystem)
                return
            }
            if response.succeeded, response.snapshot.isCooling, let issuingConnection {
                self.apply(response)
                self.ownedSession = (issuingConnection, configuration, response.supportsSessionRelease == true)
                if self.ownsSession {
                    self.resumeBlocked = false
                    self.resumeFailures = 0
                    self.resumeFailed = false
                    if action != .returnToSystem { self.rememberForResume(configuration) }
                }
                if action == .keepRunning {
                    self.startTimerIfNeeded()
                } else if self.ownsSession {
                    self.restoreAutomatic(supersedingCurrentRequest: false, forSleep: action == .restoreForSleep)
                } else {
                    self.disconnectSession(on: issuingConnection)
                }
            } else {
                // An apply can be the first reply to report the watchdog's stop.
                // Consume its cause before a later idle read can replace it.
                let rejectedDuringRecovery = resuming && action == .keepRunning && !self.ownsSession
                    && response.error == .controlFailed && response.isRecovering == true
                if action != .keepRunning {
                    self.pendingStop = .keepSystem
                    self.blockResumeAfterStop()
                } else if rejectedDuringRecovery {
                    self.pendingStop = .previousSession(.beforeRetry)
                }
                let observedStop = self.ownsSession && self.connection === issuingConnection
                self.applySessionResponse(response, observed: observedStop ? .resumeAfterHeartbeatLoss : nil)
                self.restoreAutomatic(supersedingCurrentRequest: false,
                                      preserving: response.error ?? .controlFailed,
                                      retrySnapshot: retrySnapshot)
                if resuming, action == .keepRunning, !rejectedDuringRecovery, !self.resumeBlocked, self.pendingStop == nil {
                    self.resumeDidFail(response.error ?? .controlFailed,
                                       stopReason: observedStop ? response.sessionStop?.reason : nil)
                }
            }
        }
    }

    private func disconnectSession(on issuingConnection: NSXPCConnection) {
        // Older helpers still release by owner ID on disconnect. A new
        // connection can confirm automatic mode, but cannot claim that stop.
        pendingStop = .keepSystem
        issuingConnection.invalidate()
        if connection === issuingConnection { connection = nil }
        ownedSession = nil
        startTimerIfNeeded()
    }

    func restoreAutomatic() {
        restoreAutomatic(supersedingCurrentRequest: false)
    }

    func forgetResume() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        cancelResumeRetry()
    }

    func returnToSystem() {
        forgetResume()
        if pendingStop != nil, pendingStop != .otherController { pendingStop = .keepSystem }
        restoreAutomatic()
    }

    private func restoreAutomatic(supersedingCurrentRequest: Bool,
                                  preserving failure: FanControlErrorCode? = nil,
                                  retrySnapshot: FanControlSnapshot? = nil,
                                  forSleep: Bool = false) {
        // The apply reply identifies the owner. A status request here would
        // supersede that reply and could only show that some client is cooling.
        if pendingApply != nil {
            if !AppFeature.fanControl.isAvailable { unregisterAfterRestore = true }
            if pendingApply != .returnToSystem {
                pendingApply = forSleep ? .restoreForSleep : .returnToSystem
            }
            return
        }
        // A previous session has no control for this connection to release.
        // Preserve its first status reply across a sleep and wake.
        if forSleep, case .previousSession? = pendingStop { return }
        let requestedStop: StopConfirmation = forSleep ? .resumeAfterSleep : .keepSystem
        if !AppFeature.fanControl.isAvailable {
            unregisterAfterRestore = true
        }
        if pendingStop == .otherController {
            startTimerIfNeeded()
            return
        }
        if unregisterAfterRestore { pendingStop = .keepSystem }
        // A second notification can change the intent, but the first release
        // reply may be the only proof of an orderly return to automatic.
        if isWorking && requestInFlight { return }
        guard supersedingCurrentRequest || !isWorking else { return }
        let canRestore = ownsSession
        refreshAccessState()
        guard ownedSession != nil || accessState == .enabled else { return }
        if let session = ownedSession {
            if !canRestore || !session.supportsSessionRelease {
                disconnectSession(on: session.connection)
                return
            }
            if pendingStop == nil { pendingStop = requestedStop }
        }
        let generation = beginRequest()
        isWorking = true
        startTimerIfNeeded()
        // A persisted marker can outlive its client. The helper's status path
        // recovers abandoned control without restoring another live session.
        send { proxy, reply in
            if canRestore {
                proxy.releaseControl(withReply: reply)
            } else {
                proxy.status(withReply: reply)
            }
        } completion: { response, issuingConnection in
            guard self.finishRequest(generation, response: response) else { return }
            self.isWorking = false
            if canRestore, let issuingConnection, response == nil || self.connection !== issuingConnection {
                self.disconnectSession(on: issuingConnection)
                return
            }
            guard self.connection === issuingConnection, let response else { return }
            self.applySessionResponse(response, observed: canRestore ? requestedStop : nil,
                                      isReleaseReply: canRestore)
            if response.succeeded, !response.snapshot.isCooling {
                if self.snapshot.fans.isEmpty, let retrySnapshot {
                    self.snapshot.fans = retrySnapshot.fans
                }
                if let failure, self.error == nil { self.error = failure }
            }
        }
    }

    static func restoreBeforeTerminationIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded),
              shared.ownsSession else { return }
        shared.restoreBeforeTermination()
    }

    private func restoreBeforeTermination() {
        // Exit cannot wait for an acknowledgement. All supported helpers
        // release this connection only if it still owns the fans.
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
        requestRemovalRestore(using: proxy) { confirmed in
            resultLock.withLock { restored = confirmed }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 20)
        connection.invalidate()
        guard resultLock.withLock({ restored }) else { return false }
        return unregisterForRemoval(service)
    }

    // Full uninstall is the one operation that must stop the daemon even if a
    // different connection owns it. Negotiate on this live connection so an
    // older installed helper can still complete its original removal protocol.
    private static func requestRemovalRestore(using proxy: FanControlXPCProtocol, completion: @escaping (Bool) -> Void) {
        proxy.status { data in
            guard let status = FanControlIPC.decode(data) else { completion(false); return }
            let confirm: (Data) -> Void = { data in
                guard let response = FanControlIPC.decode(data) else { completion(false); return }
                completion(response.succeeded && !response.snapshot.isCooling)
            }
            if status.supportsSessionRelease == true {
                proxy.restoreForRemoval(withReply: confirm)
            } else {
                proxy.restoreAutomatic(withReply: confirm)
            }
        }
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
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlResume) else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
            cancelResumeRetry()
            return
        }
        // Only the control running now is kept, never an older one left
        // behind, for example by a restored backup.
        if ownsSession, let ownedSession {
            rememberForResume(ownedSession.configuration)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        }
    }

    /// The manual speed or curve to bring back when the app opens or the Mac
    /// wakes, while resume is on and the user has not returned to System.
    private static var resumableConfiguration: FanControlConfiguration? {
        // Picking System in the card is a return to System too, even when a
        // safety stop had already handed the fans back and left no button.
        guard AppFeature.fanControl.isAvailable,
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
        // A fresh retry budget cannot override a safety stop.
        guard !resumeBlocked, pendingStop == nil, pendingApply == nil, !ownsSession else { return true }
        if let session = ownedSession {
            disconnectSession(on: session.connection)
            return true
        }
        cancelResumeRetry()
        guard !isWorking, !FanControlResumePolicy.defersResume(thermalState: ProcessInfo.processInfo.thermalState) else {
            startObservingSystemState()
            scheduleResumeAttempt(after: FanControlResumePolicy.retryDelays[0])
            return true
        }
        return resume(configuration)
    }

    private func cancelResumeRetry() {
        cancelResumeAttempt()
        resumeFailures = 0
        resumeFailed = false
    }

    /// One refused resume used to leave the fans on System for good while the
    /// card still showed the curve, so a hot Mac kept its fans at idle speed.
    private func resumeDidFail(_ failure: FanControlErrorCode, stopReason: FanControlStopReason? = nil) {
        guard Self.resumableConfiguration != nil else { return }
        guard (failure == .controlFailed || failure == .helperUnavailable),
              stopReason != .hardwareChanged, stopReason != .temperatureUnavailable,
              stopReason != .thermalPressure else {
            resumeFailed = true
            return
        }
        Self.log.error("Fan control resume attempt \(self.resumeFailures + 1) failed: \(failure.rawValue, privacy: .public)")
        scheduleResumeRetry()
    }

    private func scheduleResumeRetry() {
        guard let delay = FanControlResumePolicy.retryDelay(afterFailures: resumeFailures) else {
            resumeFailed = true
            Self.log.error("Fan control resume gave up; the fans stay with the system")
            return
        }
        resumeFailures += 1
        scheduleResumeAttempt(after: delay)
    }

    private func retryResume() {
        guard !isSleeping, pendingStop == nil, !resumeBlocked, !resumeFailed,
              let configuration = Self.resumableConfiguration else { return }
        guard !isWorking,
              !FanControlResumePolicy.defersResume(thermalState: ProcessInfo.processInfo.thermalState) else {
            scheduleResumeAttempt(after: FanControlResumePolicy.retryDelays[0])
            return
        }
        guard !snapshot.isCooling else { return }
        if !resume(configuration) { resumeFailed = true }
    }

    private func applyStatus(_ response: FanControlResponse) {
        let observed: StopConfirmation = ownsSession ? .resumeAfterHeartbeatLoss : .keepSystem
        applySessionResponse(response, observed: ownedSession != nil ? observed : nil)
    }

    /// Keep the global snapshot for the panel. An automatic retry needs a
    /// stop attributed to this client and a confirmed return to automatic.
    private func applySessionResponse(_ response: FanControlResponse, observed: StopConfirmation?,
                                      isReleaseReply: Bool = false) {
        let previous = pendingStop
        let stop = previous ?? observed
        apply(response)
        if response.error == .alreadyControlled || (snapshot.isCooling && (!ownsSession || response.sessionStop != nil)) {
            ownedSession = nil
            pendingStop = .otherController
            blockResumeAfterStop()
            if needsTimer { startTimerIfNeeded() } else { stopIdleWorkIfPossible() }
            return
        }
        guard !snapshot.isCooling else { return }
        if case let .previousSession(phase)? = previous {
            confirmPreviousRecovery(response, phase: phase)
            return
        }
        guard response.succeeded else {
            guard let stop,
                  response.error == .controlFailed || previous != nil || observed == .resumeAfterSleep else { return }
            // An idle telemetry read can fail with no sample or stop reason.
            // It adds no evidence about a handoff already in progress.
            if !isReleaseReply, previous != nil, response.sessionStop == nil,
               response.error == .controlFailed, snapshot == .empty { return }
            if response.error == .controlFailed, stop.allowsSessionResume(response, isReleaseReply: isReleaseReply) {
                pendingStop = stop
            } else {
                pendingStop = .keepSystem
                blockResumeAfterStop()
            }
            return
        }
        automaticControlConfirmed()
        guard let stop, Self.resumableConfiguration != nil else { return }
        guard stop.allowsSessionResume(response, isReleaseReply: isReleaseReply) else {
            blockResumeAfterStop()
            return
        }
        if !isSleeping { scheduleResumeRetry() }
    }

    private func confirmPreviousRecovery(_ response: FanControlResponse, phase: StopConfirmation.RecoveryPhase) {
        guard response.succeeded else {
            if response.error == .controlFailed {
                // Older helpers report recovery as a failed read with the
                // stop reason. A failed telemetry read alone has no cause.
                guard response.isRecovering ?? (snapshot.stopReason != nil) else { return }
                if snapshot.stopReason == nil || phase.allowsResume(after: snapshot.stopReason) {
                    if phase == .checkingAtLaunch { pendingStop = .previousSession(.recoveringAtLaunch) }
                    return
                }
            }
            pendingStop = .keepSystem
            blockResumeAfterStop()
            return
        }
        automaticControlConfirmed()
        guard !resumeBlocked, let configuration = Self.resumableConfiguration else { return }
        guard phase.allowsResume(after: snapshot.stopReason) else {
            blockResumeAfterStop()
            return
        }
        guard !isSleeping else { return }
        if phase == .beforeRetry {
            scheduleResumeRetry()
        } else {
            _ = beginResume(configuration)
        }
    }

    private func automaticControlConfirmed() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
        if unregisterAfterRestore {
            unregisterAfterRestore = false
            if !AppFeature.fanControl.isAvailable { unregisterHelper() }
        }
        stopIdleWorkIfPossible()
    }

    private func blockResumeAfterStop() {
        resumeBlocked = true
        cancelResumeAttempt()
        if Self.resumableConfiguration != nil { resumeFailed = true }
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
        guard !requestInFlight else { return }
        let generation = beginRequest()
        send { proxy, reply in proxy.status(withReply: reply) } completion: { response, issuingConnection in
            guard self.finishRequest(generation, response: response),
                  self.connection === issuingConnection, let response else { return }
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
                      completion: @escaping (FanControlResponse?, NSXPCConnection?) -> Void) {
        var finished = false
        let finish: (FanControlResponse?, NSXPCConnection?) -> Void = { response, issuingConnection in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(response, issuingConnection)
            }
        }
        guard let proxy = proxy(errorHandler: { [weak self] failedConnection in
            DispatchQueue.main.async {
                if self?.connection === failedConnection {
                    failedConnection.invalidate()
                    self?.connection = nil
                }
                finish(nil, failedConnection)
            }
        }) else {
            finish(nil, nil)
            return
        }
        let issuingConnection = connection
        operation(proxy) { data in
            finish(FanControlIPC.decode(data), issuingConnection)
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
                    self?.connection = nil
                }
            }
            connection.invalidationHandler = { [weak self, weak connection] in
                DispatchQueue.main.async {
                    guard let connection else { return }
                    if self?.connection === connection { self?.connection = nil }
                }
            }
            connection.activate()
            self.connection = connection
        }
        guard let connection else { return nil }
        return connection.remoteObjectProxyWithErrorHandler { _ in errorHandler(connection) }
            as? FanControlXPCProtocol
    }

    private func heartbeat() {
        guard ownsSession, !requestInFlight, !isWorking else { return }
        let generation = beginRequest()
        send { proxy, reply in proxy.heartbeat(withReply: reply) } completion: { response, issuingConnection in
            guard self.finishRequest(generation, response: response),
                  self.connection === issuingConnection, let response else { return }
            self.applyStatus(response)
        }
    }

    private func apply(_ response: FanControlResponse) {
        snapshot = response.snapshot
        error = response.error
        if !snapshot.isCooling { ownedSession = nil }
        if response.succeeded { pendingStop = nil }
    }

    private func beginRequest() -> Int {
        requestGeneration += 1
        requestInFlight = true
        return requestGeneration
    }

    private func finishRequest(_ generation: Int, response: FanControlResponse?) -> Bool {
        guard generation == requestGeneration else { return false }
        requestInFlight = false
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
              pendingStop == nil, !snapshot.isCooling,
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
        if pendingApply != nil || ownsSession || accessState == .enabled {
            restoreAutomatic(supersedingCurrentRequest: true)
            return
        }
        guard accessState != .notRegistered else { return }
        guard pendingStop == nil, !UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else {
            unregisterAfterRestore = true
            error = .authorizationRequired
            return
        }
        unregisterHelper()
    }

    private func unregisterHelper() {
        do {
            refreshAccessState()
            if accessState != .notRegistered { try Self.appService.unregister() }
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
            refreshAccessState()
        } catch {
            self.error = .helperUnavailable
        }
    }

    // MARK: - Timers and system state

    private var needsTimer: Bool {
        if pendingStop == .previousSession(.checkingAtLaunch), accessState != .enabled { return false }
        if panelIsVisible || ownsSession || unregisterAfterRestore
            || UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) { return true }
        // Merely viewing another client's fans has no background work to finish.
        if pendingStop == .otherController { return Self.resumableConfiguration != nil }
        return pendingStop != nil
    }

    private func startTimerIfNeeded() {
        guard needsTimer else { return }
        startObservingSystemState()
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
        guard needsTimer else { stopIdleWorkIfPossible(); return }
        tickCount += 1
        if pendingStop != nil {
            // While another controller owns the fans, a background status
            // check once a minute can finish cleanup when it releases them.
            let interval = pendingStop == .otherController && !panelIsVisible ? 60 : 2
            if tickCount.isMultiple(of: interval) { requestStatus() }
        } else if ownsSession {
            heartbeat()
        } else if tickCount.isMultiple(of: 2) {
            if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
                requestStatus()
            } else if panelIsVisible, error != .controlFailed {
                refresh()
            }
        }
    }

    private func stopIdleWorkIfPossible() {
        guard !needsTimer else { return }
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
        isSleeping = false
    }

    @objc private func workspaceWillSleep() {
        // A retry must not re-apply control on the way into sleep; the wake
        // starts a fresh resume.
        cancelResumeAttempt()
        isSleeping = true
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            restoreAutomatic(supersedingCurrentRequest: true, forSleep: true)
        }
    }

    @objc private func workspaceDidWake() {
        isSleeping = false
        if pendingApply == .restoreForSleep || pendingApply == .returnToSystem { return }
        if pendingStop == .previousSession(.checkingAtLaunch) {
            checkLaunchRecovery()
            return
        }
        if let configuration = Self.resumableConfiguration, beginResume(configuration) { return }
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            restoreAutomatic(supersedingCurrentRequest: true)
        } else if panelIsVisible {
            refresh()
        }
    }
}
