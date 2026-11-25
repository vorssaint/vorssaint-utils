// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit
import ObjectiveC

protocol BatteryNativeControl {
    func read() throws -> BatteryNativeLimit.Setting
    func apply(_ setting: BatteryNativeLimit.Setting) throws
}

/// Runtime-checked PowerUI bridge. No private framework is linked into the app.
final class BatteryNativeLimit: BatteryNativeControl {
    struct Setting: Codable { var enabled: Bool; var limit: Int }
    private typealias ReadByte = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> UInt8
    private typealias ReadWord = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> UInt64
    private typealias Write = @convention(c) (AnyObject, Selector, UInt8, UnsafeMutablePointer<NSError?>) -> Bool
    private typealias Toggle = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> Bool
    private let client: NSObject

    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_LAZY) != nil,
              let type = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else { return nil }
        typealias Create = @convention(c) (AnyObject, Selector, NSString) -> AnyObject?
        guard let object = type.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject else { return nil }
        let selector = NSSelectorFromString("initWithClientName:")
        guard object.responds(to: selector),
              let instance = unsafeBitCast(object.method(for: selector), to: Create.self)(object, selector, "Vorssaint") as? NSObject,
              ["isMCLSupported", "getMCLLimitWithError:", "isMCLCurrentlyEnabled:", "setMCLLimit:error:", "enableMCL:", "disableMCL:"]
                .allSatisfy({ instance.responds(to: NSSelectorFromString($0)) }) else { return nil }
        typealias Supported = @convention(c) (AnyObject, Selector) -> Bool
        let supported = NSSelectorFromString("isMCLSupported")
        guard unsafeBitCast(instance.method(for: supported), to: Supported.self)(instance, supported) else { return nil }
        client = instance
    }

    // Allows the selector bridge to be tested without sending hardware requests.
    init(client: NSObject) { self.client = client }

    private func method<T>(_ name: String, _ type: T.Type) -> T {
        unsafeBitCast(client.method(for: NSSelectorFromString(name)), to: type)
    }
    func read() throws -> Setting {
        var error: NSError?
        let limit = method("getMCLLimitWithError:", ReadByte.self)(client, NSSelectorFromString("getMCLLimitWithError:"), &error)
        if let error { throw BatteryHardwareError.operation("PowerUI getMCLLimit: \(BatteryHardwareError.describe(error))") }
        let enabled = method("isMCLCurrentlyEnabled:", ReadWord.self)(client, NSSelectorFromString("isMCLCurrentlyEnabled:"), &error)
        if let error { throw BatteryHardwareError.operation("PowerUI isMCLCurrentlyEnabled: \(BatteryHardwareError.describe(error))") }
        guard enabled == 0 || (20...100).contains(Int(limit)) else { throw BatteryHardwareError.unavailable }
        return Setting(enabled: enabled != 0, limit: (20...100).contains(Int(limit)) ? Int(limit) : 100)
    }
    func apply(_ setting: Setting) throws {
        guard (20...100).contains(setting.limit) else { throw BatteryHardwareError.unavailable }
        let previous = try read()
        if setting.enabled {
            if previous.limit != setting.limit && !(previous.enabled && (setting.limit < 80 || setting.limit % 5 != 0)) {
                var error: NSError?
                let apiLimit = setting.limit < 80 || setting.limit % 5 != 0 ? 80 : setting.limit
                let accepted = method("setMCLLimit:error:", Write.self)(client, NSSelectorFromString("setMCLLimit:error:"), UInt8(apiLimit), &error)
                guard accepted, error == nil else {
                    throw BatteryHardwareError.operation("PowerUI setMCLLimit(\(apiLimit)): \(error.map(BatteryHardwareError.describe) ?? "request rejected")")
                }
            }
            // Setting the limit can enable it; check the new state before enabling again.
            if try !read().enabled { try toggle("enableMCL:") }
            if setting.limit < 80 || setting.limit % 5 != 0 {
                // PowerUI's selector imposes an 80% floor. The agent's native preference
                // accepts a lower limit; require readback before reporting success.
                let domain = "com.apple.smartcharging.topoffprotection" as CFString
                let key = "mclLimitValue" as CFString
                let host = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) == nil
                    ? kCFPreferencesAnyHost : kCFPreferencesCurrentHost
                CFPreferencesSetValue(key, setting.limit as CFNumber, domain, kCFPreferencesCurrentUser, host)
                guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, host) else { throw BatteryHardwareError.operation("PowerUI limit preferences could not be saved") }
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName("com.apple.smartcharging.defaultschanged" as CFString), nil, nil, true)
            }
        } else {
            // A disabled limit has no active target. Do not enable a new limit during recovery or top-up.
            if previous.enabled { try toggle("disableMCL:") }
        }
        for _ in 0..<20 {
            let actual = try read()
            if actual.enabled == setting.enabled && (!setting.enabled || actual.limit == setting.limit) { return }
            usleep(100_000)
        }
        let actual = try read()
        throw BatteryHardwareError.operation("PowerUI readback: requested enabled=\(setting.enabled), limit=\(setting.limit); received enabled=\(actual.enabled), limit=\(actual.limit)")
    }
    private func toggle(_ name: String) throws {
        var error: NSError?
        guard method(name, Toggle.self)(client, NSSelectorFromString(name), &error), error == nil else {
            throw BatteryHardwareError.operation("PowerUI \(name): \(error.map(BatteryHardwareError.describe) ?? "request rejected")")
        }
    }
}

