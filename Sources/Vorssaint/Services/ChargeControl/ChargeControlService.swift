// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import IOKit
import IOKit.ps
import ServiceManagement

enum ChargeControlStatus: Equatable {
    case uninstalled, disabled, charging, paused, discharging, onBattery, systemConflict, approvalRequired,
         unsupportedHardware, helperUnavailable, controlFailed
}

final class ChargeControlService: ObservableObject {
    enum AccessState: Equatable { case notRegistered, requiresApproval, enabled, unavailable }
    static let shared = ChargeControlService()

    @Published private(set) var status: ChargeControlStatus = .uninstalled
    @Published private(set) var accessState: AccessState = .notRegistered
    @Published private(set) var percent: Int?
    @Published private(set) var isPluggedIn = false
    @Published private(set) var api: ChargeControlAPI = .unavailable
    @Published private(set) var isWorking = false
    @Published private(set) var sessionAction: ChargeControlSessionAction = .normal

    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var previousMode: ChargeControlMode = .charging
    private var tick = 0
    private var requestInFlight = false
    private var pendingMode: ChargeControlMode?
    private var openedApprovalSettings = false
    private var lastChargingCommandAt: TimeInterval?
    private var helperUpgradeInProgress = false
    private var registrationRetryCount = 0
    private var registrationRetryWorkItem: DispatchWorkItem?

    private static var appService: SMAppService {
        SMAppService.daemon(plistName: ChargeControlIdentifiers.plistName)
    }

