// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// CodexBar owns the Muse website session. Vorssaint only consumes its quota result.
enum AgentMuseUsage {
    static let interval: TimeInterval = 5 * 60
    private static let weeklyMinutes = 7 * 24 * 60

    private struct Payload: Decodable {
        struct Usage: Decodable {
            struct Window: Decodable {
                let usedPercent: Double
                let windowMinutes: Int?
                let resetsAt: Date?
            }

            let primary: Window?
            let secondary: Window?
            let tertiary: Window?
        }

        let provider: String
        let usage: Usage?
    }

    static func read(home: URL, cancellation: BoundedProcessCancellation) -> AgentLimits? {
        let files = FileManager.default
        let helper = "CodexBar.app/Contents/Helpers/CodexBarCLI"
        let paths = [
            "/Applications/" + helper,
            home.appendingPathComponent("Applications/" + helper).path,
            "/opt/homebrew/bin/codexbar",
            "/usr/local/bin/codexbar",
            home.appendingPathComponent(".local/bin/codexbar").path
        ]
        guard let executable = paths.first(where: { files.isExecutableFile(atPath: $0) }) else { return nil }
        let result = BoundedProcessRunner.run(executable,
            ["usage", "--provider", "museai", "--source", "web", "--format", "json", "--json-only"],
            timeout: 40, maxOutputBytes: 64 * 1024, cancellation: cancellation)
        guard result.status == 0, !result.timedOut, !cancellation.isCancelled else { return nil }
        return limits(from: result.output, observedAt: Date())
    }

    static func limits(from data: Data, observedAt: Date) -> AgentLimits? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payloads = try? decoder.decode([Payload].self, from: data),
              payloads.count == 1, let payload = payloads.first, payload.provider == "museai",
              let usage = payload.usage,
              let weekly = [usage.primary, usage.secondary, usage.tertiary].compactMap({ $0 })
                .first(where: { $0.windowMinutes == weeklyMinutes }),
              (0...100).contains(weekly.usedPercent),
              weekly.resetsAt.map({ $0 > observedAt }) ?? true else { return nil }
        let window = AgentLimitWindow(id: "weekly", kind: .weekly, minutes: weeklyMinutes, scope: nil,
                                      usedPercent: weekly.usedPercent, resetsAt: weekly.resetsAt)
        return AgentLimits(provider: .muse, windows: [window], observedAt: observedAt, source: .account)
    }
}
