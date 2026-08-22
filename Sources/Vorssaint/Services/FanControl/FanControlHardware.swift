// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FanControlHardwareError: Error {
    case noFans
    case unsupported
    case alreadyControlled
    case operationFailed
}

/// The only SMC write policy used by Fan Control. It discovers the keys the
/// hardware actually exposes, accepts only sane reported bounds, and writes
/// only a validated cooling level or automatic mode. There is no arbitrary key
/// or RPM entry point.
final class FanControlHardware {
    private struct TelemetryFan {
        let index: Int
        let actual: SMCClient.Key
    }

    private struct Fan {
        let index: Int
        let actual: SMCClient.Key
        let minimum: SMCClient.Key
        let maximum: SMCClient.Key
        let target: SMCClient.Key?
        let mode: SMCClient.Key?
        let minimumRPM: Double
        let maximumRPM: Double
    }

    private struct TemperatureKeys {
        let cpu: [SMCClient.Key]
        let gpu: [SMCClient.Key]
    }

    private let client: SMCClient
    private var controlledFans: [Fan]?
    private var telemetryFans: [TelemetryFan]?
    private var cachedForceTestKey: SMCClient.Key?
    private var didDiscoverForceTestKey = false
    private var cachedForceBitsKey: SMCClient.Key?
    private var didDiscoverForceBitsKey = false
    private var activeTargets: [Double] = []
    private var temperatureKeys: TemperatureKeys?
    private let temperaturePlatform = TemperatureSensorSelector.currentPlatform()

    init?() {
        guard let client = SMCClient() else { return nil }
        self.client = client
    }

    func readOnlySnapshot() throws -> FanControlSnapshot {
        let fans = try discoverControlledFans()
        let snapshot = FanControlSnapshot(fans: try readings(for: fans), isCooling: false,
                                          endsAt: nil, stopReason: nil,
                                          coolingLevel: nil,
                                          configuration: nil,
                                          temperatures: readTemperatures())
        if let forceTest = forceTestKey(), try byteValue(forceTest) != 0 {
            throw FanControlHardwareError.alreadyControlled
        }
        return snapshot
    }

    func telemetrySnapshot() throws -> FanControlSnapshot {
        let fans = try discoverTelemetryFans()
        guard let speeds = FanControlPolicy.telemetryReadings(
            expectedCount: fans.count,
            readings: fans.map { client.readValue($0.actual) }
        ) else {
            throw FanControlHardwareError.operationFailed
        }
        let readings = zip(fans, speeds).map { fan, actual in
            FanControlFanReading(index: fan.index,
                                 actualRPM: actual,
                                 minimumRPM: 0,
                                 maximumRPM: 0,
                                 targetRPM: 0,
                                 isManuallyControlled: false)
        }
        return FanControlSnapshot(fans: readings, isCooling: false,
                                  endsAt: nil, stopReason: nil,
                                  coolingLevel: nil,
                                  configuration: nil,
                                  temperatures: nil)
    }

    func startCooling(level: Int) throws -> [FanControlFanReading] {
        let fans = try discoverControlledFans()
        let targets = try fans.map { fan -> Double in
            guard let target = FanControlPolicy.coolingTargetRPM(
                    minimum: fan.minimumRPM,
                    maximum: fan.maximumRPM,
                    level: level
                  ) else {
                throw FanControlHardwareError.operationFailed
            }
            return target
        }

        var anySuccess = false
        for (fan, target) in zip(fans, targets) {
            _ = setManualMode(for: fan, enable: true)
            if writeTargetRPM(target, for: fan) {
                anySuccess = true
            }
        }

        guard anySuccess else {
            throw FanControlHardwareError.operationFailed
        }

        activeTargets = targets
        return try readings(for: fans)
    }

    func updateCooling(level: Int) throws -> [FanControlFanReading] {
        let fans = try discoverControlledFans()
        guard FanControlPolicy.validCoolingLevel(level) else {
            throw FanControlHardwareError.operationFailed
        }
        let targets = try fans.map { fan -> Double in
            guard let target = FanControlPolicy.coolingTargetRPM(
                minimum: fan.minimumRPM,
                maximum: fan.maximumRPM,
                level: level
            ) else { throw FanControlHardwareError.operationFailed }
            return target
        }
        for (fan, target) in zip(fans, targets) {
            _ = setManualMode(for: fan, enable: true)
            _ = writeTargetRPM(target, for: fan)
        }
        activeTargets = targets
        return try readings(for: fans)
    }

    func validateAutomaticControl() throws {
        let fans = try discoverControlledFans()
        guard !fans.isEmpty else {
            throw FanControlHardwareError.noFans
        }
    }

