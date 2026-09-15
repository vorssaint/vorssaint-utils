// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import ServiceManagement
import NativeChargeControl

final class ChargeControlService: ObservableObject {
    enum AccessState: Equatable {
        case notRegistered
        case requiresApproval
        case enabled
        case unavailable
    }

    static let shared = ChargeControlService()

    @Published private(set) var accessState: AccessState = .notRegistered
    @Published private(set) var snapshot: ChargeControlSnapshot = .idle
    @Published private(set) var profile: ChargeControlHardwareProfile?
    @Published private(set) var error: ChargeControlErrorCode?
    @Published private(set) var isWorking = false
    @Published private(set) var chargePercent: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var externalConnected = false
    @Published private(set) var hasBattery = PowerSampler.hasInternalBattery
    @Published private(set) var enabled = true
    @Published private(set) var limitPercent = ChargeControlPolicy.defaultLimit
    @Published private(set) var sailingEnabled = false
    @Published private(set) var sailingRangePercent = ChargeControlPolicy.defaultSailingRange
    @Published private(set) var mode: ChargeControlMode = .limit
    @Published private(set) var appliedGate: ChargeControlGate = .allowCharging
    @Published private(set) var now = Date()
    @Published private(set) var nativeChargingAvailable = false

    var usesNativeCharging: Bool { nativeChargingAvailable && profile?.family == .nativePowerUI }
    var minimumSupportedLimit: Int { usesNativeCharging ? 80 : ChargeControlPolicy.minimumLimit }

    private let sampler = PowerSampler(smc: SMCClient())
    private let probeQueue = DispatchQueue(label: "com.vorssaint.charge-control.probe", qos: .utility)
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var controllerStateObserver: AnyCancellable?
    private var panelIsVisible = false
    private var requestInFlight = false
    private var requestGeneration = 0
    private var evaluationCoalescer = ChargeControlEvaluationCoalescer()
    private var registrationAttemptedVersion: String?
    private var didRequestAuthorization = false
    private var sleepAssertion: IOPMAssertionID = 0
    private var lastAppliedRequest: ChargeControlRequest?
    private var connectionRevision = 0
    private var inhibitedConnectionRevision = 0

    private static var appService: SMAppService {
        SMAppService.daemon(plistName: ChargeControlIdentifiers.plistName)
    }

