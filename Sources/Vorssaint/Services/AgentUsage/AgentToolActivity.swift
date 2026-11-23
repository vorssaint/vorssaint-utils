// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

enum AgentToolKind: Int, CaseIterable {
    case shell, read, edit, search, web, mcp, subagent, other

    private static let claudeKinds: [String: Self] = [
        "Bash": .shell, "Read": .read, "Edit": .edit, "Write": .edit, "MultiEdit": .edit,
        "NotebookEdit": .edit, "Glob": .search, "Grep": .search, "WebFetch": .web,
        "WebSearch": .web, "web_search": .web, "web_fetch": .web,
        "Agent": .subagent, "Task": .subagent, "SendMessage": .subagent, "TaskStop": .subagent,
    ]

    private static let codexKinds: [String: Self] = [
        "exec_command": .shell, "shell": .shell, "shell_command": .shell,
        "read_file": .read, "view_image": .read, "apply_patch": .edit,
        "grep_files": .search, "list_dir": .search, "web_search": .web,
        "spawn_agent": .subagent, "send_input": .subagent, "wait_agent": .subagent,
        "close_agent": .subagent, "resume_agent": .subagent, "send_message": .subagent,
        "followup_task": .subagent, "list_agents": .subagent, "interrupt_agent": .subagent,
    ]

    static func claude(_ name: String) -> Self {
        name.hasPrefix("mcp__") ? .mcp : claudeKinds[name] ?? .other
    }

    static func codex(_ name: String) -> Self? {
        // Exec and its result wait are wrappers for separately logged actions.
        guard !["exec", "wait"].contains(name) else { return nil }
        return name.hasPrefix("mcp__") ? .mcp : codexKinds[name] ?? .other
    }
}

struct AgentToolCall: Equatable {
    struct Key: Hashable {
        let provider: AgentProvider
        let digest: Data
    }

    static let maximumIDBytes = 128
    static let digestBytes = 16

    let key: Key
    struct Observation: Equatable {
        var date: Date
        var kind: AgentToolKind

        mutating func merge(_ other: Self) {
            date = min(date, other.date)
            // Other sorts last, so a recognized category wins over a fallback.
            if other.kind.rawValue < kind.rawValue { kind = other.kind }
        }
    }

    let observation: Observation

    init?(provider: AgentProvider, id: String, date: Date, kind: AgentToolKind) {
        guard !id.isEmpty, id.utf8.count <= Self.maximumIDBytes,
              id.utf8.allSatisfy(Self.isIDByte) else { return nil }
        let digest = Data(SHA256.hash(data: Data(id.utf8)).prefix(Self.digestBytes))
        self.key = Key(provider: provider, digest: digest)
        observation = Observation(date: date, kind: kind)
    }

    private static func isIDByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 48...57, 65...90, 97...122, 45, 95: return true
        default: return false
        }
    }
}

typealias AgentToolCounts = [AgentProvider: [AgentToolKind: Int]]

/// Each log contributes its own observations. Daily totals incorporate
/// changes as they happen and are rebuilt when their calendar changes.
struct AgentToolActivity {
    struct Source: Equatable {
        let path: String
        var observation: AgentToolCall.Observation
    }

    struct Entry: Equatable {
        var sources: [Source]

        var observation: AgentToolCall.Observation? {
            guard var reading = sources.first?.observation else { return nil }
            for source in sources.dropFirst() { reading.merge(source.observation) }
            return reading
        }
    }

    private(set) var entries: [AgentToolCall.Key: Entry]
    private(set) var revision = 0
    private var calendar: Calendar?
    private var days: [Date: AgentToolCounts] = [:]
    private var prunedBefore = Date.distantPast

    init(entries: [AgentToolCall.Key: Entry] = [:]) {
        self.entries = entries
    }

    mutating func add(_ call: AgentToolCall, source: String) {
        var entry = entries[call.key] ?? Entry(sources: [])
        let previous = entry.observation
        if let index = entry.sources.firstIndex(where: { $0.path == source }) {
            entry.sources[index].observation.merge(call.observation)
        } else {
            entry.sources.append(Source(path: source, observation: call.observation))
        }
        replace(entry, for: call.key, previous: previous)
    }

    mutating func forget(files: Set<String>) -> Bool {
        var changed = false
        for (key, old) in entries where old.sources.contains(where: { files.contains($0.path) }) {
            let entry = Entry(sources: old.sources.filter { !files.contains($0.path) })
            changed = replace(entry, for: key, previous: old.observation) || changed
        }
        return changed
    }

    mutating func drop(before date: Date) {
        // Prune once a day. The visible periods end well before this cutoff.
        let boundary = (calendar ?? .current).startOfDay(for: date)
        guard boundary > prunedBefore else { return }
        prunedBefore = boundary
        for (key, entry) in entries {
            guard let reading = entry.observation, reading.date < boundary else { continue }
            let retained = entry.sources.filter { $0.observation.date >= boundary }
            replace(Entry(sources: retained), for: key, previous: reading)
        }
    }

    @discardableResult
    private mutating func replace(_ entry: Entry, for key: AgentToolCall.Key,
                                  previous: AgentToolCall.Observation?) -> Bool {
        guard entries[key] != entry else { return false }
        let next = entry.observation
        entries[key] = next == nil ? nil : entry
        revision &+= 1
        guard previous != next else { return false }
        if let previous { countIfReady(previous, provider: key.provider, by: -1) }
        if let next { countIfReady(next, provider: key.provider, by: 1) }
        return true
    }

    mutating func periods(providers: Set<AgentProvider>, now: Date, calendar: Calendar) -> [AgentPeriod: AgentToolCounts] {
        if calendar != self.calendar {
            self.calendar = calendar
            days = [:]
            for (key, entry) in entries {
                if let reading = entry.observation { countIfReady(reading, provider: key.provider, by: 1) }
            }
        }

        var result: [AgentPeriod: AgentToolCounts] = [:]
        let today = calendar.startOfDay(for: now)
        for period in AgentPeriod.allCases {
            guard let start = calendar.date(byAdding: .day, value: 1 - period.days, to: today) else { continue }
            var counts: AgentToolCounts = [:]
            for (date, day) in days where date >= start && date <= today {
                for (provider, tools) in day where providers.contains(provider) {
                    for (kind, count) in tools { counts[provider, default: [:]][kind, default: 0] += count }
                }
            }
            if !counts.isEmpty { result[period] = counts }
        }
        return result
    }

    private mutating func countIfReady(_ reading: AgentToolCall.Observation, provider: AgentProvider, by delta: Int) {
        guard let calendar else { return }
        let day = calendar.startOfDay(for: reading.date)
        let kind = reading.kind
        let total = (days[day]?[provider]?[kind] ?? 0) + delta
        if total > 0 {
            days[day, default: [:]][provider, default: [:]][kind] = total
        } else {
            days[day]?[provider]?[kind] = nil
            if days[day]?[provider]?.isEmpty == true { days[day]?[provider] = nil }
            if days[day]?.isEmpty == true { days[day] = nil }
        }
    }
}
