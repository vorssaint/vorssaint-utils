// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

public enum TemperatureLabelType: String, CaseIterable, Codable, Equatable {
    case cpuPerformanceCores
    case cpuEfficiencyCores
    case cpu
    case graphics
    case battery
    case ssd
    case palmRest
    case airflow
    case airport
}

public struct TemperatureReading: Identifiable, Equatable {
    public var id: String { key }
    public let key: String
    public let labelType: TemperatureLabelType
    public var valueCelsius: Double
    public var group: TemperatureGroup

    public init(key: String, labelType: TemperatureLabelType, valueCelsius: Double, group: TemperatureGroup) {
        self.key = key
        self.labelType = labelType
        self.valueCelsius = valueCelsius
        self.group = group
    }
}

public enum TemperatureGroup: String, Equatable {
    case cpu
    case gpu
    case battery
    case storage
    case enclosure
    case wireless
    case other
}

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

enum TemperatureSensorClassifier {
    static func classify(key: String, value: Double, platform: CPUTemperaturePlatform) -> TemperatureReading? {
        guard value > 1 && value < 125 else { return nil }

        let group: TemperatureGroup
        let labelType: TemperatureLabelType

        if TemperatureSensorSelector.isCPUCoreKey(key, platform: platform) {
            group = .cpu
            let isEfficiency: Bool
            if key.hasPrefix("Te") {
                isEfficiency = true
            } else if platform == .appleM1Family && (key == "Tp09" || key == "Tp0T") {
                isEfficiency = true
            } else if platform == .appleM2Family && (key == "Tp1h" || key == "Tp1t" || key == "Tp1p" || key == "Tp1l") {
                isEfficiency = true
            } else {
                isEfficiency = false
            }
            labelType = isEfficiency ? .cpuEfficiencyCores : .cpuPerformanceCores
        } else if key.hasPrefix("Tp") || key.hasPrefix("Te") || key.hasPrefix("Tf") {
            group = .cpu
            labelType = .cpu
        } else if key.hasPrefix("Tg") {
            group = .gpu
            labelType = .graphics
        } else if key.hasPrefix("TB") || key.hasPrefix("Tb") {
            group = .battery
            labelType = .battery
        } else if key.hasPrefix("Ts") {
            group = .storage
            labelType = .ssd
        } else if key.hasPrefix("Th") {
            group = .enclosure
            if key.lowercased() == "th0f" {
                labelType = .palmRest
            } else {
                labelType = .airflow
            }
        } else if key.hasPrefix("TW") || key.hasPrefix("Tw") {
            group = .wireless
            labelType = .airport
        } else if key.hasPrefix("Ta") {
            group = .enclosure
            labelType = .airflow
        } else {
            return nil
        }

        return TemperatureReading(key: key, labelType: labelType, valueCelsius: value, group: group)
    }
}
