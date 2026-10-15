// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Antigravity's plan limits, as its own CLI reports them: `agy -p /usage
/// --output-format json` answers locally with the account's quota buckets,
/// without starting a conversation or spending quota. Vorssaint never reads
/// the account's credentials; `agy` signs in itself.
enum AgentAntigravityLimits {
    /// The first version that answers `/usage` as a command. An older one
    /// reads it as a prompt and would spend quota on it.
    static let minimumVersion = [1, 1, 11]
    static let timeout: TimeInterval = 30
    /// Asked at most this often, and sooner while an Antigravity turn runs.
    static let interval: TimeInterval = 300
    static let busyInterval: TimeInterval = 90

    static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        [home.appending(path: ".local/bin/agy").path, "/opt/homebrew/bin/agy", "/usr/local/bin/agy"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// The account's limits, or nil when `agy` is missing, too old, signed
    /// out or does not answer. Blocks its caller: run it off the main thread.
    static func read(now: Date = Date()) -> AgentLimits? {
        guard let agy = executable(),
              let version = run(agy, ["--version"], timeout: 5).flatMap(parseVersion),
              version.lexicographicallyPrecedes(minimumVersion) == false,
              let output = run(agy, ["-p", "/usage", "--output-format", "json", "--print-timeout", "20s"],
                               timeout: timeout) else { return nil }
        return parse(output, observed: now)
    }

    static func parseVersion(_ text: String) -> [Int]? {
        // The first word shaped like "1.3.3".
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            let parts = word.split(separator: ".").map { Int($0) }
            if parts.count >= 3, parts.allSatisfy({ $0 != nil }) { return parts.prefix(3).compactMap { $0 } }
        }
        return nil
    }

    /// The first JSON line that is a successful `usage` command, reduced to
    /// limit windows: five-hour buckets as sessions, weekly ones as weeks.
    /// Only the Gemini group counts; the Claude and GPT models Antigravity
    /// also offers have limits of their own that go unused here.
    static func parse(_ output: String, observed: Date) -> AgentLimits? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"),
                  let json = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any],
                  json["status"] as? String == "SUCCESS",
                  let command = json["command"] as? [String: Any], command["name"] as? String == "usage",
                  let data = command["data"] as? [String: Any],
                  let groups = data["groups"] as? [[String: Any]] else { continue }
            var windows: [AgentLimitWindow] = []
            for group in groups {
                guard let name = group["name"] as? String, name.lowercased().hasPrefix("gemini") else { continue }
                for bucket in group["buckets"] as? [[String: Any]] ?? [] where bucket["disabled"] as? Bool != true {
                    guard let id = bucket["id"] as? String, !id.isEmpty,
                          let remaining = (bucket["remaining_fraction"] as? NSNumber)?.doubleValue,
                          remaining.isFinite else { continue }
                    let window = bucket["window"] as? String
                    let kind: AgentLimitWindow.Kind = window == "5h" ? .session : window == "weekly" ? .weekly : .other
                    let minutes: Int? = window == "5h" ? 300 : window == "weekly" ? 10_080 : nil
                    windows.append(AgentLimitWindow(
                        id: "antigravity:\(id)", kind: kind, minutes: minutes, scope: nil,
                        usedPercent: min(100, max(0, (1 - remaining) * 100)),
                        resetsAt: (bucket["reset_time"] as? String).flatMap(AgentTimestamp.parse)))
                }
            }
            guard !windows.isEmpty else { return nil }
            return AgentLimits(provider: .antigravity, windows: windows, observedAt: observed, source: .account)
        }
        return nil
    }

    /// Standard output of one short run, or nil when it fails or overruns.
    private static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
                               environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"].joined(separator: ":")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        var data = Data()
        let lock = NSLock()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            lock.withLock { if data.count < 1 << 20 { data.append(chunk) } }
        }
        do { try process.run() } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        output.fileHandleForReading.readabilityHandler = nil
        let rest = (try? output.fileHandleForReading.readToEnd()) ?? nil
        return lock.withLock {
            if let rest { data.append(rest) }
            return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
        }
    }
}
