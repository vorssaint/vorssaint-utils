// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Interacts with Google Antigravity CLI (`agy`) to fetch account quota and rate limits (`/usage`).
enum AgentAgyServer {
    enum Failure: Error, Equatable {
        case missing, timeout, failed(String)
    }

    static let timeout: TimeInterval = 15
    /// Refresh interval when AI page is visible.
    static let freshness: TimeInterval = 60
    /// Background refresh interval.
    static let backgroundFreshness: TimeInterval = 5 * 60

    static func executable(home: URL, searchPath: String? = nil) -> URL? {
        var candidates: [String] = [
            home.appending(path: ".local/bin/agy").path,
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy"
        ]
        if let searchPath {
            candidates += searchPath.split(separator: ":").map { String($0) + "/agy" }
        }
        for path in candidates {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue,
               FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private struct UsageResponse: Codable {
        struct CommandData: Codable {
            let name: String?
            let data: UsageData?
        }
        struct UsageData: Codable {
            let description: String?
            let groups: [Group]?
        }
        struct Group: Codable {
            let name: String
            let description: String?
            let buckets: [Bucket]?
        }
        struct Bucket: Codable {
            let id: String
            let name: String
            let description: String?
            let window: String?
            let remaining_fraction: Double?
            let reset_time: String?
        }
        let command: CommandData?
    }

    final class Request {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func cancel() {
            lock.withLock {
                cancelled = true
                if let process, process.isRunning {
                    process.terminate()
                }
            }
        }

        func run(executable: URL, home: URL, timeout: TimeInterval = AgentAgyServer.timeout) -> Result<AgentLimits, Failure> {
            let isCancelled = lock.withLock { cancelled }
            guard !isCancelled else { return .failure(.failed("Cancelled")) }

            let proc = Process()
            let pipe = Pipe()
            proc.executableURL = executable
            proc.arguments = ["-p", "/usage", "--output-format", "json"]

            var environment = ProcessInfo.processInfo.environment
            environment["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
            environment["HOME"] = home.path
            let currentPath = environment["PATH"] ?? ""
            let extraPaths = [home.appending(path: ".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
            environment["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
            proc.environment = environment
            proc.currentDirectoryURL = home
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice

            lock.withLock { self.process = proc }
            defer { lock.withLock { self.process = nil } }

            do {
                try proc.run()
            } catch {
                return .failure(.failed(error.localizedDescription))
            }

            let deadline = DispatchTime.now() + timeout
            let exited = DispatchSemaphore(value: 0)
            proc.terminationHandler = { _ in exited.signal() }

            if exited.wait(timeout: deadline) == .timedOut {
                if proc.isRunning { proc.terminate() }
                return .failure(.timeout)
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty else { return .failure(.failed("Empty output from agy")) }

            let decoder = JSONDecoder()
            guard let parsed = try? decoder.decode(UsageResponse.self, from: data),
                  let groups = parsed.command?.data?.groups else {
                return .failure(.failed("Failed to parse agy JSON"))
            }

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]

            var windows: [AgentLimitWindow] = []
            for group in groups {
                for bucket in group.buckets ?? [] {
                    let kind: AgentLimitWindow.Kind
                    let minutes: Int?
                    if bucket.window == "5h" {
                        kind = .session
                        minutes = 300
                    } else if bucket.window == "weekly" {
                        kind = .weekly
                        minutes = 10080
                    } else {
                        kind = .other
                        minutes = nil
                    }
                    let remaining = bucket.remaining_fraction ?? 1.0
                    let usedPercent = max(0, min(100, (1.0 - remaining) * 100.0))
                    let resetsAt = bucket.reset_time.flatMap { isoFormatter.date(from: $0) }

                    windows.append(AgentLimitWindow(
                        id: "agy.\(bucket.id)",
                        kind: kind,
                        minutes: minutes,
                        scope: group.name,
                        usedPercent: usedPercent,
                        resetsAt: resetsAt,
                        name: bucket.name,
                        detail: group.description
                    ))
                }
            }

            return .success(AgentLimits(
                provider: .agy,
                windows: windows,
                observedAt: Date(),
                source: .account
            ))
        }
    }
}
