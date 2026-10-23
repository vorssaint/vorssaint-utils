// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CryptoKit

enum AgentWeeklyAccount {
    /// A local namespace, never the original email, UUID or organization.
    static func scope(identifier: String?, organization: String? = nil) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        let value = identifier + "\u{0}" + (organization ?? "")
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Quota observations, never reconstructed token totals or synthetic ticks.
/// Only the default Claude/Codex sources participate; added Codex homes keep
/// their separate Limits cards. Private history is excluded from settings export.
struct AgentWeeklyUsage: Codable, Equatable {
    struct Sample: Codable, Equatable {
        let observedAt: Date
        let usedPercent: Double
        let resetsAt: Date?
        let source: String

        func isStale(at now: Date) -> Bool {
            now < observedAt || now.timeIntervalSince(observedAt) >= 600 || resetsAt.map { $0 <= now } == true
        }

        var valid: Bool {
            observedAt.timeIntervalSince1970.isFinite && observedAt.timeIntervalSince1970 > 0
                && usedPercent.isFinite && (0...100).contains(usedPercent)
                && ["account", "sessionLog", "claudeApp"].contains(source)
                && (resetsAt.map { $0.timeIntervalSince1970.isFinite && $0 > observedAt } ?? true)
        }
    }

    struct Cycle: Codable, Equatable {
        let provider: String
        let accountScope: String
        /// The first source-reported reset stays fixed if the source revises it.
        var originalReset: Date?
        /// Inferred from the source's duration; never an observed zero point.
        var inferredStart: Date?
        var samples: [Sample]
        var latest: Sample? { samples.last }
    }

    private(set) var cycles: [Cycle] = []
    private var activeScopes: [String: String] = [:]
    /// A revoked Claude sign-in outlives cached OAuth metadata and relaunches.
    /// Optional so archives from before this marker still decode unchanged.
    var claudeAccountInvalidated: Bool?
    static let maxSamples = 40_000
    static let maxCycles = 400

    func current(_ provider: AgentProvider) -> Cycle? {
        guard provider != .claude || claudeAccountInvalidated != true else { return nil }
        return cycles.last { $0.provider == provider.rawValue && $0.accountScope == activeScopes[provider.rawValue] }
    }

    /// Clearing the selected scope removes its plan immediately without
    /// deleting private observations from the previous account.
    @discardableResult
    mutating func selectAccount(_ scope: String?, provider: AgentProvider) -> Bool {
        let scope = provider == .claude && claudeAccountInvalidated == true ? nil : scope
        guard activeScopes[provider.rawValue] != scope else { return false }
        activeScopes[provider.rawValue] = scope
        return true
    }

    @discardableResult
    mutating func record(_ reading: AgentLimits, now: Date) -> Bool {
        guard reading.provider != .claude || claudeAccountInvalidated != true else { return false }
        guard reading.source != .claudeApp, let scope = reading.accountScope, !scope.isEmpty,
              [.claude, .codex].contains(reading.provider), reading.observedAt <= now,
              let window = reading.windows.first(where: { $0.kind == .weekly && $0.scope == nil }) else { return false }
        let source: String
        switch reading.source {
        case .account: source = "account"
        case .sessionLog: source = "sessionLog"
        case .claudeApp: source = "claudeApp"
        }
        // Claude Desktop's historical drops cannot establish a reset deadline.
        let reset = reading.source == .claudeApp ? nil : window.resetsAt
        let sample = Sample(observedAt: reading.observedAt, usedPercent: window.usedPercent,
                            resetsAt: reset, source: source)
        guard sample.valid else { return false }
        let previous = cycles.lastIndex { $0.provider == reading.provider.rawValue && $0.accountScope == scope }
        if let latest = previous.flatMap({ cycles[$0].latest }), latest.observedAt >= sample.observedAt { return false }
        // A reset-less observation must not undo a provider's later revision.
        // This boundary is independent of the fixed original-ideal reference.
        let previousReset = previous.flatMap {
            cycles[$0].samples.last(where: { $0.resetsAt != nil })?.resetsAt ?? cycles[$0].originalReset
        }
        let usageDropped = previous.flatMap { cycles[$0].latest }.map { sample.usedPercent < $0.usedPercent } ?? false
        let beginsCycle = previous == nil || previousReset.map { $0 <= sample.observedAt } == true || usageDropped
        if beginsCycle {
            cycles.append(Cycle(provider: reading.provider.rawValue, accountScope: scope, samples: []))
        }
        let index = beginsCycle ? cycles.count - 1 : previous!
        if cycles[index].originalReset == nil, let reset {
            cycles[index].originalReset = reset
            if let minutes = window.minutes, minutes > 0 {
                cycles[index].inferredStart = reset.addingTimeInterval(-Double(minutes) * 60)
            }
        }
        cycles[index].samples.append(sample)
        activeScopes[reading.provider.rawValue] = scope
        prune(now: now)
        return true
    }

