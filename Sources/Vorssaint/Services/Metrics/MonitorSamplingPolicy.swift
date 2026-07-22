// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MonitorSamplingKind: String {
    case cpu
    case memory
    case network
    case disk
    case power
    case peripheralBattery
    case gpuUsage
    case temperature
    case fanSpeeds
}

enum MonitorSamplingPolicy {
    static func shouldSample(_ kind: MonitorSamplingKind,
                             tick: Int,
                             intervalSeconds: Int,
                             foreground: Bool) -> Bool {
        let stride = sampleStride(for: kind,
                                  intervalSeconds: intervalSeconds,
                                  foreground: foreground)
        return tick % stride == 0
    }

    static func sampleStride(for kind: MonitorSamplingKind,
                             intervalSeconds: Int,
                             foreground: Bool) -> Int {
        let interval = max(1, intervalSeconds)
        let targetSeconds = targetIntervalSeconds(for: kind, foreground: foreground)
        return max(1, Int(ceil(targetSeconds / Double(interval))))
    }

    /// The timer cadence, in base ticks, that still lands every needed kind
    /// exactly on its stride: the GCD of the strides. With only slow metrics
    /// on (say, temperature in the menu bar and nothing else) the timer can
    /// wake once per several ticks instead of waking just to skip everything;
    /// with any every-tick metric this stays 1 and nothing changes.
    static func wakeTicks(for kinds: [MonitorSamplingKind],
                          intervalSeconds: Int,
                          foreground: Bool) -> Int {
        let cadence = kinds.reduce(0) { partial, kind in
            gcd(partial, sampleStride(for: kind, intervalSeconds: intervalSeconds, foreground: foreground))
        }
        return max(1, cadence)
    }

    /// Rounds a tick up onto the wake grid after a cadence change. Ticks then
    /// advance in `wakeTicks` steps, and `tick % stride == 0` only stays
    /// reachable for grid-aligned ticks (an off-grid tick would never hit a
    /// stride multiple again and the metric would silently stop sampling).
    static func alignedTick(_ tick: Int, wakeTicks: Int) -> Int {
        guard wakeTicks > 1 else { return tick }
        let remainder = tick % wakeTicks
        return remainder == 0 ? tick : tick + (wakeTicks - remainder)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a
        var b = b
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return a
    }

    private static func targetIntervalSeconds(for kind: MonitorSamplingKind,
                                              foreground: Bool) -> Double {
        if foreground {
            switch kind {
            case .peripheralBattery:
                return 15
            case .cpu, .memory, .network, .disk, .power, .gpuUsage, .temperature, .fanSpeeds:
                return 1
            }
        }

        switch kind {
        case .cpu, .memory, .network:
            return 1
        case .gpuUsage:
            return 10
        case .power, .temperature, .fanSpeeds:
            return 15
        case .disk:
            // Must stay comfortably under DiskSampler.maxGap (15 s) even
            // after timer tolerance and scheduling slop, or the delta guard
            // discards background samples, blanking the menu bar IO metric
            // and freezing session totals while the panel is closed.
            return 10
        case .peripheralBattery:
            return 60
        }
    }
}
