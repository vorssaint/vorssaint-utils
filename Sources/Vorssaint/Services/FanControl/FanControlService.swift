// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
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
    /// The running timed manual speed: when it hands the fans back to the
    /// system and the minutes picked for it.
    @Published private(set) var timedManual: FanControlTimedManual?

    private let probeQueue = DispatchQueue(label: "com.vorssaint.fan-control.probe",
                                           qos: .utility)
    private var probeHardware: FanControlHardware?
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var panelIsVisible = false
    private var requestInFlight = false
    private var requestGeneration = 0
    private var tickCount = 0
    private var registrationAttemptedVersion: String?
    private var observingWorkspace = false

    private static var appService: SMAppService {
        SMAppService.daemon(plistName: FanControlIdentifiers.plistName)
    }

    private static var helperVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "VorssaintFanControlHelperVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? AppInfo.version
    }

    private init() {
        timedManual = Self.storedTimedManual
        refreshAccessState()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        connection?.invalidate()
        timer?.invalidate()
    }

    static func recoverIfNeeded() {
        // A timed speed that ended while the app was closed resumes nothing.
        // Without a stored end a launch reaches the service only for a kept
        // control or a recovery, so a Mac that never ran a timed speed, or
        // has the feature off, does not load it here.
        if storedTimedManual != nil, AppFeature.fanControl.isAvailable {
            shared.discardEndedTimedManual(now: Date())
        }
        // Re-applying supersedes the recovery: a start that fails restores too.
        if let configuration = resumableConfiguration, shared.resume(configuration) { return }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        shared.restoreAutomatic()
    }

    func syncWithPreferences() {
        if AppFeature.fanControl.isAvailable {
            if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
                restoreAutomatic()
            }
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
            rememberTimedManual(nil)
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
        applyConfiguration(configuration, timed: nil)
    }

    /// A manual speed that holds for `minutes`, or until the user changes it
    /// when `minutes` is `FanControlManualDuration.untilChanged`.
    func applyManual(level: Int, minutes: Int) {
        applyConfiguration(.manual(level: level),
                           timed: FanControlManualDuration.timed(minutes: minutes, from: Date()))
    }

    private func applyConfiguration(_ configuration: FanControlConfiguration,
                                    timed: FanControlTimedManual?) {
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
        // Whatever this request ends in replaces the running speed and its
        // end: its own control on success, the system otherwise. A request
        // that fails, gets no reply, is superseded by sleep or outlived by
        // the app must not leave the timed speed kept without its end.
        forgetTimedManual()
        let retrySnapshot = snapshot
        startObservingSystemState()
        let generation = beginRequest()
        UserDefaults.standard.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)
        isWorking = true
        send({ proxy, reply in
            proxy.applyConfiguration(encodedConfiguration, withReply: reply)
        }) { response in
            guard self.finishRequest(generation) else { return }
            self.isWorking = false
            guard let response else {
                self.error = .helperUnavailable
                self.restoreAutomatic()
                return
            }
            self.apply(response)
            if response.succeeded, response.snapshot.isCooling {
                self.rememberTimedManual(configuration.mode == .manual ? timed : nil)
                self.rememberForResume(configuration)
                self.startTimerIfNeeded()
            } else {
                self.restoreAutomatic(supersedingCurrentRequest: false,
                                      preserving: response.error ?? .controlFailed,
                                      retrySnapshot: retrySnapshot)
            }
        }
    }

    func restoreAutomatic() {
        restoreAutomatic(supersedingCurrentRequest: false)
    }

    /// The user's own return to System, the one stop a resume must honor.
    func returnToSystem() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        rememberTimedManual(nil)
        restoreAutomatic()
    }

    private func restoreAutomatic(supersedingCurrentRequest: Bool,
                                  preserving failure: FanControlErrorCode? = nil,
                                  retrySnapshot: FanControlSnapshot? = nil) {
        guard supersedingCurrentRequest || !isWorking else { return }
        refreshAccessState()
        guard accessState == .enabled else { return }
        let generation = beginRequest()
        isWorking = true
        startTimerIfNeeded()
        send { proxy, reply in proxy.restoreAutomatic(withReply: reply) } completion: { response in
            guard self.finishRequest(generation) else { return }
            self.isWorking = false
            guard let response else {
                self.error = .helperUnavailable
                return
            }
            self.apply(response)
            if response.succeeded, !response.snapshot.isCooling {
                if self.snapshot.fans.isEmpty, let retrySnapshot {
                    self.snapshot = retrySnapshot
                }
                if let failure { self.error = failure }
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
                if !AppFeature.fanControl.isAvailable {
                    do {
                        try Self.appService.unregister()
                        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
                        self.refreshAccessState()
                    } catch {
                        self.error = .helperUnavailable
                    }
                }
                self.stopIdleWorkIfPossible()
            }
        }
    }

    static func restoreBeforeTerminationIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        shared.restoreBeforeTermination()
    }

    private func restoreBeforeTermination() {
        send { proxy, reply in proxy.restoreAutomatic(withReply: reply) } completion: { response in
            if let response, response.succeeded, !response.snapshot.isCooling {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
            }
        }
        // Losing the authenticated client connection is itself a restore
        // trigger in the helper, including if the reply cannot beat app exit.
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
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlResume) else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
            return
        }
        // Only the control running now is kept, never an older one left
        // behind, for example by a restored backup. While a request stops or
        // replaces it, the snapshot still shows the old control, which may
        // already have lost its end; that request decides what runs, and an
        // apply it confirms keeps its own control then.
        if !isWorking, snapshot.isCooling, let configuration = snapshot.configuration {
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
        // A timed speed comes back for the time it had left, never a new one.
        applyConfiguration(configuration, timed: timedManual)
        return true
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

    // MARK: - Timed manual speed

    private func rememberTimedManual(_ timed: FanControlTimedManual?) {
        timedManual = timed
        if let timed {
            UserDefaults.standard.set(timed.end.timeIntervalSinceReferenceDate,
                                      forKey: DefaultsKey.fanControlManualEnd)
            UserDefaults.standard.set(timed.minutes, forKey: DefaultsKey.fanControlManualEndMinutes)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlManualEnd)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlManualEndMinutes)
        }
    }

    /// The timed speed kept on this Mac. An end stored without its minutes
    /// has nothing to bound it and counts as ended, so it is never resumed
    /// as an untimed speed.
    private static var storedTimedManual: FanControlTimedManual? {
        let end = UserDefaults.standard.double(forKey: DefaultsKey.fanControlManualEnd)
        guard end > 0 else { return nil }
        return FanControlTimedManual(
            end: Date(timeIntervalSinceReferenceDate: end),
            minutes: UserDefaults.standard.integer(forKey: DefaultsKey.fanControlManualEndMinutes))
    }

    /// Forgets a timed speed together with the kept control that would bring
    /// it back: a kept manual speed without its end would resume untimed.
    private func forgetTimedManual() {
        guard timedManual != nil else { return }
        rememberTimedManual(nil)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
    }

    /// Forgets a timed speed whose end has passed, so no wake or launch can
    /// resume it, and puts the card back on System, where the end hands the
    /// fans. Reports whether it did.
    @discardableResult private func discardEndedTimedManual(now: Date) -> Bool {
        guard let timed = timedManual,
              FanControlManualDuration.hasEnded(timed, now: now) else { return false }
        forgetTimedManual()
        // A Curve or System picked since stays: only the Manual whose time
        // ran out goes back.
        if UserDefaults.standard.string(forKey: DefaultsKey.fanControlMode)
            == FanControlMode.manual.rawValue {
            UserDefaults.standard.set(FanControlMode.system.rawValue, forKey: DefaultsKey.fanControlMode)
        }
        return true
    }

    /// Hands the fans back once a running timed speed ends, through the same
    /// plain restore as the user's own return to System: it leaves the helper
    /// no stop reason, so the card reports no interruption for an end the
    /// user picked. The restore supersedes any request in flight, the way
    /// sleep does: a pending reply must not keep the speed past its end.
    private func expireTimedManualIfNeeded(now: Date) -> Bool {
        guard discardEndedTimedManual(now: now) else { return false }
        restoreAutomatic(supersedingCurrentRequest: true)
        return true
    }

    // MARK: - Requests

    private func requestStatus() {
        guard !requestInFlight else { return }
        let generation = beginRequest()
        send { proxy, reply in proxy.status(withReply: reply) } completion: { response in
            guard self.finishRequest(generation) else { return }
            guard let response else {
                self.error = .helperUnavailable
                return
            }
            self.apply(response)
            // Any decoded reply proves that the installed helper speaks this
            // protocol, even when the hardware itself is unsupported.
            UserDefaults.standard.set(Self.helperVersion,
                                      forKey: DefaultsKey.fanControlHelperVersion)
            if response.succeeded, !response.snapshot.isCooling {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
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
                    self?.connection = nil
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
        guard snapshot.isCooling, !requestInFlight, !isWorking else { return }
        let generation = beginRequest()
        send { proxy, reply in proxy.heartbeat(withReply: reply) } completion: { response in
            guard self.finishRequest(generation) else { return }
            guard let response else {
                self.error = .helperUnavailable
                return
            }
            self.apply(response)
            if response.succeeded, !response.snapshot.isCooling {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
                self.stopIdleWorkIfPossible()
            }
        }
    }

    private func apply(_ response: FanControlResponse) {
        snapshot = response.snapshot
        error = response.error
    }

    private func beginRequest() -> Int {
        requestGeneration += 1
        requestInFlight = true
        return requestGeneration
    }

    private func finishRequest(_ generation: Int) -> Bool {
        guard generation == requestGeneration else { return false }
        requestInFlight = false
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
        let generation = beginRequest()
        isWorking = true
        send { proxy, reply in proxy.restoreAutomatic(withReply: reply) } completion: { response in
            guard self.finishRequest(generation) else { return }
            self.isWorking = false
            guard let response, response.succeeded, !response.snapshot.isCooling else { return }
            UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlRecoveryNeeded)
            guard !AppFeature.fanControl.isAvailable else {
                self.stopIdleWorkIfPossible()
                return
            }
            do {
                try Self.appService.unregister()
                UserDefaults.standard.removeObject(forKey: DefaultsKey.fanControlHelperVersion)
                self.refreshAccessState()
            } catch {
                self.error = .helperUnavailable
            }
            self.stopIdleWorkIfPossible()
        }
    }

    // MARK: - Timers and system state

    private func startTimerIfNeeded() {
        guard panelIsVisible || snapshot.isCooling
                || UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        startObservingSystemState()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tickCount += 1
            if self.snapshot.isCooling {
                if !self.expireTimedManualIfNeeded(now: Date()) { self.heartbeat() }
            } else if self.panelIsVisible, self.error != .controlFailed,
                      self.tickCount.isMultiple(of: 2) {
                self.refresh()
            }
        }
        // The helper drops cooling once a heartbeat is `heartbeatLimit` seconds
        // old, so a second's cadence has six to spare; matching the leeway the
        // helper's own watchdog already takes lets these wakes coalesce with
        // everything else on the run loop instead of standing alone.
        timer?.tolerance = 0.1
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
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            restoreAutomatic(supersedingCurrentRequest: true)
        }
    }

    @objc private func workspaceDidWake() {
        // An end that passed during sleep returns the fans to the system
        // below instead of resuming the timed speed.
        discardEndedTimedManual(now: Date())
        if let configuration = Self.resumableConfiguration, resume(configuration) { return }
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            restoreAutomatic(supersedingCurrentRequest: true)
        } else if panelIsVisible {
            refresh()
        }
    }
}
