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
        let target: SMCClient.Key
        let mode: SMCClient.Key
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
        guard try fans.allSatisfy({ try FanControlPolicy.isAutomaticMode(modeValue($0.mode)) }) else {
            throw FanControlHardwareError.alreadyControlled
        }
        if let forceTest = forceTestKey(), try byteValue(forceTest) != 0 {
            throw FanControlHardwareError.alreadyControlled
        }

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

        // Keep the target write adjacent to manual mode. The thermal controller
        // can reclaim automatic mode between a separate verification and target.
        var directSucceeded = true
        for (fan, target) in zip(fans, targets) {
            if !writeManualPair(for: fan, target: target) { directSucceeded = false }
        }

        if directSucceeded {
            Thread.sleep(forTimeInterval: 0.25)
            directSucceeded = fans.allSatisfy { (try? modeValue($0.mode)) == 1 }
        }

        if !directSucceeded {
            guard let forceTest = forceTestKey(), setByte(1, for: forceTest, attempts: 20) else {
                throw FanControlHardwareError.operationFailed
            }
            // A stopped Apple Silicon fan can reject manual mode until the
            // automatic controller has accepted a protective maximum target.
            // Apply the requested level only after manual mode sticks.
            for fan in fans {
                guard setValue(fan.maximumRPM, for: fan.target, attempts: 10) else {
                    throw FanControlHardwareError.operationFailed
                }
            }
            Thread.sleep(forTimeInterval: 3)
            for fan in fans {
                let deadline = ProcessInfo.processInfo.systemUptime + 10
                guard setMode(1, for: fan, untilUptime: deadline) else {
                    throw FanControlHardwareError.operationFailed
                }
            }
        }

        if !directSucceeded {
            for (fan, target) in zip(fans, targets) {
                guard setValue(target, for: fan.target, attempts: 10) else {
                    throw FanControlHardwareError.operationFailed
                }
            }
        }
        guard verifyCooling(fans, targets: targets) else {
            throw FanControlHardwareError.operationFailed
        }
        activeTargets = targets
        return try readings(for: fans)
    }

    func updateCooling(level: Int) throws -> [FanControlFanReading] {
        let fans = try discoverControlledFans()
        guard FanControlPolicy.validCoolingLevel(level),
              activeTargets.count == fans.count,
              fans.allSatisfy({ (try? modeValue($0.mode)) == 1 }) else {
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
            guard setValue(target, for: fan.target, attempts: 10) else {
                throw FanControlHardwareError.operationFailed
            }
        }
        guard verifyCooling(fans, targets: targets) else {
            throw FanControlHardwareError.operationFailed
        }
        activeTargets = targets
        return try readings(for: fans)
    }

    func validateAutomaticControl() throws {
        let fans = try discoverControlledFans()
        guard try fans.allSatisfy({ try FanControlPolicy.isAutomaticMode(modeValue($0.mode)) }) else {
            throw FanControlHardwareError.alreadyControlled
        }
        if let forceTest = forceTestKey() {
            guard try byteValue(forceTest) == 0 else {
                throw FanControlHardwareError.alreadyControlled
            }
        }
    }

    /// Best effort across every discovered fan. Returning false keeps the
    /// helper's recovery marker in place so its watchdog continues retrying.
    func restoreAutomatic() -> Bool {
        guard let fans = try? discoverControlledFans() else { return false }
        for fan in fans {
            _ = setMode(0, for: fan, attempts: 20)
            // The target is ignored in automatic mode. Clear it when the
            // controller accepts the write, but never mistake a rejected
            // target reset for a failure to return control to the firmware.
            _ = setValue(0, for: fan.target, attempts: 10)
        }
        if let forceTest = forceTestKey() {
            _ = setByte(0, for: forceTest, attempts: 20)
        }
        let automatic = fans.allSatisfy { fan in
            (try? modeValue(fan.mode)).map(FanControlPolicy.isAutomaticMode) == true
        }
        let forceTestOff = forceTestKey().map { (try? byteValue($0)) == 0 } ?? true
        if automatic && forceTestOff { activeTargets.removeAll() }
        return automatic && forceTestOff
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
        return verifyCooling(fans, targets: activeTargets)
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
                  let target = client.key(named: "F\(index)Tg"),
                  let mode = modeKey(for: index),
                  mode.dataSize == 1,
                  let minimumRPM = client.readValue(minimum),
                  let maximumRPM = client.readValue(maximum),
                  FanControlPolicy.validBounds(minimum: minimumRPM, maximum: maximumRPM),
                  SMCValueCodec.encode(maximumRPM, type: target.dataType,
                                       size: Int(target.dataSize)) != nil else {
                throw FanControlHardwareError.unsupported
            }
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
                  let target = client.readValue(fan.target),
                  FanControlPolicy.validReading(actual),
                  FanControlPolicy.validReading(target),
                  FanControlPolicy.validBounds(minimum: minimum, maximum: maximum) else {
                throw FanControlHardwareError.operationFailed
            }
            return FanControlFanReading(index: fan.index,
                                        actualRPM: max(0, actual),
                                        minimumRPM: minimum,
                                        maximumRPM: maximum,
                                        targetRPM: max(0, target),
                                        isManuallyControlled: try !FanControlPolicy.isAutomaticMode(
                                            modeValue(fan.mode)
                                        ))
        }
    }

    private func verifyCooling(_ fans: [Fan], targets: [Double]) -> Bool {
        guard fans.count == targets.count else { return false }
        return zip(fans, targets).allSatisfy { fan, expected in
            guard (try? modeValue(fan.mode)) == 1,
                  let target = client.readValue(fan.target) else { return false }
            return abs(target - expected) <= max(2, expected * 0.001)
        }
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

    private func setMode(_ value: UInt8, for fan: Fan, attempts: Int) -> Bool {
        guard setByte(value, for: fan.mode, attempts: attempts) else { return false }
        return (try? modeValue(fan.mode)) == value
    }

    private func writeManualPair(for fan: Fan, target: Double) -> Bool {
        do {
            try client.writeBytes([1], to: fan.mode)
            try client.writeValue(target, to: fan.target)
            return true
        } catch {
            return false
        }
    }

    private func setMode(_ value: UInt8, for fan: Fan, untilUptime deadline: TimeInterval) -> Bool {
        repeat {
            if setMode(value, for: fan, attempts: 1) { return true }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 { return false }
            Thread.sleep(forTimeInterval: min(0.1, remaining))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return false
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
