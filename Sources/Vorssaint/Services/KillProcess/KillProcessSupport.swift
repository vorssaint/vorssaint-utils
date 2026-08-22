// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure helpers for the Kill Process feature: protected system processes and
/// safety boundaries.
enum KillProcessSupport {
    /// Parses `lsof -Fpn` output into sorted, de-duplicated listening ports.
    static func listeningTCPPorts(from output: String) -> [pid_t: [Int]] {
        var currentPID: pid_t?
        var values: [pid_t: Set<Int>] = [:]
        for line in output.split(separator: "\n") {
            guard let prefix = line.first else { continue }
            let value = line.dropFirst()
            if prefix == "p" {
                currentPID = pid_t(value)
            } else if prefix == "n", let pid = currentPID,
                      let separator = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: separator)...]),
                      (1...65_535).contains(port) {
                values[pid, default: []].insert(port)
            }
        }
        return values.mapValues { $0.sorted() }
    }

    static func matches(query: String, name: String, pid: pid_t, ports: [Int]) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return name.lowercased().contains(needle)
            || String(pid) == needle
            || ports.contains { String($0) == needle }
    }

    static func mergedPorts(_ groups: [[Int]]) -> [Int] {
        Array(Set(groups.flatMap { $0 })).sorted()
    }

    /// Header and rows reserve the same fixed width for metrics and actions.
    static func processColumnWidth(availableWidth: CGFloat) -> CGFloat {
        max(80, availableWidth - 442)
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
