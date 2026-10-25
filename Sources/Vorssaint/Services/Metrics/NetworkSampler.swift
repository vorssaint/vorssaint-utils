// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// One network reading: instantaneous speed plus session totals.
struct NetworkReading {
    var downBytesPerSec: Double?   // nil until there is a previous sample
    var upBytesPerSec: Double?
    var totalDown: UInt64          // accumulated since the app started watching
    var totalUp: UInt64
    var totalDownloadSinceBootUp: UInt64?     // total data received since Mac boot
    var totalUploadSinceBootUp: UInt64?       // total data sent since Mac boot
}

/// Samples per-interface byte counters and derives speed, session totals and a
/// total data usage since boot up. State (previous counters, accumulated totals,
/// data usage accumulator) is only touched from the monitor's serial queue, so no
/// extra synchronization is needed.
final class NetworkSampler {
    private var previous: (counters: NetworkCounters, time: TimeInterval)?
    private var totalDownload: UInt64 = 0
    private var totalUpload: UInt64 = 0
    private var counterFallback = NetworkCounterFallback()
    private var processDeltaTracker = NetworkProcessDeltaTracker(maxGap: 30)
    private var dataUsageAccumulator = NetworkDataUsageAccumulator()
    private var bootID = ""
    private let counterReader: () -> [String: NetworkCounters]?
    private let processReader: () -> [NetworkProcessSample]?
    private let defaults: UserDefaults

    /// After a gap longer than this (sampling was paused), the previous reading
    /// is treated as a fresh baseline instead of producing a misleading spike.
    private static let maxGap: TimeInterval = 10

    init(counterReader: @escaping () -> [String: NetworkCounters]? = NetworkSampler.readCounters,
         processReader: @escaping () -> [NetworkProcessSample]? = {
             NetworkProcessSupport.currentExternalActivitySamples()
         },
         defaults: UserDefaults = .standard) {
        self.counterReader = counterReader
        self.processReader = processReader
        self.defaults = defaults
    }

    /// Read the total data usage, or nil until the first successful read.
    private var totalDataUsage: (download: UInt64?, upload: UInt64?) {
        dataUsageAccumulator.isSeeded ? (dataUsageAccumulator.totalDownload,
                                        dataUsageAccumulator.totalUpload)
                : (nil, nil)
    }

    func sample(now: TimeInterval) -> NetworkReading {
        guard let counters = counterReader() else {
            return NetworkReading(downBytesPerSec: nil, upBytesPerSec: nil,
                                  totalDown: totalDownload, totalUp: totalUpload,
                                  totalDownloadSinceBootUp: totalDataUsage.download, totalUploadSinceBootUp: totalDataUsage.upload)
        }

        // The total data usage hold steady while counters are unavailable above, so a Wi-Fi
        // drop, a VPN reconnect or an unplugged adapter never moves them down.
        if dataUsageAccumulator.isSeeded {
            dataUsageAccumulator.observe(counters)
        } else {
            bootID = LoadTotalDataUsage.currentBootID()
            dataUsageAccumulator.seed(current: counters,
                                 persisted: LoadTotalDataUsage.load(bootID: bootID, defaults: defaults))
        }
        LoadTotalDataUsage.save(bootID: bootID,
                                    down: dataUsageAccumulator.totalDownload,
                                    up: dataUsageAccumulator.totalUpload,
                                    defaults: defaults)

        let aggregate = NetworkCounters.totalData(counters)
        defer { previous = (aggregate, now) }

        guard let prev = previous, now > prev.time, now - prev.time <= Self.maxGap else {
            counterFallback.reset()
            processDeltaTracker.reset()
            return NetworkReading(downBytesPerSec: nil, upBytesPerSec: nil,
                                  totalDown: totalDownload, totalUp: totalUpload,
                                  totalDownloadSinceBootUp: dataUsageAccumulator.totalDownload,
                                  totalUploadSinceBootUp: dataUsageAccumulator.totalUpload)
        }

        let elapsed = now - prev.time
        let interfaceSpeed = MetricFormat.netSpeed(previous: prev.counters,
                                                   current: aggregate,
                                                   elapsed: elapsed)
        let fallback = counterFallback.observe(previous: prev.counters, current: aggregate)
        var processDown: Double?
        if fallback.sampleProcesses,
           let samples = processReader() {
            let hadBaseline = processDeltaTracker.hasBaseline(now: now)
            let rates = processDeltaTracker.rates(from: samples, now: now)
            if fallback.useProcessDownload, hadBaseline {
                processDown = rates.reduce(0) { $0 + $1.bytesIn }
            }
        } else if !fallback.useProcessDownload {
            processDeltaTracker.reset()
        }

        if let processDown {
            accumulate(rate: processDown, elapsed: elapsed, into: &totalDownload)
        } else if aggregate.received >= prev.counters.received {
            totalDownload = NetworkCounters.sumUpData(totalDownload, aggregate.received - prev.counters.received)
        }
        if aggregate.sent >= prev.counters.sent {
            totalUpload = NetworkCounters.sumUpData(totalUpload, aggregate.sent - prev.counters.sent)
        }
        return NetworkReading(downBytesPerSec: processDown ?? interfaceSpeed.down,
                              upBytesPerSec: interfaceSpeed.up,
                              totalDown: totalDownload, totalUp: totalUpload,
                              totalDownloadSinceBootUp: dataUsageAccumulator.totalDownload,
                              totalUploadSinceBootUp: dataUsageAccumulator.totalUpload)
    }

