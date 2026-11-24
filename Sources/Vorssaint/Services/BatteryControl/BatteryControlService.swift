// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ServiceManagement

final class BatteryControlService: ObservableObject {
    static let shared = BatteryControlService()
    @Published private(set) var response: BatteryResponse?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var authorized = false
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var synchronized = false
    private var visible = false
    private var pending: (() -> Void)?

    var configuration: BatteryConfiguration {
        var value = UserDefaults.standard.data(forKey: DefaultsKey.batteryCareConfiguration)
            .flatMap { try? JSONDecoder().decode(BatteryConfiguration.self, from: $0) } ?? BatteryConfiguration()
        if !value.valid { value = BatteryConfiguration() }
        value.enabled = AppFeature.batteryCare.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.batteryCareEnabled)
        return value
    }
    func authorize() {
        guard AppFeature.batteryCare.isAvailable, PowerSampler.hasInternalBattery else { return }
        FanControlService.shared.authorize()
        refresh()
    }
    func appear() { visible = true; FanControlService.shared.refresh(); refresh(); startTimer() }
    func disappear() { visible = false; updateTimer() }
    func refresh() {
        authorized = SMAppService.daemon(plistName: FanControlIdentifiers.plistName).status == .enabled
        guard authorized else { return }
        send(nil) { response in
            if response.error != "restoreFailed", self.configuration.enabled || response.configuration.enabled {
                self.store(response.configuration)
            }
        }
    }
    func save(_ configuration: BatteryConfiguration, completion: ((Bool) -> Void)? = nil) {
        guard AppFeature.batteryCare.isAvailable, PowerSampler.hasInternalBattery, configuration.valid else { return }
        guard authorized else { error = "authorizationRequired"; return }
        if configuration.enabled { UserDefaults.standard.set(true, forKey: DefaultsKey.batteryCareEnabled) }
        send(BatteryRequest(configuration: configuration)) { response in
            let accepted = response.error == nil && response.configuration == configuration
            if response.error == nil {
                self.store(response.configuration)
                self.updateTimer()
            }
            completion?(accepted)
        }
    }
    func action(_ action: BatteryAction, value: Int? = nil, completion: ((Bool) -> Void)? = nil) {
        guard AppFeature.batteryCare.isAvailable, configuration.enabled, PowerSampler.hasInternalBattery else {
            error = "enableFirst"; completion?(false); return
        }
        send(BatteryRequest(action: action, value: value ?? configuration.limit)) { response in
            if response.error == nil { self.store(response.configuration) }
            completion?(response.error == nil)
        }
    }
    func syncWithPreferences() {
        let enabled = configuration.enabled
        authorized = SMAppService.daemon(plistName: FanControlIdentifiers.plistName).status == .enabled
        if authorized && enabled && !synchronized {
            synchronized = true
            send(nil) { response in
                if response.configuration.enabled {
                    self.store(response.configuration)
                } else {
                    self.send(BatteryRequest(configuration: self.configuration))
                }
                self.updateTimer()
            }
            return
        }
        if authorized {
            send(BatteryRequest(configuration: configuration)) { response in
                if response.error == nil { self.store(response.configuration) }
                self.updateTimer()
            }
        } else { updateTimer() }
        if enabled { startTimer() }
    }
    private func store(_ configuration: BatteryConfiguration) {
        // Enabled control is machine-specific; portable policy restores without activating hardware.
        var saved = configuration; saved.enabled = false
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: DefaultsKey.batteryCareConfiguration)
        UserDefaults.standard.set(configuration.enabled, forKey: DefaultsKey.batteryCareEnabled)
    }
    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 1
    }
    private func updateTimer() {
        if visible || configuration.enabled { startTimer() }
        else { timer?.invalidate(); timer = nil; connection?.invalidate(); connection = nil }
    }
    private func send(_ request: BatteryRequest?, completion: ((BatteryResponse) -> Void)? = nil) {
        guard !busy else {
            if request != nil { pending = { [weak self] in self?.send(request, completion: completion) } }
            return
        }
        busy = true
        var finished = false
        let finish: (Data?) -> Void = { data in
            DispatchQueue.main.async {
                guard !finished else { return }; finished = true
                self.busy = false
                defer {
                    let pending = self.pending; self.pending = nil; pending?()
                }
                guard let data, let response = try? JSONDecoder().decode(BatteryResponse.self, from: data) else {
                    self.error = "helperUnavailable"
                    self.connection?.invalidate(); self.connection = nil
                    return
                }
                self.response = response; self.error = response.error
                if response.error == "restoreFailed" {
                    UserDefaults.standard.set(true, forKey: DefaultsKey.batteryCareEnabled)
                }
                completion?(response)
            }
        }
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: FanControlIdentifiers.helperID, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
            connection.setCodeSigningRequirement(FanControlIdentifiers.helperCodeRequirement)
            connection.activate(); self.connection = connection
        }
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in finish(nil) }) as? FanControlXPCProtocol else { finish(nil); return }
        if let request, let data = try? JSONEncoder().encode(request) { proxy.batteryRequest(data, withReply: finish) }
        else { proxy.batteryStatus(withReply: finish) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { finish(nil) }
    }

    /// Uninstallation must restore charging before removing the shared daemon.
    static func restoreForRemoval() -> Bool {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.batteryCareEnabled) else { return true }
        guard SMAppService.daemon(plistName: FanControlIdentifiers.plistName).status == .enabled else {
            return !UserDefaults.standard.bool(forKey: DefaultsKey.batteryCareEnabled)
        }
        let connection = NSXPCConnection(machServiceName: FanControlIdentifiers.helperID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
        connection.setCodeSigningRequirement(FanControlIdentifiers.helperCodeRequirement)
        connection.activate()
        defer { connection.invalidate() }
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var succeeded = false
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in semaphore.signal() }) as? FanControlXPCProtocol,
              let data = try? JSONEncoder().encode(BatteryRequest(configuration: BatteryConfiguration())) else { return false }
        proxy.batteryRequest(data) { data in
            if let response = try? JSONDecoder().decode(BatteryResponse.self, from: data) {
                lock.withLock { succeeded = response.state == .disabled && response.error != "restoreFailed" }
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 20)
        return lock.withLock { succeeded }
    }
}
