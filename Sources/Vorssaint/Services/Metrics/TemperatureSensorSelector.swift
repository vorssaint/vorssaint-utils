// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum CPUTemperaturePlatform: Equatable {
    case appleM1Family
    case appleM2Family
    case appleM3Family
    case appleM4Family
    case appleM4ProFamily
    case appleM4MaxFamily
    case appleM5Family
    case unmappedAppleSilicon
    case generic
}

struct CachedSensorReading {
    var value: Double
    var updatedAt: TimeInterval
    var missedSamples: Int
}

enum TemperatureSensorSelector {
    static let minimumChipTemperature = 10.0

    // The alternate M1 layout was read on a MacBook Pro 13-inch
    // (MacBookPro17,1) on macOS 27 and reported on a Mac mini (Macmini9,1,
    // #1353), neither of which carries any key of the original layout.
    // In contributed idle and load samples, Tp<n>a and Te<n>a tracked the
    // named pACC/eACC MTR die sensors with the same index. Keep the b, x
    // and z variants auxiliary; most read above those die sensors.
    private static let appleM1CPUCoreKeys: Set<String> = [
        "Tp09", "Tp0T",
        "Tp01", "Tp05", "Tp0D", "Tp0H",
        "Tp0L", "Tp0P", "Tp0X", "Tp0b",
        "Tp2a", "Tp3a", "Tp4a", "Tp5a", "Tp7a", "Tp8a", "Tp9a", "Te0a", "Te3a",
    ]

    private static let appleM2CPUCoreKeys: Set<String> = [
        "Tp1h", "Tp1t", "Tp1p", "Tp1l",
        "Tp01", "Tp05", "Tp09", "Tp0D",
        "Tp0X", "Tp0b", "Tp0f", "Tp0j",
    ]

    private static let appleM3CPUCoreKeys: Set<String> = [
        "Te05", "Te0L", "Te0P", "Te0S",
        "Tf04", "Tf09", "Tf0A", "Tf0B",
        "Tf0D", "Tf0E", "Tf44", "Tf49",
        "Tf4A", "Tf4B", "Tf4D", "Tf4E",
    ]

    private static let appleM4CPUCoreKeys: Set<String> = [
        "Te05", "Te0S", "Te09", "Te0H",
        "Tp01", "Tp05", "Tp09", "Tp0D",
        "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
    ]

    // Observed on M4 Pro (Mac16,8) and M4 Max (Mac16,5, 10P + 4E).
    // These are CPU regions, not a per-core map. Tex keys keep answering
    // while Tpx keys park. currentPlatform validates the Max configuration.
    private static let appleM4ProMaxCPUCoreKeys: Set<String> = [
        "Tex0", "Tex1", "Tex2", "Tex3",
        "Tpx0", "Tpx1", "Tpx2", "Tpx3", "Tpx4", "Tpx5",
        "Tpx8", "Tpx9", "TpxA", "TpxB", "TpxC", "TpxD",
    ]

    private static let appleM5CPUCoreKeys: Set<String> = [
        "Tp00", "Tp04", "Tp08", "Tp0C",
        "Tp0G", "Tp0K",
        "Tp0O", "Tp0R", "Tp0U", "Tp0X",
        "Tp0a", "Tp0d", "Tp0g", "Tp0j",
        "Tp0m", "Tp0p", "Tp0u", "Tp0y",
    ]

    static func platform(brandString: String?) -> CPUTemperaturePlatform {
        let brand = brandString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Preserve the established Tp/Te reading path for this supported chip
        // until a verified per-core map is available.
        if brand == "Apple A18 Pro" { return .generic }
        switch appleSiliconGeneration(in: brand) {
        case 1: return .appleM1Family
        case 2: return .appleM2Family
        case 3: return .appleM3Family
        case 4: return brand == "Apple M4 Pro" ? .appleM4ProFamily : .appleM4Family
        case 5: return .appleM5Family
        default: return brand.hasPrefix("Apple ") ? .unmappedAppleSilicon : .generic
        }
    }

    static func currentPlatform() -> CPUTemperaturePlatform {
        guard let brand = sysctlString("machdep.cpu.brand_string") else {
            return .unmappedAppleSilicon
        }
        let identified = platform(brandString: brand)
        guard brand.trimmingCharacters(in: .whitespacesAndNewlines) == "Apple M4 Max" else {
            return identified
        }
        return platform(brandString: brand,
                        modelIdentifier: sysctlString("hw.model"),
                        performanceCoreCount: sysctlInteger("hw.perflevel0.physicalcpu"),
                        efficiencyCoreCount: sysctlInteger("hw.perflevel1.physicalcpu"))
    }

