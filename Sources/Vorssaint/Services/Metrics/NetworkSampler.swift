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
}

/// Samples cumulative interface byte counters and derives speed + session totals.
/// State (previous counters, accumulated totals) is only touched from the
/// monitor's serial queue, so no extra synchronization is needed.
final class NetworkSampler {
    private var previous: (counters: NetworkCounters, time: TimeInterval)?
    private var totalDown: UInt64 = 0
    private var totalUp: UInt64 = 0
    private var counterFallback = NetworkCounterFallback()
    private var processDeltaTracker = NetworkProcessDeltaTracker(maxGap: 30)
    private let counterReader: () -> NetworkCounters
    private let processReader: () -> [NetworkProcessSample]?

    /// After a gap longer than this (sampling was paused), the previous reading
    /// is treated as a fresh baseline instead of producing a misleading spike.
    private static let maxGap: TimeInterval = 10

    init(counterReader: @escaping () -> NetworkCounters = NetworkSampler.readCounters,
         processReader: @escaping () -> [NetworkProcessSample]? = {
             NetworkProcessSupport.currentExternalActivitySamples()
         }) {
        self.counterReader = counterReader
        self.processReader = processReader
    }

    func sample(now: TimeInterval) -> NetworkReading {
        let counters = counterReader()
        defer { previous = (counters, now) }

        guard let prev = previous, now > prev.time, now - prev.time <= Self.maxGap else {
            return NetworkReading(downBytesPerSec: nil, upBytesPerSec: nil,
                                  totalDown: totalDown, totalUp: totalUp)
        }

        let elapsed = now - prev.time
        let interfaceSpeed = MetricFormat.netSpeed(previous: prev.counters,
                                                   current: counters,
                                                   elapsed: elapsed)
        let fallback = counterFallback.observe(previous: prev.counters, current: counters)
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
            accumulate(rate: processDown, elapsed: elapsed, into: &totalDown)
        } else if counters.received >= prev.counters.received {
            totalDown += counters.received - prev.counters.received
        }
        if counters.sent >= prev.counters.sent {
            totalUp += counters.sent - prev.counters.sent
        }
        return NetworkReading(downBytesPerSec: processDown ?? interfaceSpeed.down,
                              upBytesPerSec: interfaceSpeed.up,
                              totalDown: totalDown, totalUp: totalUp)
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

    /// Sums received/sent bytes across the physical interfaces via the routing
    /// socket (`NET_RT_IFLIST2`), which reports 64-bit counters in `if_data64` —
    /// unlike `getifaddrs`, whose 32-bit counters wrap and corrupt totals.
    static func readCounters() -> NetworkCounters {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else {
            return NetworkCounters()
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else {
            return NetworkCounters()
        }

        var result = NetworkCounters()
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr>.size
            while offset + headerSize <= length {
                let header = base.advanced(by: offset)
                    .assumingMemoryBound(to: if_msghdr.self).pointee
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }

                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = base.advanced(by: offset)
                        .assumingMemoryBound(to: if_msghdr2.self).pointee
                    var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        if MetricFormat.includeNetworkInterface(name) {
                            result.received += info.ifm_data.ifi_ibytes
                            result.sent += info.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += messageLength
            }
        }
        return result
    }
}