    private func accumulate(rate: Double, elapsed: TimeInterval, into total: inout UInt64) {
        let bytes = rate * elapsed
        guard bytes.isFinite, bytes > 0 else { return }
        guard bytes < Double(UInt64.max) else {
            total = UInt64.max
            return
        }
        let amount = UInt64(bytes.rounded(.down))
        let addition = total.addingReportingOverflow(amount)
        total = addition.overflow ? UInt64.max : addition.partialValue
    }

    /// Reads per-interface byte counters keyed by BSD interface name, keeping
    /// only the interfaces `MetricFormat.includeNetworkInterface` accepts.
    ///
    /// Counters come from the `net.link.generic.ifdata` MIB (`IFMIB_IFDATA`),
    /// which reports genuine 64-bit `if_data64` values. `NET_RT_IFLIST2` is
    /// avoided here because on current macOS the routing-socket path truncates
    /// `ifi_ibytes`/`ifi_obytes` to 32 bits, so a busy interface appears to roll
    /// back to zero after 4 GiB. The ifdata MIB matches `netstat -ib` exactly.
    static func readCounters() -> [String: NetworkCounters]? {
        let names = interfaceNames()
        guard !names.isEmpty else { return nil }
        var result: [String: NetworkCounters] = [:]
        for name in names {
            if let counters = readCounters(forInterface: name) {
                result[name] = counters
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func interfaceNames() -> Set<String> {
        var firstInterface: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstInterface) == 0 else { return [] }
        defer { freeifaddrs(firstInterface) }

        var interfaceNames = Set<String>()
        var currentInterface = firstInterface
        while let entry = currentInterface?.pointee {
            defer { currentInterface = entry.ifa_next }
            let name = String(cString: entry.ifa_name)
            if MetricFormat.includeNetworkInterface(name) {
                interfaceNames.insert(name)
            }
        }
        return interfaceNames
    }

    private static func readCounters(forInterface name: String) -> NetworkCounters? {
        let index = if_nametoindex(name)
        guard index > 0 else { return nil }

        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(index), IFDATA_GENERAL]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length >= MemoryLayout<ifmibdata>.size else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }

        let data = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: ifmibdata.self) }
        return NetworkCounters(received: data.ifmd_data.ifi_ibytes,
                               sent: data.ifmd_data.ifi_obytes)
    }
}
