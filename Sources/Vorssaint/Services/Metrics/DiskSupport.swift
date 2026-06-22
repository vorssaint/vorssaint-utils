// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DiskSMARTReading: Equatable {
    var status: String?
    var totalReadBytes: UInt64?
    var totalWrittenBytes: UInt64?
    var temperatureCelsius: Double?
    var healthPercent: Int?
    var powerCycles: UInt64?
    var powerOnHours: UInt64?
    var unsafeShutdowns: UInt64?
    var mediaErrors: UInt64?

    var hasDetails: Bool {
        status != nil || totalReadBytes != nil || totalWrittenBytes != nil
            || temperatureCelsius != nil || healthPercent != nil
            || powerCycles != nil || powerOnHours != nil
            || unsafeShutdowns != nil || mediaErrors != nil
    }
}

struct DiskDeviceReading: Identifiable, Equatable {
    var id: String
    var name: String
    var mountPath: String
    var bsdName: String?
    var wholeDisk: String?
    var ioCounterID: String?
    var totalBytes: UInt64
    var freeBytes: UInt64
    var usedBytes: UInt64
    var isInternal: Bool
    var isRemovable: Bool
    var isEjectable: Bool
    var smart: DiskSMARTReading?
    var readBytesPerSec: Double?
    var writeBytesPerSec: Double?
    var totalReadBytes: UInt64?
    var totalWrittenBytes: UInt64?

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    var canEject: Bool {
        !isInternal && (isEjectable || isRemovable) && ejectBSDName != nil
    }

    var ejectBSDName: String? {
        wholeDisk ?? bsdName
    }
}

struct DiskReading: Equatable {
    var devices: [DiskDeviceReading] = []

    var isEmpty: Bool { devices.isEmpty }

    var uniqueIODevices: [DiskDeviceReading] {
        var seen = Set<String>()
        return devices.filter { device in
            let key = device.ioCounterID ?? device.wholeDisk ?? device.bsdName ?? device.id
            return seen.insert(key).inserted
        }
    }
}

enum DiskSupport {
    static let nvmeDataUnitBytes: UInt64 = 512_000

    static func nvmeBytes(low: UInt64?, high: UInt64?) -> UInt64? {
        guard let low else { return nil }
        let high = high ?? 0
        guard high <= UInt64(UInt32.max) else { return nil }
        let units = low.addingReportingOverflow(high << 32)
        guard !units.overflow else { return nil }
        let bytes = units.partialValue.multipliedReportingOverflow(by: nvmeDataUnitBytes)
        return bytes.overflow ? nil : bytes.partialValue
    }

    static func celsius(fromSMARTTemperature raw: UInt64?) -> Double? {
        guard let raw else { return nil }
        let value = Double(raw)
        if value > 150 {
            let celsius = value - 273.15
            return (-40...125).contains(celsius) ? celsius : nil
        }
        return (1...125).contains(value) ? value : nil
    }

    static func healthPercent(fromPercentageUsed used: UInt64?) -> Int? {
        guard let used else { return nil }
        return max(0, min(100, 100 - Int(used)))
    }

    static func smartReading(status: String?, vendorKeys: [String: Any]?) -> DiskSMARTReading? {
        let keys = vendorKeys ?? [:]
        var reading = DiskSMARTReading()
        reading.status = status?.isEmpty == false ? status : nil
        reading.totalReadBytes = nvmeBytes(low: uint(keys["DATA_UNITS_READ_0"]),
                                           high: uint(keys["DATA_UNITS_READ_1"]))
        reading.totalWrittenBytes = nvmeBytes(low: uint(keys["DATA_UNITS_WRITTEN_0"]),
                                              high: uint(keys["DATA_UNITS_WRITTEN_1"]))
        reading.temperatureCelsius = celsius(fromSMARTTemperature: uint(keys["TEMPERATURE"]))
        reading.healthPercent = healthPercent(fromPercentageUsed: uint(keys["PERCENTAGE_USED"]))
        reading.powerCycles = uint(keys["POWER_CYCLES_0"])
        reading.powerOnHours = uint(keys["POWER_ON_HOURS_0"])
        reading.unsafeShutdowns = uint(keys["UNSAFE_SHUTDOWNS_0"])
        reading.mediaErrors = uint(keys["MEDIA_ERRORS_0"])
        return reading.hasDetails ? reading : nil
    }

    static func uint(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            let int = number.int64Value
            return int < 0 ? nil : UInt64(int)
        }
        if let string = value as? String {
            return UInt64(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
