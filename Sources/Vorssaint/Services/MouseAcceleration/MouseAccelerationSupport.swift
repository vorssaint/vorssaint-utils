// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MouseAccelerationDeviceIdentity: Codable, Equatable {
    let vendorID: Int64?
    let productID: Int64?
    let locationID: Int64?
    let transport: String?
    let physicalUniqueID: String?
    let serialNumber: String?

    func matches(_ other: MouseAccelerationDeviceIdentity) -> Bool {
        if let physicalUniqueID, let otherID = other.physicalUniqueID {
            return physicalUniqueID == otherID
        }
        if let serialNumber, let otherSerial = other.serialNumber {
            return serialNumber == otherSerial
        }
        return vendorID == other.vendorID
            && productID == other.productID
            && locationID == other.locationID
            && transport == other.transport
    }

    var canMatchAcrossRegistryIDs: Bool {
        physicalUniqueID != nil
            || serialNumber != nil
            || ((vendorID ?? 0) > 0 && (productID ?? 0) > 0 && (locationID ?? 0) > 0)
    }
}

struct MouseAccelerationStoredValue: Codable, Equatable {
    let rawValue: Int64
    let isBoolean: Bool
}

struct MouseAccelerationRecoveryEntry: Codable, Equatable {
    let registryID: UInt64
    let identity: MouseAccelerationDeviceIdentity
    let key: String
    let original: MouseAccelerationStoredValue
}

struct MouseAccelerationRecoveryJournal: Codable, Equatable {
    let bootTime: Int64
    var entries: [MouseAccelerationRecoveryEntry]

    func entry(registryID: UInt64,
               identity: MouseAccelerationDeviceIdentity) -> MouseAccelerationRecoveryEntry? {
        entries.first { $0.registryID == registryID && $0.identity.matches(identity) }
    }

    func entriesToRestore(preserving connectedDevices: [UInt64: MouseAccelerationDeviceIdentity])
        -> [MouseAccelerationRecoveryEntry] {
        entries.filter { entry in
            guard let identity = connectedDevices[entry.registryID] else { return true }
            return !entry.identity.matches(identity)
        }
    }

    mutating func upsert(_ entry: MouseAccelerationRecoveryEntry) {
        entries.removeAll { $0.registryID == entry.registryID }
        entries.append(entry)
        entries.sort { $0.registryID < $1.registryID }
    }

    mutating func remove(registryID: UInt64) {
        entries.removeAll { $0.registryID == registryID }
    }
}

/// A short settling window after hotplug, never a repeating idle timer.
struct MouseAccelerationReapplySchedule {
    private var generation: UUID?
    private var delays: ArraySlice<TimeInterval> = []

    mutating func restart() -> UUID {
        let token = UUID()
        generation = token
        delays = [0, 0.25, 0.75, 1.5, 2.5]
        return token
    }

    func isCurrent(_ token: UUID) -> Bool {
        generation == token
    }

    mutating func nextDelay(for token: UUID) -> TimeInterval? {
        guard isCurrent(token) else { return nil }
        guard let delay = delays.popFirst() else {
            cancel()
            return nil
        }
        return delay
    }

    mutating func cancel() {
        generation = nil
        delays = []
    }
}

enum MouseAccelerationSupport {
    static let linearScalingKey = "HIDUseLinearScalingMouseAcceleration"
    static let pointerAccelerationTypeKey = "HIDPointerAccelerationType"
    static let pointerAccelerationKey = "HIDPointerAcceleration"
    static let mouseAccelerationKey = "HIDMouseAcceleration"
    static let trackpadAccelerationType = "HIDTrackpadAcceleration"

    static func validatedRegistryID(_ value: UInt64?) -> UInt64? {
        guard let value, value != 0 else { return nil }
        return value
    }

    static func isRestorableKey(_ key: String) -> Bool {
        key == linearScalingKey || key == pointerAccelerationKey || key == mouseAccelerationKey
    }

    static func targetValue(for key: String,
                            originalIsBoolean: Bool) -> MouseAccelerationStoredValue {
        if key == linearScalingKey {
            return MouseAccelerationStoredValue(rawValue: 1, isBoolean: originalIsBoolean)
        }
        return MouseAccelerationStoredValue(rawValue: -1, isBoolean: false)
    }
}
