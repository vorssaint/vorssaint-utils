// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import IOKit

struct CPUCoreTicks {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func usage(since previous: Self) -> Double? {
        let current = [user, system, idle, nice]
        let earlier = [previous.user, previous.system, previous.idle, previous.nice]
        var deltas: [UInt64] = []
        for (new, old) in zip(current, earlier) {
            // A small backwards step is a reset; a large one is UInt32 rollover.
            guard new >= old || old - new > UInt32.max / 2 else { return nil }
            deltas.append(UInt64(new &- old))
        }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        return Double(total - deltas[2]) / Double(total)
    }
}

/// Per logical core load from PROCESSOR_CPU_LOAD_INFO. Called only from the
/// monitor's serial queue.
final class CPUCoreSampler {
    private var previous: (ticks: [CPUCoreTicks], time: TimeInterval)?

    /// One value per logical core, in Mach processor order; nil until a core
    /// has a fresh interval. After a gap the old ticks only become a baseline.
    func sample(now: TimeInterval) -> [Double?] {
        let stride = Int(CPU_STATE_MAX)
        guard let ticks = processorInfo(PROCESSOR_CPU_LOAD_INFO, stride: stride, { info, processors in
            (0..<processors).map { index in
                let base = index * stride
                return CPUCoreTicks(user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                                    system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                                    idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                                    nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            }
        }) else {
            previous = nil
            return []
        }
        defer { previous = (ticks, now) }
        guard let previous, previous.ticks.count == ticks.count,
              now > previous.time, now - previous.time <= 12.5 else {
            return Array(repeating: nil, count: ticks.count)
        }
        return zip(ticks, previous.ticks).map { $0.usage(since: $1) }
    }

    /// Drops the baseline, so the first sample after a pause only sets a new one.
    func reset() {
        previous = nil
    }
}

/// Runs `host_processor_info` and hands `read` the records, `stride` integers
/// per processor, and the processor count.
private func processorInfo<T>(_ flavor: processor_flavor_t, stride: Int,
                              _ read: (processor_info_array_t, Int) -> T) -> T? {
    var processors: natural_t = 0
    var info: processor_info_array_t?
    var count: mach_msg_type_number_t = 0
    let host = mach_host_self()
    defer { mach_port_deallocate(mach_task_self_, host) }
    guard host_processor_info(host, flavor, &processors, &info, &count) == KERN_SUCCESS, let info else { return nil }
    defer {
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                      vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride))
    }
    guard processors > 0, Int(processors) <= Int(count) / stride else { return nil }
    return read(info, Int(processors))
}

/// A core class (sysctl perflevel name, such as "Performance") and the
/// sampler indices of its cores.
struct CPUCoreGroup: Equatable {
    let name: String
    let indices: [Int]
    /// Faster cores get wider bars.
    var weight: Double {
        switch name.lowercased() {
        case "super": return 1.5
        case "performance": return 1.25
        default: return 1
        }
    }
}

struct CPUCoreSegment {
    let group: CPUCoreGroup
    let width: Double
    /// Every bar shares one scale, so a class that wraps onto a row of its
    /// own never gets wider bars than faster cores.
    var barWidth: Double = 14
}

enum CPUCoreLayout {
    /// Packs groups side by side into rows of `width` points, splitting a group
    /// that cannot keep 14 pt bars into balanced chunks. Groups sit 12 pt apart
    /// and bars 4 pt apart; spare width goes to groups by weighted core count,
    /// and the tightest group sets the bar scale for all of them.
    static func rows(groups: [CPUCoreGroup], width: Double) -> [[CPUCoreSegment]] {
        guard width.isFinite, width >= 70 else { return [] }
        func minimum(_ group: CPUCoreGroup) -> Double {
            max(70, Double(group.indices.count) * 14 * group.weight + Double(group.indices.count - 1) * 4)
        }
        var packed: [[CPUCoreGroup]] = []
        var row: [CPUCoreGroup] = []
        var used = 0.0
        for group in groups where !group.indices.isEmpty {
            let limit = min(12, max(1, Int((width + 4) / (14 * group.weight + 4))))
            let chunkCount = (group.indices.count + limit - 1) / limit
            let baseCount = group.indices.count / chunkCount
            let remainder = group.indices.count % chunkCount
            var offset = 0
            for part in 0..<chunkCount {
                let count = baseCount + (part < remainder ? 1 : 0)
                let chunk = CPUCoreGroup(name: group.name, indices: Array(group.indices[offset..<(offset + count)]))
                offset += count
                let required = minimum(chunk)
                if !row.isEmpty, used + 12 + required > width {
                    packed.append(row)
                    row = []
                    used = 0
                }
                used += (row.isEmpty ? 0 : 12) + required
                row.append(chunk)
            }
        }
        if !row.isEmpty { packed.append(row) }
        let sized = packed.map { row in
            let available = width - Double(row.count - 1) * 12
            let minimums = row.map(minimum)
            let extra = max(0, available - minimums.reduce(0, +))
            let weights = row.map { Double($0.indices.count) * $0.weight }
            let total = weights.reduce(0, +)
            return row.indices.map { index in
                CPUCoreSegment(group: row[index], width: minimums[index] + extra * weights[index] / total)
            }
        }
        let scale = sized.joined().map { segment -> Double in
            let count = Double(segment.group.indices.count)
            return (segment.width - (count - 1) * 4) / count / (14 * segment.group.weight)
        }.min() ?? 1
        return sized.map { row in
            row.map { CPUCoreSegment(group: $0.group, width: $0.width, barWidth: 14 * $0.group.weight * scale) }
        }
    }
}

