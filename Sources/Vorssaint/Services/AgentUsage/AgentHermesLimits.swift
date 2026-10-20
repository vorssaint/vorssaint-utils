// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Hermes owns credential resolution; only its public usage document enters the app.
enum AgentHermesLimits {
    enum Failure: Error { case missingCLI, unavailable, timedOut, cancelled }

    /// Finder's PATH is sparse; the standard Hermes installer uses ~/.local/bin.
    static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home.appending(path: ".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        return paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).appending(path: "hermes") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Invoke only Hermes's public account-usage command. Credentials never
    /// enter Vorssaint, and no prompt/session/model request is made here.
    /// The caller owns throttling; work runs off the main and log-reader queues.
    static func fetch(home: URL, executable supplied: URL? = nil, timeout: TimeInterval = 25,
                      cancellation: BoundedProcessCancellation? = nil) -> Result<Reading, Failure> {
        guard cancellation?.isCancelled != true else { return .failure(.cancelled) }
        guard let cli = supplied ?? executable() else { return .failure(.missingCLI) }
        var environment = ProcessInfo.processInfo.environment
        environment["HERMES_HOME"] = home.path
        let result = BoundedProcessRunner.run(cli.path, ["usage", "--json"], timeout: timeout,
                                             maxOutputBytes: 128 << 10, environment: environment,
                                             cancellation: cancellation)
        guard cancellation?.isCancelled != true else { return .failure(.cancelled) }
        guard !result.timedOut else { return .failure(.timedOut) }
        guard result.status == 0, let reading = parse(result.output) else { return .failure(.unavailable) }
        return .success(reading)
    }

    struct Reading: Equatable {
        let provider: String
        let plan: String?
        let limits: AgentLimits
        let details: [String]
        let unavailableReason: String?

        /// Missing checks and passed resets mean unknown, not a renewed zero.
        func current(at now: Date) -> Reading? {
            let age = now.timeIntervalSince(limits.observedAt)
            guard unavailableReason == nil, age >= -60, age < 600 else { return nil }
            var current = limits
            current.windows.removeAll { $0.resetsAt.map { $0 <= now } ?? false }
            guard !current.windows.isEmpty || !details.isEmpty else { return nil }
            return Reading(provider: provider, plan: plan, limits: current, details: details, unavailableReason: nil)
        }
    }

    static func parse(_ data: Data) -> Reading? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let provider = object["provider"] as? String, !provider.isEmpty,
              let fetched = date(object["fetched_at"]) else { return nil }
        let windows = (object["windows"] as? [[String: Any]] ?? []).enumerated().compactMap { index, item -> AgentLimitWindow? in
            guard let label = item["label"] as? String,
                  let number = item["used_percent"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  (0...100).contains(number.doubleValue) else { return nil }
            let normalized = label.lowercased()
            let kind: AgentLimitWindow.Kind = ["weekly", "current week"].contains(normalized) ? .weekly
                : ["session", "current session", "5 hour", "5-hour"].contains(normalized) ? .session : .other
            return AgentLimitWindow(id: "hermes-\(index)-\(label)", kind: kind, minutes: nil,
                                    scope: kind == .other ? label : nil,
                                    usedPercent: number.doubleValue, resetsAt: date(item["resets_at"]))
        }
        return Reading(provider: provider, plan: object["plan"] as? String,
                       limits: AgentLimits(provider: .hermes, windows: windows, observedAt: fetched, source: .account),
                       details: object["details"] as? [String] ?? [],
                       unavailableReason: object["unavailable_reason"] as? String)
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: value) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
