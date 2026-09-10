// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import IOKit
import IOKit.ps

struct BatteryInfo: Equatable {
    let percent: Int
    let isCharging: Bool
    let isOnBattery: Bool
    let externalConnected: Bool
}

/// Point-in-time system facts that need no special permissions.
/// The battery snapshot feeds the keep-awake battery protection; the memory
/// reading feeds the system monitor.
enum SystemInfo {
    static func wallClockUptimeSeconds(now: Date = Date()) -> Int? {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else { return nil }
        guard bootTime.tv_sec > 0 else { return nil }

        let bootSeconds = Double(bootTime.tv_sec) + Double(bootTime.tv_usec) / 1_000_000
        let elapsed = now.timeIntervalSince1970 - bootSeconds
        guard elapsed.isFinite, elapsed >= 0 else { return nil }
        return Int(elapsed.rounded(.down))
    }

    static func batterySnapshot() -> BatteryInfo? {
        guard PowerSampler.hasInternalBattery else { return nil }
        guard let blobRef = IOPSCopyPowerSourcesInfo() else { return nil }
        let blob = blobRef.takeRetainedValue()
        guard let listRef = IOPSCopyPowerSourcesList(blob) else { return nil }
        let list = listRef.takeRetainedValue() as [AnyObject]
        guard let first = list.first,
              let descRef = IOPSGetPowerSourceDescription(blob, first),
              let desc = descRef.takeUnretainedValue() as? [String: Any]
        else { return nil }

        let current = desc["Current Capacity"] as? Int ?? 0
        let max = desc["Max Capacity"] as? Int ?? 100
        let percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
        let state = desc[kIOPSPowerSourceStateKey] as? String ?? ""
        let externalConnected = state == kIOPSACPowerValue
        let charging = externalConnected && (desc[kIOPSIsChargingKey] as? Bool ?? false)
        return BatteryInfo(percent: percent,
                           isCharging: charging,
                           isOnBattery: state == kIOPSBatteryPowerValue,
                           externalConnected: externalConnected)
    }

    /// Reads the battery driver directly, bypassing the cached IOPS snapshot.
    static func batteryRegistrySnapshot() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
                == kIOReturnSuccess,
              let values = properties?.takeRetainedValue() as? [String: Any],
              let externalConnected = values["ExternalConnected"] as? Bool,
              let isCharging = values["IsCharging"] as? Bool else { return nil }
        let current = values["CurrentCapacity"] as? Int ?? 0
        let maximum = values["MaxCapacity"] as? Int ?? 100
        let percent = maximum > 0
            ? Int((Double(current) / Double(maximum) * 100).rounded())
            : current
        return BatteryInfo(percent: percent,
                           isCharging: externalConnected && isCharging,
                           isOnBattery: !externalConnected,
                           externalConnected: externalConnected)
    }

    static func memoryUsage() -> (used: UInt64, appUsed: UInt64, total: UInt64, compressed: UInt64, cached: UInt64, swapUsed: UInt64?)? {
        guard let stats = VMStatisticsDecoder.read() else { return nil }
        let total = ProcessInfo.processInfo.physicalMemory
        let pageSize = UInt64(vm_kernel_page_size)
        let tagStoragePages = VMStatisticsDecoder.validatedTagStoragePages(
            stats.tagStoragePages,
            totalBytes: total,
            pageSize: pageSize)
        let appUsed = MetricFormat.appMemory(totalBytes: total,
                                             pageSize: pageSize,
                                             internalPages: stats.internalPages,
                                             purgeablePages: stats.purgeablePages)
        let used = MetricFormat.memoryUsed(totalBytes: total,
                                           appBytes: appUsed,
                                           pageSize: pageSize,
                                           wiredPages: stats.wiredPages,
                                           compressorPages: stats.compressorPages,
                                           tagStoragePages: tagStoragePages)
        let compressed = MetricFormat.compressedMemory(totalBytes: total,
                                                       pageSize: pageSize,
                                                       compressorPages: stats.compressorPages)
        let cached = MetricFormat.cachedFiles(totalBytes: total,
                                              pageSize: pageSize,
                                              fileBackedPages: stats.externalPages)
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
            ? swap.xsu_used
            : nil
        return (used, appUsed, total, compressed, cached, swapUsed)
    }
}
