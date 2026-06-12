import AppKit
import Foundation
import IOKit

/// One row of the per-app breakdown shown when a System stat is expanded.
struct ProcessUsage: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    /// CPU/GPU: percentage (0–100+). Memory: bytes.
    let value: Double

    var id: pid_t { pid }
}

/// Answers "which apps are eating this resource?" for the panel's System
/// section. CPU and memory come from `ps`; GPU comes from the accelerator's
/// per-process `accumulatedGPUTime` counters, sampled as deltas between calls.
/// Helper processes are consolidated under the app responsible for them, so
/// Safari shows up once — not as a dozen "Web Content" rows.
final class ProcessUsageService {
    static let shared = ProcessUsageService()

    private init() {}

    // MARK: - CPU

    func topCPU(limit: Int = 5) -> [ProcessUsage] {
        let result = Shell.run("/bin/ps", ["-Aceo", "pid,pcpu,comm", "-r"])
        guard result.status == 0 else { return [] }
        return groupedByApp(parsePS(result.output) { Double($0) ?? 0 }, limit: limit)
    }

    // MARK: - Memory

    func topMemory(limit: Int = 5) -> [ProcessUsage] {
        let result = Shell.run("/bin/ps", ["-Aceo", "pid,rss,comm", "-m"])
        guard result.status == 0 else { return [] }
        // rss is reported in KiB.
        return groupedByApp(parsePS(result.output) { (Double($0) ?? 0) * 1024 }, limit: limit)
    }

    /// Lines look like "  437  12.5 WindowServer" (value column varies).
    private func parsePS(_ output: String, transform: (String) -> Double) -> [ProcessUsage] {
        var rows: [ProcessUsage] = []
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard columns.count == 3, let pid = pid_t(columns[0]) else { continue }
            let value = transform(String(columns[1]))
            guard value > 0 else { continue }
            rows.append(ProcessUsage(pid: pid,
                                     name: String(columns[2]).trimmingCharacters(in: .whitespaces),
                                     value: value))
        }
        return rows
    }

    // MARK: - Consolidation

    /// Sums per-process values under each process's responsible app and keeps
    /// the heaviest `limit` rows. The row's pid becomes the responsible pid,
    /// so the app's proper name and icon are shown.
    private func groupedByApp(_ rows: [ProcessUsage], limit: Int) -> [ProcessUsage] {
        var totals: [pid_t: Double] = [:]
        var fallbackNames: [pid_t: String] = [:]

        for row in rows {
            let owner = ResponsibleProcess.owner(of: row.pid)
            totals[owner, default: 0] += row.value
            if fallbackNames[owner] == nil {
                fallbackNames[owner] = row.name
            }
        }

        return totals
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { owner, value in
                ProcessUsage(pid: owner,
                             name: ResponsibleProcess.displayName(pid: owner,
                                                                  fallback: fallbackNames[owner] ?? "pid \(owner)"),
                             value: value)
            }
    }

    // MARK: - GPU

    private var previousGPUSample: (time: TimeInterval, perPid: [pid_t: Double])?

    /// Per-process GPU share since the previous call. The first call after a
    /// while only primes the baseline and returns [] — callers show a
    /// "measuring" placeholder until the next tick.
    func topGPU(limit: Int = 5) -> [ProcessUsage] {
        let now = ProcessInfo.processInfo.systemUptime
        let current = Self.gpuTimePerPid()
        defer { previousGPUSample = (now, current) }

        guard let previous = previousGPUSample, now > previous.time,
              now - previous.time < 30 // stale baseline => re-prime
        else { return [] }

        let elapsedNs = (now - previous.time) * 1_000_000_000
        var rows: [ProcessUsage] = []
        for (pid, total) in current {
            guard let before = previous.perPid[pid], total > before else { continue }
            let percent = (total - before) / elapsedNs * 100
            guard percent >= 0.05 else { continue }
            rows.append(ProcessUsage(pid: pid, name: "pid \(pid)", value: min(percent, 100)))
        }
        return groupedByApp(rows, limit: limit)
    }

    /// Walks the accelerator's user clients and sums `accumulatedGPUTime`
    /// (nanoseconds of GPU work since the context was created) per process.
    private static func gpuTimePerPid() -> [pid_t: Double] {
        var perPid: [pid_t: Double] = [:]

        var accelIterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &accelIterator) == kIOReturnSuccess else { return perPid }
        defer { IOObjectRelease(accelIterator) }

        var accelerator = IOIteratorNext(accelIterator)
        while accelerator != 0 {
            defer {
                IOObjectRelease(accelerator)
                accelerator = IOIteratorNext(accelIterator)
            }

            var clients = io_iterator_t()
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &clients) == kIOReturnSuccess
            else { continue }
            defer { IOObjectRelease(clients) }

            var client = IOIteratorNext(clients)
            while client != 0 {
                defer {
                    IOObjectRelease(client)
                    client = IOIteratorNext(clients)
                }

                guard let creatorRef = IORegistryEntryCreateCFProperty(
                          client, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0),
                      let creator = creatorRef.takeRetainedValue() as? String,
                      let pid = Self.pid(fromCreator: creator)
                else { continue }

                guard let usageRef = IORegistryEntryCreateCFProperty(
                          client, "AppUsage" as CFString, kCFAllocatorDefault, 0),
                      let usage = usageRef.takeRetainedValue() as? [[String: Any]]
                else { continue }

                for entry in usage {
                    if let time = entry["accumulatedGPUTime"] as? Double {
                        perPid[pid, default: 0] += time
                    } else if let time = entry["accumulatedGPUTime"] as? Int64 {
                        perPid[pid, default: 0] += Double(time)
                    }
                }
            }
        }
        return perPid
    }

    /// "pid 437, WindowServer" → 437
    private static func pid(fromCreator creator: String) -> pid_t? {
        guard creator.hasPrefix("pid ") else { return nil }
        let digits = creator.dropFirst(4).prefix { $0.isNumber }
        return pid_t(digits)
    }

}