    /// Only the measured Max configuration opts into the region map. Other
    /// configurations and incomplete discovery keep the existing M4 readings
    /// for the display, alerts, and CPU/SoC fan curves.
    static func platform(brandString: String?, modelIdentifier: String?,
                         performanceCoreCount: Int?, efficiencyCoreCount: Int?) -> CPUTemperaturePlatform {
        let identified = platform(brandString: brandString)
        guard brandString?.trimmingCharacters(in: .whitespacesAndNewlines) == "Apple M4 Max",
              modelIdentifier == "Mac16,5", performanceCoreCount == 10, efficiencyCoreCount == 4 else {
            return identified
        }
        return .appleM4MaxFamily
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInteger(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0,
              size == MemoryLayout<Int32>.size else { return nil }
        return Int(value)
    }

    static func displayedCPUTemperature(readings: [(key: String, value: Double)],
                                        platform: CPUTemperaturePlatform) -> Double? {
        let valid = readings.filter { isPlausibleTemperature($0.value) }
        guard !valid.isEmpty else { return nil }

        let core = valid.filter { isCPUCoreKey($0.key, platform: platform) }
        if let value = core.map({ $0.value }).max() {
            return value
        }
        // Not every Mac carries the sensors its chip generation is mapped to.
        // One that does not showed the hottest reading of its CPU families
        // instead, for as long as the app has had this panel, until 3.3.3
        // restricted the answer to the mapped sensors and left those Macs with
        // nothing. This is that reading, restored exactly. Fan control is a
        // separate decision and keeps requiring its own mapped readings.
        return valid.map { $0.value }.max()
    }

    static func hasCPUCoreSet(platform: CPUTemperaturePlatform) -> Bool {
        switch platform {
        case .appleM1Family, .appleM2Family, .appleM3Family, .appleM4Family,
             .appleM4ProFamily, .appleM4MaxFamily, .appleM5Family:
            return true
        case .unmappedAppleSilicon, .generic: return false
        }
    }

    static func isCPUCoreKey(_ key: String, platform: CPUTemperaturePlatform) -> Bool {
        switch platform {
        case .appleM1Family:
            return appleM1CPUCoreKeys.contains(key)
        case .appleM2Family:
            return appleM2CPUCoreKeys.contains(key)
        case .appleM3Family:
            return appleM3CPUCoreKeys.contains(key)
        case .appleM4Family:
            return appleM4CPUCoreKeys.contains(key)
        case .appleM4ProFamily, .appleM4MaxFamily:
            return appleM4ProMaxCPUCoreKeys.contains(key)
        case .appleM5Family:
            return appleM5CPUCoreKeys.contains(key)
        case .unmappedAppleSilicon, .generic:
            return false
        }
    }

    static func isCPUTemperatureKey(_ key: String,
                                    platform: CPUTemperaturePlatform) -> Bool {
        if key.hasPrefix("Tp") || key.hasPrefix("Te") { return true }
        return platform == .appleM3Family && key.hasPrefix("Tf")
    }

    static func stabilizedTemperature(_ reading: Double?,
                                      cache: inout CachedSensorReading?,
                                      now: TimeInterval,
                                      maxAge: TimeInterval,
                                      minimum: Double = 1) -> Double? {
        if let reading, reading > 1, reading >= minimum, reading < 125 {
            cache = CachedSensorReading(value: reading, updatedAt: now, missedSamples: 0)
            return reading
        }
        guard var cached = cache else { return nil }
        cached.missedSamples += 1
        if cached.missedSamples <= 4, now - cached.updatedAt <= maxAge {
            cache = cached
            return cached.value
        }
        cache = nil
        return nil
    }

    private static func appleSiliconGeneration(in brand: String) -> Int? {
        guard brand.hasPrefix("Apple M") else { return nil }
        let remainder = brand.dropFirst("Apple M".count)
        guard let first = remainder.first, let generation = Int(String(first)) else { return nil }
        guard generation >= 1, generation <= 5 else { return nil }
        let afterGeneration = remainder.dropFirst()
        guard afterGeneration.isEmpty || afterGeneration.first == " " else { return nil }
        return generation
    }

    private static func isPlausibleTemperature(_ value: Double) -> Bool {
        value >= minimumChipTemperature && value < 125
    }
}
