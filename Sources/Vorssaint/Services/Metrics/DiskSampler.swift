// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit

final class DiskSampler {
    private struct DiskMetadata {
        var bsdName: String?
        var wholeDisk: String?
        var ioCounterIDs: [String] = []
        var totalBytes: UInt64?
        var freeBytes: UInt64?
        var usedBytes: UInt64?
        var isInternal: Bool?
        var isRemovable: Bool?
        var isEjectable: Bool?
        var smart: DiskSMARTReading?
    }

    private var previous: [String: (counters: DiskIOCounters, time: TimeInterval)] = [:]
    private var sessionTotals: [String: DiskIOCounters] = [:]
    private var metadataCache: [String: (metadata: DiskMetadata, updatedAt: TimeInterval)] = [:]
    private static let metadataRefreshInterval: TimeInterval = 30
    private static let maxGap: TimeInterval = 10

    func sample(now: TimeInterval) -> DiskReading {
        let counters = Self.readCounters()
        let devices = Self.mountedVolumes().map { volume -> DiskDeviceReading in
            let metadata = metadata(for: volume.mountPath, now: now)
            let wholeDisk = metadata.wholeDisk
            let counter = Self.bestCounter(from: metadata.ioCounterIDs, counters: counters)
            let ioCounters = counter?.counters ?? DiskIOCounters()
            let diskID = counter?.id ?? wholeDisk ?? metadata.bsdName ?? volume.mountPath
            let rates = ratesAndTotals(for: diskID, counters: ioCounters, now: now)
            let isInternal = metadata.isInternal ?? volume.isInternal
            let isRemovable = metadata.isRemovable ?? volume.isRemovable
            let isEjectable = (metadata.isEjectable ?? volume.isEjectable) || (!isInternal && isRemovable)
            let capacity = Self.bestCapacity(volume: volume, metadata: metadata)
            return DiskDeviceReading(id: volume.mountPath,
                                     name: volume.name,
                                     mountPath: volume.mountPath,
                                     bsdName: metadata.bsdName,
                                     wholeDisk: wholeDisk,
                                     ioCounterID: counter?.id,
                                     totalBytes: capacity.total,
                                     freeBytes: capacity.free,
                                     usedBytes: capacity.used,
                                     isInternal: isInternal,
                                     isRemovable: isRemovable,
                                     isEjectable: isEjectable,
                                     smart: metadata.smart,
                                     readBytesPerSec: rates.readBytesPerSec,
                                     writeBytesPerSec: rates.writeBytesPerSec,
                                     totalReadBytes: rates.totalRead,
                                     totalWrittenBytes: rates.totalWritten)
        }
        return DiskReading(devices: devices.sorted(by: sortVolumes))
    }

    private static func bestCounter(from ids: [String], counters: [String: DiskIOCounters])
        -> (id: String, counters: DiskIOCounters)? {
        for id in ids {
            if let value = counters[id] {
                return (id, value)
            }
        }
        return nil
    }

    private static func bestCapacity(volume: MountedVolume, metadata: DiskMetadata)
        -> (total: UInt64, free: UInt64, used: UInt64) {
        let total = volume.totalBytes > 0 ? volume.totalBytes : (metadata.totalBytes ?? 0)
        let free: UInt64
        if volume.freeBytes > 0 {
            free = volume.freeBytes
        } else if let metadataFree = metadata.freeBytes {
            free = metadataFree
        } else {
            free = 0
        }
        if let metadataUsed = metadata.usedBytes, volume.freeBytes == 0 {
            return (total, min(free, total), min(metadataUsed, total))
        }
        let clampedFree = min(free, total)
        return (total, clampedFree, total - clampedFree)
    }

    private func ratesAndTotals(for diskID: String, counters: DiskIOCounters, now: TimeInterval)
        -> (readBytesPerSec: Double?, writeBytesPerSec: Double?, totalRead: UInt64?, totalWritten: UInt64?) {
        defer { previous[diskID] = (counters, now) }
        var totals = sessionTotals[diskID] ?? DiskIOCounters()
        guard let prev = previous[diskID], now > prev.time, now - prev.time <= Self.maxGap else {
            sessionTotals[diskID] = totals
            return (nil, nil, totals.read, totals.written)
        }

        let speed = MetricFormat.diskSpeed(previous: prev.counters, current: counters, elapsed: now - prev.time)
        if counters.read >= prev.counters.read {
            totals.read += counters.read - prev.counters.read
        }
        if counters.written >= prev.counters.written {
            totals.written += counters.written - prev.counters.written
        }
        sessionTotals[diskID] = totals
        return (speed.read, speed.write, totals.read, totals.written)
    }

