// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The complete production hardware class is generated inside this namespace.
/// Only SMC transport, sensor discovery and elapsed time are replaced; no test
/// opens AppleSMC or changes the machine's fan modes.
enum FanControlHardwareContract {
    enum ProcessInfo {
        static let processInfo = Clock()
        final class Clock { var systemUptime: TimeInterval = 100 }
    }

    enum Thread {
        static var waits: [TimeInterval] = []
        static func sleep(forTimeInterval interval: TimeInterval) {
            waits.append(interval)
            ProcessInfo.processInfo.systemUptime += interval
        }
    }

    enum TemperatureSensorSelector {
        static let minimumChipTemperature = 10.0
        static func currentPlatform() -> CPUTemperaturePlatform { .generic }
        static func isCPUTemperatureKey(_ name: String, platform: CPUTemperaturePlatform) -> Bool {
            name.hasPrefix("TC")
        }
    }

    struct Write {
        let key: String
        let value: Double
    }

    final class State {
        var values: [String: Double] = ["FNum": 2]
        var bytes: [String: [UInt8]] = [:]
        var writes: [Write] = []
        var reads: [String: Int] = [:]
        var rejectWrite: ((Write) -> Bool)?
        var readValue: ((String, Int, Double?) -> Double?)?

        init() {
            for index in 0..<2 {
                values["F\(index)Ac"] = 2_000
                values["F\(index)Mn"] = 1_200
                values["F\(index)Mx"] = 5_800
                values["F\(index)Tg"] = 0
                bytes["F\(index)md"] = [0]
            }
        }

        var automatic: Bool { (0..<2).allSatisfy { bytes["F\($0)md"] == [0] } }
    }

    final class SMCClient {
        enum Failure: Error { case write }
        struct Key {
            let name: String
            let dataSize: UInt32
            let dataType: String
        }
        static var current = State()
        let state: State
        init?() { state = Self.current }

        func key(named name: String) -> Key? {
            if state.bytes[name] != nil { return Key(name: name, dataSize: 1, dataType: "ui8 ") }
            if state.values[name] != nil { return Key(name: name, dataSize: 4, dataType: "flt ") }
            return nil
        }
        func keys(where filter: (String) -> Bool) -> [Key] {
            state.values.keys.filter(filter).sorted().compactMap { key(named: $0) }
        }
        func readValue(_ key: Key) -> Double? {
            state.reads[key.name, default: 0] += 1
            if let readValue = state.readValue {
                return readValue(key.name, state.reads[key.name]!, state.values[key.name])
            }
            return state.values[key.name]
        }
        func readBytes(_ key: Key) -> [UInt8]? { state.bytes[key.name] }
        func writeValue(_ value: Double, to key: Key) throws {
            try record(Write(key: key.name, value: value))
            state.values[key.name] = value
        }
        func writeBytes(_ bytes: [UInt8], to key: Key) throws {
            try record(Write(key: key.name, value: Double(bytes[0])))
            state.bytes[key.name] = bytes
        }
        private func record(_ write: Write) throws {
            state.writes.append(write)
            if state.rejectWrite?(write) == true { throw Failure.write }
        }
    }

    private static func fresh() -> (FanControlHardware, State) {
        SMCClient.current = State()
        Thread.waits = []
        ProcessInfo.processInfo.systemUptime = 100
        return (FanControlHardware()!, SMCClient.current)
    }

    private static func operationFails(_ operation: () throws -> [FanControlFanReading]) -> Bool {
        do {
            _ = try operation()
            return false
        } catch FanControlHardwareError.operationFailed {
            return true
        } catch {
            return false
        }
    }

