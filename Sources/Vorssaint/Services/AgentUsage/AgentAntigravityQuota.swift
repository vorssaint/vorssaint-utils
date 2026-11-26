// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreFoundation
import Foundation

/// The signed-in Antigravity CLI reports account quotas through /usage.
enum AgentAntigravityQuota {
    static let title = "Antigravity · Gemini"
    static let symbol = "gauge.with.dots.needle.33percent"

    private static let queue = DispatchQueue(label: "com.vorssaint.antigravity-quota", qos: .utility)
    private static let arguments = ["--output-format", "json", "--print=/usage"]

    static func executable(home: URL) -> URL? {
        let candidates = [
            home.appending(path: ".local/bin/agy"),
            URL(fileURLWithPath: "/opt/homebrew/bin/agy"),
            URL(fileURLWithPath: "/usr/local/bin/agy")
        ]
        return candidates.first { candidate in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: candidate.path, isDirectory: &directory)
                && !directory.boolValue && FileManager.default.isExecutableFile(atPath: candidate.path)
        }
    }

    /// Check the version before handing older binaries a slash command that
    /// they might send as a prompt.
    static func supportsUsage(_ version: Data) -> Bool {
        let raw = String(decoding: version, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        let numbers = parts.compactMap { part in
            part.allSatisfy { $0.isASCII && $0.isNumber } ? Int(part) : nil
        }
        return numbers.count == 3 && !numbers.lexicographicallyPrecedes([1, 1, 11])
    }

    static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) async -> [AgentLimitWindow] {
        let cancellation = BoundedProcessCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: read(home: home, cancellation: cancellation)) }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func read(home: URL, cancellation: BoundedProcessCancellation) -> [AgentLimitWindow] {
        guard !cancellation.isCancelled, let cli = executable(home: home) else { return [] }
        // Use the CLI's own sign-in even when Vorssaint was launched by a
        // terminal with a model provider's credentials in its environment.
        let inherited = ProcessInfo.processInfo.environment
        let allowed = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
                       "http_proxy", "https_proxy", "all_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR"]
        var environment = inherited.filter { allowed.contains($0.key) || $0.key.hasPrefix("LC_") }
        environment["PATH"] = [cli.deletingLastPathComponent().path, "/usr/bin", "/bin"].joined(separator: ":")
        environment["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"

        let version = BoundedProcessRunner.run(cli.path, ["--version"], timeout: 5, maxOutputBytes: 1024,
                                               environment: environment, cancellation: cancellation)
        guard version.status == 0, supportsUsage(version.output), !cancellation.isCancelled else { return [] }
        let result = BoundedProcessRunner.run(cli.path, arguments, timeout: 20, maxOutputBytes: 64 * 1024,
                                              environment: environment, cancellation: cancellation)
        guard result.status == 0, !cancellation.isCancelled else { return [] }
        return windows(result.output, observedAt: Date())
    }

    static func windows(_ data: Data, observedAt: Date) -> [AgentLimitWindow] {
        func envelope(_ bytes: Data) -> [String: Any]? {
            (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
        }
        // The runner drains both streams. Some CLI setups print a diagnostic
        // before the single-line command result.
        guard let response = envelope(data) ?? data.split(separator: 10).lazy.compactMap({ envelope(Data($0)) })
            .first(where: { $0["command"] != nil }),
            response["status"] as? String == "SUCCESS", let turns = response["num_turns"] as? NSNumber,
            CFGetTypeID(turns) != CFBooleanGetTypeID(), turns.doubleValue == 0,
            let command = response["command"] as? [String: Any], command["name"] as? String == "usage",
            let payload = command["data"] as? [String: Any],
            let groups = payload["groups"] as? [[String: Any]] else { return [] }

        let buckets = groups.flatMap { $0["buckets"] as? [[String: Any]] ?? [] }
        return [("gemini-5h", "5h", AgentLimitWindow.Kind.session, 300),
                ("gemini-weekly", "weekly", .weekly, 10_080)].compactMap { id, duration, kind, minutes in
            // IDs identify the shared Gemini pool even if the CLI changes a
            // display label. A different model pool may have the same period.
            let matches = buckets.filter { ($0["id"] as? String) == id }
            guard matches.count == 1, let bucket = matches.first, bucket["window"] as? String == duration,
                  let fraction = bucket["remaining_fraction"] as? NSNumber,
                  CFGetTypeID(fraction) != CFBooleanGetTypeID(), (0...1).contains(fraction.doubleValue) else { return nil }
            let reset = bucket["reset_time"].flatMap { $0 is NSNull ? nil : $0 }
            let resetsAt = (reset as? String).flatMap(AgentTimestamp.parse)
            guard reset == nil || resetsAt.map({ $0 > observedAt }) == true else { return nil }
            return AgentLimitWindow(id: "antigravity." + id, kind: kind, minutes: minutes, scope: nil,
                                    usedPercent: (1 - fraction.doubleValue) * 100, resetsAt: resetsAt)
        }
    }

    /// After a reset, the new usage is unknown until the next reading.
    static func current(_ windows: [AgentLimitWindow], now: Date) -> [AgentLimitWindow] {
        windows.filter { $0.resetsAt.map { $0 > now } ?? true }
    }
}
