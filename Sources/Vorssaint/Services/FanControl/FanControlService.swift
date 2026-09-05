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
        reconcileManualTimerOnLaunch()
        refreshAccessState()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        connection?.invalidate()
        timer?.invalidate()
    }

    static func recoverIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) else { return }
        shared.restoreAutomatic()
    }

    func syncWithPreferences() {
        if AppFeature.fanControl.isAvailable {
            if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
                restoreAutomatic()
            }
        } else {
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
        guard FanControlPolicy.validConfiguration(configuration) else {
            error = .controlFailed
            return
        }
        if configuration.mode == .system {
            clearManualTimerState()
            restoreAutomatic()
            return
        }
        guard accessState == .enabled else { authorize(); return }
        guard let encodedConfiguration = FanControlIPC.encode(configuration) else {
            error = .controlFailed
            return
        }
        error = nil
        if configuration.mode != .manual {
            clearManualTimerState()
        }
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
                // No confirmation either way: do not let a half-applied
                // request leave a later override reading a stale "previous
                // mode" or deadline.
                self.clearManualTimerState()
                self.restoreAutomatic()
                return
            }
            self.apply(response)
            if response.succeeded, response.snapshot.isCooling {
                // Only recorded once the helper has actually confirmed the
                // override is running, using the state from just before this
                // apply (retrySnapshot), not the just-applied response.
                if configuration.mode == .manual {
                    self.recordManualTimerState(for: configuration, previousSnapshot: retrySnapshot)
                }
                self.startTimerIfNeeded()
            } else {
                self.clearManualTimerState()
                self.restoreAutomatic(supersedingCurrentRequest: false,
                                      preserving: response.error ?? .controlFailed,
                                      retrySnapshot: retrySnapshot)
            }
        }
    }

    func restoreAutomatic() {
        restoreAutomatic(supersedingCurrentRequest: false)
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
                // Same reasoning as applyConfiguration's no-response branch:
                // an unconfirmed restore must not leave stale bookkeeping for
                // a later override to inherit.
                self.clearManualTimerState()
                return
            }
            self.apply(response)
            if response.succeeded, !response.snapshot.isCooling {
                if self.snapshot.fans.isEmpty, let retrySnapshot {
                    self.snapshot = retrySnapshot
                }
                if let failure { self.error = failure }
                self.clearManualTimerState()
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
                self.clearManualTimerState()
            }
        }
        // Losing the authenticated client connection is itself a restore
        // trigger in the helper, including if the reply cannot beat app exit.
        connection?.invalidate()
        connection = nil
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
                if response.snapshot.stopReason == .timeLimit, self.resumePreviousCurveAfterManualExpiry() {
                    // Reapplying the interrupted curve is in flight.
                } else {
                    self.clearManualTimerState()
                }
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
                if response.snapshot.stopReason == .timeLimit, self.resumePreviousCurveAfterManualExpiry() {
                    // A curve was running before the timed manual override;
                    // reapplying it is already in flight, so idle work stays up.
                } else {
                    self.clearManualTimerState()
                    self.stopIdleWorkIfPossible()
                }
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

    // MARK: - Manual session timer

    /// The deadline itself is enforced by the helper (see
    /// `FanControlPolicy.sessionDuration`), reusing the `endsAt`/watchdog
    /// mechanism it already had; the panel's remaining-time label reads that
    /// live value from `snapshot.endsAt`, not from these UserDefaults keys.
    /// What these keys are actually for: letting `reconcileManualTimerOnLaunch`
    /// notice a deadline that elapsed while the app was not running, and
    /// letting `resumePreviousCurveAfterManualExpiry` know what to hand
    /// control back to once a real, observed expiry happens. Called only
    /// after the helper has confirmed the override is actually running, so a
    /// failed apply can never leave a later override inheriting a wrong
    /// "previous mode".
    private func recordManualTimerState(for configuration: FanControlConfiguration,
                                        previousSnapshot: FanControlSnapshot) {
        let defaults = UserDefaults.standard
        guard let seconds = configuration.manualDuration.seconds else {
            clearManualTimerState()
            return
        }
        if defaults.object(forKey: DefaultsKey.fanControlManualUntil) == nil {
            // A fresh override: remember what to hand control back to once it
            // expires, using the state from right before this apply. Later
            // tweaks (level, duration) while still in manual go through this
            // same function but land here with the key already set, so they
            // fall into the branch below and must not overwrite this.
            let previous = FanControlPolicy.manualOverridePreviousMode(
                isCooling: previousSnapshot.isCooling,
                activeMode: previousSnapshot.configuration?.mode
            )
            defaults.set(previous.rawValue, forKey: DefaultsKey.fanControlModeBeforeManual)
            // The curve editor writes fanControlCurves live as the user drags
            // points, with no Apply step, so by the time the override expires
            // that key may no longer match what is actually running. Freeze
            // the curve that was actually confirmed active instead.
            if previous == .curve, let curves = previousSnapshot.configuration?.curves,
               let encoded = FanControlConfiguration.encodeCurves(curves) {
                defaults.set(encoded, forKey: DefaultsKey.fanControlManualPreviousCurves)
            }
        }
        defaults.set(Date().addingTimeInterval(seconds).timeIntervalSince1970,
                     forKey: DefaultsKey.fanControlManualUntil)
    }

    private func clearManualTimerState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DefaultsKey.fanControlManualUntil)
        defaults.removeObject(forKey: DefaultsKey.fanControlModeBeforeManual)
        defaults.removeObject(forKey: DefaultsKey.fanControlManualPreviousCurves)
    }

    /// Called once a response reports the manual session ended on its own
    /// deadline. Returns whether a curve was interrupted and is being
    /// reapplied; the caller leaves idle work running in that case instead of
    /// treating the fans as settled on system control.
    @discardableResult
    private func resumePreviousCurveAfterManualExpiry() -> Bool {
        let defaults = UserDefaults.standard
        let previousMode = (defaults.string(forKey: DefaultsKey.fanControlModeBeforeManual))
            .flatMap(FanControlMode.init(rawValue:))
        guard FanControlPolicy.modeAfterManualExpiry(previousMode: previousMode) == .curve else {
            return false
        }
        // Prefer the curve frozen when the override began, since the editor
        // may have since changed fanControlCurves without an Apply; fall back
        // to the current stored curves only if that snapshot is missing.
        let storage = defaults.string(forKey: DefaultsKey.fanControlManualPreviousCurves)
            ?? defaults.string(forKey: DefaultsKey.fanControlCurves)
        guard let storage, let curves = FanControlConfiguration.decodeCurves(storage) else {
            return false
        }
        clearManualTimerState()
        applyConfiguration(.curve(curves))
        return true
    }

    /// Reverting the hardware, if a session is somehow still running, is
    /// already handled unconditionally by `recoverIfNeeded()` whenever the
    /// app was not shut down cleanly, and by the helper's own watchdog
    /// regardless of this app process. This only clears a stale label so the
    /// panel does not show a countdown for a session that already ended.
    private func reconcileManualTimerOnLaunch() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: DefaultsKey.fanControlManualUntil) != nil else { return }
        let until = Date(timeIntervalSince1970: defaults.double(forKey: DefaultsKey.fanControlManualUntil))
        if FanControlPolicy.manualDurationElapsed(until: until, now: Date()) {
            clearManualTimerState()
        }
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
            self.clearManualTimerState()
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
                self.heartbeat()
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
        if UserDefaults.standard.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) {
            restoreAutomatic(supersedingCurrentRequest: true)
        } else if panelIsVisible {
            refresh()
        }
    }
}
