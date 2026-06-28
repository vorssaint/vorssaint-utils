// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

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
/// one app shows up once instead of as a pile of helper rows.
final class ProcessUsageService {
    static let shared = ProcessUsageService()

    private struct CachedRows {
        var rows: [ProcessUsage]
        var updatedAt: TimeInterval
    }

    private let cacheLock = NSLock()
    private let cacheFreshSeconds: TimeInterval = 5
    private let memoryCacheFreshSeconds: TimeInterval = 8
    private let staleCacheSeconds: TimeInterval = 18
    private let minimumGPUSampleInterval: TimeInterval = 1.8
    private let maximumCachedRows = 60
    private var cpuCache: CachedRows?
    private var memoryCache: CachedRows?
    private var gpuCache: CachedRows?
    private var energyCache: CachedRows?
    private var cpuLoading = false
    private var memoryLoading = false
    private var gpuLoading = false
    private var energyLoading = false

    private init() {}

    func cachedTop(_ kind: BreakdownKind, limit: Int, maxAge: TimeInterval = 18) -> [ProcessUsage]? {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let cache: CachedRows?
        switch kind {
        case .cpu: cache = cpuCache
        case .gpu: cache = gpuCache
        case .memory: cache = memoryCache
        case .energy: cache = energyCache
        }
        return limitedRows(cache, limit: limit, now: now, maxAge: maxAge)
    }

    func top(_ kind: BreakdownKind, limit: Int) -> [ProcessUsage] {
        switch kind {
        case .cpu: return topCPU(limit: limit)
        case .gpu: return topGPU(limit: limit)
        case .memory: return topMemory(limit: limit)
        case .energy: return topEnergy(limit: limit)
        }
    }

    func clearCachedRows() {
        cacheLock.lock()
        cpuCache = nil
        memoryCache = nil
        gpuCache = nil
        energyCache = nil
        cacheLock.unlock()
    }