    private static var helperVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "VorssaintChargeControlHelperVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? AppInfo.version
    }

    private init() {
        refreshAccessState()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
    }

    deinit {
        timer?.invalidate()
        connection?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    var enabled: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.chargeLimitEnabled) }
    var limit: Int { ChargeLimitPolicy.sanitizedLimit(UserDefaults.standard.integer(forKey: DefaultsKey.chargeLimitPercent)) }
    var canStartDischarge: Bool {
        enabled && accessState == .enabled && isPluggedIn && (percent ?? 0) > limit
    }

    var canStartTopUp: Bool {
        enabled && accessState == .enabled && isPluggedIn && (percent ?? 100) < 100
    }

    func startDischargeToLimit() {
        guard canStartDischarge else { return }
        sessionAction = .dischargeToLimit
        ensureHelperRegistered()
        startTimer()
        evaluate()
    }

    func cancelDischarge() {
        guard sessionAction == .dischargeToLimit else { return }
        sessionAction = .normal
        evaluate()
    }

    func startTopUp() {
        guard canStartTopUp else { return }
        sessionAction = .topUp
        ensureHelperRegistered()
        startTimer()
        evaluate()
    }

    func cancelTopUp() {
        guard sessionAction == .topUp else { return }
        sessionAction = .normal
        evaluate()
    }

    func syncWithPreferences() {
        guard AppFeature.batteryChargeLimit.isAvailable else {
            sessionAction = .normal
            restoreAndStop(unregister: true)
            status = .uninstalled
            return
        }
        ensureHelperRegistered()
        guard enabled else {
            sessionAction = .normal
            restoreAndStop(unregister: false)
            status = .disabled
            return
        }
        refreshAccessState()
        guard accessState == .enabled else {
            status = accessState == .requiresApproval ? .approvalRequired : .helperUnavailable
            openApprovalSettingsIfNeeded()
            return
        }
        startTimer()
        evaluate()
    }

    func authorize() {
        ensureHelperRegistered()
        refreshAccessState()
        openApprovalSettingsIfNeeded()
        if accessState == .enabled { connect(restoringFirst: true); startTimer(); evaluate() }
    }

    func restoreSystemCharging() { restoreAndStop(unregister: false) }

    func evaluate() {
        guard AppFeature.batteryChargeLimit.isAvailable, enabled else { return }
        let battery = batteryState()
        percent = battery?.percent
        isPluggedIn = battery?.pluggedIn ?? false
        guard let battery else { status = .unsupportedHardware; return }
        refreshAccessState()
        guard accessState == .enabled else {
            status = accessState == .requiresApproval ? .approvalRequired : .helperUnavailable
            openApprovalSettingsIfNeeded()
            return
        }
        let displayOnline = builtInDisplayIsOnline()
        switch sessionAction {
        case .dischargeToLimit where ChargeLimitPolicy.shouldEndDischarge(
            percent: battery.percent, limit: limit, pluggedIn: battery.pluggedIn,
            builtInDisplayOnline: displayOnline):
            sessionAction = .normal
        case .topUp where ChargeLimitPolicy.shouldEndTopUp(percent: battery.percent,
                                                           pluggedIn: battery.pluggedIn):
            sessionAction = .normal
        default: break
        }
        var desired: ChargeControlMode
        switch sessionAction {
        case .dischargeToLimit: desired = .discharging
        case .topUp: desired = .charging
        case .normal:
            desired = ChargeLimitPolicy.desiredMode(percent: battery.percent,
                                                    limit: limit,
                                                    pluggedIn: battery.pluggedIn,
                                                    previous: previousMode)
            if desired == .discharging, !displayOnline {
                desired = .paused
            }
        }
        if !battery.pluggedIn {
            status = .onBattery
        }
        if desired == previousMode {
            if battery.pluggedIn {
                if desired == .charging, battery.percent < (sessionAction == .topUp ? 100 : limit),
                   !battery.isCharging, lastChargingCommandAt == nil {
                    send(.charging)
                    return
                }
                let elapsed = lastChargingCommandAt.map {
                    ProcessInfo.processInfo.systemUptime - $0
                }
                if ChargeLimitPolicy.shouldReportSystemConflict(
                    wantsCharging: desired == .charging
                        && battery.percent < (sessionAction == .topUp ? 100 : limit),
                    isCharging: battery.isCharging,
                    secondsSinceAllow: elapsed) {
                    status = .systemConflict
                } else {
                    status = desired == .paused ? .paused : (desired == .discharging ? .discharging : .charging)
                }
            }
            return
        }
        send(desired)
    }

    private func send(_ mode: ChargeControlMode) {
        guard !requestInFlight else {
            pendingMode = mode
            return
        }
        requestInFlight = true
        if mode == .charging {
            lastChargingCommandAt = ProcessInfo.processInfo.systemUptime
        } else {
            lastChargingCommandAt = nil
        }
        proxy { proxy, reply in
            switch mode {
            case .paused: proxy.pauseCharging(withReply: reply)
            case .discharging: proxy.startDischarging(withReply: reply)
            case .charging: proxy.allowCharging(withReply: reply)
            }
        } completion: { response in
            self.requestInFlight = false
            defer {
                if let pending = self.pendingMode {
                    self.pendingMode = nil
                    self.send(pending)
                }
            }
            guard let response else { self.status = .helperUnavailable; return }
            self.api = response.api
            if response.succeeded {
                self.previousMode = response.mode
                self.status = response.mode == .paused ? .paused
                    : (response.mode == .discharging ? .discharging : (self.isPluggedIn ? .charging : .onBattery))
            } else {
                self.status = response.error == .unsupportedHardware ? .unsupportedHardware : .controlFailed
            }
        }
    }

    private func heartbeat() {
        proxy({ $0.heartbeat(withReply: $1) }) { response in
            guard let response else { self.status = .helperUnavailable; return }
            self.api = response.api
        }
    }

    private func restoreAndStop(unregister: Bool) {
        sessionAction = .normal
        timer?.invalidate(); timer = nil
        if accessState == .enabled {
            proxy({ $0.restoreSystemDefault(withReply: $1) }) { _ in }
        }
        previousMode = .charging
        connection?.invalidate(); connection = nil
        if unregister { try? Self.appService.unregister(); refreshAccessState() }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            self.evaluate()
            if self.tick.isMultiple(of: 2) { self.heartbeat() }
        }
    }

    private func connect(restoringFirst: Bool = false) {
        guard connection == nil else { return }
        let connection = NSXPCConnection(machServiceName: ChargeControlIdentifiers.helperID,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ChargeControlXPCProtocol.self)
        connection.setCodeSigningRequirement(ChargeControlIdentifiers.helperCodeRequirement)
        connection.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.connection = nil } }
        connection.resume()
        self.connection = connection
        if restoringFirst {
            proxy({ $0.restoreSystemDefault(withReply: $1) }) { _ in
                self.previousMode = .charging
                self.lastChargingCommandAt = ProcessInfo.processInfo.systemUptime
                self.evaluate()
            }
        }
    }

    private func proxy(_ operation: @escaping (ChargeControlXPCProtocol, @escaping (Data) -> Void) -> Void,
                       completion: @escaping (ChargeControlResponse?) -> Void) {
        connect()
        guard let connection else { completion(nil); return }
        let error: (Error) -> Void = { _ in DispatchQueue.main.async { completion(nil) } }
        guard let remote = connection.remoteObjectProxyWithErrorHandler(error) as? ChargeControlXPCProtocol else {
            completion(nil); return
        }
        operation(remote) { data in
            let response = ChargeControlIPC.decode(data)
            DispatchQueue.main.async { completion(response) }
        }
    }

    private func refreshAccessState() {
        switch Self.appService.status {
        case .notRegistered: accessState = .notRegistered
        case .requiresApproval: accessState = .requiresApproval
        case .enabled: accessState = .enabled
        case .notFound: accessState = .unavailable
        @unknown default: accessState = .unavailable
        }
    }

    private func ensureHelperRegistered() {
        refreshAccessState()
        let installedVersion = UserDefaults.standard.string(
            forKey: DefaultsKey.chargeControlHelperVersion) ?? ""
        if !helperUpgradeInProgress,
           accessState != .notRegistered, accessState != .unavailable,
           installedVersion != Self.helperVersion {
            helperUpgradeInProgress = true
            connection?.invalidate()
            connection = nil
            try? Self.appService.unregister()
            UserDefaults.standard.removeObject(forKey: DefaultsKey.chargeControlHelperVersion)
            refreshAccessState()
            scheduleRegistrationRetry()
            return
        }
        if helperUpgradeInProgress,
           accessState != .notRegistered, accessState != .unavailable {
            scheduleRegistrationRetry()
            return
        }
        guard accessState == .notRegistered || accessState == .unavailable else { return }
        do {
            try Self.appService.register()
            UserDefaults.standard.set(Self.helperVersion,
                                      forKey: DefaultsKey.chargeControlHelperVersion)
            helperUpgradeInProgress = false
            registrationRetryCount = 0
            refreshAccessState()
        } catch {
            refreshAccessState()
            if helperUpgradeInProgress || registrationRetryCount < 10 {
                scheduleRegistrationRetry()
            } else {
                status = .helperUnavailable
            }
        }
    }

    /// Service Management removes a daemon asynchronously. Registering its
    /// replacement before the old BTM record disappears leaves launchd with a
    /// stale lightweight code requirement and the new helper exits EX_CONFIG.
    private func scheduleRegistrationRetry() {
        guard registrationRetryWorkItem == nil, registrationRetryCount < 10 else {
            if registrationRetryCount >= 10 { status = .helperUnavailable }
            return
        }
        registrationRetryCount += 1
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.registrationRetryWorkItem = nil
            self.ensureHelperRegistered()
            if self.accessState == .enabled {
                self.connect(restoringFirst: true)
                self.startTimer()
            }
        }
        registrationRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func openApprovalSettingsIfNeeded() {
        guard accessState == .requiresApproval, !openedApprovalSettings else { return }
        openedApprovalSettings = true
        SMAppService.openSystemSettingsLoginItems()
    }

    private func batteryState() -> (percent: Int, pluggedIn: Bool, isCharging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            return (Int((Double(current) / Double(maximum) * 100).rounded()),
                    physicalAdapterIsPresent(fallback: state == kIOPSACPowerValue), charging)
        }
        return nil
    }

    /// Forced discharge intentionally makes IOPS report Battery Power and sets
    /// ExternalConnected to false even though the cable is still attached. The
    /// adapter descriptor remains present in AppleSmartBattery, so use it to
    /// distinguish forced discharge from a real unplug event.
    private func physicalAdapterIsPresent(fallback: Bool) -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return fallback }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service, "AdapterDetails" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let details = value as? [String: Any] else { return fallback }
        if let watts = details["Watts"] as? Int { return watts > 0 }
        return !details.isEmpty
    }

    private func builtInDisplayIsOnline() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 }
    }

    @objc private func didWake() { evaluate() }
    @objc private func willSleep() {
        if sessionAction == .dischargeToLimit || previousMode == .discharging {
            sessionAction = .normal
            send(.paused)
        }
    }
}
