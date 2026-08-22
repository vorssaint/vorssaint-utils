// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import IOKit.ps

struct BatteryInfo {
    let percent: Int
    let isCharging: Bool
    let isOnBattery: Bool
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
        let charging = desc["Is Charging"] as? Bool ?? false
        let state = desc["Power Source State"] as? String ?? ""
        return BatteryInfo(percent: percent,
                           isCharging: charging,
                           isOnBattery: state == "Battery Power")
    }

    static func memoryUsage() -> (used: UInt64, appUsed: UInt64, total: UInt64, compressed: UInt64, cached: UInt64, swapUsed: UInt64?)? {
        guard let stats = vmStats() else { return nil }
        let total = ProcessInfo.processInfo.physicalMemory
        let pageSize = UInt64(vm_kernel_page_size)
        let appUsed = MetricFormat.appMemory(totalBytes: total,
                                             pageSize: pageSize,
                                             internalPages: UInt64(stats.internal_page_count),
                                             purgeablePages: UInt64(stats.purgeable_count))
        let used = MetricFormat.memoryUsed(totalBytes: total,
                                           appBytes: appUsed,
                                           pageSize: pageSize,
                                           wiredPages: UInt64(stats.wire_count),
                                           compressorPages: UInt64(stats.compressor_page_count),
                                           tagStoragePages: stats.total_tag_storage_pages)
        let compressed = MetricFormat.compressedMemory(totalBytes: total,
                                                       pageSize: pageSize,
                                                       compressorPages: UInt64(stats.compressor_page_count))
        let cached = MetricFormat.cachedFiles(totalBytes: total,
                                              pageSize: pageSize,
                                              fileBackedPages: UInt64(stats.external_page_count))
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
            ? swap.xsu_used
            : nil
        return (used, appUsed, total, compressed, cached, swapUsed)
    }

    /// A local copy of the HOST_VM_INFO64 rev3 layout.  Xcode 16.2's SDK only
    /// exposes rev2, despite newer kernels reporting the tagged-storage fields.
    private struct VMStatistics64 {
        var free_count: natural_t = 0
        var active_count: natural_t = 0
        var inactive_count: natural_t = 0
        var wire_count: natural_t = 0
        var zero_fill_count: UInt64 = 0
        var reactivations: UInt64 = 0
        var pageins: UInt64 = 0
        var pageouts: UInt64 = 0
        var faults: UInt64 = 0
        var cow_faults: UInt64 = 0
        var lookups: UInt64 = 0
        var hits: UInt64 = 0
        var purges: UInt64 = 0
        var purgeable_count: natural_t = 0
        var speculative_count: natural_t = 0
        var decompressions: UInt64 = 0
        var compressions: UInt64 = 0
        var swapins: UInt64 = 0
        var swapouts: UInt64 = 0
        var compressor_page_count: natural_t = 0
        var throttled_count: natural_t = 0
        var external_page_count: natural_t = 0
        var internal_page_count: natural_t = 0
        var total_uncompressed_pages_in_compressor: UInt64 = 0
        var swapped_count: UInt64 = 0
        var total_tag_storage_pages: UInt64 = 0
        var nontag_pageable_tag_storage_pages: UInt64 = 0
        var nontag_wired_tag_storage_pages: UInt64 = 0
        var free_tag_storage_pages: UInt64 = 0
        var tag_storing_tag_storage_pages: UInt64 = 0
        var total_tagged_pages: UInt64 = 0
        var resident_tagged_pages: UInt64 = 0
        var compressed_tagged_pages: UInt64 = 0
        var tagged_compressions: UInt64 = 0
        var tagged_decompressions: UInt64 = 0
        var compressed_tag_storage_bytes: UInt64 = 0

        init() {}

        init(legacy stats: vm_statistics64) {
            free_count = stats.free_count
            active_count = stats.active_count
            inactive_count = stats.inactive_count
            wire_count = stats.wire_count
            purgeable_count = stats.purgeable_count
            speculative_count = stats.speculative_count
            compressor_page_count = stats.compressor_page_count
            external_page_count = stats.external_page_count
            internal_page_count = stats.internal_page_count
        }
    }

    private static func vmStats() -> VMStatistics64? {
        var stats = VMStatistics64()
        if readVMStats(into: &stats) == KERN_SUCCESS {
            return stats
        }

        // Older kernels may reject a rev3-sized request. In that case, retain
        // the fields available in their SDK layout and leave tag storage at 0.
        var legacy = vm_statistics64()
        guard readVMStats(into: &legacy) == KERN_SUCCESS else { return nil }
        return VMStatistics64(legacy: legacy)
    }

    private static func readVMStats<T>(into stats: inout T) -> kern_return_t {
        var count = mach_msg_type_number_t(MemoryLayout<T>.stride / MemoryLayout<integer_t>.stride)
        // mach_host_self() returns a send right the caller owns; release it or each
        // call leaks a mach port (this runs every couple of seconds while sampling).
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        return kr
    }
}
