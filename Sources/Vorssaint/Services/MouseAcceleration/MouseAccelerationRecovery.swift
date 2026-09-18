// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import HIDEventSystem

enum MouseAccelerationRecovery {
    private static let journalName = "MouseAccelerationRecovery.json"

    static func restorePending() -> Bool {
        guard let journal = loadJournal() else { return false }
        guard !journal.entries.isEmpty else { return true }
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        return restorePending(using: client)
    }

    static func restorePending(using client: IOHIDEventSystemClient,
                               preservingConnectedEntries: Bool = false) -> Bool {
        guard var journal = loadJournal(),
              let services = services(using: client) else { return false }

        var servicesByID: [UInt64: IOHIDServiceClient] = [:]
        for service in services {
            guard let id = registryID(of: service) else { continue }
            servicesByID[id] = service
        }
        let reservedRegistryIDs = Set(journal.entries.map(\.registryID))
        let connectedDevices = preservingConnectedEntries ? servicesByID.compactMapValues(identity(of:)) : [:]

        for entry in journal.entriesToRestore(preserving: connectedDevices) {
            guard let service = service(for: entry,
                                        in: services,
                                        servicesByID: servicesByID,
                                        reservedRegistryIDs: reservedRegistryIDs) else { continue }
            if setAndVerify(entry.original, key: entry.key, on: service) {
                journal.remove(registryID: entry.registryID)
            }
        }
        return writeJournal(journal) && journal.entries.isEmpty
    }

    static func journalForMutation() -> MouseAccelerationRecoveryJournal? {
        loadJournal()
    }

    static func record(_ entry: MouseAccelerationRecoveryEntry,
                       in journal: inout MouseAccelerationRecoveryJournal) -> Bool {
        var updated = journal
        updated.upsert(entry)
        guard writeJournal(updated) else { return false }
        journal = updated
        return true
    }

    static func remove(registryID: UInt64,
                       from journal: inout MouseAccelerationRecoveryJournal) -> Bool {
        var updated = journal
        updated.remove(registryID: registryID)
        guard writeJournal(updated) else { return false }
        journal = updated
        return true
    }

    static func hasPendingEntries() -> Bool {
        guard let url = journalURL,
              FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let journal = loadJournal() else { return true }
        return !journal.entries.isEmpty
    }