    static func run(_ suite: TestSuite) {
        let (healthy, healthyState) = fresh()
        let started = try? healthy.startCooling(level: 50)
        suite.expect(started?.count == 2 && started?.allSatisfy(\.isManuallyControlled) == true
                        && healthyState.values["F0Tg"] == 3_500
                        && healthyState.values["F1Tg"] == 3_500 && healthy.coolingIsIntact(),
                     "direct manual control writes and verifies the requested target on both fans")
        let updated = try? healthy.updateCooling(level: 80)
        suite.expect(updated?.count == 2 && healthyState.values["F0Tg"] == 4_880
                        && healthyState.values["F1Tg"] == 4_880 && healthy.coolingIsIntact(),
                     "an active cooling update preserves manual mode at the new targets")
        suite.expect(healthy.restoreAutomatic() && healthyState.automatic
                        && !healthy.coolingIsIntact(),
                     "successful restoration returns every fan to firmware and forgets active targets")

        for index in 0..<2 {
            let (starting, startingState) = fresh()
            startingState.rejectWrite = { $0.key == "F\(index)Tg" && $0.value > 0 }
            suite.expect(operationFails { try starting.startCooling(level: 50) }
                            && startingState.automatic,
                         "failed direct and fallback writes on fan \(index) restore all fans during start")

            let (hardware, state) = fresh()
            suite.expect((try? hardware.startCooling(level: 50)) != nil,
                         "the write-failure fixture starts a real manual session")
            state.rejectWrite = { $0.key == "F\(index)Tg" && $0.value > 0 }
            suite.expect(operationFails { try hardware.updateCooling(level: 75) }
                            && state.automatic
                            && state.writes.contains { $0.key == "F0md" && $0.value == 0 }
                            && state.writes.contains { $0.key == "F1md" && $0.value == 0 },
                         "a target failure on fan \(index) restores all fans, including an earlier successful write")
        }

        for updating in [false, true] {
            let (hardware, state) = fresh()
            if updating {
                suite.expect((try? hardware.startCooling(level: 50)) != nil,
                             "the verification-failure fixture starts manual control")
            }
            state.reads = [:]
            state.readValue = { key, count, value in
                // An update first verifies its individual pair, then the full set.
                key == "F0Tg" && count > (updating ? 1 : 0) ? nil : value
            }
            let failed = operationFails {
                if updating { return try hardware.updateCooling(level: 75) }
                return try hardware.startCooling(level: 75)
            }
            suite.expect(failed && state.automatic,
                         "failed final target verification restores firmware during \(updating ? "update" : "start")")

            let (readingHardware, readingState) = fresh()
            if updating {
                suite.expect((try? readingHardware.startCooling(level: 50)) != nil,
                             "the final-reading fixture starts manual control")
            }
            readingState.readValue = { key, _, value in key == "F1Ac" ? nil : value }
            let readingFailed = operationFails {
                if updating { return try readingHardware.updateCooling(level: 75) }
                return try readingHardware.startCooling(level: 75)
            }
            suite.expect(readingFailed && readingState.automatic,
                         "a missing RPM after successful writes and verification restores firmware during \(updating ? "update" : "start")")
        }

        let (recovering, recoveryState) = fresh()
        suite.expect((try? recovering.startCooling(level: 50)) != nil,
                     "the restoration-failure fixture starts manual control")
        recoveryState.rejectWrite = {
            ($0.key == "F1Tg" && $0.value > 0) || ($0.key == "F0md" && $0.value == 0)
        }
        suite.expect(operationFails { try recovering.updateCooling(level: 75) }
                        && recoveryState.bytes["F0md"] == [1] && recoveryState.bytes["F1md"] == [0]
                        && !recovering.restoreAutomatic(),
                     "a failed restore is reported and still attempts the other fan")
        suite.expect(recoveryState.values["F0Tg"] == 4_650
                        && !recoveryState.writes.contains { $0.key == "F0Tg" && $0.value == 0 },
                     "a fan that rejects automatic mode keeps its safe target instead of receiving zero RPM")
        recoveryState.rejectWrite = nil
        suite.expect(recovering.restoreAutomatic() && recoveryState.automatic,
                     "a later restoration attempt recovers the fan left in manual mode")

        let (resetRejected, resetState) = fresh()
        suite.expect((try? resetRejected.startCooling(level: 50)) != nil,
                     "the target-reset fixture starts manual control")
        resetState.rejectWrite = { $0.key.hasSuffix("Tg") && $0.value == 0 }
        suite.expect(resetRejected.restoreAutomatic() && resetState.automatic,
                     "returning to firmware does not depend on clearing the unused manual target")
        suite.expect(resetState.values["F0Tg"] == 3_500 && resetState.values["F1Tg"] == 3_500
                        && !resetState.writes.contains { $0.key.hasSuffix("Tg") && $0.value == 0 },
                     "automatic restoration never sends a zero target while mode or force-test state can be changing")

        let (firmware, firmwareState) = fresh()
        suite.expect((try? firmware.startCooling(level: 50)) != nil,
                     "the firmware-mode fixture starts manual control")
        firmwareState.bytes["F0md"] = [3]
        firmwareState.bytes["F1md"] = [3]
        firmwareState.rejectWrite = { $0.key.hasSuffix("md") && $0.value == 0 }
        suite.expect(firmware.restoreAutomatic() && firmwareState.bytes["F0md"] == [3]
                        && firmwareState.bytes["F1md"] == [3]
                        && firmwareState.values["F0Tg"] == 3_500 && firmwareState.values["F1Tg"] == 3_500,
                     "firmware mode three is accepted as automatic even when it rejects mode zero")

        let (unreadable, unreadableState) = fresh()
        suite.expect((try? unreadable.startCooling(level: 50)) != nil,
                     "the unreadable-mode fixture starts manual control")
        unreadableState.bytes.removeValue(forKey: "F0md")
        unreadableState.rejectWrite = { $0.key == "F0md" }
        suite.expect(!unreadable.restoreAutomatic() && unreadableState.bytes["F1md"] == [0]
                        && unreadableState.values["F0Tg"] == 3_500,
                     "an unreadable mode preserves the last target and does not block recovery of the other fan")

        let (stuckForceTest, stuckForceState) = fresh()
        stuckForceState.bytes["Ftst"] = [0]
        suite.expect((try? stuckForceTest.startCooling(level: 50)) != nil,
                     "the stuck force-test fixture starts manual control")
        stuckForceState.bytes["Ftst"] = [1]
        stuckForceState.rejectWrite = { $0.key == "Ftst" && $0.value == 0 }
        suite.expect(!stuckForceTest.restoreAutomatic() && stuckForceState.automatic
                        && stuckForceState.bytes["Ftst"] == [1]
                        && stuckForceState.values["F0Tg"] == 3_500 && stuckForceState.values["F1Tg"] == 3_500,
                     "a force-test flag that rejects automatic mode preserves targets and leaves recovery pending")
        stuckForceState.rejectWrite = nil
        suite.expect(stuckForceTest.restoreAutomatic() && stuckForceState.bytes["Ftst"] == [0],
                     "a later retry clears the force-test flag before reporting automatic recovery")

        for forceTest in [false, true] {
            let (owned, ownedState) = fresh()
            if forceTest { ownedState.bytes["Ftst"] = [1] }
            else { ownedState.bytes["F0md"] = [1] }
            var alreadyControlled = false
            do { _ = try owned.startCooling(level: 50) }
            catch FanControlHardwareError.alreadyControlled { alreadyControlled = true }
            catch {}
            suite.expect(alreadyControlled && ownedState.writes.isEmpty,
                         "preexisting control is rejected without writing or restoring another owner's fans")
        }

        for hasForceTest in [false, true] {
            let (fallback, fallbackState) = fresh()
            if hasForceTest { fallbackState.bytes["Ftst"] = [0] }
            var initialModes: Set<String> = ["F0md", "F1md"]
            fallbackState.rejectWrite = {
                $0.value == 1 && initialModes.remove($0.key) != nil
            }
            suite.expect((try? fallback.startCooling(level: 50))?.count == 2
                            && fallbackState.values["F0Tg"] == 3_500
                            && fallbackState.values["F1Tg"] == 3_500
                            && fallbackState.writes.contains { $0.key == "F0Tg" && $0.value == 5_800 }
                            && fallback.coolingIsIntact(),
                         "the stopped-fan fallback reaches the requested target \(hasForceTest ? "with" : "without") Ftst")
            suite.expect(fallback.restoreAutomatic() && fallbackState.automatic
                            && (!hasForceTest || fallbackState.bytes["Ftst"] == [0]),
                         "fallback restoration clears automatic mode and the optional force-test flag")
        }

        let (forcedFailure, forcedState) = fresh()
        forcedState.bytes["Ftst"] = [0]
        forcedState.rejectWrite = { $0.value == 1 }
        suite.expect(operationFails { try forcedFailure.startCooling(level: 50) }
                        && forcedState.automatic && forcedState.bytes["Ftst"] == [0],
                     "a present force-test key that rejects activation fails closed and restores")

        for value in [Double.nan, Double.infinity, -Double.infinity] {
            for key in ["F0Mn", "F1Mx"] {
                let (invalid, invalidState) = fresh()
                invalidState.values[key] = value
                let readings = try? invalid.startCooling(level: 50)
                suite.expect(readings == nil && invalidState.writes.isEmpty && invalidState.automatic,
                             "non-finite \(key) is rejected before any manual-mode or target write")
            }
        }
        let (invalidLevel, invalidLevelState) = fresh()
        suite.expect(operationFails { try invalidLevel.startCooling(level: 101) }
                        && invalidLevelState.writes.isEmpty,
                     "an invalid cooling level cannot begin a manual write")
    }
}
