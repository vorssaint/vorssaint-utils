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
