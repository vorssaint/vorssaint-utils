// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import os
import ServiceManagement

/// Ships the chosen limits to the privileged helper and mirrors its
/// snapshots for the settings card. The helper is the fan-control daemon:
/// registration, approval and updates all go through `FanControlService`, so
/// charging asks for no second Login Items approval. The enforcing loop lives
/// in the daemon (the app may be gone), so every call here is idempotent
/// state transfer, not session keeping.
final class BatteryControlService: ObservableObject {
    typealias AccessState = FanControlService.AccessState

    static let shared = BatteryControlService()

    @Published private(set) var accessState: AccessState = .notRegistered
    @Published private(set) var snapshot = BatteryControlSnapshot.empty
    /// Whether `snapshot` came from the daemon. Until it has answered, the
    /// snapshot is a placeholder whose backend reads `.unsupported`; that must
    /// never be shown as a verdict about this Mac's hardware.
    @Published private(set) var hasLiveSnapshot = false
    @Published var error: BatteryControlError?

    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var lastAccessState = AccessState.notRegistered
    private var registrationChanges: AnyCancellable?
    private static let log = Logger(subsystem: FanControlIdentifiers.helperID,
                                    category: "ChargeLimit")

    enum BatteryControlError: String {
        case helperUnavailable
        case controlFailed
    }

    var isWorking: Bool { FanControlService.shared.isWorking }