    func canActivate(_ row: ProcessUsage) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: row.pid),
              app.activationPolicy == .regular,
              !app.isTerminated
        else { return false }
        return true
    }

    func activate(_ row: ProcessUsage) {
        guard canActivate(row),
              let app = NSRunningApplication(processIdentifier: row.pid)
        else { return }
        NSApp.yieldActivation(to: app)
        if !app.activate(from: NSRunningApplication.current, options: []) {
            app.activate(options: [])
        }
    }

    // MARK: - Energy

    /// macOS does not expose Activity Monitor's Energy Impact as a `ps` column.
    /// For the live battery list, combine the current CPU and GPU app shares and
    /// keep only rows that are meaningfully active right now.
    func topEnergy(limit: Int = 5) -> [ProcessUsage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        if let cached = limitedRows(energyCache, limit: limit, now: now, maxAge: cacheFreshSeconds) {
            cacheLock.unlock()
            return cached
        }
        if energyLoading {
            let cached = limitedRows(energyCache, limit: limit, now: now, maxAge: staleCacheSeconds) ?? []
            cacheLock.unlock()
            return cached
        }
        energyLoading = true
        cacheLock.unlock()

        let sampleLimit = max(limit * 3, 12)
        let cpuRows = topCPU(limit: sampleLimit)
        let gpuRows = topGPU(limit: sampleLimit)
        var scores: [pid_t: (name: String, value: Double)] = [:]

        for row in cpuRows + gpuRows {
            var score = scores[row.pid] ?? (row.name, 0)
            score.value += row.value
            if score.name.hasPrefix("pid ") { score.name = row.name }
            scores[row.pid] = score
        }

        let rows = scores
            .filter { _, score in score.value >= 2 }
            .sorted { $0.value.value > $1.value.value }
            .map { pid, score in
                ProcessUsage(pid: pid, name: score.name, value: score.value)
            }
        cacheLock.lock()
        energyCache = cachedRows(from: rows)
        energyLoading = false
        cacheLock.unlock()
        return Array(rows.prefix(limit))
    }

    // MARK: - CPU

    func topCPU(limit: Int = 5) -> [ProcessUsage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        if let cached = limitedRows(cpuCache, limit: limit, now: now, maxAge: cacheFreshSeconds) {
            cacheLock.unlock()
            return cached
        }
        if cpuLoading {
            let cached = limitedRows(cpuCache, limit: limit, now: now, maxAge: staleCacheSeconds) ?? []
            cacheLock.unlock()
            return cached
        }
        cpuLoading = true
        cacheLock.unlock()

        let result = Shell.run("/bin/ps", ["-Aceo", "pid,pcpu,comm", "-r"])
        let rows = result.status == 0
            ? groupedByApp(parsePS(result.output, maxRows: rawProcessRowLimit(for: limit)) { Double($0) ?? 0 })
            : nil
        return finishCPU(rows, limit: limit)
    }

    // MARK: - Memory

    func topMemory(limit: Int = 5) -> [ProcessUsage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        if let cached = limitedRows(memoryCache, limit: limit, now: now, maxAge: memoryCacheFreshSeconds) {
            cacheLock.unlock()
            return cached
        }
        if memoryLoading {
            let cached = limitedRows(memoryCache, limit: limit, now: now, maxAge: staleCacheSeconds) ?? []
            cacheLock.unlock()
            return cached
        }
        memoryLoading = true
        cacheLock.unlock()

        let result = Shell.run("/bin/ps", ["-Aceo", "pid,rss,comm", "-m"])
        // rss is reported in KiB.
        let rows = result.status == 0
            ? groupedByApp(parsePS(result.output, maxRows: rawProcessRowLimit(for: limit)) { (Double($0) ?? 0) * 1024 })
            : nil
        return finishMemory(rows, limit: limit)
    }

    /// Lines look like "  437  12.5 WindowServer" (value column varies).
    private func parsePS(_ output: String, maxRows: Int, transform: (String) -> Double) -> [ProcessUsage] {
        var rows: [ProcessUsage] = []
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard columns.count == 3, let pid = pid_t(columns[0]) else { continue }
            let value = transform(String(columns[1]))
            guard value > 0 else { continue }
            rows.append(ProcessUsage(pid: pid,
                                     name: String(columns[2]).trimmingCharacters(in: .whitespaces),
                                     value: value))
            if rows.count >= maxRows { break }
        }
        return rows
    }

    private func rawProcessRowLimit(for limit: Int) -> Int {
        max(limit * 10, 120)
    }

    // MARK: - Consolidation

    /// Sums per-process values under each process's responsible app and keeps
    /// the heaviest `limit` rows. The row's pid becomes the responsible pid,
    /// so the app's proper name and icon are shown.
    private func groupedByApp(_ rows: [ProcessUsage]) -> [ProcessUsage] {
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
            .map { owner, value in
                ProcessUsage(pid: owner,
                             name: ResponsibleProcess.displayName(pid: owner,
                                                                  fallback: fallbackNames[owner] ?? "pid \(owner)"),
                             value: value)
            }
    }

    // MARK: - GPU

    private var previousGPUSample: (time: TimeInterval, perPid: [pid_t: Double])?
    private let gpuSampleLock = NSLock()

    /// Per-process GPU share since the previous call. The first call after a
    /// while only primes the baseline and returns [] — callers show a
    /// "measuring" placeholder until the next tick.
    func topGPU(limit: Int = 5) -> [ProcessUsage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        if let cached = limitedRows(gpuCache, limit: limit, now: now, maxAge: cacheFreshSeconds) {
            cacheLock.unlock()
            return cached
        }
        if gpuLoading {
            let cached = limitedRows(gpuCache, limit: limit, now: now, maxAge: staleCacheSeconds) ?? []
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        gpuSampleLock.lock()
        let previousTime = previousGPUSample?.time
        gpuSampleLock.unlock()
        if let previousTime, now - previousTime < minimumGPUSampleInterval {
            return cachedTop(.gpu, limit: limit, maxAge: staleCacheSeconds) ?? []
        }

        cacheLock.lock()
        if gpuLoading {
            let cached = limitedRows(gpuCache, limit: limit, now: now, maxAge: staleCacheSeconds) ?? []
            cacheLock.unlock()
            return cached
        }
        gpuLoading = true
        cacheLock.unlock()

        let current = Self.gpuTimePerPid()
        gpuSampleLock.lock()
        let previous = previousGPUSample
        previousGPUSample = (now, current)
        gpuSampleLock.unlock()

        guard let previous, now > previous.time,
              now - previous.time < 30 // stale baseline => re-prime
        else { return finishGPU(nil, limit: limit) }

        let elapsedNs = (now - previous.time) * 1_000_000_000
        var rows: [ProcessUsage] = []
        for (pid, total) in current {
            guard let before = previous.perPid[pid], total > before else { continue }
            let percent = (total - before) / elapsedNs * 100
            guard percent >= 0.05 else { continue }
            rows.append(ProcessUsage(pid: pid, name: "pid \(pid)", value: min(percent, 100)))
        }
        return finishGPU(groupedByApp(rows), limit: limit)
    }

    private func finishCPU(_ rows: [ProcessUsage]?, limit: Int) -> [ProcessUsage] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cpuLoading = false
        if let rows {
            cpuCache = cachedRows(from: rows)
            return Array(rows.prefix(limit))
        }
        return limitedRows(cpuCache, limit: limit, now: ProcessInfo.processInfo.systemUptime, maxAge: staleCacheSeconds) ?? []
    }

    private func finishMemory(_ rows: [ProcessUsage]?, limit: Int) -> [ProcessUsage] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        memoryLoading = false
        if let rows {
            memoryCache = cachedRows(from: rows)
            return Array(rows.prefix(limit))
        }
        return limitedRows(memoryCache, limit: limit, now: ProcessInfo.processInfo.systemUptime, maxAge: staleCacheSeconds) ?? []
    }

    private func finishGPU(_ rows: [ProcessUsage]?, limit: Int) -> [ProcessUsage] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        gpuLoading = false
        if let rows {
            gpuCache = cachedRows(from: rows)
            return Array(rows.prefix(limit))
        }
        return limitedRows(gpuCache, limit: limit, now: ProcessInfo.processInfo.systemUptime, maxAge: staleCacheSeconds) ?? []
    }

    private func cachedRows(from rows: [ProcessUsage]) -> CachedRows {
        CachedRows(rows: Array(rows.prefix(maximumCachedRows)),
                   updatedAt: ProcessInfo.processInfo.systemUptime)
    }

    private func limitedRows(_ cache: CachedRows?, limit: Int, now: TimeInterval, maxAge: TimeInterval) -> [ProcessUsage]? {
        guard let cache, now - cache.updatedAt <= maxAge else { return nil }
        return Array(cache.rows.prefix(limit))
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
