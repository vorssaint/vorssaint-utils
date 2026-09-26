// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Runs the production CPU reader against scripted host tick counters.
enum SystemMonitorCPUTests {
    class Fixture {
        var previousCPUTicks: (busy: UInt64, total: UInt64, time: TimeInterval)?
        var lastCPUUsage: Double?
        var lastCPUUsageReadAt: TimeInterval?
        var ticks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) = (0, 0, 0, 0)
        func host_statistics(_ host: host_t, _ flavor: host_flavor_t, _ info: host_info_t,
                             _ count: UnsafeMutablePointer<mach_msg_type_number_t>) -> kern_return_t {
            info.withMemoryRebound(to: host_cpu_load_info.self, capacity: 1) {
                $0.pointee.cpu_ticks = (ticks.user, ticks.system, ticks.idle, ticks.nice)
            }
            return KERN_SUCCESS
        }
    }

    static func run(_ suite: TestSuite) {
        let monitor = Monitor()
        monitor.ticks = (100, 100, 800, 0)
        suite.expect(monitor.readCPUUsage(now: 0) == nil, "the first CPU read only sets a baseline")
        monitor.ticks = (200, 200, 1_400, 0)
        suite.expect(monitor.readCPUUsage(now: 5) == 0.25, "a regular CPU read is the busy share since the last one")
        monitor.lastCPUUsage = 0.25
        monitor.lastCPUUsageReadAt = 5
        monitor.ticks = (1_200, 1_200, 1_600, 0)
        suite.expect(monitor.readCPUUsage(now: 65) == nil,
                     "a CPU read after a long gap only resets the baseline instead of reporting the gap's average")
        suite.expect(monitor.lastCPUUsage == nil && monitor.lastCPUUsageReadAt == nil,
                     "a CPU read after a long gap drops the value and read time held from before the gap")
        monitor.ticks = (1_300, 1_300, 1_800, 0)
        suite.expect(monitor.readCPUUsage(now: 70) == 0.5, "sampling resumes from the reset baseline")
    }
}
