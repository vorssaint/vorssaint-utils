// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AntigravityQuota {
    static func executable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let search = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let folders = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
            + search.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return folders.map { $0 + "/agy" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func read(cancellation: BoundedProcessCancellation) -> AgentLimits? {
        guard let path = executable() else { return nil }
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        let result = BoundedProcessRunner.run(path, ["--output-format", "json", "--print=/usage"],
                                              timeout: 15, maxOutputBytes: 262144, environment: environment,
                                              cancellation: cancellation)
        guard !result.timedOut, result.status == 0 else { return nil }
        return parse(result.output)
    }

    static func parse(_ data: Data, now: Date = Date()) -> AgentLimits? {
        struct Response: Decodable {
            struct Command: Decodable {
                struct Payload: Decodable {
                    struct Group: Decodable {
                        struct Bucket: Decodable {
                            let id: String
                            let window: String
                            let remainingFraction: Double?
                            let resetTime: String?
                        }
                        let name: String
                        let buckets: [Bucket]
                    }
                    let groups: [Group]
                }
                let name: String
                let data: Payload
            }
            let status: String
            let command: Command
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(Response.self, from: data),
              response.status == "SUCCESS", response.command.name == "usage" else { return nil }
        let date = ISO8601DateFormatter()
        let fractionalDate = ISO8601DateFormatter()
        fractionalDate.formatOptions.insert(.withFractionalSeconds)
        var windows: [AgentLimitWindow] = []
        for group in response.command.data.groups {
            for bucket in group.buckets {
                guard let remaining = bucket.remainingFraction, (0...1).contains(remaining) else { continue }
                let kind: AgentLimitWindow.Kind
                let minutes: Int?
                switch bucket.window {
                case "5h": (kind, minutes) = (.session, 300)
                case "weekly": (kind, minutes) = (.weekly, 10080)
                default: (kind, minutes) = (.other, nil)
                }
                let reset = bucket.resetTime.flatMap { date.date(from: $0) ?? fractionalDate.date(from: $0) }
                windows.append(AgentLimitWindow(id: bucket.id, kind: kind, minutes: minutes, scope: group.name,
                                                usedPercent: (1 - remaining) * 100, resetsAt: reset))
            }
        }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .antigravity, windows: windows, observedAt: now, source: .account)
    }
}
