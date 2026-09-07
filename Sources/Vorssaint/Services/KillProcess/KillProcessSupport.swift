// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure helpers for the Kill Process feature: protected system processes and
/// safety boundaries.
enum KillProcessSupport {
    static func numberComesBefore(_ lhs: Double,
                                  _ rhs: Double,
                                  lhsPID: pid_t,
                                  rhsPID: pid_t,
                                  ascending: Bool) -> Bool {
        if lhs == rhs { return lhsPID < rhsPID }
        return ascending ? lhs < rhs : lhs > rhs
    }

    static func nameComesBefore(_ lhs: String,
                                _ rhs: String,
                                lhsPID: pid_t,
                                rhsPID: pid_t,
                                ascending: Bool) -> Bool {
        let comparison = lhs.localizedCaseInsensitiveCompare(rhs)
        if comparison == .orderedSame { return lhsPID < rhsPID }
        return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    /// Every descendant of `root` from a flat parent table, breadth first so
    /// the caller can reverse it and kill deepest first. A pid is visited
    /// once, so a self-parenting or circular row cannot loop, and the total
    /// is capped well above any real process tree.
    static func descendants(of root: pid_t, parents: [(pid: pid_t, ppid: pid_t)]) -> [pid_t] {
        var children: [pid_t: [pid_t]] = [:]
        for row in parents {
            children[row.ppid, default: []].append(row.pid)
        }
        var result: [pid_t] = []
        var seen: Set<pid_t> = [root]
        var frontier = [root]
        while !frontier.isEmpty, result.count < 4096 {
            var next: [pid_t] = []
            for parent in frontier {
                for child in children[parent] ?? [] where seen.insert(child).inserted {
                    next.append(child)
                }
            }
            result.append(contentsOf: next)
            frontier = next
        }
        return result
    }

    static func normalizedStartDescription(_ value: String) -> String? {
        let normalized = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !normalized.isEmpty,
              normalized.range(of: "^[A-Za-z0-9: ]+$", options: .regularExpression) != nil
        else { return nil }
        return normalized
    }

    /// Protects kernel, launchd, vital window/session infrastructure, and the
    /// app's own process from being terminated.
    static func isProtected(pid: pid_t, name: String = "", path: String = "") -> Bool {
        if pid <= 1 || pid == ProcessInfo.processInfo.processIdentifier { return true }
        let lowerName = name.trimmingCharacters(in: .whitespaces).lowercased()
        let lowerPath = path.trimmingCharacters(in: .whitespaces).lowercased()
        let protectedNames: Set<String> = [
            "kernel_task", "launchd", "windowserver", "loginwindow",
            "vorssaint", "vorssaint (developer)", "vorssaintdeveloper"
        ]
        if protectedNames.contains(lowerName) { return true }
        if lowerPath.hasSuffix("/windowserver") || lowerPath.hasSuffix("/loginwindow") || lowerPath.hasSuffix("/launchd") {
            return true
        }
        return false
    }
}