    private func metadata(for mountPath: String, now: TimeInterval) -> DiskMetadata {
        if let cached = metadataCache[mountPath],
           now - cached.updatedAt < Self.metadataRefreshInterval {
            return cached.metadata
        }
        let metadata = Self.diskutilInfo(for: mountPath)
        metadataCache[mountPath] = (metadata, now)
        return metadata
    }

    private func sortVolumes(_ lhs: DiskDeviceReading, _ rhs: DiskDeviceReading) -> Bool {
        if lhs.isInternal != rhs.isInternal { return lhs.isInternal && !rhs.isInternal }
        if lhs.mountPath == "/" { return true }
        if rhs.mountPath == "/" { return false }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private struct MountedVolume {
        var name: String
        var mountPath: String
        var totalBytes: UInt64
        var freeBytes: UInt64
        var usedBytes: UInt64
        var isInternal: Bool
        var isRemovable: Bool
        var isEjectable: Bool
    }

    private static func mountedVolumes() -> [MountedVolume] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeLocalizedNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsLocalKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys),
                                                               options: [.skipHiddenVolumes]) else {
            return []
        }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsLocal != false,
                  let total = positiveUInt(values.volumeTotalCapacity),
                  total > 0 else { return nil }
            let free = positiveUInt(values.volumeAvailableCapacityForImportantUsage, requiringPositive: true)
                ?? positiveUInt(values.volumeAvailableCapacity, requiringPositive: true)
                ?? positiveUInt(values.volumeAvailableCapacityForImportantUsage)
                ?? positiveUInt(values.volumeAvailableCapacity)
                ?? 0
            let name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
            return MountedVolume(name: name.isEmpty ? url.path : name,
                                 mountPath: url.path,
                                 totalBytes: total,
                                 freeBytes: min(free, total),
                                 usedBytes: total - min(free, total),
                                 isInternal: values.volumeIsInternal ?? false,
                                 isRemovable: values.volumeIsRemovable ?? false,
                                 isEjectable: values.volumeIsEjectable ?? false)
        }
    }

    private static func positiveUInt(_ value: Int?) -> UInt64? {
        guard let value, value >= 0 else { return nil }
        return UInt64(value)
    }

    private static func positiveUInt(_ value: Int?, requiringPositive: Bool) -> UInt64? {
        guard let result = positiveUInt(value), !requiringPositive || result > 0 else { return nil }
        return result
    }

    private static func positiveUInt(_ value: Int64?, requiringPositive: Bool) -> UInt64? {
        guard let result = positiveUInt(value), !requiringPositive || result > 0 else { return nil }
        return result
    }

    private static func positiveUInt(_ value: Int64?) -> UInt64? {
        guard let value, value >= 0 else { return nil }
        return UInt64(value)
    }

    private static func diskutilInfo(for mountPath: String) -> DiskMetadata {
        guard let info = runDiskutilInfo(mountPath) else { return DiskMetadata() }
        let bsdName = info["DeviceIdentifier"] as? String
        let parentWholeDisk = info["ParentWholeDisk"] as? String
        let physicalStore = (info["APFSPhysicalStores"] as? [[String: Any]])?.first?["APFSPhysicalStore"] as? String
        let wholeDisk = physicalWholeDisk(from: physicalStore)
            ?? physicalWholeDisk(from: parentWholeDisk)
            ?? physicalWholeDisk(from: bsdName)
        let total = DiskSupport.uint(info["APFSContainerSize"]) ?? DiskSupport.uint(info["TotalSize"])
        let free = DiskSupport.uint(info["APFSContainerFree"]) ?? DiskSupport.uint(info["FreeSpace"])
        let used = DiskSupport.uint(info["CapacityInUse"])
            ?? total.flatMap { total in free.map { total >= $0 ? total - $0 : 0 } }
        let status = info["SMARTStatus"] as? String
        let vendorKeys = info["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any]
        let ioIDs = ioCounterIDs(bsdName: bsdName,
                                 parentWholeDisk: parentWholeDisk,
                                 physicalStore: physicalStore,
                                 isInternal: info["Internal"] as? Bool ?? false)
        return DiskMetadata(bsdName: bsdName,
                            wholeDisk: wholeDisk,
                            ioCounterIDs: ioIDs,
                            totalBytes: total,
                            freeBytes: free,
                            usedBytes: used,
                            isInternal: info["Internal"] as? Bool,
                            isRemovable: (info["RemovableMediaOrExternalDevice"] as? Bool)
                                ?? (info["Removable"] as? Bool)
                                ?? (info["RemovableMedia"] as? Bool),
                            isEjectable: (info["Ejectable"] as? Bool)
                                ?? (info["EjectableOnly"] as? Bool),
                            smart: DiskSupport.smartReading(status: status, vendorKeys: vendorKeys))
    }

    private static func ioCounterIDs(bsdName: String?, parentWholeDisk: String?,
                                     physicalStore: String?, isInternal: Bool) -> [String] {
        let physicalWhole = physicalWholeDisk(from: physicalStore)
        let parentWhole = physicalWholeDisk(from: parentWholeDisk)
        let bsdWhole = physicalWholeDisk(from: bsdName)
        let raw = isInternal
            ? [physicalWhole, parentWhole, bsdWhole, bsdName]
            : [bsdName, parentWhole, physicalWhole, bsdWhole]
        var seen = Set<String>()
        return raw.compactMap { $0 }.filter { seen.insert($0).inserted }
    }

    private static func physicalWholeDisk(from identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        let trimmed = identifier.replacingOccurrences(of: "/dev/", with: "")
        guard trimmed.hasPrefix("disk") else { return nil }
        var index = trimmed.index(trimmed.startIndex, offsetBy: 4)
        let numberStart = index
        while index < trimmed.endIndex, trimmed[index].isNumber {
            index = trimmed.index(after: index)
        }
        guard index > numberStart else { return nil }
        return String(trimmed[..<index])
    }

    private static func runDiskutilInfo(_ mountPath: String) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", mountPath]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
              let dict = plist as? [String: Any] else { return nil }
        return dict
    }

    static func readCounters() -> [String: DiskIOCounters] {
        var counters = readBlockStorageCounters()
        for (key, value) in readMediaCounters() where counters[key] == nil {
            counters[key] = value
        }
        return counters
    }

    private static func readBlockStorageCounters() -> [String: DiskIOCounters] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == kIOReturnSuccess else { return [:] }
        defer { IOObjectRelease(iterator) }

        var result: [String: DiskIOCounters] = [:]
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let bsdName = wholeDiskBSDName(descendingFrom: service),
               let stats = property("Statistics", from: service) as? [String: Any] {
                result[bsdName] = DiskIOCounters(read: DiskSupport.uint(stats["Bytes (Read)"]) ?? 0,
                                                 written: DiskSupport.uint(stats["Bytes (Write)"]) ?? 0)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    private static func readMediaCounters() -> [String: DiskIOCounters] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOMedia"),
                                           &iterator) == kIOReturnSuccess else { return [:] }
        defer { IOObjectRelease(iterator) }

        var result: [String: DiskIOCounters] = [:]
        var media = IOIteratorNext(iterator)
        while media != 0 {
            if let bsdName = property("BSD Name", from: media) as? String,
               let stats = property("Statistics", from: media) as? [String: Any],
               let counters = counters(from: stats) {
                result[bsdName] = counters
            }
            IOObjectRelease(media)
            media = IOIteratorNext(iterator)
        }
        return result
    }

    private static func counters(from stats: [String: Any]) -> DiskIOCounters? {
        let read = DiskSupport.uint(stats["Bytes (Read)"])
            ?? DiskSupport.uint(stats["Bytes read from block device"])
            ?? DiskSupport.uint(stats["Bytes read by user"])
        let written = DiskSupport.uint(stats["Bytes (Write)"])
            ?? DiskSupport.uint(stats["Bytes written to block device"])
            ?? DiskSupport.uint(stats["Bytes written by user"])
        guard read != nil || written != nil else { return nil }
        return DiskIOCounters(read: read ?? 0, written: written ?? 0)
    }

    private static func wholeDiskBSDName(descendingFrom entry: io_registry_entry_t) -> String? {
        if let whole = property("Whole", from: entry) as? Bool,
           whole,
           let name = property("BSD Name", from: entry) as? String {
            return name
        }

        var iterator = io_iterator_t()
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var child = IOIteratorNext(iterator)
        while child != 0 {
            if let name = wholeDiskBSDName(descendingFrom: child) {
                IOObjectRelease(child)
                return name
            }
            IOObjectRelease(child)
            child = IOIteratorNext(iterator)
        }
        return nil
    }

    private static func property(_ key: String, from entry: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