    /// Best effort across every discovered fan. Returning false keeps the
    /// helper's recovery marker in place so its watchdog continues retrying.
    func restoreAutomatic() -> Bool {
        guard let fans = try? discoverControlledFans() else { return false }
        for fan in fans {
            _ = setManualMode(for: fan, enable: false)
            _ = setValue(fan.minimumRPM, for: fan.minimum, attempts: 10)
            if let target = fan.target {
                _ = setValue(0, for: target, attempts: 5)
            }
        }
        if let forceTest = forceTestKey() {
            _ = setByte(0, for: forceTest, attempts: 10)
        }
        if let forceKey = forceBitsKey(), let bytes = client.readBytes(forceKey) {
            let zeroBytes = [UInt8](repeating: 0, count: bytes.count)
            _ = try? client.writeBytes(zeroBytes, to: forceKey)
        }
        activeTargets.removeAll()
        return true
    }

    func snapshot(isCooling: Bool, endsAt: Date?,
                  stopReason: FanControlStopReason?,
                  coolingLevel: Int? = nil,
                  configuration: FanControlConfiguration? = nil) throws -> FanControlSnapshot {
        let fans = try discoverControlledFans()
        return FanControlSnapshot(fans: try readings(for: fans),
                                  isCooling: isCooling,
                                  endsAt: endsAt,
                                  stopReason: stopReason,
                                  coolingLevel: coolingLevel,
                                  configuration: configuration,
                                  temperatures: readTemperatures())
    }

    func coolingIsIntact() -> Bool {
        guard let fans = try? discoverControlledFans() else { return false }
        return !fans.isEmpty
    }

    func readTemperatures() -> [FanControlTemperatureReading] {
        let keys = discoverTemperatureKeys()
        let cpuReadings = temperatureReadings(keys.cpu)
        return FanControlPolicy.aggregatedTemperatures(
            cpuReadings: cpuReadings,
            gpuReadings: temperatureReadings(keys.gpu).map(\.value),
            platform: temperaturePlatform
        )
    }

    // MARK: - Discovery

    private func fanCount() throws -> Int {
        guard let key = client.key(named: "FNum"),
              let value = client.readValue(key) else {
            throw FanControlHardwareError.noFans
        }
        guard let count = FanControlPolicy.fanCount(from: value) else {
            throw value == 0 ? FanControlHardwareError.noFans
                             : FanControlHardwareError.unsupported
        }
        return count
    }

    private func discoverControlledFans() throws -> [Fan] {
        if let controlledFans { return controlledFans }
        let count = try fanCount()
        var fans: [Fan] = []
        for index in 0..<count {
            guard let actual = client.key(named: "F\(index)Ac"),
                  let minimum = client.key(named: "F\(index)Mn"),
                  let maximum = client.key(named: "F\(index)Mx"),
                  let minimumRPM = client.readValue(minimum),
                  let maximumRPM = client.readValue(maximum),
                  FanControlPolicy.validBounds(minimum: minimumRPM, maximum: maximumRPM) else {
                throw FanControlHardwareError.unsupported
            }
            let target = client.key(named: "F\(index)Tg")
            let mode = modeKey(for: index)
            fans.append(Fan(index: index, actual: actual, minimum: minimum,
                            maximum: maximum, target: target, mode: mode,
                            minimumRPM: minimumRPM, maximumRPM: maximumRPM))
        }
        controlledFans = fans
        return fans
    }

    private func discoverTelemetryFans() throws -> [TelemetryFan] {
        if let telemetryFans { return telemetryFans }
        let count = try fanCount()
        let fans = try (0..<count).map { index -> TelemetryFan in
            guard let actual = client.key(named: "F\(index)Ac") else {
                throw FanControlHardwareError.unsupported
            }
            return TelemetryFan(index: index, actual: actual)
        }
        telemetryFans = fans
        return fans
    }

    private func modeKey(for index: Int) -> SMCClient.Key? {
        for name in ["F\(index)md", "F\(index)Md"] {
            if let key = client.key(named: name), client.readBytes(key) != nil { return key }
        }
        return nil
    }

    private func forceTestKey() -> SMCClient.Key? {
        if didDiscoverForceTestKey { return cachedForceTestKey }
        didDiscoverForceTestKey = true
        guard let key = client.key(named: "Ftst"), key.dataSize == 1 else { return nil }
        cachedForceTestKey = key
        return key
    }

    private func forceBitsKey() -> SMCClient.Key? {
        if didDiscoverForceBitsKey { return cachedForceBitsKey }
        didDiscoverForceBitsKey = true
        guard let key = client.key(named: "FS! ") else { return nil }
        cachedForceBitsKey = key
        return key
    }

