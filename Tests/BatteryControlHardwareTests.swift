// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BatteryControlHardwareTests {
    private final class Device: BatterySMCIO {
        var bytes: [String: [UInt8]]
        var writes: [String] = []
        var fail: Set<String> = []
        var ignoreWrites = false
        init(_ values: [String: [UInt8]]) { bytes = values }
        func key(named name: String) -> SMCClient.Key? {
            bytes[name].map { SMCClient.Key(code: 0, name: name, dataSize: UInt32($0.count), dataType: "ui8 ") }
        }
        func readBytes(_ key: SMCClient.Key) -> [UInt8]? { bytes[key.name] }
        func readValue(_ key: SMCClient.Key) -> Double? { bytes[key.name]?.first.map(Double.init) }
        func writeBytes(_ values: [UInt8], to key: SMCClient.Key) throws {
            writes.append(key.name)
            if fail.contains(key.name) { throw BatteryHardwareError.rejected }
            if !ignoreWrites { bytes[key.name] = values }
        }
    }
    private final class NativeClient: NSObject {
        var enabled: UInt64 = 0
        var limit: UInt8 = 80
        var calls: [String] = []
        @objc(getMCLLimitWithError:)
        func readLimit(_ error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8 { limit }
        @objc(isMCLCurrentlyEnabled:)
        func readEnabled(_ error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt64 { enabled }
        @objc(setMCLLimit:error:)
        func setLimit(_ value: UInt8, error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool {
            calls.append("set")
            // Model an API that rejects 100 and enables the limit when setting it.
            guard value < 100 else { return false }
            limit = value; enabled = 1; return true
        }
        @objc(enableMCL:)
        func enable(_ error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool {
            calls.append("enable")
            guard enabled == 0 else { return false }
            enabled = 1; return true
        }
        @objc(disableMCL:)
        func disable(_ error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool {
            calls.append("disable"); enabled = 0; return true
        }
    }
    private final class Native: BatteryNativeControl {
        var setting = BatteryNativeLimit.Setting(enabled: false, limit: 100)
        var applied: [BatteryNativeLimit.Setting] = []
        var failure: Error?
        func read() throws -> BatteryNativeLimit.Setting { setting }
        func apply(_ setting: BatteryNativeLimit.Setting) throws {
            if let failure { throw failure }
            applied.append(setting); self.setting = setting
        }
    }
    static func run(_ t: TestSuite) {
        let device = Device(["CH0B": [0], "CH0C": [0], "CHIE": [0], "ACLC": [0]])
        let hardware = BatteryControlHardware(smc: device, native: nil)
        t.expect(hardware.supportsLimit && hardware.supportsDischarge && hardware.supportsLED, "discovers independent control capabilities")
        do {
            let baseline = try hardware.baseline()
            try hardware.apply(.init(state: .holding, limit: 80), reading: BatteryControlTests.reading(85), led: .green)
            t.expect(device.bytes["CH0B"] == [2] && device.bytes["CH0C"] == [2], "both legacy charging gates pause together")
            t.expect(device.bytes["CHIE"] == [0], "holding charge leaves adapter connected")
            t.expect(device.bytes["ACLC"] == [3], "LED uses the known green value")
            try hardware.apply(.init(state: .discharging, limit: 80, disconnectAdapter: true), reading: BatteryControlTests.reading(90), led: .green)
            t.expect(device.bytes["CHIE"] == [8], "only explicit discharge cuts adapter power")
            try hardware.apply(.init(state: .charging, limit: 80), reading: BatteryControlTests.reading(70), led: .automatic)
            t.expect(device.bytes["CHIE"] == [0] && device.bytes["CH0C"] == [0], "resume reconnects the adapter and releases charging gates")
            try hardware.restore(baseline)
            t.expect(device.bytes.values.allSatisfy { $0 == [0] }, "restores all original bytes")
            device.bytes["CHIE"] = [8]; device.bytes["CH0B"] = [2]; device.bytes["CH0C"] = [2]; device.bytes["ACLC"] = [4]
            device.fail = ["CH0B"]; device.writes = []
            var recovery = baseline; recovery.ledOverridden = nil // Older recovery records must still restore the LED.
            do { try hardware.restore(recovery); t.expect(false, "restore must report a rejected write") } catch {}
            t.expect(device.writes.first == "CHIE", "recovery reconnects external power before other controls")
            t.expect(device.bytes["CH0C"] == [0] && device.bytes["ACLC"] == [0], "one failed restore does not skip the other controls")
        } catch { t.expect(false, "normal control fixture failed: \(error)") }

        let modern = Device(["CHTE": [0, 0, 0, 0]])
        let modernHardware = BatteryControlHardware(smc: modern, native: nil)
        do {
            let baseline = try modernHardware.baseline()
            try modernHardware.apply(.init(state: .holding, limit: 80), reading: BatteryControlTests.reading(85), led: .automatic)
            t.expect(modern.bytes["CHTE"] == [1, 0, 0, 0], "uses the full four-byte CHTE payload")
            try modernHardware.restore(baseline)
            t.expect(modern.bytes["CHTE"] == [0, 0, 0, 0], "restores four-byte gate")
        } catch { t.expect(false, "modern fixture failed: \(error)") }
        for values: [String: [UInt8]] in [["CH0B": [0]], ["CHTE": [0]], [:]] {
            t.expect(!BatteryControlHardware(smc: Device(values), native: nil).supportsLimit, "partial or wrong-size interfaces are unsupported")
        }
        let controlled = BatteryControlHardware(smc: Device(["CH0B": [2], "CH0C": [2]]), native: nil)
        do { _ = try controlled.baseline(); t.expect(false, "must not overwrite another charge controller") } catch {}
        let stale = Device(["CH0B": [0], "CH0C": [0]])
        stale.ignoreWrites = true
        let staleHardware = BatteryControlHardware(smc: stale, native: nil)
        do {
            try staleHardware.apply(.init(state: .holding, limit: 80), reading: BatteryControlTests.reading(90), led: .automatic)
            t.expect(false, "successful transport with unchanged readback must fail")
        } catch { t.expect(true, "readback mismatch is rejected") }
        let client = NativeClient()
        let bridge = BatteryNativeLimit(client: client)
        do {
            try bridge.apply(.init(enabled: true, limit: 90))
            t.expect(client.calls == ["set"] && client.enabled == 1, "setting an enabled native limit does not redundantly enable it")
            client.calls = []
            try bridge.apply(.init(enabled: false, limit: 100))
            t.expect(client.calls == ["disable"] && client.enabled == 0, "native top-up does not set or enable 100 before disabling")
            client.calls = []
            try bridge.apply(.init(enabled: false, limit: 80))
            t.expect(client.calls.isEmpty, "restoring an already disabled native limit makes no mutating calls")
            try bridge.apply(.init(enabled: true, limit: 90))
            t.expect(client.calls == ["enable"], "an unchanged but disabled native limit can still be enabled")
        } catch { t.expect(false, "native selector fixture failed: \(error)") }

        // A readable MagSafe LED is not necessarily writable. Normal native
        // limits must work without trying to override its current system color.
        let native = Native()
        let nativeDevice = Device(["CHIE": [0], "ACLC": [4]])
        nativeDevice.fail = ["ACLC"]
        let nativeHardware = BatteryControlHardware(smc: nativeDevice, native: native)
        do {
            let baseline = try nativeHardware.baseline()
            try nativeHardware.apply(.init(state: .charging, limit: 90), reading: BatteryControlTests.reading(43), led: .automatic)
            t.expect(native.setting.enabled && native.setting.limit == 90, "native limit succeeds with a read-only system LED")
            t.expect(nativeDevice.writes.isEmpty, "ordinary native charging does not write SMC controls")
            try nativeHardware.apply(.init(state: .charging, limit: 90), reading: BatteryControlTests.reading(44), led: .automatic)
            t.expect(native.applied.count == 1, "unchanged native limit is not reapplied on every sample")
            try nativeHardware.apply(.init(state: .topUp, limit: 100), reading: BatteryControlTests.reading(44), led: .automatic)
            t.expect(!native.setting.enabled, "top-up disables the native limit")
            nativeDevice.bytes["ACLC"] = [3] // The system may change its own light during charging.
            try nativeHardware.restore(baseline)
            t.expect(!native.setting.enabled && nativeDevice.writes.isEmpty, "restore preserves system control without an LED write")
            nativeDevice.bytes["ACLC"] = [4]
            do {
                try nativeHardware.apply(.init(state: .charging, limit: 90), reading: BatteryControlTests.reading(43), led: .green)
                t.expect(false, "explicit unsupported LED override must report failure")
            } catch {
                t.expect(BatteryHardwareError.describe(error).contains("SMC write ACLC"), "LED failure identifies its operation and key")
            }
            nativeDevice.fail = []
            try nativeHardware.apply(.init(state: .charging, limit: 90), reading: BatteryControlTests.reading(43), led: .green)
            try nativeHardware.apply(.init(state: .charging, limit: 90), reading: BatteryControlTests.reading(43), led: .automatic)
            t.expect(nativeDevice.bytes["ACLC"] == [0], "automatic mode releases a previous explicit LED override")
            native.failure = BatteryHardwareError.operation("PowerUI setMCLLimit: test rejection")
            do { try nativeHardware.restore(baseline); t.expect(false, "native recovery must report failure") }
            catch { t.expect(BatteryHardwareError.describe(error).contains("PowerUI setMCLLimit"), "recovery preserves the native operation diagnostic") }
        } catch { t.expect(false, "native fixture failed: \(error)") }
        do {
            let response = BatteryResponse(configuration: .init(), state: .unavailable, mode: .automatic, phase: .firstCharge,
                                           supportsLimit: true, supportsDischarge: false, supportsLED: false, error: "failed")
            let old = try JSONEncoder().encode(response)
            t.expect(try JSONDecoder().decode(BatteryResponse.self, from: old).errorDetail == nil, "responses from older helpers remain readable")
            var updated = response; updated.errorDetail = "SMC write CHTE: controller(132)"
            let data = try JSONEncoder().encode(updated)
            t.expect(try JSONDecoder().decode(BatteryResponse.self, from: data).errorDetail == updated.errorDetail, "operation diagnostics survive helper transport")
        } catch { t.expect(false, "diagnostic response fixture failed: \(error)") }
        let allowed: Set<String> = ["CH0B", "CH0C", "CHIE", "ACLC"]
        t.expect(device.writes.allSatisfy(allowed.contains), "control never writes an unrelated SMC key")
        t.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.batteryCareConfiguration), "policy participates in backup")
        t.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.batteryCareEnabled), "backup cannot activate another Mac's hardware")
    }
}