    /// Older archives can contain a reset that arrived before the previously
    /// reported deadline. Match incoming-sample handling by splitting such a
    /// cycle at every observed drop in weekly consumption.
    @discardableResult
    mutating func splitCyclesAtUsageDrops() -> Bool {
        var segmented: [Cycle] = []
        segmented.reserveCapacity(cycles.count)
        var changed = false

        for cycle in cycles {
            guard cycle.samples.count > 1 else {
                segmented.append(cycle)
                continue
            }

            let inferredDuration = cycle.originalReset.flatMap { reset in
                cycle.inferredStart.map { reset.timeIntervalSince($0) }
            }.flatMap { $0 > 0 ? $0 : nil }
            let resetIndices = cycle.samples.indices.dropFirst().filter {
                cycle.samples[$0].usedPercent < cycle.samples[$0 - 1].usedPercent
            }
            guard !resetIndices.isEmpty else {
                segmented.append(cycle)
                continue
            }

            changed = true
            var segmentStart = 0
            for segmentEnd in Array(resetIndices) + [cycle.samples.count] {
                let samples = Array(cycle.samples[segmentStart..<segmentEnd])
                let originalReset: Date?
                let inferredStart: Date?
                if segmentStart == 0 {
                    originalReset = cycle.originalReset
                    inferredStart = cycle.inferredStart
                } else {
                    originalReset = samples.compactMap(\.resetsAt).first
                    if let reset = originalReset, let inferredDuration {
                        inferredStart = reset.addingTimeInterval(-inferredDuration)
                    } else {
                        inferredStart = nil
                    }
                }
                segmented.append(Cycle(provider: cycle.provider, accountScope: cycle.accountScope,
                                       originalReset: originalReset, inferredStart: inferredStart,
                                       samples: samples))
                segmentStart = segmentEnd
            }
        }

        if changed { cycles = segmented }
        return changed
    }

    /// Also runs without new readings, at archive load and service maintenance.
    @discardableResult
    mutating func prune(now: Date) -> Bool {
        let before = cycles.reduce(0) { $0 + $1.samples.count }
        let scopesBefore = activeScopes.count
        let cutoff = now.addingTimeInterval(-91 * 86_400)
        for index in cycles.indices { cycles[index].samples.removeAll { $0.observedAt < cutoff } }
        cycles.removeAll { $0.samples.isEmpty }
        if cycles.count > Self.maxCycles {
            // A long-lived cycle can still be receiving current readings.
            // Evict by its last observation, preserving retained cycle order.
            let oldest = cycles.indices.sorted {
                let left = cycles[$0].latest!.observedAt, right = cycles[$1].latest!.observedAt
                return left == right ? $0 < $1 : left < right
            }
            let removed = Set(oldest.prefix(cycles.count - Self.maxCycles))
            cycles = cycles.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
        }
        var excess = cycles.reduce(0) { $0 + $1.samples.count } - Self.maxSamples
        for index in cycles.indices where excess > 0 {
            let removed = min(excess, max(0, cycles[index].samples.count - 1))
            cycles[index].samples.removeFirst(removed)
            excess -= removed
        }
        // A selected account with no surviving observations must not leave
        // its digest in an otherwise expired archive indefinitely.
        activeScopes = activeScopes.filter { provider, scope in
            cycles.contains { $0.provider == provider && $0.accountScope == scope }
        }
        return cycles.reduce(0) { $0 + $1.samples.count } != before || activeScopes.count != scopesBefore
    }

    var valid: Bool {
        guard cycles.count <= Self.maxCycles, cycles.reduce(0, { $0 + $1.samples.count }) <= Self.maxSamples else { return false }
        return cycles.allSatisfy { cycle in
            guard ["claude", "codex"].contains(cycle.provider), !cycle.accountScope.isEmpty, !cycle.samples.isEmpty,
                  cycle.samples.allSatisfy(\.valid) else { return false }
            if let reset = cycle.originalReset, !reset.timeIntervalSince1970.isFinite { return false }
            if let start = cycle.inferredStart {
                guard let reset = cycle.originalReset, start.timeIntervalSince1970.isFinite, start < reset else { return false }
            }
            return zip(cycle.samples, cycle.samples.dropFirst()).allSatisfy { $0.observedAt < $1.observedAt }
        }
    }
}

/// A budget, not a prediction. An expired or stale reading cannot promise a
/// current allowance. The UI still shows its actual value and timestamp.
struct AgentWeeklyPlan {
    struct Checkpoint {
        let date: Date
        let usedPercent: Double
    }
    struct Target: Identifiable {
        let date: Date
        let actualPercent: Double
        let speculativePercent: Double?
        let isActualReset: Bool
        let isSpeculativeReset: Bool
        var id: Date { date }
    }
    let start: Date
    let reset: Date
    let initialPercent: Double
    var remainingPercent: Double { 100 - initialPercent }

