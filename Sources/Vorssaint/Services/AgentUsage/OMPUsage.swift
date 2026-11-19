// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreFoundation
import Foundation

struct OMPUsageReading: Equatable, Identifiable {
    let id: String
    let name: String
    let limits: AgentLimits

    func currentLimits(at now: Date) -> AgentLimits? {
        var current = limits
        current.windows.removeAll { $0.resetsAt.map { $0 <= now } ?? false }
        return current.windows.isEmpty ? nil : current
    }
}

enum OMPCLI {
    static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           searchPath: String? = ProcessInfo.processInfo.environment["PATH"]) -> [URL] {
        let folders = [home.appending(path: ".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
            + (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return folders.map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "omp") }
    }

    static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           searchPath: String? = ProcessInfo.processInfo.environment["PATH"]) -> URL? {
        candidates(home: home, searchPath: searchPath).first {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }
}

enum OMPUsageError: Error, Equatable {
    case missing, unavailable, invalidResponse, cancelled
}

/// The public `omp usage --json` report. One reading per authenticated account
/// keeps accounts separate in the UI; the merged limits feed alerts and the
/// resting island just like every other provider.
enum OMPUsageParser {
    static func readings(_ data: Data, observedAt: Date) -> [OMPUsageReading]? {
        guard data.count <= 4 * 1024 * 1024,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let reports = root["reports"] as? [[String: Any]]
        else { return nil }
        let generatedAt = milliseconds(root["generatedAt"]) ?? observedAt
        var readings: [OMPUsageReading] = []
        var identifiers: Set<String> = []

        for (index, report) in reports.enumerated() {
            guard let provider = report["provider"] as? String, !provider.isEmpty,
                  let items = report["limits"] as? [[String: Any]]
            else { continue }
            let metadata = report["metadata"] as? [String: Any] ?? [:]
            let metadataAccount = ((metadata["accountId"] as? String) ?? (metadata["email"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let credential = number(metadata["credentialId"]).flatMap { value -> String? in
                guard value > 0, value.rounded() == value, value < Double(Int.max) else { return nil }
                return String(Int(value))
            }
            let grouped = Dictionary(grouping: items) { item in
                let scope = item["scope"] as? [String: Any] ?? [:]
                return ((scope["accountId"] as? String) ?? (scope["email"] as? String) ?? metadataAccount)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let observed = milliseconds(report["fetchedAt"]) ?? generatedAt
            for (groupIndex, account) in grouped.keys.sorted().enumerated() {
                var id = provider + ":" + (credential ?? "account") + (grouped.count > 1 ? ".\(groupIndex)" : "")
                if identifiers.contains(id) { id += ".\(index)" }
                identifiers.insert(id)
                let windows = (grouped[account] ?? []).compactMap {
                    window($0, reading: "\(provider).\(index).\(groupIndex)")
                }
                guard !windows.isEmpty else { continue }
                var name = displayName(provider)
                if !account.isEmpty { name += " · " + String(account.prefix(100)) }
                readings.append(OMPUsageReading(id: id, name: name,
                    limits: AgentLimits(provider: .omp, windows: windows, observedAt: observed, source: .account)))
            }
        }
        return readings
    }

    static func limits(for readings: [OMPUsageReading]) -> AgentLimits? {
        let windows = readings.flatMap(\.limits.windows)
        guard let observed = readings.map(\.limits.observedAt).max(), !windows.isEmpty else { return nil }
        return AgentLimits(provider: .omp, windows: windows, observedAt: observed, source: .account)
    }

    private static func window(_ item: [String: Any], reading: String) -> AgentLimitWindow? {
        guard let itemID = item["id"] as? String, !itemID.isEmpty,
              let amount = item["amount"] as? [String: Any],
              let used = number(amount["usedFraction"]), used >= 0,
              (used * 100).isFinite
        else { return nil }
        let descriptor = item["window"] as? [String: Any] ?? [:]
        let scopeDescriptor = item["scope"] as? [String: Any] ?? [:]
        let windowID = (descriptor["id"] as? String) ?? (scopeDescriptor["windowId"] as? String) ?? ""
        let label = (descriptor["label"] as? String ?? item["label"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let minutes = number(descriptor["durationMs"]).flatMap { milliseconds -> Int? in
            let value = milliseconds / 60_000
            return value > 0 && value.rounded() == value && value < Double(Int.max) ? Int(value) : nil
        }
        var kind = AgentLogParser.kind(minutes: minutes)
        if windowID == "5h" { kind = .session }
        if windowID == "7d" { kind = .weekly }
        let identity = (windowID + " " + label).lowercased()
        if identity.contains("month") || minutes.map({ (27 * 1440...32 * 1440).contains($0) }) == true {
            kind = .monthly
        }

        let scope: String?
        switch kind {
        case .session:
            scope = nil
        case .weekly:
            scope = identity == "7d" || identity.contains("weekly limit") || identity.contains("7d limit") ? nil : label.nilIfEmpty
        case .monthly:
            if windowID == "limit_month_total" || identity == "monthly total" {
                scope = nil
            } else if windowID == "limit_month_code" {
                scope = "Kimi Code"
            } else {
                scope = label.nilIfEmpty
            }
        case .other:
            scope = minutes == nil ? label.nilIfEmpty : nil
        }
        return AgentLimitWindow(id: "omp.\(reading).\(itemID)", kind: kind, minutes: minutes, scope: scope,
                                usedPercent: used * 100, resetsAt: milliseconds(descriptor["resetsAt"]))
    }

    private static func displayName(_ provider: String) -> String {
        switch provider {
        case "anthropic": return "Claude"
        case "openai-codex", "codex": return "Codex"
        case "github-copilot": return "GitHub Copilot"
        case "kimi-code": return "Kimi Code"
        case "opencode": return "OpenCode"
        default:
            return provider.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }
    }

    private static func milliseconds(_ value: Any?) -> Date? {
        number(value).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0
        else { return nil }
        return number.doubleValue
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