enum CPUCoreTopology {
    /// Read once. Anything that does not add up falls back to one "CPU" group
    /// rather than guessing which core belongs to which class.
    static let groups: [CPUCoreGroup] = read()

    static func groups(for count: Int) -> [CPUCoreGroup] {
        guard groups.reduce(0, { $0 + $1.indices.count }) == count else {
            return count == 0 ? [] : [CPUCoreGroup(name: "CPU", indices: Array(0..<count))]
        }
        return groups
    }

    /// `levels` come from sysctl in perflevel order, `cores` from the device
    /// tree (logical CPU ID and cluster type), and `slots` map each sampler
    /// index to its logical CPU ID.
    static func groups(levels: [(name: String, count: Int)],
                       cores: [(id: Int, type: String)],
                       slots: [Int]) -> [CPUCoreGroup] {
        let fallback = slots.isEmpty ? [] : [CPUCoreGroup(name: "CPU", indices: Array(slots.indices))]
        guard Set(levels.map(\.name)).count == levels.count, Set(slots).count == slots.count,
              cores.count == slots.count, Set(cores.map(\.id)) == Set(slots)
        else { return fallback }
        // XNU orders perflevels by cluster performance, not by logical CPU ID.
        let order = ["S", "P", "E"]
        let types = Set(cores.map(\.type))
        guard types.isSubset(of: Set(order)), types.count == levels.count else { return fallback }
        let byID = Dictionary(uniqueKeysWithValues: cores.map { ($0.id, $0.type) })
        var groups: [CPUCoreGroup] = []
        for (level, type) in zip(levels, order.filter(types.contains)) {
            let indices = slots.indices.filter { byID[slots[$0]] == type }
            guard indices.count == level.count else { return fallback }
            groups.append(CPUCoreGroup(name: level.name, indices: indices))
        }
        return groups
    }

    private static func read() -> [CPUCoreGroup] {
        #if arch(arm64)
        guard let levelCount = integer("hw.nperflevels"), (1...8).contains(levelCount) else { return [] }
        let recordStride = MemoryLayout<processor_basic_info>.stride / MemoryLayout<integer_t>.stride
        guard let slots = processorInfo(PROCESSOR_BASIC_INFO, stride: recordStride, { info, processors in
            let records = UnsafeRawPointer(info).assumingMemoryBound(to: processor_basic_info.self)
            return (0..<processors).map { Int(records[$0].slot_num) }
        }) else { return [] }
        var levels: [(name: String, count: Int)] = []
        for level in 0..<levelCount {
            guard let name = string("hw.perflevel\(level).name"),
                  let cpuCount = integer("hw.perflevel\(level).logicalcpu_max") else { return [] }
            levels.append((name, cpuCount))
        }
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard root != 0 else { return [] }
        defer { IOObjectRelease(root) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(root, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var cores: [(id: Int, type: String)] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let id = IORegistryEntryCreateCFProperty(entry, "logical-cpu-id" as CFString,
                                                           kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber,
                  let data = IORegistryEntryCreateCFProperty(entry, "cluster-type" as CFString,
                                                             kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
                  let type = String(data: data.prefix(while: { $0 != 0 }), encoding: .utf8) else { continue }
            cores.append((id.intValue, type))
        }
        return groups(levels: levels, cores: cores, slots: slots)
        #else
        return []
        #endif
    }

    private static func integer(_ key: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(key, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }

    private static func string(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0, size < 256 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(bytes: bytes.prefix(while: { $0 != 0 }), encoding: .utf8)
    }
}
