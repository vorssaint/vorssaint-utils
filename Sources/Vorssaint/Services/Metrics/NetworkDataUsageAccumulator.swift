// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// The persisted the total data usage, tagged with the boot they belong to so a
/// reboot starts fresh instead of carrying bytes across boots.
struct TotalDataUsage: Codable, Equatable {
    var bootID: String
    var totalDownload: UInt64
    var totalUpload: UInt64
}

/// Loads and saves the data network usage in UserDefaults and detects reboots.
enum LoadTotalDataUsage {
    /// A per-boot identifier from the kernel (`kern.bootsessionuuid`), falling
    /// back to the boot time when the UUID is unavailable.
    static func currentBootID() -> String {
        var uuid = [CChar](repeating: 0, count: 64)
        var uuidSize = uuid.count
        if sysctlbyname("kern.bootsessionuuid", &uuid, &uuidSize, nil, 0) == 0 {
            return String(cString: uuid)
        }
        var boot = timeval()
        var bootSize = MemoryLayout<timeval>.stride
        if sysctlbyname("kern.boottime", &boot, &bootSize, nil, 0) == 0 {
            return "boottime-\(boot.tv_sec)-\(boot.tv_usec)"
        }
        return "unknown"
    }

    /// Returns the persisted totals only when they belong to this boot.
    static func load(bootID: String, defaults: UserDefaults = .standard) -> (down: UInt64, up: UInt64)? {
        guard let data = defaults.data(forKey: DefaultsKey.monitorDataUsage),
              let saved = try? JSONDecoder().decode(TotalDataUsage.self, from: data),
              saved.bootID == bootID else { return nil }
        return (saved.totalDownload, saved.totalUpload)
    }

    static func save(bootID: String, down: UInt64, up: UInt64, defaults: UserDefaults = .standard) {
        let payload = TotalDataUsage(bootID: bootID, totalDownload: down, totalUpload: up)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: DefaultsKey.monitorDataUsage)
    }
}

/// Accumulates "bytes since boot" from per-interface counters so the total only
/// ever climbs, across interface, counter resets, and app restarts.
///
/// The kernel exposes per-interface counters, not a cross-interface total.
/// Summing raw counters drops bytes when an interface disappears (an unplugged
/// Ethernet adapter, a VPN that carried traffic). This type keeps its own
/// running total and only ever adds forward progress, one interface at a time.
struct NetworkDataUsageAccumulator: Equatable {
    private(set) var baselines: [String: NetworkCounters] = [:]
    private(set) var totalDownload: UInt64 = 0
    private(set) var totalUpload: UInt64 = 0
    private(set) var isSeeded = false

    /// Seeds baselines and totals from the first observation, never lowering a
    /// persisted total data usage. A `nil` persisted value
    /// means a fresh boot or first run, so the total starts from the current sum.
    mutating func seed(current: [String: NetworkCounters],
                       persisted: (down: UInt64, up: UInt64)?) {
        baselines = current
        let seed = NetworkCounters.totalData(current)
        totalDownload = max(persisted?.down ?? 0, seed.received)
        totalUpload = max(persisted?.up ?? 0, seed.sent)
        isSeeded = true
    }

    /// Adds forward progress for one interval and returns the updated totals.
    /// A counter that moved backward is a reset: its delta is skipped and the new value becomes the baseline.
    /// A new interface only establishes a baseline.
    /// Interfaces no longer present drop only their baseline, never their already-counted bytes.
    @discardableResult
    mutating func observe(_ current: [String: NetworkCounters]) -> (down: UInt64, up: UInt64) {
        let present = Set(current.keys)
        baselines = baselines.filter { present.contains($0.key) }

        for (name, counters) in current {
            if let baseline = baselines[name] {
                if counters.received > baseline.received {
                    totalDownload = NetworkCounters.sumUpData(totalDownload, counters.received - baseline.received)
                }
                if counters.sent > baseline.sent {
                    totalUpload = NetworkCounters.sumUpData(totalUpload, counters.sent - baseline.sent)
                }
            }
            baselines[name] = counters
        }
        return (totalDownload, totalUpload)
    }
}
