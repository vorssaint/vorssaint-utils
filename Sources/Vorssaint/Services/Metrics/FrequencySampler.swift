// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit

/// Current active clock frequency of the CPU efficiency/performance clusters and
/// the GPU, in GHz. All optional: any cluster we can't read stays nil.
struct ClusterFrequencies: Equatable {
    var eCoreGHz: Double?
    var pCoreGHz: Double?
    var gpuGHz: Double?
    var isEmpty: Bool { eCoreGHz == nil && pCoreGHz == nil && gpuGHz == nil }
}

/// Reads DVFS residency from the private IOReport framework and weights it against
/// the per-cluster frequency tables in the device tree to derive an active
/// frequency, the same technique used by macmon / asitop. IOReport is loaded with
/// dlopen (no linker/notarization impact); if anything is missing the sampler
/// simply returns nils. EXPERIMENTAL: the frequency tables are chip-specific and
/// the values want real-hardware verification.
final class FrequencySampler {
    // IOReport function signatures (framework ships without headers).
    private typealias CopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias MergeChannels = @convention(c) (CFMutableDictionary, CFMutableDictionary, CFTypeRef?) -> Void
    private typealias CreateSubscription = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> UnsafeRawPointer?
    private typealias CreateSamples = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelGetGroup = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias ChannelGetChannelName = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias StateGetCount = @convention(c) (CFDictionary) -> Int32
    private typealias StateGetNameForIndex = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    private typealias StateGetResidency = @convention(c) (CFDictionary, Int32) -> Int64

    private let copyChannels: CopyChannelsInGroup
    private let mergeChannels: MergeChannels
    private let createSubscription: CreateSubscription
    private let createSamples: CreateSamples
    private let createSamplesDelta: CreateSamplesDelta
    private let channelGetGroup: ChannelGetGroup
    private let channelGetChannelName: ChannelGetChannelName
    private let stateGetCount: StateGetCount
    private let stateGetNameForIndex: StateGetNameForIndex
    private let stateGetResidency: StateGetResidency

    private var subscription: UnsafeRawPointer?
    private var subscribedChannels: CFMutableDictionary?
    private var previousSample: CFDictionary?

    // DVFS frequency tables (Hz) per cluster, read once from the device tree.
    private let eCoreFreqs: [Double]
    private let pCoreFreqs: [Double]
    private let gpuFreqs: [Double]