    private func discoverTemperatureKeys() -> TemperatureKeys {
        if let temperatureKeys { return temperatureKeys }
        let keys = client.keys { name in
            TemperatureSensorSelector.isCPUTemperatureKey(name, platform: temperaturePlatform)
                || name.hasPrefix("Tg")
        }
        let result = TemperatureKeys(
            cpu: keys.filter {
                TemperatureSensorSelector.isCPUTemperatureKey($0.name,
                                                              platform: temperaturePlatform)
            },
            gpu: keys.filter { $0.name.hasPrefix("Tg") }
        )
        temperatureKeys = result
        return result
    }

    private func temperatureReadings(_ keys: [SMCClient.Key]) -> [(key: String, value: Double)] {
        keys.compactMap { key in
            guard let value = client.readValue(key),
                  value >= TemperatureSensorSelector.minimumChipTemperature,
                  FanControlPolicy.validTemperature(value) else { return nil }
            return (key.name, value)
        }
    }

    // MARK: - Reads and writes

    private func readings(for fans: [Fan]) throws -> [FanControlFanReading] {
        try fans.map { fan in
            guard let actual = client.readValue(fan.actual),
                  let minimum = client.readValue(fan.minimum),
                  let maximum = client.readValue(fan.maximum),
                  FanControlPolicy.validReading(actual),
                  FanControlPolicy.validBounds(minimum: minimum, maximum: maximum) else {
                throw FanControlHardwareError.operationFailed
            }
            let target = fan.target.flatMap { client.readValue($0) } ?? actual
            let isManual = isManualMode(for: fan)
            return FanControlFanReading(index: fan.index,
                                        actualRPM: max(0, actual),
                                        minimumRPM: minimum,
                                        maximumRPM: maximum,
                                        targetRPM: max(0, target),
                                        isManuallyControlled: isManual)
        }
    }

    private func isManualMode(for fan: Fan) -> Bool {
        if let modeKey = fan.mode, let val = try? modeValue(modeKey), val == 1 {
            return true
        }
        if let forceKey = forceBitsKey(), let bytes = client.readBytes(forceKey), !bytes.isEmpty {
            let mask: UInt16 = bytes.count >= 2 ? ((UInt16(bytes[0]) << 8) | UInt16(bytes[1])) : UInt16(bytes[0])
            if (mask & (1 << fan.index)) != 0 {
                return true
            }
        }
        if let forceTest = forceTestKey(), let val = try? byteValue(forceTest), val != 0 {
            return true
        }
        return false
    }

    private func setManualMode(for fan: Fan, enable: Bool) -> Bool {
        var ok = true
        if let modeKey = fan.mode {
            if !setByte(enable ? 1 : 0, for: modeKey, attempts: 10) { ok = false }
        }
        if let forceKey = forceBitsKey(), let bytes = client.readBytes(forceKey), !bytes.isEmpty {
            var mask: UInt16 = bytes.count >= 2 ? ((UInt16(bytes[0]) << 8) | UInt16(bytes[1])) : UInt16(bytes[0])
            if enable {
                mask |= (1 << fan.index)
            } else {
                mask &= ~(1 << fan.index)
            }
            let newBytes: [UInt8] = bytes.count >= 2 ? [UInt8((mask >> 8) & 0xFF), UInt8(mask & 0xFF)] : [UInt8(mask & 0xFF)]
            _ = try? client.writeBytes(newBytes, to: forceKey)
        }
        if let forceTest = forceTestKey() {
            _ = setByte(enable ? 1 : 0, for: forceTest, attempts: 10)
        }
        return ok || isManualMode(for: fan) == enable
    }

    private func writeTargetRPM(_ target: Double, for fan: Fan) -> Bool {
        var written = false
        if let targetKey = fan.target {
            if setValue(target, for: targetKey, attempts: 10) {
                written = true
            }
        }
        if setValue(target, for: fan.minimum, attempts: 10) {
            written = true
        }
        return written
    }

    private func modeValue(_ key: SMCClient.Key) throws -> UInt8 {
        try byteValue(key)
    }

    private func byteValue(_ key: SMCClient.Key) throws -> UInt8 {
        guard let bytes = client.readBytes(key), bytes.count == 1 else {
            throw FanControlHardwareError.operationFailed
        }
        return bytes[0]
    }

    private func setByte(_ value: UInt8, for key: SMCClient.Key, attempts: Int) -> Bool {
        for attempt in 0..<attempts {
            do {
                try client.writeBytes([value], to: key)
                if (try? byteValue(key)) == value { return true }
            } catch {}
            if attempt + 1 < attempts { Thread.sleep(forTimeInterval: 0.05) }
        }
        return false
    }

    private func setValue(_ value: Double, for key: SMCClient.Key, attempts: Int) -> Bool {
        for attempt in 0..<attempts {
            do {
                try client.writeValue(value, to: key)
                return true
            } catch {}
            if attempt + 1 < attempts { Thread.sleep(forTimeInterval: 0.05) }
        }
        return false
    }
}
