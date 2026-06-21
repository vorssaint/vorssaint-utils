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

    static func memoryUsage() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        // mach_host_self() returns a send right the caller owns; release it or each
        // call leaks a mach port (this runs every couple of seconds while sampling).
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let total = ProcessInfo.processInfo.physicalMemory
        let used = MetricFormat.memoryUsed(totalBytes: total,
                                           pageSize: UInt64(vm_kernel_page_size),
                                           freePages: UInt64(stats.free_count),
                                           speculativePages: UInt64(stats.speculative_count),
                                           fileBackedPages: UInt64(stats.external_page_count))
        return (used, total)
    }
}
