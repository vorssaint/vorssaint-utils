// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Cumulative interface byte counters (since boot), read from the kernel.
/// 64-bit so they never wrap on fast links — the reason totals stay accurate.
struct NetworkCounters: Equatable {
    var received: UInt64 = 0
    var sent: UInt64 = 0
}

/// Detects the macOS failure mode where outbound interface counters keep moving
/// while inbound counters stay frozen. The first suspect sample only primes the
/// process reader; a second consecutive sample is required before using it.
struct NetworkCounterFallback {
    private(set) var isActive = false
    private var missingInboundSamples = 0

    mutating func observe(previous: NetworkCounters,
                          current: NetworkCounters) -> (sampleProcesses: Bool, useProcessDownload: Bool) {
        guard current.received >= previous.received,
              current.sent >= previous.sent else {
            reset()
            return (false, false)
        }

        if current.received > previous.received {
            reset()
            return (false, false)
        }

        let outgoingAdvanced = current.sent > previous.sent
        if isActive {
            // Once the inbound interface counter is known to be frozen, lack
            // of upload says nothing about download. Keep sampling socket
            // flows until the received counter itself proves recovery.
            return (true, true)
        }

        if outgoingAdvanced {
            missingInboundSamples += 1
        } else {
            missingInboundSamples = 0
        }
        if missingInboundSamples >= 2 {
            isActive = true
        }
        return (outgoingAdvanced, isActive)
    }

    mutating func reset() {
        isActive = false
        missingInboundSamples = 0
    }
}

struct DiskIOCounters: Equatable {
    var read: UInt64 = 0
    var written: UInt64 = 0
}

/// Pure, deterministic helpers for the system monitor: number formatting, the
/// fixed-size history buffer, network speed math and interface filtering.
///
/// Everything here depends only on Foundation — no IOKit, no AppKit, no UI — so
/// it compiles and runs standalone in the unit-test target (`./build.sh --test`).
enum MetricFormat {
    // MARK: Memory

    /// Matches Activity Monitor's "Memory Used": physical RAM minus pages that
    /// are free, speculative, or file-backed cache. The side breakdown
    /// (App/Wired/Compressed) does not expose every bucket counted in the total.
    static func memoryUsed(totalBytes: UInt64,
                           pageSize: UInt64,
                           freePages: UInt64,
                           speculativePages: UInt64,
                           fileBackedPages: UInt64) -> UInt64 {
        guard totalBytes > 0, pageSize > 0 else { return 0 }
        let freeAndSpeculative = freePages.addingReportingOverflow(speculativePages)
        guard !freeAndSpeculative.overflow else { return 0 }
        let availablePages = freeAndSpeculative.partialValue.addingReportingOverflow(fileBackedPages)
        guard !availablePages.overflow else { return 0 }
        let availableBytes = availablePages.partialValue.multipliedReportingOverflow(by: pageSize)
        guard !availableBytes.overflow else { return 0 }
        return availableBytes.partialValue >= totalBytes ? 0 : totalBytes - availableBytes.partialValue
    }

    /// Purgeable internal pages do not count because the system can reclaim
    /// them on demand.
    static func appMemory(totalBytes: UInt64,
                          pageSize: UInt64,
                          internalPages: UInt64,
                          purgeablePages: UInt64) -> UInt64 {
        guard totalBytes > 0, pageSize > 0 else { return 0 }
        let activePages = internalPages.subtractingReportingOverflow(purgeablePages)
        guard !activePages.overflow else { return 0 }
        let activeBytes = activePages.partialValue.multipliedReportingOverflow(by: pageSize)
        guard !activeBytes.overflow else { return 0 }
        return min(activeBytes.partialValue, totalBytes)
    }

    /// Physical RAM held by the compressor. Already counted inside Memory Used.
    static func compressedMemory(totalBytes: UInt64,
                                 pageSize: UInt64,
                                 compressorPages: UInt64) -> UInt64 {
        pageBytes(pageCount: compressorPages, pageSize: pageSize, totalBytes: totalBytes)
    }