enum BatteryHardwareError: LocalizedError {
    case unavailable, rejected, competingController, operation(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The requested battery control or telemetry is unavailable."
        case .rejected: return "The battery controller rejected the operation."
        case .competingController: return "Another controller may own the battery controls."
        case .operation(let message): return message
        }
    }
    static func describe(_ error: Error) -> String {
        if let error = error as? BatteryHardwareError { return error.localizedDescription }
        if let error = error as? SMCClient.WriteError { return String(describing: error) }
        let value = error as NSError
        return "\(value.domain) (\(value.code)): \(value.localizedDescription)"
    }
}

protocol BatterySMCIO {
    func key(named: String) -> SMCClient.Key?
    func readBytes(_ key: SMCClient.Key) -> [UInt8]?
    func readValue(_ key: SMCClient.Key) -> Double?
    func writeBytes(_ bytes: [UInt8], to key: SMCClient.Key) throws
}
extension SMCClient: BatterySMCIO {}

final class BatteryControlHardware {
    struct Baseline: Codable {
        var native: BatteryNativeLimit.Setting?
        var inhibit: [String: [UInt8]] = [:]
        var adapter: [UInt8]?
        var led: [UInt8]?
        var ledOverridden: Bool? = nil // nil preserves recovery of older saved records.
    }
    private let smc: BatterySMCIO?
    private let native: BatteryNativeControl?
    private var adapter: (key: SMCClient.Key, off: UInt8)?
    private var inhibit: [SMCClient.Key] = []
    private var led: SMCClient.Key?
    private var appliedLimit: Int?
    private var holding = false
    private var lastLED: BatteryLED?
    private var touchedLED = false

    init(smc: BatterySMCIO? = SMCClient(), native: BatteryNativeControl? = BatteryNativeLimit()) {
        self.smc = smc; self.native = native
        guard let smc else { return }
        for (name, value) in [("CHIE", UInt8(8)), ("CH0I", UInt8(1)), ("CH0J", UInt8(1))] {
            if let key = smc.key(named: name), key.dataSize == 1 { adapter = (key, value); break }
        }
        inhibit = ["CH0B", "CH0C"].compactMap { name in
            guard let key = smc.key(named: name), key.dataSize == 1 else { return nil }
            return key
        }
        if inhibit.count != 2 { inhibit = [] }
        if let key = smc.key(named: "CHTE"), key.dataSize == 4 { inhibit = [key] }
        if let key = smc.key(named: "ACLC"), key.dataSize == 1 { led = key }
    }
    var supportsLimit: Bool { native != nil || !inhibit.isEmpty }
    var supportsDischarge: Bool { adapter != nil }
    var supportsLED: Bool { led != nil }

