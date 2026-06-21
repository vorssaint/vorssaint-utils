// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit

/// One power reading. Every field is optional: a Mac mini has no battery, a
/// desktop may expose no SMC power key, so the UI shows only what is real.
struct PowerReading {
    var systemWatts: Double?       // total the Mac is consuming (SMC PSTR)
    var adapterWatts: Double?      // real-time draw from the adapter (SMC PDTR)
    var adapterMaxWatts: Double?   // the charger's rated wattage
    var batteryWatts: Double?      // + charging, - discharging
    var chargePercent: Int?        // current charge level
    var healthPercent: Double?     // max capacity vs design (battery health)
    var cycleCount: Int?
    var isCharging = false
    var externalConnected = false
    var hasBattery = false

    var isEmpty: Bool {
        systemWatts == nil && adapterWatts == nil && adapterMaxWatts == nil
            && batteryWatts == nil && !hasBattery
    }
}

/// Reads power without any special permission. Total system power and adapter
/// input come from the SMC (the same sensors Activity Monitor's energy tab is
/// built on); battery flow and the charger's rating come from AppleSmartBattery.
/// Anything the hardware does not expose stays nil.
final class PowerSampler {
    private let smc: SMCClient?
    private var systemKey: SMCClient.Key?
    private var adapterKey: SMCClient.Key?
    private var resolvedKeys = false
    private var batteryService: io_service_t = 0

    /// `PSTR` = System Total Power. `PDTR` = DC-In (adapter) Total Power. PSTR is
    /// also a reasonable system-power fallback if a Mac only exposes PDTR.
    private static let systemPowerKeys = ["PSTR", "PDTR"]
    private static let adapterPowerKeys = ["PDTR"]

    init(smc: SMCClient?) {
        self.smc = smc
    }

    deinit {
        if batteryService != 0 {
            IOObjectRelease(batteryService)
        }
    }

    func sample() -> PowerReading {
        var reading = PowerReading()

        if let smc {
            if !resolvedKeys {
                resolvedKeys = true
                systemKey = Self.systemPowerKeys.lazy.compactMap { smc.key(named: $0) }.first
                adapterKey = Self.adapterPowerKeys.lazy.compactMap { smc.key(named: $0) }.first
            }
            reading.systemWatts = plausibleWatts(systemKey)
            reading.adapterWatts = plausibleWatts(adapterKey)
        }

        if let props = batteryProperties() {
            reading.hasBattery = true
            reading.externalConnected = (props["ExternalConnected"] as? Bool) ?? false
            reading.isCharging = (props["IsCharging"] as? Bool) ?? false

            let voltageMv = (props["Voltage"] as? Int) ?? 0
            let amperageMa = (props["Amperage"] as? Int) ?? (props["InstantAmperage"] as? Int) ?? 0
            if voltageMv > 0, amperageMa != 0 {
                // Power = V x I, signed by the amperage (negative while discharging).
                reading.batteryWatts = (Double(voltageMv) / 1000.0) * (Double(amperageMa) / 1000.0)
            }

            if let adapter = props["AdapterDetails"] as? [String: Any],
               let rated = adapter["Watts"] as? Int, rated > 0 {
                reading.adapterMaxWatts = Double(rated)
            }

            if let capacity = props["CurrentCapacity"] as? Int,
               let maxCapacity = props["MaxCapacity"] as? Int, maxCapacity > 0 {
                reading.chargePercent = Int((Double(capacity) / Double(maxCapacity) * 100).rounded())
            }
            if let cycles = props["CycleCount"] as? Int { reading.cycleCount = cycles }
            if let design = props["DesignCapacity"] as? Int, design > 0 {
                // Fallback estimate from IORegistry: a full-charge capacity over
                // design. NominalChargeCapacity is the smoothed value (closest of
                // the raw fields); fall back to AppleRawMaxCapacity when absent.
                let fullCharge = (props["NominalChargeCapacity"] as? Int) ?? (props["AppleRawMaxCapacity"] as? Int)
                if let fullCharge, fullCharge > 0 {
                    reading.healthPercent = min(100, Double(fullCharge) / Double(design) * 100)
                }
            }
            // Prefer the exact "Maximum Capacity" macOS shows in System Information
            // (a smoothed value no raw ratio reproduces). Cached + off the hot path;
            // the ratio above stands in until the first reading lands or when macOS
            // doesn't expose the field.
            MaxCapacityProbe.shared.refreshIfStale()
            if let exact = MaxCapacityProbe.shared.percent {
                reading.healthPercent = Double(exact)
            }
        }

        // Derive a system figure when no SMC key reports one (e.g. older chips).
        if reading.systemWatts == nil {
            if reading.externalConnected, let input = reading.adapterWatts {
                reading.systemWatts = input
            } else if let flow = reading.batteryWatts, flow < 0 {
                reading.systemWatts = -flow
            }
        }

        return reading
    }

    private func plausibleWatts(_ key: SMCClient.Key?) -> Double? {
        guard let key, let smc, let watts = smc.readValue(key), watts > 0, watts < 1000 else { return nil }
        return watts
    }

    private func batteryProperties() -> [String: Any]? {
        let service = resolvedBatteryService()
        guard service != 0 else { return nil }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = properties?.takeRetainedValue() as? [String: Any]
        else {
            IOObjectRelease(service)
            batteryService = 0
            return nil
        }
        return dict
    }

    private func resolvedBatteryService() -> io_service_t {
        if batteryService != 0 { return batteryService }
        batteryService = IOServiceGetMatchingService(kIOMainPortDefault,
                                                     IOServiceMatching("AppleSmartBattery"))
        return batteryService
    }
}
