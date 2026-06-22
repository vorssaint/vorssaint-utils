// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import IOKit.pwr_mgt

/// Quick subsystem check, run with `Vorssaint --selftest`.
/// Core capabilities fail the test; hardware-dependent readings only warn.
enum SelfTest {
    static func runAndExit() -> Never {
        var failures: [String] = []
        var warnings: [String] = []

        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Vorssaint selftest" as CFString,
                                                 &assertionID)
        if result == kIOReturnSuccess {
            IOPMAssertionRelease(assertionID)
        } else {
            failures.append("power assertion (\(result))")
        }

        if let memory = SystemInfo.memoryUsage() {
            if memory.used == 0 || memory.total == 0 || memory.used > memory.total {
                failures.append("memory bounds")
            }
        } else {
            failures.append("memory reading")
        }
        _ = SystemInfo.batterySnapshot() // may be nil on desktops

        if SystemInfo.wallClockUptimeSeconds() == nil {
            failures.append("uptime reading")
        }

        if let smc = SMCClient() {
            let keys = smc.keys { $0.hasPrefix("Tp") || $0.hasPrefix("Te") || $0.hasPrefix("Tg") }
            if keys.isEmpty {
                warnings.append("no SMC temperature keys")
            } else if keys.compactMap({ smc.readValue($0) }).isEmpty {
                warnings.append("SMC keys found but unreadable")
            }
        } else {
            warnings.append("AppleSMC unavailable")
        }

        // Network counters should be readable and never run backwards.
        let net1 = NetworkSampler.readCounters()
        let net2 = NetworkSampler.readCounters()
        if net1 == NetworkCounters(), net2 == NetworkCounters() {
            warnings.append("network counters unavailable")
        } else if net2.received < net1.received || net2.sent < net1.sent {
            failures.append("network counters decreased")
        }

        let diskCounters = DiskSampler.readCounters()
        let disks = DiskSampler().sample(now: ProcessInfo.processInfo.systemUptime)
        if diskCounters.isEmpty {
            warnings.append("disk counters unavailable")
        }
        if disks.isEmpty {
            warnings.append("no mounted disk volumes found")
        }

        // Power: laptops report battery/adapter flow; some desktops report nothing.
        if PowerSampler(smc: SMCClient()).sample().isEmpty {
            warnings.append("no power metrics on this Mac")
        }

        UserDefaults.standard.set("ok", forKey: "selftest")
        if UserDefaults.standard.string(forKey: "selftest") != "ok" {
            failures.append("UserDefaults")
        }
        UserDefaults.standard.removeObject(forKey: "selftest")

        for warning in warnings {
            print("SELFTEST WARNING: \(warning)")
        }
        if failures.isEmpty {
            print("SELFTEST OK")
            exit(0)
        } else {
            print("SELFTEST FAILED: \(failures.joined(separator: ", "))")
            exit(1)
        }
    }
}

/// Prints every temperature sensor the monitor would consider, with its
/// classification. Run with `Vorssaint --sensors`; handy when porting
/// the sensor mapping to a new chip generation.
enum SensorDump {
    static func runAndExit() -> Never {
        guard let smc = SMCClient() else {
            print("AppleSMC unavailable")
            exit(1)
        }
        let keys = smc.keys { name in
            name.hasPrefix("Tp") || name.hasPrefix("Te") || name.hasPrefix("Tg")
                || name.range(of: "^TB[0-9]T$", options: .regularExpression) != nil
        }
        let cpuPlatform = TemperatureSensorSelector.currentPlatform()
        let hasCPUCoreSet = TemperatureSensorSelector.hasCPUCoreSet(platform: cpuPlatform)
        print("component    key   type   °C")
        for key in keys.sorted(by: { $0.name < $1.name }) {
            guard let value = smc.readValue(key), value > 1, value < 125 else { continue }
            let component: String
            if key.name.hasPrefix("TB") {
                component = "battery"
            } else if key.name.hasPrefix("Tg") {
                component = "gpu"
            } else if hasCPUCoreSet {
                component = TemperatureSensorSelector.isCPUCoreKey(key.name, platform: cpuPlatform) ? "cpu-core" : "cpu-aux"
            } else {
                component = "cpu"
            }
            print(String(format: "%-11@  %@  %@  %6.2f",
                         component as NSString, key.name, key.dataType, value))
        }
        exit(0)
    }
}