    static func services(using client: IOHIDEventSystemClient) -> [IOHIDServiceClient]? {
        IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]
    }

    static func registryID(of service: IOHIDServiceClient) -> UInt64? {
        let value = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value
        return MouseAccelerationSupport.validatedRegistryID(value)
    }

    static func identity(of service: IOHIDServiceClient) -> MouseAccelerationDeviceIdentity? {
        guard registryID(of: service) != nil else { return nil }
        return MouseAccelerationDeviceIdentity(
            vendorID: numberProperty("VendorID", of: service),
            productID: numberProperty("ProductID", of: service),
            locationID: numberProperty("LocationID", of: service),
            transport: stringProperty("Transport", of: service),
            physicalUniqueID: stringProperty("PhysicalDeviceUniqueID", of: service),
            serialNumber: stringProperty("SerialNumber", of: service)
        )
    }

    static func isMouse(_ service: IOHIDServiceClient) -> Bool {
        guard IOHIDServiceClientConformsTo(service,
                                           UInt32(kHIDPage_GenericDesktop),
                                           UInt32(kHIDUsage_GD_Mouse)) != 0 else {
            return false
        }
        let accelerationType = stringProperty(MouseAccelerationSupport.pointerAccelerationTypeKey,
                                              of: service)
        return accelerationType != MouseAccelerationSupport.trackpadAccelerationType
    }

    static func captureEntry(for service: IOHIDServiceClient,
                             registryID: UInt64,
                             identity: MouseAccelerationDeviceIdentity) -> MouseAccelerationRecoveryEntry? {
        if let value = storedValue(for: MouseAccelerationSupport.linearScalingKey, on: service) {
            return MouseAccelerationRecoveryEntry(registryID: registryID,
                                                  identity: identity,
                                                  key: MouseAccelerationSupport.linearScalingKey,
                                                  original: value)
        }
        let key = accelerationKey(for: service)
        guard let value = storedValue(for: key, on: service) else { return nil }
        return MouseAccelerationRecoveryEntry(registryID: registryID,
                                              identity: identity,
                                              key: key,
                                              original: value)
    }

    static func applyTarget(for entry: MouseAccelerationRecoveryEntry,
                            to service: IOHIDServiceClient) -> Bool {
        setAndVerify(MouseAccelerationSupport.targetValue(
                         for: entry.key,
                         originalIsBoolean: entry.original.isBoolean
                     ),
                     key: entry.key,
                     on: service)
    }

    static func restore(_ entry: MouseAccelerationRecoveryEntry,
                        on service: IOHIDServiceClient) -> Bool {
        setAndVerify(entry.original, key: entry.key, on: service)
    }

    private static var journalURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent(journalName, isDirectory: false)
    }

    private static func loadJournal() -> MouseAccelerationRecoveryJournal? {
        guard let bootTime = currentBootTime(), let url = journalURL else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return MouseAccelerationRecoveryJournal(bootTime: bootTime, entries: [])
        }
        guard let data = try? Data(contentsOf: url),
              let journal = try? JSONDecoder().decode(MouseAccelerationRecoveryJournal.self,
                                                      from: data) else { return nil }
        guard journal.bootTime == bootTime else {
            try? FileManager.default.removeItem(at: url)
            return MouseAccelerationRecoveryJournal(bootTime: bootTime, entries: [])
        }
        let registryIDs = journal.entries.map(\.registryID)
        guard Set(registryIDs).count == registryIDs.count,
              journal.entries.allSatisfy({
                  MouseAccelerationSupport.validatedRegistryID($0.registryID) != nil
                      && MouseAccelerationSupport.isRestorableKey($0.key)
              }) else { return nil }
        return journal
    }

    @discardableResult
    private static func writeJournal(_ journal: MouseAccelerationRecoveryJournal) -> Bool {
        guard let url = journalURL else { return false }
        if journal.entries.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    return false
                }
            }
            return true
        }
        guard let container = PrivateFileStore.containerURL,
              PrivateFileStore.createDirectory(at: container),
              let data = try? JSONEncoder().encode(journal) else { return false }
        return PrivateFileStore.write(data, to: url)
    }

    private static func currentBootTime() -> Int64? {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0,
              bootTime.tv_sec > 0 else { return nil }
        return Int64(bootTime.tv_sec)
    }

    private static func accelerationKey(for service: IOHIDServiceClient) -> String {
        if let key = stringProperty(MouseAccelerationSupport.pointerAccelerationTypeKey,
                                    of: service),
           key == MouseAccelerationSupport.pointerAccelerationKey
            || key == MouseAccelerationSupport.mouseAccelerationKey {
            return key
        }
        if storedValue(for: MouseAccelerationSupport.pointerAccelerationKey, on: service) != nil {
            return MouseAccelerationSupport.pointerAccelerationKey
        }
        return MouseAccelerationSupport.mouseAccelerationKey
    }

    private static func service(for entry: MouseAccelerationRecoveryEntry,
                                in services: [IOHIDServiceClient],
                                servicesByID: [UInt64: IOHIDServiceClient],
                                reservedRegistryIDs: Set<UInt64>) -> IOHIDServiceClient? {
        if let exact = servicesByID[entry.registryID],
           let liveIdentity = identity(of: exact),
           entry.identity.matches(liveIdentity) {
            return exact
        }
        guard entry.identity.canMatchAcrossRegistryIDs else { return nil }
        let matches = services.filter { service in
            guard isMouse(service),
                  let registryID = registryID(of: service),
                  !reservedRegistryIDs.contains(registryID),
                  let liveIdentity = identity(of: service) else { return false }
            return entry.identity.matches(liveIdentity)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func storedValue(for key: String,
                                    on service: IOHIDServiceClient) -> MouseAccelerationStoredValue? {
        guard let value = IOHIDServiceClientCopyProperty(service, key as CFString),
              let number = value as? NSNumber else { return nil }
        return MouseAccelerationStoredValue(
            rawValue: number.int64Value,
            isBoolean: CFGetTypeID(value) == CFBooleanGetTypeID()
        )
    }

    private static func setAndVerify(_ value: MouseAccelerationStoredValue,
                                     key: String,
                                     on service: IOHIDServiceClient) -> Bool {
        if storedValue(for: key, on: service) == value { return true }
        guard IOHIDServiceClientSetProperty(service, key as CFString, cfValue(value)) == true else {
            return false
        }
        return storedValue(for: key, on: service) == value
    }

    private static func cfValue(_ value: MouseAccelerationStoredValue) -> CFTypeRef {
        if value.isBoolean {
            return value.rawValue == 0 ? kCFBooleanFalse : kCFBooleanTrue
        }
        return value.rawValue as CFNumber
    }

    private static func numberProperty(_ key: String,
                                       of service: IOHIDServiceClient) -> Int64? {
        (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.int64Value
    }

    private static func stringProperty(_ key: String,
                                       of service: IOHIDServiceClient) -> String? {
        guard let value = IOHIDServiceClientCopyProperty(service, key as CFString) else {
            return nil
        }
        if let string = value as? String, !string.isEmpty { return string }
        return nil
    }
}
