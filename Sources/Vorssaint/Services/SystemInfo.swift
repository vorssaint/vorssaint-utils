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
                                             internalPages: stats.internalPages,
                                             purgeablePages: stats.purgeablePages)
        let used = MetricFormat.memoryUsed(totalBytes: total,
                                           appBytes: appUsed,
                                           pageSize: pageSize,
                                           wiredPages: stats.wiredPages,
                                           compressorPages: stats.compressorPages,
                                           tagStoragePages: stats.tagStoragePages)
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

    private struct VMStatisticsSnapshot {
        let wiredPages: UInt64
        let purgeablePages: UInt64
        let compressorPages: UInt64
        let externalPages: UInt64
        let internalPages: UInt64
        let tagStoragePages: UInt64
    }

    /// Byte offsets in Apple's public HOST_VM_INFO64 rev3 ABI. Requesting the
    /// rev3 size is backward-compatible: older kernels return a shorter count,
    /// leaving the zero-initialized tagged-storage tail unavailable.
    private enum VMStatistics64Layout {
        static let integerSize = MemoryLayout<integer_t>.stride
        static let rev3ByteCount = 248
        static let rev3Count = rev3ByteCount / integerSize

        static let wired = 12
        static let purgeable = 88
        static let compressor = 128
        static let external = 136
        static let `internal` = 140
        static let totalTagStorage = 160
    }

    private static func vmStats() -> VMStatisticsSnapshot? {
        let layout = VMStatistics64Layout.self
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: layout.rev3ByteCount,
                                                      alignment: MemoryLayout<UInt64>.alignment)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: layout.rev3ByteCount)
        var count = mach_msg_type_number_t(layout.rev3Count)
        // mach_host_self() returns a send right the caller owns; release it or each
        // call leaks a mach port (this runs every couple of seconds while sampling).
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let kr = host_statistics64(host,
                                   HOST_VM_INFO64,
                                   buffer.assumingMemoryBound(to: integer_t.self),
                                   &count)
        guard kr == KERN_SUCCESS else { return nil }

        func natural(at offset: Int) -> UInt64 {
            UInt64(buffer.load(fromByteOffset: offset, as: natural_t.self))
        }
        func uint64(at offset: Int) -> UInt64 {
            buffer.load(fromByteOffset: offset, as: UInt64.self)
        }
        let hasRev3 = Int(count) >= layout.rev3Count

        return VMStatisticsSnapshot(
            wiredPages: natural(at: layout.wired),
            purgeablePages: natural(at: layout.purgeable),
            compressorPages: natural(at: layout.compressor),
            externalPages: natural(at: layout.external),
            internalPages: natural(at: layout.internal),
            tagStoragePages: hasRev3 ? uint64(at: layout.totalTagStorage) : 0)
    }
}