    init?() {
        // IOReport lives at different paths across macOS versions.
        func open(_ path: String) -> UnsafeMutableRawPointer? { path.withCString { dlopen($0, RTLD_NOW) } }
        guard let handle = open("/usr/lib/libIOReport.dylib")
            ?? open("/System/Library/PrivateFrameworks/IOReport.framework/IOReport") else { return nil }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let f1 = sym("IOReportCopyChannelsInGroup", CopyChannelsInGroup.self),
              let f2 = sym("IOReportMergeChannels", MergeChannels.self),
              let f3 = sym("IOReportCreateSubscription", CreateSubscription.self),
              let f4 = sym("IOReportCreateSamples", CreateSamples.self),
              let f5 = sym("IOReportCreateSamplesDelta", CreateSamplesDelta.self),
              let f6 = sym("IOReportChannelGetGroup", ChannelGetGroup.self),
              let f7 = sym("IOReportChannelGetChannelName", ChannelGetChannelName.self),
              let f8 = sym("IOReportStateGetCount", StateGetCount.self),
              let f9 = sym("IOReportStateGetNameForIndex", StateGetNameForIndex.self),
              let f10 = sym("IOReportStateGetResidency", StateGetResidency.self)
        else { return nil }
        copyChannels = f1; mergeChannels = f2; createSubscription = f3; createSamples = f4
        createSamplesDelta = f5; channelGetGroup = f6; channelGetChannelName = f7
        stateGetCount = f8; stateGetNameForIndex = f9; stateGetResidency = f10

        // Device-tree DVFS tables. Key indices are the ones used on M-series
        // (ECPU=1, PCPU=5, GPU=9); missing tables leave that cluster nil.
        let pmgr = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pmgr")
        defer { if pmgr != 0 { IOObjectRelease(pmgr) } }
        eCoreFreqs = Self.voltageStates(pmgr, key: "voltage-states1-sram")
        pCoreFreqs = Self.voltageStates(pmgr, key: "voltage-states5-sram")
        gpuFreqs = Self.voltageStates(pmgr, key: "voltage-states9")

        guard let channels = copyChannels("CPU Stats" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else {
            return nil
        }
        if let gpu = copyChannels("GPU Stats" as CFString, nil, 0, 0, 0)?.takeRetainedValue() {
            mergeChannels(channels, gpu, nil)
        }
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = createSubscription(nil, channels, &subbed, 0, nil),
              let subbedChannels = subbed?.takeRetainedValue() else { return nil }
        subscription = sub
        self.subscribedChannels = subbedChannels
        previousSample = createSamples(sub, subbedChannels, nil)?.takeRetainedValue()
    }

    /// Parses a `voltage-states*` blob: little-endian (freqValue, voltage) UInt32
    /// pairs. The freq value is the DVFS clock in Hz.
    private static func voltageStates(_ entry: io_registry_entry_t, key: String) -> [Double] {
        guard entry != 0,
              let data = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data, data.count >= 8 else { return [] }
        var freqs: [Double] = []
        data.withUnsafeBytes { raw in
            let count = raw.count / 8
            for i in 0..<count {
                let value = raw.loadUnaligned(fromByteOffset: i * 8, as: UInt32.self)
                if value != 0 { freqs.append(Double(value)) }
            }
        }
        // CPU (-sram) tables store the clock in kHz, the GPU table in Hz. Normalise
        // small-valued tables up to Hz so the GHz math is uniform.
        if let maxValue = freqs.max(), maxValue < 10_000_000 {
            freqs = freqs.map { $0 * 1000 }
        }
        return freqs
    }

    /// Returns residency-weighted active GHz for each cluster over the window
    /// since the previous call. Skips the idle (first) state.
    func sample() -> ClusterFrequencies {
        var result = ClusterFrequencies()
        guard let sub = subscription, let subbed = subscribedChannels,
              let current = createSamples(sub, subbed, nil)?.takeRetainedValue() else { return result }
        defer { previousSample = current }
        guard let previous = previousSample,
              let delta = createSamplesDelta(previous, current, nil)?.takeRetainedValue(),
              let channels = (delta as NSDictionary)["IOReportChannels"] as? [CFDictionary] else { return result }

        for channel in channels {
            let group = channelGetGroup(channel)?.takeUnretainedValue() as String? ?? ""
            let name = channelGetChannelName(channel)?.takeUnretainedValue() as String? ?? ""
            let table: [Double]
            switch (group, name) {
            case ("CPU Stats", "ECPU"), ("CPU Stats", "ECPU0"): table = eCoreFreqs
            case ("CPU Stats", "PCPU"), ("CPU Stats", "PCPU0"): table = pCoreFreqs
            case ("GPU Stats", "GPUPH"): table = gpuFreqs
            default: continue
            }
            guard !table.isEmpty else { continue }
            if let ghz = weightedGHz(channel, table: table) {
                switch (group, name) {
                case ("CPU Stats", let n) where n.hasPrefix("ECPU"): result.eCoreGHz = ghz
                case ("CPU Stats", let n) where n.hasPrefix("PCPU"): result.pCoreGHz = ghz
                case ("GPU Stats", _): result.gpuGHz = ghz
                default: break
                }
            }
        }
        return result
    }

    private func weightedGHz(_ channel: CFDictionary, table: [Double]) -> Double? {
        let states = Int(stateGetCount(channel))
        guard states > 1 else { return nil }
        var weighted = 0.0
        var total = 0.0
        // State 0 is idle/off; DVFS states 1... map onto the frequency table.
        for i in 1..<states {
            let residency = Double(stateGetResidency(channel, Int32(i)))
            guard residency > 0 else { continue }
            let freqIndex = min(i - 1, table.count - 1)
            weighted += residency * table[freqIndex]
            total += residency
        }
        guard total > 0 else { return nil }
        return weighted / total / 1_000_000_000  // Hz → GHz
    }
}