    init?(sample: AgentWeeklyUsage.Sample, now: Date, speculativeReset: Date? = nil) {
        guard sample.valid, !sample.isStale(at: now),
              let reset = speculativeReset ?? sample.resetsAt, reset > now else { return nil }
        start = sample.observedAt
        self.reset = reset
        initialPercent = sample.usedPercent
    }

    func used(at date: Date) -> Double {
        let elapsed = min(1, max(0, date.timeIntervalSince(start) / reset.timeIntervalSince(start)))
        return initialPercent + remainingPercent * elapsed
    }

    /// Compare both budgets at the same local checkpoints, including each
    /// exact deadline. Nothing is assumed after the speculative reset.
    func targets(comparing speculative: Self?, calendar: Calendar = .autoupdatingCurrent) -> [Target] {
        let actualDates = checkpoints(calendar: calendar).map(\.date)
        let speculativeDates = speculative?.checkpoints(calendar: calendar).map(\.date) ?? []
        let deadlines = [reset, speculative?.reset].compactMap { $0 }
        let dates = Set(actualDates + speculativeDates).sorted().filter { date in
            guard date <= reset else { return false }
            // Keep both exact deadlines; suppress only ordinary weekday rows
            // that would repeat a deadline's displayed local minute.
            return deadlines.contains(date) || !deadlines.contains {
                calendar.isDate(date, equalTo: $0, toGranularity: .minute)
            }
        }
        return dates.map { date in
            let estimate = speculative.flatMap { date <= $0.reset ? $0.used(at: date) : nil }
            return Target(date: date, actualPercent: used(at: date), speculativePercent: estimate,
                          isActualReset: date == reset, isSpeculativeReset: date == speculative?.reset)
        }
    }

    /// Local 17:00 on working weekdays, plus the source's actual reset even
    /// when it falls on a weekend. Holidays are not inferred from the locale.
    func checkpoints(calendar: Calendar = .autoupdatingCurrent) -> [Checkpoint] {
        var day = calendar.startOfDay(for: start)
        var dates: [Date] = []
        for _ in 0..<32 {
            guard day < reset else { break }
            if !calendar.isDateInWeekend(day),
               let checkpoint = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day),
               checkpoint > start, checkpoint < reset,
               !calendar.isDate(checkpoint, equalTo: reset, toGranularity: .minute) {
                // Both rows would display 17:00. Keep the exact source reset.
                dates.append(checkpoint)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        dates.append(reset)
        return dates.map { Checkpoint(date: $0, usedPercent: used(at: $0)) }
    }
}

enum AgentWeeklyUsageFile {
    private struct Archive: Codable { let version: Int; let history: AgentWeeklyUsage }
    static var url: URL? { PrivateFileStore.containerURL?.appendingPathComponent("AgentUsage/weekly-usage.json") }

    static func load(from url: URL?, now: Date = Date()) -> (history: AgentWeeklyUsage, failed: Bool) {
        var loaded = read(from: url)
        guard !loaded.failed else { return loaded }
        let splitResets = loaded.history.splitCyclesAtUsageDrops()
        let pruned = loaded.history.prune(now: now)
        if splitResets || pruned {
            loaded.failed = !save(loaded.history, to: url)
        }
        return loaded
    }

    private static func read(from url: URL?) -> (history: AgentWeeklyUsage, failed: Bool) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return (AgentWeeklyUsage(), false) }
        guard let data = try? Data(contentsOf: url), data.count <= 16_000_000,
              let archive = try? JSONDecoder().decode(Archive.self, from: data), archive.version == 1,
              archive.history.valid else { return (AgentWeeklyUsage(), true) }
        return (archive.history, false)
    }

    @discardableResult
    static func save(_ history: AgentWeeklyUsage, to url: URL?) -> Bool {
        guard let url, history.valid, !read(from: url).failed,
              let data = try? JSONEncoder().encode(Archive(version: 1, history: history)),
              PrivateFileStore.createDirectory(at: url.deletingLastPathComponent()) else { return false }
        return PrivateFileStore.write(data, to: url)
    }
}