    private init() {
        refreshAccessState()
        snapshot = storedConfigurationSnapshot
        registrationChanges = FanControlService.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
                self?.refreshAccessState()
            }
        }
    }

    deinit {
        connection?.invalidate()
        timer?.invalidate()
    }

    // MARK: Registration

    func authorize() {
        FanControlService.shared.authorize()
        refreshAccessState()
        if accessState == .enabled { applyStoredConfiguration() }
        startVisibleTimer()
    }

    func refreshAccessState() {
        switch SMAppService.daemon(plistName: FanControlIdentifiers.plistName).status {
        case .enabled: accessState = .enabled
        case .requiresApproval: accessState = .requiresApproval
        case .notRegistered, .notFound: accessState = .notRegistered
        @unknown default: accessState = .unavailable
        }
    }

    /// Runs when the feature is installed or removed, and at launch.
    func syncWithPreferences() {
        guard AppFeature.chargeLimit.isAvailable else {
            releaseHelper()
            return
        }
        // A registration that already happened: re-apply so the limit
        // survives a wiped /var/run. Offering registration is the card's job.
        refreshAccessState()
        if accessState == .enabled { applyStoredConfiguration() }
    }

    // MARK: Configuration

    var storedConfiguration: BatteryLimitState {
        guard let data = UserDefaults.standard.string(
            forKey: DefaultsKey.batteryChargeLimitConfiguration)?.data(using: .utf8),
              let stored = BatteryControlIPC.decodeLimits(data),
              BatteryLimitState.valid(stored) else {
            return BatteryLimitState(enabled: false,
                                     upper: BatteryControlCore.defaultUpper,
                                     lowerDelta: BatteryControlCore.defaultLowerDelta)
        }
        return stored
    }

    static var hasStoredConfiguration: Bool {
        !(UserDefaults.standard.string(forKey: DefaultsKey.batteryChargeLimitConfiguration) ?? "").isEmpty
    }

    private var storedConfigurationSnapshot: BatteryControlSnapshot {
        var result = BatteryControlSnapshot.empty
        result.limits = storedConfiguration
        return result
    }

    /// The daemon survives on its own, but the re-apply costs one XPC round
    /// trip and papers over a wiped /var/run.
    private func applyStoredConfiguration() {
        apply(storedConfiguration)
    }

    func apply(_ limits: BatteryLimitState) {
        guard BatteryLimitState.valid(limits) else {
            error = .controlFailed
            return
        }
        send { proxy, reply in
            proxy.applyChargeLimits(BatteryControlIPC.encode(limits), withReply: reply)
        } completion: { [weak self] response in
            guard let self else { return }
            self.snapshot = response
            self.error = response.lastFault != "none" ? .controlFailed : self.error
        }
        UserDefaults.standard.set(String(data: BatteryControlIPC.encode(limits),
                                         encoding: .utf8),
                                  forKey: DefaultsKey.batteryChargeLimitConfiguration)
    }

    // MARK: Status polling

    /// The visible card starts (and the page leaving stops) a slow refresh.
    /// Approval can flip `requiresApproval` to `enabled` while the card sits
    /// open in front of the user, so the loop re-reads the access state too.
    func setObserved(_ observed: Bool) {
        if observed {
            refresh()
            startVisibleTimer()
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    func refresh() {
        refreshAccessState()
        guard accessState == .enabled else { return }
        // An app update can replace the helper binary while launchd still
        // pins the one from the last approval; the fan service owns that
        // repair. Its cue is an update, or a daemon that stays unreachable:
        // without Fan Control open, nothing else would swap the old helper.
        if error == .helperUnavailable { FanControlService.shared.refresh() }
        FanControlService.shared.refreshIfHelperOutdated()
        // Just reached `enabled`: whatever the user configured before the
        // approval lands in the daemon now.
        if lastAccessState != .enabled { applyStoredConfiguration() }
        lastAccessState = accessState
        send { proxy, reply in proxy.chargeStatus(withReply: reply) } completion: { [weak self] response in
            guard let self else { return }
            self.snapshot = response
            // A helper that was down when the choice was made holds older
            // limits than the card shows: send the choice again.
            if self.hasLiveSnapshot, response.limits != self.storedConfiguration {
                self.applyStoredConfiguration()
            }
        }
    }

    private func startVisibleTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: XPC plumbing

    private func send(block: @escaping (FanControlXPCProtocol,
                                        @escaping (Data) -> Void) -> Void,
                      completion: @escaping (BatteryControlSnapshot) -> Void) {
        guard let proxy = proxy(errorHandler: {
            DispatchQueue.main.async {
                self.hasLiveSnapshot = false
                self.error = .helperUnavailable
            }
        }) else {
            hasLiveSnapshot = false
            error = .helperUnavailable
            return
        }
        block(proxy) { data in
            DispatchQueue.main.async {
                let decoded = BatteryControlIPC.decodeSnapshot(data)
                self.hasLiveSnapshot = decoded != nil
                if decoded != nil, self.error == .helperUnavailable { self.error = nil }
                completion(decoded ?? .empty)
            }
        }
    }

    private func proxy(errorHandler: @escaping () -> Void) -> FanControlXPCProtocol? {
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: FanControlIdentifiers.helperID,
                                             options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
            connection.setCodeSigningRequirement(FanControlIdentifiers.helperCodeRequirement)
            let forget = { [weak self, weak connection] in
                DispatchQueue.main.async {
                    guard let connection, self?.connection === connection else { return }
                    connection.invalidate()
                    self?.connection = nil
                }
            }
            connection.interruptionHandler = forget
            connection.invalidationHandler = forget
            connection.activate()
            self.connection = connection
        }
        guard let connection else { return nil }
        return connection.remoteObjectProxyWithErrorHandler { error in
            Self.log.error("xpc: call failed — \(String(describing: error), privacy: .public)")
            // A dead remote must release the connection object, or every
            // later request keeps failing on the same zombie.
            connection.invalidate()
            DispatchQueue.main.async { if self.connection === connection { self.connection = nil } }
            errorHandler()
        } as? FanControlXPCProtocol
    }

    // MARK: Removal

    /// The feature was removed: charging goes back to platform defaults and
    /// the stored choice is dropped. Fan control owns the daemon's
    /// registration, so it decides whether the daemon stays.
    private func releaseHelper() {
        guard Self.hasStoredConfiguration else { return }
        refreshAccessState()
        let finish = {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.batteryChargeLimitConfiguration)
            FanControlService.shared.syncWithPreferences()
        }
        guard accessState == .enabled else { return finish() }
        send { proxy, reply in proxy.restoreCharging(withReply: reply) } completion: { _ in finish() }
    }
}