    /// File-backed pages the system can drop. Memory Used already excludes them.
    static func cachedFiles(totalBytes: UInt64,
                            pageSize: UInt64,
                            fileBackedPages: UInt64) -> UInt64 {
        pageBytes(pageCount: fileBackedPages, pageSize: pageSize, totalBytes: totalBytes)
    }

    private static func pageBytes(pageCount: UInt64, pageSize: UInt64, totalBytes: UInt64) -> UInt64 {
        guard totalBytes > 0, pageSize > 0 else { return 0 }
        let bytes = pageCount.multipliedReportingOverflow(by: pageSize)
        guard !bytes.overflow else { return 0 }
        return min(bytes.partialValue, totalBytes)
    }

    /// Keeps every memory surface on the same persisted choice. Unknown
    /// values intentionally fall back to total memory in use.
    static func selectedMemory<Value>(used: Value, app: Value, metric: String) -> Value {
        metric == "app" ? app : used
    }

    /// Menu bar memory should keep its slot even while a transient sample is
    /// unavailable, so the status item does not disappear and reappear.
    static func menuBarMemoryPercent(used: UInt64?, total: UInt64?) -> String {
        guard let used, let total, total > 0 else { return "--%" }
        return percent(Double(used) / Double(total))
    }

    // MARK: Byte sizes

    /// Splits a byte count into a human value + unit, base-1024.
    static func scale(_ bytes: Double) -> (value: Double, unit: String) {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = max(0, bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return (value, units[index])
    }

    /// Bytes (raw) → "0", "8" for B; one decimal under 10, none at or above.
    private static func number(_ value: Double, unit: String) -> String {
        if unit == "B" { return String(format: "%.0f", value) }
        return value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }

    /// A whole quantity of bytes, e.g. "1.2 GB". Used for session totals.
    static func bytes(_ bytes: UInt64) -> String {
        let (value, unit) = scale(Double(bytes))
        return "\(number(value, unit: unit)) \(unit)"
    }

    static func diskBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = max(0, Double(bytes))
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if units[index] == "B" {
            return String(format: "%.0f B", value)
        }
        return value < 10 ? String(format: "%.1f %@", value, units[index])
            : String(format: "%.0f %@", value, units[index])
    }

    static func diskBytesPrecise(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = max(0, Double(bytes))
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let unit = units[index]
        if unit == "B" {
            return String(format: "%.0f B", value)
        }
        if unit == "TB" || unit == "PB" {
            return String(format: "%.2f %@", value, unit)
        }
        return value < 10 ? String(format: "%.1f %@", value, unit)
            : String(format: "%.0f %@", value, unit)
    }

    /// A throughput, e.g. "1.2 MB/s". Used in the panel.
    static func bytesPerSec(_ bytesPerSecond: Double) -> String {
        let (value, unit) = scale(bytesPerSecond)
        return "\(number(value, unit: unit)) \(unit)/s"
    }

    /// A compact throughput for the menu bar, e.g. "1.2M", "320K", "0B".
    static func bytesPerSecCompact(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G", "T", "P"]
        var value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        while index < units.count - 1 {
            if index == 0 {
                guard value.rounded() >= 1024 else { break }
            } else if value >= 10 {
                guard value.rounded() >= 1024 else { break }
            } else {
                break
            }
            value /= 1024
            index += 1
        }
        if index == 0 {
            return "\(Int(value.rounded()))B"
        }
        if value < 10 {
            let rounded = (value * 10).rounded() / 10
            if rounded >= 10 {
                return "\(Int(rounded.rounded()))\(units[index])"
            }
            return String(format: "%.1f%@", rounded, units[index])
        }
        return "\(Int(value.rounded()))\(units[index])"
    }

    // MARK: Watts & percentages

    /// Power, e.g. "8.5 W" / "23 W" (one decimal under 10, none above).
    static func watts(_ value: Double) -> String {
        let magnitude = abs(value)
        return magnitude < 10 ? String(format: "%.1f W", value) : String(format: "%.0f W", value)
    }