    private static var helperVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "VorssaintChargeControlHelperVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? AppInfo.version
    }

    private init() {
        refreshFromDefaults()
        refreshAccessState()
        installPowerSourceObserver()
        controllerStateObserver = BatteryPowerStateMonitor.shared.$state.sink { [weak self] state in
            guard let self else { return }
            self.updateBatteryState(state)
            self.evaluate(refreshBattery: self.chargePercent == nil)
        }
        probeQueue.async { [weak self] in
            let available = VSNativeChargeLimit() >= 0
            DispatchQueue.main.async {
                guard let self else { return }
                self.nativeChargingAvailable = available
                self.refresh()
            }
        }
    }

    deinit {
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .commonModes)
        }
        connection?.invalidate()
        timer?.invalidate()
        releaseSleepAssertion()
    }

    var isCalibrating: Bool {
        if case .calibration = mode { return true }
        return false
    }

    var isDischargingToLimit: Bool {
        if case .dischargeToLimit = mode { return true }
        return false
    }

    var isToppingUp: Bool {
        if case .topUp = mode { return true }
        return false
    }

    var isHolding: Bool {
        guard externalConnected else { return false }
        if usesNativeCharging {
            return enabled && error == nil && !isCharging && !isDischargingToLimit && !isToppingUp
                && lastAppliedRequest?.limitPercent == limitPercent
                && (chargePercent ?? 0) >= limitPercent
        }
        if appliedGate == .inhibitCharging { return true }
        guard enabled, sailingEnabled, accessState == .enabled,
              profile?.supportsInhibit == true, error == nil else { return false }
        return ChargeControlPolicy.desiredGate(
            chargePercent: chargePercent ?? 0,
            limit: limitPercent,
            sailingRange: sailingRangePercent,
            wasInhibited: false,
            mode: mode,
            family: profile?.family ?? snapshot.profile?.family,
            externalConnected: true) == .inhibitCharging
    }

    var holdRemainingSeconds: TimeInterval? {
        guard case .calibration(let state) = mode else { return nil }
        return ChargeControlPolicy.holdRemaining(state: state, now: now)
    }

    var calibrationPhase: ChargeCalibrationPhase? {
        guard case .calibration(let state) = mode else { return nil }
        return state.phase
    }

    static func recoverIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded) else { return }
        let service = shared
        guard !AppFeature.chargeControl.isAvailable || !service.enabled else { return }
        service.restoreCharging()
    }

    func syncWithPreferences() {
        refreshFromDefaults()
        if AppFeature.chargeControl.isAvailable, hasBattery {
            startTimerIfNeeded()
            refresh()
        } else {
            cancelTransientModes()
            restoreThenUnregister()
        }
    }

    func panelDidAppear() {
        panelIsVisible = true
        refresh()
        if AppFeature.chargeControl.isAvailable, hasBattery, enabled {
            ensureHelperForControl()
        }
        startTimerIfNeeded()
    }

    func panelDidDisappear() {
        panelIsVisible = false
        stopIdleWorkIfPossible()
    }

    func refresh() {
        refreshFromDefaults()
        refreshAccessState()
        sampleBattery()
        if accessState == .enabled {
            guard !replaceRegistrationIfNeeded() else { return }
            requestStatus()
        } else {
            refreshLocalProbe()
        }
        evaluate()
    }

    func authorize() {
        refreshAccessState()
        switch accessState {
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        case .enabled:
            requestStatus()
            evaluate()
        case .unavailable, .notRegistered:
            isWorking = true
            do {
                try Self.appService.register()
                UserDefaults.standard.set(Self.helperVersion,
                                          forKey: DefaultsKey.chargeControlHelperVersion)
                refreshAccessState()
                isWorking = false
                if accessState == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else if accessState == .enabled {
                    requestStatus()
                    evaluate()
                } else {
                    self.error = .helperUnavailable
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

    /// Register the helper once when the user sets a limit. Login Items
    /// approval is a system sheet; repeating it on every slider tick is noise.
    private func ensureHelperForControl() {
        refreshAccessState()
        guard accessState != .enabled else { return }
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        authorize()
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.chargeLimitEnabled)
        self.enabled = enabled
        if !enabled {
            cancelTransientModes()
        } else {
            ensureHelperForControl()
        }
        evaluate()
    }

    func setLimit(_ percent: Int) {
        let cap = usesNativeCharging ? min(100, max(80, Int((Double(percent) / 5).rounded()) * 5))
            : ChargeControlPolicy.sanitizedLimit(percent)
        UserDefaults.standard.set(cap, forKey: DefaultsKey.chargeLimitPercent)
        limitPercent = cap
        setSailingRange(sailingRangePercent, evaluateAfterChange: false)
        if accessState != .enabled { ensureHelperForControl() }
        evaluate(refreshBattery: false)
    }

    func setSailingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.chargeSailingEnabled)
        sailingEnabled = enabled
        ensureHelperForControl()
        evaluate()
    }

    func setSailingRange(_ percent: Int) {
        setSailingRange(percent, evaluateAfterChange: true)
    }

    func startDischargeToLimit() {
        guard hasBattery, profile?.supportsDischarge == true else { return }
        guard accessState == .enabled else { authorize(); return }
        mode = .dischargeToLimit
        releaseSleepAssertion()
        evaluate()
    }

    func stopDischarge() {
        guard isDischargingToLimit else { return }
        mode = .limit
        releaseSleepAssertion()
        evaluate()
    }

    func startTopUp() {
        guard profile?.supportsInhibit == true,
              externalConnected,
              limitPercent < ChargeControlPolicy.maximumLimit,
              (chargePercent ?? 0) < ChargeControlPolicy.maximumLimit else { return }
        guard accessState == .enabled else { authorize(); return }
        mode = .topUp
        releaseSleepAssertion()
        evaluate()
    }

    func stopTopUp() {
        guard isToppingUp else { return }
        mode = .limit
        evaluate()
    }

    func startCalibration() {
        guard profile?.supportsDischarge == true, externalConnected else { return }
        guard accessState == .enabled else { authorize(); return }
        mode = .calibration(ChargeControlPolicy.startCalibration(chargePercent: chargePercent ?? 0,
                                                                 savedLimit: limitPercent))
        takeSleepAssertion()
        evaluate()
    }

    func cancelCalibration() {
        guard isCalibrating else { return }
        mode = .limit
        releaseSleepAssertion()
        evaluate()
    }

    func restoreCharging() {
        restoreCharging(supersedingCurrentRequest: false)
    }

    static func restoreBeforeTerminationIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded) else { return }
        shared.restoreBeforeTermination()
    }

    @discardableResult
    static func restoreAndUnregisterForRemoval() -> Bool {
        let service = appService
        guard service.status == .enabled else {
            guard service.status != .notRegistered else { return true }
            guard !UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded)
            else { return false }
            return unregisterForRemoval(service)
        }
        let connection = NSXPCConnection(machServiceName: ChargeControlIdentifiers.helperID,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ChargeControlXPCProtocol.self)
        connection.setCodeSigningRequirement(ChargeControlIdentifiers.helperCodeRequirement)
        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var restored = false
        connection.activate()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in semaphore.signal() }
            as? ChargeControlXPCProtocol
        guard let proxy else {
            connection.invalidate()
            return false
        }
        proxy.restoreNormal { data in
            if let response = ChargeControlIPC.decodeResponse(data) {
                resultLock.withLock {
                    restored = response.succeeded && response.snapshot.gate == .allowCharging
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

    private func evaluate(refreshBattery: Bool = true) {
        if refreshBattery { sampleBattery() }
        advanceCalibrationIfNeeded()
        settleTopUpIfNeeded()

        let active = AppFeature.chargeControl.isAvailable && hasBattery && enabled
        let needsControl = active || isCalibrating || isDischargingToLimit || isToppingUp
        guard needsControl else {
            if usesNativeCharging || lastAppliedRequest?.gate != .allowCharging || appliedGate != .allowCharging {
                applyGate(.allowCharging)
            }
            releaseSleepAssertion()
            stopIdleWorkIfPossible()
            return
        }
        guard accessState == .enabled, !isWorking else { return }
        let gate = ChargeControlPolicy.desiredGate(
            chargePercent: chargePercent ?? 0,
            limit: limitPercent,
            sailingRange: sailingEnabled && !usesNativeCharging ? sailingRangePercent : nil,
            wasInhibited: !usesNativeCharging && appliedGate == .inhibitCharging && inhibitedConnectionRevision == connectionRevision,
            mode: mode,
            family: profile?.family ?? snapshot.profile?.family,
            externalConnected: externalConnected)
        applyGate(gate)
        startTimerIfNeeded()
    }

    /// Release an old gate on unplug before the next connection negotiates power.
    private func installPowerSourceObserver() {
        guard hasBattery else { return }
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        powerSourceRunLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<ChargeControlService>.fromOpaque(context).takeUnretainedValue()
            service.evaluate()
        }, context)?.takeRetainedValue()
        if let powerSourceRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .commonModes)
        }
    }

    private func advanceCalibrationIfNeeded() {
        guard case .calibration(let state) = mode, let charge = chargePercent else { return }
        now = Date()
        if let next = ChargeControlPolicy.advanceCalibration(state, chargePercent: charge, now: now) {
            if next != state { mode = .calibration(next) }
        } else {
            mode = .limit
            releaseSleepAssertion()
        }
    }

    private func settleTopUpIfNeeded() {
        guard isToppingUp, let charge = chargePercent else { return }
        if charge >= ChargeControlPolicy.maximumLimit {
            mode = .limit
        }
    }

    private func applyGate(_ gate: ChargeControlGate) {
        guard accessState == .enabled else { return }
        if usesNativeCharging { applyNativeGate(gate); return }
        // Always queue a trailing evaluation before deduplication: a request
        // in flight can still be applying the opposite of the current intent.
        guard !evaluationCoalescer.deferIfBusy(requestInFlight) else { return }
        let requestLimit = isToppingUp ? ChargeControlPolicy.maximumLimit : limitPercent
        let request = ChargeControlRequest(gate: gate, limitPercent: requestLimit)
        guard request != lastAppliedRequest || gate != appliedGate || error != nil else {
            if gate == .inhibitCharging { inhibitedConnectionRevision = connectionRevision }
            return
        }
        let generation = beginRequest()
        let requestConnectionRevision = connectionRevision
        if gate != .allowCharging {
            UserDefaults.standard.set(true, forKey: DefaultsKey.chargeControlRecoveryNeeded)
        }
        send { proxy, reply in
            proxy.apply(ChargeControlIPC.encode(request), withReply: reply)
        } completion: { response in
            guard self.finishRequest(generation) else { return }
            guard let response else {
                self.error = .helperUnavailable
                return
            }
            self.apply(response)
            if response.succeeded {
                self.lastAppliedRequest = request
                self.appliedGate = gate
                if gate == .inhibitCharging { self.inhibitedConnectionRevision = requestConnectionRevision }
                if gate == .allowCharging {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.chargeControlRecoveryNeeded)
                }
            }
        }
    }

    private func applyNativeGate(_ gate: ChargeControlGate) {
        guard !evaluationCoalescer.deferIfBusy(requestInFlight) else { return }
        let active = AppFeature.chargeControl.isAvailable && enabled
        let full = isToppingUp || !active || (isCalibrating && calibrationPhase != .restoringLimit)
        let target = full ? 100 : min(100, max(80, Int((Double(limitPercent) / 5).rounded()) * 5))
        let request = ChargeControlRequest(gate: gate, limitPercent: target)
        guard request != lastAppliedRequest || gate != appliedGate || error != nil else { return }
        let generation = beginRequest()
        let helperGate: ChargeControlGate = gate == .forceDischarge ? .forceDischarge : .allowCharging
        let helperRequest = ChargeControlRequest(gate: helperGate, limitPercent: target)

        // Set the native cap before discharge. It remains enforced when the
        // adapter is restored at the target, avoiding charge/discharge cycling.
        probeQueue.async { [weak self] in
            let succeeded = VSNativeSetChargeLimit(Int32(target))
            DispatchQueue.main.async {
                guard let self, generation == self.requestGeneration else { return }
                guard succeeded else {
                    if self.finishRequest(generation) { self.error = .controlFailed }
                    return
                }
                if helperGate == .forceDischarge {
                    UserDefaults.standard.set(true, forKey: DefaultsKey.chargeControlRecoveryNeeded)
                }
                self.send { proxy, reply in
                    proxy.apply(ChargeControlIPC.encode(helperRequest), withReply: reply)
                } completion: { response in
                    guard self.finishRequest(generation) else { return }
                    guard let response else { self.error = .helperUnavailable; return }
                    self.apply(response)
                    guard response.succeeded else { return }
                    self.lastAppliedRequest = request
                    self.appliedGate = gate
                    if helperGate == .allowCharging {
                        UserDefaults.standard.removeObject(forKey: DefaultsKey.chargeControlRecoveryNeeded)
                    }
                    self.sampleBattery(notifyMonitor: true)
                }
            }
        }
    }

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
            UserDefaults.standard.set(Self.helperVersion, forKey: DefaultsKey.chargeControlHelperVersion)
            if response.succeeded, response.snapshot.gate == .allowCharging {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.chargeControlRecoveryNeeded)
            }
        }
    }

    private func heartbeat() {
        if usesNativeCharging && appliedGate != .forceDischarge { return }
        guard appliedGate != .allowCharging, !requestInFlight, !isWorking else { return }
        let generation = beginRequest()
        send { proxy, reply in proxy.heartbeat(withReply: reply) } completion: { response in
            guard self.finishRequest(generation) else { return }
            guard let response else {
                self.error = .helperUnavailable
                return
            }
            self.apply(response)
            if response.succeeded, response.snapshot.gate == .allowCharging,
               self.isCalibrating || self.isDischargingToLimit {
                self.mode = .limit
                self.releaseSleepAssertion()
            }
        }
    }

    private func restoreCharging(supersedingCurrentRequest: Bool) {
        guard supersedingCurrentRequest || !isWorking else { return }
        refreshAccessState()
        guard accessState == .enabled else { return }
        let generation = beginRequest()
        isWorking = true
        let restoreAdapter = {
        self.send { proxy, reply in proxy.restoreNormal(withReply: reply) } completion: { response in
            guard self.finishRequest(generation) else { return }
            self.isWorking = false
            guard let response else {
                self.error = .helperUnavailable
                return
            }
            self.apply(response)
            if response.succeeded, response.snapshot.gate == .allowCharging {
                self.lastAppliedRequest = ChargeControlRequest(gate: .allowCharging, limitPercent: self.limitPercent)
                self.appliedGate = .allowCharging
                UserDefaults.standard.removeObject(forKey: DefaultsKey.chargeControlRecoveryNeeded)
                if !AppFeature.chargeControl.isAvailable { self.unregisterHelper() }
                self.stopIdleWorkIfPossible()
            }
        }
        }
        if usesNativeCharging {
            probeQueue.async {
                let restored = VSNativeSetChargeLimit(100)
                DispatchQueue.main.async {
                    guard generation == self.requestGeneration else { return }
                    guard restored else {
                        _ = self.finishRequest(generation)
                        self.isWorking = false
                        self.error = .controlFailed
                        return
                    }
                    restoreAdapter()
                }
            }
        } else {
            restoreAdapter()
        }
    }

    private func restoreBeforeTermination() {
        send { proxy, reply in proxy.restoreNormal(withReply: reply) } completion: { response in
            if let response, response.succeeded, response.snapshot.gate == .allowCharging {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.chargeControlRecoveryNeeded)
            }
        }
        connection?.invalidate()
        connection = nil
        releaseSleepAssertion()
    }

    private func restoreThenUnregister() {
        refreshAccessState()
        guard accessState != .notRegistered else { return }
        if accessState != .enabled {
            guard !UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded) else {
                error = .authorizationRequired
                return
            }
            unregisterHelper()
            return
        }
        restoreCharging(supersedingCurrentRequest: true)
    }

    private func unregisterHelper() {
        do {
            try Self.appService.unregister()
            UserDefaults.standard.removeObject(forKey: DefaultsKey.chargeControlHelperVersion)
            refreshAccessState()
        } catch {
            self.error = .helperUnavailable
        }
    }

    private func send(_ operation: @escaping (ChargeControlXPCProtocol, @escaping (Data) -> Void) -> Void,
                      completion: @escaping (ChargeControlResponse?) -> Void) {
        var finished = false
        let finish: (ChargeControlResponse?) -> Void = { response in
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
            finish(ChargeControlIPC.decodeResponse(data))
        }
        // launchd can keep retrying a stale registration without replying or
        // invalidating XPC. Do not leave every later control request queued forever.
        let requestConnection = connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self, weak requestConnection] in
            guard !finished else { return }
            if let requestConnection, self?.connection === requestConnection {
                requestConnection.invalidate()
                self?.connection = nil
            }
            finish(nil)
        }
    }

    private func proxy(errorHandler: @escaping (NSXPCConnection) -> Void) -> ChargeControlXPCProtocol? {
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: ChargeControlIdentifiers.helperID,
                                             options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: ChargeControlXPCProtocol.self)
            connection.setCodeSigningRequirement(ChargeControlIdentifiers.helperCodeRequirement)
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
            as? ChargeControlXPCProtocol
    }

    private func apply(_ response: ChargeControlResponse) {
        let gateChanged = response.succeeded && appliedGate != response.snapshot.gate
        snapshot = response.snapshot
        if var profile = response.snapshot.profile {
            if profile.family == .nativePowerUI { profile.supportsInhibit = nativeChargingAvailable }
            self.profile = profile
            if usesNativeCharging && (limitPercent < 80 || limitPercent % 5 != 0) {
                limitPercent = min(100, max(80, Int((Double(limitPercent) / 5).rounded()) * 5))
                UserDefaults.standard.set(limitPercent, forKey: DefaultsKey.chargeLimitPercent)
            }
        }
        error = response.error
        if response.succeeded { appliedGate = response.snapshot.gate }
        now = Date()
        if gateChanged {
            SystemMonitor.shared.powerStateDidChange()
            for delay in ChargeControlPolicy.postGateRefreshDelays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.sampleBattery(notifyMonitor: true)
                }
            }
        }
    }

    private func beginRequest() -> Int {
        requestGeneration += 1
        requestInFlight = true
        return requestGeneration
    }

    private func finishRequest(_ generation: Int) -> Bool {
        guard generation == requestGeneration else { return false }
        requestInFlight = false
        if evaluationCoalescer.consumePending() {
            DispatchQueue.main.async { [weak self] in
                self?.evaluate(refreshBattery: false)
            }
        }
        return true
    }

    private func refreshAccessState() {
        switch Self.appService.status {
        case .notRegistered: accessState = .notRegistered
        case .enabled: accessState = .enabled
        case .requiresApproval: accessState = .requiresApproval
        case .notFound: accessState = .unavailable
        @unknown default: accessState = .unavailable
        }
    }

    private func replaceRegistrationIfNeeded() -> Bool {
        let installed = UserDefaults.standard.string(forKey: DefaultsKey.chargeControlHelperVersion) ?? ""
        let current = Self.helperVersion
        guard !installed.isEmpty, installed != current,
              registrationAttemptedVersion != current else { return false }
        registrationAttemptedVersion = current
        isWorking = true
        // A pending restore must not strand an obsolete/missing helper. Keep
        // both recovery markers: the old helper restores on disconnect and the
        // replacement restores any abandoned gate before accepting requests.
        connection?.invalidate()
        connection = nil
        Self.appService.unregister { error in
            DispatchQueue.main.async {
                guard error == nil else {
                    self.isWorking = false
                    self.error = .helperUnavailable
                    return
                }
                do {
                    try Self.appService.register()
                    UserDefaults.standard.set(current, forKey: DefaultsKey.chargeControlHelperVersion)
                    self.isWorking = false
                    self.refreshAccessState()
                    if self.accessState == .enabled {
                        self.requestStatus()
                        self.evaluate()
                    }
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
            let profile = ChargeControlHardware()?.profile
            DispatchQueue.main.async {
                guard self.accessState != .enabled else { return }
                self.profile = profile
                // Unprivileged code cannot see every charging SMC key. Only the
                // helper may declare the Mac unsupported; until then offer Allow.
                if profile == nil, !PowerSampler.hasInternalBattery {
                    self.error = .noBattery
                }
            }
        }
    }

    private func sampleBattery(notifyMonitor: Bool = false) {
        hasBattery = PowerSampler.hasInternalBattery
        guard hasBattery else {
            chargePercent = nil
            isCharging = false
            externalConnected = false
            return
        }
        var reading = sampler.sample()
        let state = BatteryPowerStateMonitor.shared.state
        state.apply(to: &reading)
        let physicallyConnected = state.adapterConnected
            ?? (reading.externalConnected || reading.adapterMaxWatts != nil)
        let stateChanged = isCharging != reading.isCharging
            || externalConnected != physicallyConnected
        chargePercent = reading.chargePercent
        isCharging = reading.isCharging
        updateConnection(physicallyConnected)
        if stateChanged || notifyMonitor { SystemMonitor.shared.powerStateDidChange() }
    }

    private func updateBatteryState(_ state: BatteryPowerState) {
        if let connected = state.adapterConnected { updateConnection(connected) }
        isCharging = state.resolve(externalConnected: externalConnected, isCharging: isCharging).isCharging
    }

    private func updateConnection(_ connected: Bool) {
        // A new cable session must not inherit sailing/hysteresis from the
        // previous one, including an inhibit request that was still in flight.
        if externalConnected && !connected { connectionRevision &+= 1 }
        externalConnected = connected
    }

    private func refreshFromDefaults() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: DefaultsKey.chargeLimitEnabled) as? Bool ?? true
        limitPercent = ChargeControlPolicy.sanitizedLimit(defaults.integer(forKey: DefaultsKey.chargeLimitPercent))
        sailingEnabled = defaults.bool(forKey: DefaultsKey.chargeSailingEnabled)
        sailingRangePercent = ChargeControlPolicy.sanitizedSailingRange(
            defaults.integer(forKey: DefaultsKey.chargeSailingRangePercent),
            limit: limitPercent)
        hasBattery = PowerSampler.hasInternalBattery
    }

    private func setSailingRange(_ percent: Int, evaluateAfterChange: Bool) {
        let range = ChargeControlPolicy.sanitizedSailingRange(percent, limit: limitPercent)
        UserDefaults.standard.set(range, forKey: DefaultsKey.chargeSailingRangePercent)
        sailingRangePercent = range
        if evaluateAfterChange {
            if accessState != .enabled { ensureHelperForControl() }
            evaluate(refreshBattery: false)
        }
    }

    private func cancelTransientModes() {
        if isCalibrating || isDischargingToLimit || isToppingUp {
            mode = .limit
            releaseSleepAssertion()
        }
    }

    private func startTimerIfNeeded() {
        let active = AppFeature.chargeControl.isAvailable && hasBattery
            && (enabled || isCalibrating || isDischargingToLimit || isToppingUp)
        guard panelIsVisible || active
                || UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded) else { return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: ChargeControlPolicy.pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
            if self.accessState != .enabled {
                self.refreshAccessState()
                if self.accessState == .enabled { self.requestStatus() }
            }
            if self.appliedGate != .allowCharging { self.heartbeat() }
            self.evaluate()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopIdleWorkIfPossible() {
        guard !panelIsVisible,
              !(AppFeature.chargeControl.isAvailable && hasBattery && enabled),
              !isCalibrating, !isDischargingToLimit, !isToppingUp,
              !UserDefaults.standard.bool(forKey: DefaultsKey.chargeControlRecoveryNeeded) else { return }
        timer?.invalidate()
        timer = nil
    }

    private func takeSleepAssertion() {
        guard sleepAssertion == 0 else { return }
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Vorssaint battery calibration" as CFString,
            &assertionID)
        if result == kIOReturnSuccess { sleepAssertion = assertionID }
    }

    private func releaseSleepAssertion() {
        guard sleepAssertion != 0 else { return }
        IOPMAssertionRelease(sleepAssertion)
        sleepAssertion = 0
    }
}
