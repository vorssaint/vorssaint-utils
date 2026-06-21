// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum CPUTemperaturePlatform: Equatable {
    case appleM1Family
    case appleM2Family
    case appleM3Family
    case appleM4Family
    case appleM5Family
    case generic
}

enum TemperatureSensorSelector {
    private static let appleM1CPUCoreKeys: Set<String> = [
        "Tp09", "Tp0T",
        "Tp01", "Tp05", "Tp0D", "Tp0H",
        "Tp0L", "Tp0P", "Tp0X", "Tp0b",
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

    private static let appleM5CPUCoreKeys: Set<String> = [
        "Tp00", "Tp04", "Tp08", "Tp0C",
        "Tp0G", "Tp0K",
        "Tp0O", "Tp0R", "Tp0U", "Tp0X",
        "Tp0a", "Tp0d", "Tp0g", "Tp0j",
        "Tp0m", "Tp0p", "Tp0u", "Tp0y",
    ]

    static func platform(brandString: String?) -> CPUTemperaturePlatform {
        let brand = brandString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch appleSiliconGeneration(in: brand) {
        case 1: return .appleM1Family
        case 2: return .appleM2Family
        case 3: return .appleM3Family
        case 4: return .appleM4Family
        case 5: return .appleM5Family
        default: return .generic
        }
    }

    static func currentPlatform() -> CPUTemperaturePlatform {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return .generic
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return .generic
        }
        return platform(brandString: String(cString: buffer))
    }

    static func displayedCPUTemperature(readings: [(key: String, value: Double)],
                                        platform: CPUTemperaturePlatform) -> Double? {
        let valid = readings.filter { isPlausibleTemperature($0.value) }
        guard !valid.isEmpty else { return nil }

        let core = valid.filter { isCPUCoreKey($0.key, platform: platform) }
        if let value = core.map({ $0.value }).max() {
            return value
        }
        return valid.map { $0.value }.max()
    }

    static func hasCPUCoreSet(platform: CPUTemperaturePlatform) -> Bool {
        switch platform {
        case .appleM1Family, .appleM2Family, .appleM3Family, .appleM4Family, .appleM5Family:
            return true
        case .generic: return false
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
        case .appleM5Family:
            return appleM5CPUCoreKeys.contains(key)
        case .generic:
            return false
        }
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
        value > 1 && value < 125
    }
}