    /// Compact power for the menu bar, e.g. "9W".
    static func wattsCompact(_ value: Double) -> String {
        String(format: "%.0fW", value.rounded())
    }

    static func systemPowerWatts(measured: Double?,
                                 batteryWatts: Double?,
                                 externalConnected: Bool) -> Double? {
        if let measured { return measured }
        guard !externalConnected, let batteryWatts, batteryWatts < 0 else { return nil }
        return -batteryWatts
    }

    /// A 0...1 fraction as a rounded percentage, e.g. "12%".
    static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, min(1, fraction)) * 100).rounded()))%"
    }

    /// Smooths the GPU usage readout enough to hide one-sample compositor spikes
    /// from opening the menu panel, without hiding sustained load.
    static func stabilizedGPUUsage(previous: Double?, current: Double) -> Double {
        let value = current.isFinite ? max(0, min(1, current)) : 0
        guard let previous, previous.isFinite else { return value }
        let baseline = max(0, min(1, previous))
        if value > baseline {
            return min(value, baseline + 0.20)
        }
        return baseline * 0.35 + value * 0.65
    }

    /// Temperature, stored internally as Celsius and formatted in the user's
    /// preferred display unit.
    static func temperature(_ celsius: Double, unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius:
            return String(format: "%.0f °C", celsius)
        case .fahrenheit:
            return String(format: "%.0f °F", celsius * 9 / 5 + 32)
        }
    }

    /// Compact temperature for tight surfaces like the menu bar. The settings
    /// page still makes the active unit explicit.
    static func temperatureCompact(_ celsius: Double, unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius:
            return String(format: "%.0f°", celsius)
        case .fahrenheit:
            return String(format: "%.0f°", celsius * 9 / 5 + 32)
        }
    }

    static func temperatureUnitSuffix(_ unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    static func uptime(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)min" }
        return "\(minutes)min"
    }

    // MARK: Network speed & filtering

    /// Per-second download/upload from two cumulative readings. Guards against a
    /// zero/negative interval and counter resets (interface down, rare wrap):
    /// a non-increasing counter yields 0 for that tick rather than a bogus spike.
    static func netSpeed(previous: NetworkCounters,
                         current: NetworkCounters,
                         elapsed: Double) -> (down: Double, up: Double) {
        guard elapsed > 0 else { return (0, 0) }
        let down = current.received >= previous.received
            ? Double(current.received - previous.received) / elapsed : 0
        let up = current.sent >= previous.sent
            ? Double(current.sent - previous.sent) / elapsed : 0
        return (down, up)
    }

    static func diskSpeed(previous: DiskIOCounters,
                          current: DiskIOCounters,
                          elapsed: Double) -> (read: Double, write: Double) {
        guard elapsed > 0 else { return (0, 0) }
        let read = current.read >= previous.read
            ? Double(current.read - previous.read) / elapsed : 0
        let write = current.written >= previous.written
            ? Double(current.written - previous.written) / elapsed : 0
        return (read, write)
    }

    /// Whether an interface counts toward "real" network throughput. Loopback and
    /// virtual interfaces (AirDrop, VPN tunnels, bridges, etc.) are excluded so a
    /// VPN does not double-count the traffic already seen on the physical NIC.
    static func includeNetworkInterface(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let excluded = ["lo", "gif", "stf", "awdl", "llw", "nan", "utun", "bridge",
                        "ap", "anpi", "p2p", "XHC", "vmenet", "tap", "tun"]
        return !excluded.contains { name.hasPrefix($0) }
    }
}

enum TemperatureUnit: String {
    case celsius
    case fahrenheit
}

/// Fixed-size ring of recent samples (oldest → newest) for the history graphs.
/// Appending past `capacity` drops the oldest values.
struct MetricHistory {
    let capacity: Int
    private(set) var values: [Double] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    mutating func push(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    /// Graph data is useful only while a graph surface is visible. Returning an
    /// empty publication at rest leaves this ring intact for the next opening
    /// without making every background sample copy its retained array.
    func publishedValues(whileVisible visible: Bool) -> [Double] {
        visible ? values : []
    }
}