    func baseline() throws -> Baseline {
        var result = Baseline(native: try native?.read(), ledOverridden: false)
        if let smc {
            for key in inhibit {
                guard let bytes = smc.readBytes(key), bytes.allSatisfy({ $0 == 0 }) else { throw BatteryHardwareError.competingController }
                result.inhibit[key.name] = bytes
            }
            if let adapter {
                guard let bytes = smc.readBytes(adapter.key), bytes == [0] else { throw BatteryHardwareError.competingController }
                result.adapter = bytes
            }
            if let led { result.led = smc.readBytes(led) }
        }
        guard supportsLimit else { throw BatteryHardwareError.unavailable }
        return result
    }
    func restore(_ baseline: Baseline) throws {
        // Reconnect wall power first, even if another restoration fails.
        var failures: [String] = []
        if let adapter, let bytes = baseline.adapter { do { try write(bytes, key: adapter.key) } catch { failures.append(BatteryHardwareError.describe(error)) } }
        for key in inhibit {
            if let bytes = baseline.inhibit[key.name] { do { try write(bytes, key: key) } catch { failures.append(BatteryHardwareError.describe(error)) } }
        }
        if (baseline.ledOverridden != false || touchedLED), let led, let bytes = baseline.led { do { try write(bytes, key: led) } catch { failures.append(BatteryHardwareError.describe(error)) } }
        if let native, let setting = baseline.native { do { try native.apply(setting) } catch { failures.append(BatteryHardwareError.describe(error)) } }
        appliedLimit = nil; lastLED = nil; holding = false
        if !failures.isEmpty { throw BatteryHardwareError.operation(failures.joined(separator: "; ")) }
        touchedLED = false
    }
    func apply(_ decision: BatteryDecision, reading: BatteryTelemetry, led desiredLED: BatteryLED) throws {
        guard (20...100).contains(decision.limit), reading.valid else { throw BatteryHardwareError.unavailable }
        // Native limits retain external power. Never simulate a charge hold by
        // draining the battery; adapter disconnection is an explicit operation.
        if let adapter { try write([decision.disconnectAdapter ? adapter.off : 0], key: adapter.key) }
        else if decision.disconnectAdapter { throw BatteryHardwareError.unavailable }
        if let native {
            let setting = try native.read()
            if appliedLimit != decision.limit || setting.enabled != (decision.limit < 100)
                || (setting.enabled && setting.limit != decision.limit) {
                try native.apply(.init(enabled: decision.limit < 100, limit: decision.limit))
                appliedLimit = decision.limit
            }
        } else {
            guard !inhibit.isEmpty else { throw BatteryHardwareError.unavailable }
            if reading.percent >= decision.limit && decision.limit < 100 { holding = true }
            if reading.percent < decision.limit || decision.limit == 100 { holding = false }
            for key in inhibit {
                var bytes = [UInt8](repeating: 0, count: Int(key.dataSize))
                if holding { bytes[0] = key.name == "CHTE" ? 1 : 2 }
                try write(bytes, key: key)
            }
        }
        if desiredLED != lastLED {
            // Automatic leaves the system LED alone until we have applied an override.
            if let led, desiredLED != .automatic || (lastLED != nil && lastLED != .automatic) {
                let values: [BatteryLED: UInt8] = [.automatic: 0, .off: 1, .green: 3, .orange: 4, .blinking: 7]
                touchedLED = true
                try write([values[desiredLED]!], key: led)
            } else if desiredLED != .automatic { throw BatteryHardwareError.unavailable }
            lastLED = desiredLED
        }
    }
    private func write(_ bytes: [UInt8], key: SMCClient.Key) throws {
        guard let smc else { throw BatteryHardwareError.unavailable }
        if smc.readBytes(key) == bytes { return }
        do { try smc.writeBytes(bytes, to: key) }
        catch { throw BatteryHardwareError.operation("SMC write \(key.name): \(BatteryHardwareError.describe(error))") }
        let actual = smc.readBytes(key)
        guard actual == bytes else {
            throw BatteryHardwareError.operation("SMC readback \(key.name): requested \(bytes), received \(actual.map { String(describing: $0) } ?? "unavailable")")
        }
    }
    func sample() -> BatteryTelemetry? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var raw: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let p = raw?.takeRetainedValue() as? [String: Any], p["BatteryInstalled"] as? Bool == true,
              let current = p["CurrentCapacity"] as? Int, let maximum = p["MaxCapacity"] as? Int, maximum > 0 else { return nil }
        func sensor(_ name: String) -> Double? {
            guard let smc, let key = smc.key(named: name) else { return nil }
            return smc.readValue(key)
        }
        let percent = Int((Double(current) * 100 / Double(maximum)).rounded())
        let voltage = (p["Voltage"] as? Double).map { $0 / 1000 }
        let currentAmps = (p["Amperage"] as? NSNumber).map { Double(Int64(bitPattern: $0.uint64Value)) / 1000 }
        let data = p["BatteryData"] as? [String: Any] ?? [:]
        let design = p["DesignCapacity"] as? Double ?? data["DesignCapacity"] as? Double
        let full = p["NominalChargeCapacity"] as? Double ?? p["AppleRawMaxCapacity"] as? Double
        let rawCurrent = p["AppleRawCurrentCapacity"] as? Double
        let rawMax = p["AppleRawMaxCapacity"] as? Double
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        var closed = false
        if root != 0 {
            closed = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool ?? false
            IOObjectRelease(root)
        }
        let attached = sensor("AC-W").map { $0 > 0 } ?? (p["ExternalConnected"] as? Bool ?? false)
        let charging = p["IsCharging"] as? Bool ?? false
        let minutes = p["AvgTimeToFull"] as? Int
        return .init(percent: percent, temperature: sensor("TB0T"), adapterConnected: attached,
                     charging: charging, full: percent >= 100 && !charging && (currentAmps ?? 1) <= 0.05,
                     clamshell: closed, watts: voltage.flatMap { v in currentAmps.map { v * $0 } }, voltage: voltage,
                     cycles: p["CycleCount"] as? Int,
                     health: design.flatMap { d in d > 0 ? full.map { min(100, $0 * 100 / d) } : nil },
                     hardwarePercent: rawMax.flatMap { m in m > 0 ? rawCurrent.map { $0 * 100 / m } : nil },
                     adapterWatts: (p["AdapterDetails"] as? [String: Any])?["Watts"] as? Double,
                     minutesToFull: minutes.flatMap { (0..<65535).contains($0) ? $0 : nil })
    }
}
