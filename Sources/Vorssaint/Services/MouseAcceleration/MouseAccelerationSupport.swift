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

/// The two settings this feature owns on a mouse. Each keeps its own saved
/// original, so either can be turned back while the other stays applied.
enum MouseAccelerationSlot: Int, Comparable {
    case acceleration, speed

    static func < (lhs: MouseAccelerationSlot, rhs: MouseAccelerationSlot) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct MouseAccelerationRecoveryEntry: Codable, Equatable {
    let registryID: UInt64
    let identity: MouseAccelerationDeviceIdentity
    let key: String
    let original: MouseAccelerationStoredValue
    /// Absent in journals written before pointer speed existed, which only
    /// ever held acceleration originals.
    var isSpeed: Bool? = nil

    var slot: MouseAccelerationSlot { isSpeed == true ? .speed : .acceleration }
}

struct MouseAccelerationRecoveryJournal: Codable, Equatable {
    let bootTime: Int64
    var entries: [MouseAccelerationRecoveryEntry]

    func entry(registryID: UInt64,
               identity: MouseAccelerationDeviceIdentity,
               slot: MouseAccelerationSlot = .acceleration) -> MouseAccelerationRecoveryEntry? {
        entries.first { $0.registryID == registryID && $0.slot == slot && $0.identity.matches(identity) }
    }

    func entriesToRestore(preserving connectedDevices: [UInt64: MouseAccelerationDeviceIdentity])
        -> [MouseAccelerationRecoveryEntry] {
        entries.filter { entry in
            guard let identity = connectedDevices[entry.registryID] else { return true }
            return !entry.identity.matches(identity)
        }
    }

    mutating func upsert(_ entry: MouseAccelerationRecoveryEntry) {
        entries.removeAll { $0.registryID == entry.registryID && $0.slot == entry.slot }
        entries.append(entry)
        entries.sort { ($0.registryID, $0.slot) < ($1.registryID, $1.slot) }
    }

    mutating func remove(registryID: UInt64, slot: MouseAccelerationSlot) {
        entries.removeAll { $0.registryID == registryID && $0.slot == slot }
    }

    /// True when no mouse holds two saved originals for the same setting.
    var hasUniqueSlots: Bool {
        let pairs = entries.map { "\($0.registryID):\($0.slot.rawValue)" }
        return Set(pairs).count == pairs.count
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
    static let speedRange = 25...200
    static let defaultSpeed = 100

    static func validatedRegistryID(_ value: UInt64?) -> UInt64? {
        guard let value, value != 0 else { return nil }
        return value
    }

    static func isRestorableKey(_ key: String) -> Bool {
        key == linearScalingKey || key == pointerAccelerationKey || key == mouseAccelerationKey
    }

    /// Clamps the stored percentage (0 or garbage falls back to unchanged).
    static func sanitizedSpeed(_ value: Int) -> Int {
        guard value != 0 else { return defaultSpeed }
        return min(max(value, speedRange.lowerBound), speedRange.upperBound)
    }

    /// The mouse's tracking value scaled to `speed` percent of its own. This
    /// is the per-device form of the Tracking speed slider in System Settings.
    static func speedTarget(original: MouseAccelerationStoredValue,
                            speed: Int) -> MouseAccelerationStoredValue {
        MouseAccelerationStoredValue(rawValue: original.rawValue * Int64(sanitizedSpeed(speed)) / 100,
                                     isBoolean: false)
    }

    static func targetValue(for key: String,
                            originalIsBoolean: Bool) -> MouseAccelerationStoredValue {
        if key == linearScalingKey {
            return MouseAccelerationStoredValue(rawValue: 1, isBoolean: originalIsBoolean)
        }
        return MouseAccelerationStoredValue(rawValue: -1, isBoolean: false)
    }
}
