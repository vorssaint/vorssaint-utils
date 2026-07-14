// Standalone verification of the IOReport frequency approach used by
// FrequencySampler. Prints the DVFS tables + computed GHz so values can be
// sanity-checked (CPU ~1-4 GHz, GPU ~0.3-1.5 GHz).
import Foundation
import IOKit

typealias CopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
typealias MergeChannels = @convention(c) (CFMutableDictionary, CFMutableDictionary, CFTypeRef?) -> Void
typealias CreateSubscription = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> UnsafeRawPointer?
typealias CreateSamples = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
typealias ChannelGetGroup = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
typealias ChannelGetChannelName = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
typealias StateGetCount = @convention(c) (CFDictionary) -> Int32
typealias StateGetNameForIndex = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
typealias StateGetResidency = @convention(c) (CFDictionary, Int32) -> Int64

guard let h = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { print("no IOReport"); exit(1) }
func sym<T>(_ n: String, _ t: T.Type) -> T { unsafeBitCast(dlsym(h, n)!, to: T.self) }
let copyChannels = sym("IOReportCopyChannelsInGroup", CopyChannelsInGroup.self)
let mergeChannels = sym("IOReportMergeChannels", MergeChannels.self)
let createSubscription = sym("IOReportCreateSubscription", CreateSubscription.self)
let createSamples = sym("IOReportCreateSamples", CreateSamples.self)
let createSamplesDelta = sym("IOReportCreateSamplesDelta", CreateSamplesDelta.self)
let channelGetGroup = sym("IOReportChannelGetGroup", ChannelGetGroup.self)
let channelGetChannelName = sym("IOReportChannelGetChannelName", ChannelGetChannelName.self)
let stateGetCount = sym("IOReportStateGetCount", StateGetCount.self)
let stateGetNameForIndex = sym("IOReportStateGetNameForIndex", StateGetNameForIndex.self)
let stateGetResidency = sym("IOReportStateGetResidency", StateGetResidency.self)

func voltageStates(_ e: io_registry_entry_t, _ key: String) -> [Double] {
    guard let data = IORegistryEntryCreateCFProperty(e, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data, data.count >= 8 else { return [] }
    var f: [Double] = []
    data.withUnsafeBytes { raw in
        for i in 0..<(raw.count/8) {
            let v = raw.loadUnaligned(fromByteOffset: i*8, as: UInt32.self)
            if v != 0 { f.append(Double(v)) }
        }
    }
    if let mx = f.max(), mx < 1e7 { f = f.map { $0 * 1000 } }  // kHz -> Hz
    return f
}
let pmgr = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pmgr")
for k in ["voltage-states1-sram","voltage-states5-sram","voltage-states9","voltage-states1","voltage-states5"] {
    let t = voltageStates(pmgr, k)
    if !t.isEmpty { print("\(k): \(t.map { String(format: "%.3fGHz", $0/1e9) }.joined(separator: " "))") }
}
let eF = voltageStates(pmgr, "voltage-states1-sram"), pF = voltageStates(pmgr, "voltage-states5-sram"), gF = voltageStates(pmgr, "voltage-states9")

guard let channels = copyChannels("CPU Stats" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { print("no CPU channels"); exit(1) }
if let g = copyChannels("GPU Stats" as CFString, nil, 0, 0, 0)?.takeRetainedValue() { mergeChannels(channels, g, nil) }
var subbed: Unmanaged<CFMutableDictionary>?
guard let sub = createSubscription(nil, channels, &subbed, 0, nil), let sc = subbed?.takeRetainedValue() else { print("no sub"); exit(1) }
let s1 = createSamples(sub, sc, nil)!.takeRetainedValue()
var acc = 0.0; let deadline = Date().addingTimeInterval(1.0); while Date() < deadline { for _ in 0..<50000 { acc += Double.random(in: 0...1) } }; if acc < 0 { print(acc) }
let s2 = createSamples(sub, sc, nil)!.takeRetainedValue()
let delta = createSamplesDelta(s1, s2, nil)!.takeRetainedValue()
guard let chans = (delta as NSDictionary)["IOReportChannels"] as? [CFDictionary] else { print("no channels in delta"); exit(1) }

func weighted(_ ch: CFDictionary, _ table: [Double]) -> Double? {
    let n = Int(stateGetCount(ch)); guard n > 1 else { return nil }
    var w = 0.0, tot = 0.0
    for i in 1..<n {
        let r = Double(stateGetResidency(ch, Int32(i))); if r <= 0 { continue }
        w += r * table[min(i-1, table.count-1)]; tot += r
    }
    return tot > 0 ? w/tot/1e9 : nil
}
for ch in chans {
    let grp = channelGetGroup(ch)?.takeUnretainedValue() as String? ?? ""
    let nm = channelGetChannelName(ch)?.takeUnretainedValue() as String? ?? ""
    guard grp == "CPU Stats" || grp == "GPU Stats" else { continue }
    let table = nm.hasPrefix("ECPU") ? eF : (nm.hasPrefix("PCPU") ? pF : (nm == "GPUPH" ? gF : []))
    let ghz = table.isEmpty ? nil : weighted(ch, table)
    print("[\(grp)] \(nm): states=\(stateGetCount(ch)) table=\(table.count) -> \(ghz.map { String(format: "%.2f GHz", $0) } ?? "n/a")")
}
IOObjectRelease(pmgr)
