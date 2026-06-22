// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads the battery "Maximum Capacity" percentage exactly as macOS System
/// Information shows it. On Apple Silicon that figure is a smoothed value Apple
/// computes, not a raw capacity ratio, so dividing IORegistry capacities never
/// quite matches System Report. The only way to match it is to read the same
/// source macOS does: `system_profiler SPPowerDataType`.
///
/// That call is slow (seconds) and the value changes over weeks, not seconds, so
/// it runs off the hot path on a utility queue and is cached. Callers read the
/// cached value and fall back to the IORegistry ratio when it isn't available
/// (no battery, or a macOS that doesn't expose the field, e.g. some betas).
final class MaxCapacityProbe {
    static let shared = MaxCapacityProbe()

    private let queue = DispatchQueue(label: "com.vorssaint.maxcapacity", qos: .utility)
    private let lock = NSLock()
    private var cached: Int?
    private var lastRefresh: TimeInterval = -.greatestFiniteMagnitude
    private var running = false
    private let interval: TimeInterval = 1800   // 30 minutes is plenty for battery health

    private init() {}

    /// The macOS-reported maximum capacity (1...100), or nil if not yet known or
    /// unavailable. Thread-safe.
    var percent: Int? {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    /// Refreshes the cache if it's stale. Non-blocking; the slow work runs on a
    /// utility queue. Safe to call on every sample.
    func refreshIfStale() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard !running, now - lastRefresh >= interval else {
            lock.unlock()
            return
        }
        running = true
        lastRefresh = now
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            let value = Self.read()
            self.lock.lock()
            self.cached = value
            self.running = false
            self.lock.unlock()
        }
    }

    /// Parses `sppower_battery_health_maximum_capacity` (a string like "95%") out
    /// of system_profiler's JSON. Returns nil when the field is missing or not a
    /// usable number (e.g. a macOS that prints a placeholder dash).
    private static func read() -> Int? {
        let result = Shell.run("/usr/sbin/system_profiler", ["SPPowerDataType", "-json"])
        guard result.status == 0,
              let data = result.output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]]
        else { return nil }
        for item in items {
            guard let health = item["sppower_battery_health_info"] as? [String: Any],
                  let raw = health["sppower_battery_health_maximum_capacity"] as? String
            else { continue }
            let digits = raw.filter(\.isNumber)
            if let value = Int(digits), value > 0, value <= 100 { return value }
        }
        return nil
    }
}
