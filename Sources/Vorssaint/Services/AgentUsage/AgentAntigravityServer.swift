// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Reads Antigravity account quotas through the local `agy` CLI's structured
/// `/usage` command (`agy --output-format json --print /usage`). Antigravity
/// handles its own sign-in, which Vorssaint never reads. No model request or
/// conversation is created. Versions earlier than 1.1.11 are refused before
/// `/usage` is ever invoked.
enum AgentAntigravityServer {
    enum Failure: Error, Equatable {
        case missing, needsSignIn, outdated, unreachable
    }

    struct Version: Equatable, Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        static func < (lhs: Version, rhs: Version) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
    }

    /// Releases before 1.1.11 do not handle `/usage` locally in print mode.
    static let minimumVersion = Version(major: 1, minor: 1, patch: 11)
    static let versionTimeout: TimeInterval = 5
    static let timeout: TimeInterval = 20
    static let freshness: TimeInterval = 60
    static let backgroundFreshness: TimeInterval = 5 * 60
    static let retryAfter: TimeInterval = 5 * 60
    static let settledRetry: TimeInterval = 30 * 60
    private static let maximumOutputBytes = 1 << 20
    private static let maximumErrorBytes = 64 << 10

    private static let versionLock = NSLock()
    private static var verifiedVersions: [String: (inode: UInt64, modified: Date, version: Version?)] = [:]

    static func interval(after failure: Failure?, repeated: Int = 1, pageVisible: Bool) -> TimeInterval {
        switch failure {
        case nil: return pageVisible ? freshness : backgroundFreshness
        case .unreachable?: return min(settledRetry, retryAfter * Double(1 << min(3, max(0, repeated - 1))))
        case .missing?, .needsSignIn?, .outdated?: return settledRetry
        }
    }

    static func candidates(home: URL, searchPath: String? = nil) -> [URL] {
        var folders: [String] = [
            home.appending(path: ".local/bin").path,
            home.appending(path: ".gemini/antigravity-cli/bin").path,
            home.appending(path: ".gemini/antigravity/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        folders += (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        folders += AgentClaudeServer.toolFolders(home: home)
        var result = folders.map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "agy") }
        result.append(URL(fileURLWithPath: "/Applications/Antigravity.app/Contents/Resources/app/bin/agy"))
        return result
    }

    static func executable(home: URL, searchPath: String? = nil) -> URL? {
        candidates(home: home, searchPath: searchPath).first { url in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    static func environment(_ base: [String: String], for executable: URL, home: URL) -> [String: String] {
        var env = AgentCodexServer.environment(for: executable, searchPath: nil, base: base)
        env["PATH"] = AgentClaudeServer.searchPath(after: env["PATH"] ?? "", home: home)
        return env
    }

    /// Parses the first semantic version (`major.minor.patch`) in `text`.
    static func parseVersion(_ text: String) -> Version? {
        let tokens = text.split { !$0.isNumber && $0 != "." && $0 != "v" && $0 != "V" }
        for raw in tokens {
            let trimmed = raw.first == "v" || raw.first == "V" ? raw.dropFirst() : raw
            let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
            if parts.count >= 3, parts[0] >= 0, parts[1] >= 0, parts[2] >= 0 {
                return Version(major: parts[0], minor: parts[1], patch: parts[2])
            }
        }
        return nil
    }

    static func supportsUsage(versionOutput: String) -> Bool {
        guard let version = parseVersion(versionOutput) else { return false }
        return version >= minimumVersion
    }

    /// Short, scannable pool label for cards and notices.
    static func scopeLabel(for groupName: String) -> String {
        let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lower = trimmed.lowercased()
        if lower == "gemini models" || lower == "gemini" { return "Gemini" }
        if lower.contains("claude") && lower.contains("gpt") { return "Claude/GPT" }
        for suffix in [" models", " model"] where lower.hasSuffix(suffix) {
            return String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    static func limits(_ data: Data, observed: Date) -> Result<AgentLimits, Failure> {
        guard let json = parseJSONObject(from: data) else {
            return .failure(classifyFailureText(String(decoding: data.prefix(4096), as: UTF8.self)))
        }
        if let status = (json["status"] as? String)?.uppercased(), status != "SUCCESS" {
            let message = [json["error"] as? String, json["response"] as? String, json["message"] as? String]
                .compactMap { $0 }.joined(separator: " ")
            return .failure(classifyFailureText(message))
        }
        guard let command = json["command"] as? [String: Any],
              (command["name"] as? String)?.lowercased() == "usage",
              let payload = command["data"] as? [String: Any],
              let groups = payload["groups"] as? [[String: Any]] else {
            let text = (json["response"] as? String ?? "") + " " + (json["error"] as? String ?? "")
            if isAuthFailure(text) { return .failure(.needsSignIn) }
            return .failure(.unreachable)
        }

        var windows: [AgentLimitWindow] = []
        var seenIDs = Set<String>()
        for group in groups {
            let groupName = group["name"] as? String ?? ""
            let scope = scopeLabel(for: groupName)
            let buckets = group["buckets"] as? [[String: Any]] ?? []
            for bucket in buckets {
                guard let usedPercent = extractUsedPercent(from: bucket) else { continue }
                let windowSpec = windowKindAndMinutes(from: bucket)
                let resetValue = bucket["reset_time"].flatMap { $0 is NSNull ? nil : $0 }
                let resetDate = (resetValue as? String).flatMap(AgentTimestamp.parse)
                // A window whose renewal already passed before this reading
                // says nothing about the current allowance.
                guard resetValue == nil || resetDate.map({ $0 > observed }) == true else { continue }
                let rawID = (bucket["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let suffix = rawID.isEmpty ? "\(scope.lowercased()).\(windowSpec.kind.rawValue)" : rawID
                let id = "antigravity.\(suffix)"
                guard seenIDs.insert(id).inserted else { continue }
                windows.append(AgentLimitWindow(
                    id: id, kind: windowSpec.kind, minutes: windowSpec.minutes,
                    scope: scope.isEmpty ? nil : scope,
                    usedPercent: usedPercent, resetsAt: resetDate))
            }
        }
        guard !windows.isEmpty else { return .failure(.unreachable) }
        return .success(AgentLimits(provider: .antigravity, windows: windows, observedAt: observed, source: .account))
    }

    /// Expires each window once its renewal passes without inventing zero usage
    /// for remote sessions.
    static func current(_ reading: AgentLimits?, now: Date) -> AgentLimits? {
        guard var reading else { return nil }
        let age = now.timeIntervalSince(reading.observedAt)
        reading.windows.removeAll { window in
            if let resets = window.resetsAt { return resets <= now }
            return age >= (window.kind == .session ? TimeInterval(window.minutes ?? 300) * 60 : 86_400)
        }
        return reading.windows.isEmpty ? nil : reading
    }

    private static func extractUsedPercent(from bucket: [String: Any]) -> Double? {
        if let remaining = finiteNumber(bucket["remaining_fraction"]) {
            return min(100, max(0, (1 - min(1, max(0, remaining))) * 100))
        }
        if let used = finiteNumber(bucket["used_fraction"]) {
            return min(100, max(0, min(1, max(0, used)) * 100))
        }
        if let usedPct = finiteNumber(bucket["used_percent"]) {
            return min(100, max(0, usedPct))
        }
        if let remainingPct = finiteNumber(bucket["remaining_percent"]) {
            return min(100, max(0, 100 - remainingPct))
        }
        return nil
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func windowKindAndMinutes(from bucket: [String: Any]) -> (kind: AgentLimitWindow.Kind, minutes: Int?) {
        let raw = (bucket["window"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "5h", "session", "five_hour", "five-hour":
            return (.session, 300)
        case "weekly", "7d", "week", "seven_day":
            return (.weekly, 10_080)
        default:
            if raw.hasSuffix("h"), let hours = Int(raw.dropLast()), hours > 0 {
                let mins = hours * 60
                return (AgentLogParser.kind(minutes: mins), mins)
            }
            if raw.hasSuffix("d"), let days = Int(raw.dropLast()), days > 0 {
                let mins = days * 1440
                return (AgentLogParser.kind(minutes: mins), mins)
            }
            let name = (bucket["name"] as? String ?? "").lowercased()
            if name.contains("five hour") || name.contains("5-hour") || name.contains("session") {
                return (.session, 300)
            }
            if name.contains("weekly") || name.contains("week") {
                return (.weekly, 10_080)
            }
            return (.other, nil)
        }
    }

    private static func parseJSONObject(from data: Data) -> [String: Any]? {
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return object
        }
        // Tolerate leading or trailing non-JSON log lines on stdout.
        guard let start = data.firstIndex(of: 0x7B), let end = data.lastIndex(of: 0x7D), start < end else { return nil }
        return (try? JSONSerialization.jsonObject(with: data[start...end])) as? [String: Any]
    }

    private static func classifyFailureText(_ text: String) -> Failure {
        let lower = text.lowercased()
        if isAuthFailure(lower) { return .needsSignIn }
        if lower.contains("unknown flag") || lower.contains("flag provided but not defined")
            || lower.contains("unknown command") || lower.contains("unrecognized") {
            return .outdated
        }
        return .unreachable
    }

    private static func isAuthFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("not authenticated") || lower.contains("unauthenticated")
            || lower.contains("not logged in") || lower.contains("sign in") || lower.contains("login required")
            || lower.contains("please authenticate") || lower.contains("credentials")
            || lower.contains("oauth") || lower.contains("auth required")
    }

    /// Cancellable, bounded CLI runner for one version-gated `/usage` check.
    final class Request {
        private let cancellation = BoundedProcessCancellation()

        func cancel() {
            cancellation.cancel()
        }

        func run(_ executable: URL, home: URL, environment: [String: String],
                 timeout: TimeInterval = AgentAntigravityServer.timeout) -> Result<AgentLimits, Failure> {
            guard !cancellation.isCancelled else { return .failure(.unreachable) }
            let env = AgentAntigravityServer.environment(environment, for: executable, home: home)
            switch verifyVersion(executable, environment: env) {
            case .failure(let failure): return .failure(failure)
            case .success: break
            }
            guard !cancellation.isCancelled else { return .failure(.unreachable) }
            let output = execute(executable, arguments: ["--output-format", "json", "--print", "/usage"],
                                 environment: env, timeout: timeout)
            guard !cancellation.isCancelled else { return .failure(.unreachable) }
            if output.timedOut { return .failure(.unreachable) }
            let observed = Date()
            if output.status == 0 {
                return AgentAntigravityServer.limits(output.stdout, observed: observed)
            }
            // Some CLI errors still emit structured JSON on stdout.
            if !output.stdout.isEmpty, case .success(let limits) = AgentAntigravityServer.limits(output.stdout, observed: observed) {
                return .success(limits)
            }
            let combined = String(decoding: output.stderr.prefix(4096), as: UTF8.self) + " "
                + String(decoding: output.stdout.prefix(4096), as: UTF8.self)
            return .failure(AgentAntigravityServer.classifyFailureText(combined))
        }

        private func verifyVersion(_ executable: URL, environment: [String: String]) -> Result<Void, Failure> {
            var info = stat()
            guard stat(executable.path, &info) == 0 else { return .failure(.missing) }
            let inode = UInt64(info.st_ino)
            let modified = AgentLogCursor.modificationDate(info)
            if let cached = AgentAntigravityServer.versionLock.withLock({
                AgentAntigravityServer.verifiedVersions[executable.path]
            }), cached.inode == inode, cached.modified == modified {
                guard let version = cached.version, version >= AgentAntigravityServer.minimumVersion else {
                    return .failure(.outdated)
                }
                return .success(())
            }
            let output = execute(executable, arguments: ["--version"], environment: environment,
                                 timeout: AgentAntigravityServer.versionTimeout)
            guard !cancellation.isCancelled else { return .failure(.unreachable) }
            guard !output.timedOut, output.status == 0 else { return .failure(.unreachable) }
            let text = String(decoding: output.stdout, as: UTF8.self) + " " + String(decoding: output.stderr, as: UTF8.self)
            let parsed = AgentAntigravityServer.parseVersion(text)
            AgentAntigravityServer.versionLock.withLock {
                AgentAntigravityServer.verifiedVersions[executable.path] = (inode, modified, parsed)
            }
            guard let parsed, parsed >= AgentAntigravityServer.minimumVersion else { return .failure(.outdated) }
            return .success(())
        }

        private struct Output {
            let status: Int32
            let stdout: Data
            let stderr: Data
            let timedOut: Bool
        }

        private func execute(_ executable: URL, arguments: [String], environment: [String: String],
                             timeout: TimeInterval) -> Output {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = environment
            process.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
            process.standardInput = FileHandle.nullDevice
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let lock = NSLock()
            var stdout = Data()
            var stderr = Data()
            let outDrained = DispatchSemaphore(value: 0)
            let errDrained = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    outDrained.signal()
                } else {
                    lock.withLock {
                        let room = max(0, AgentAntigravityServer.maximumOutputBytes - stdout.count)
                        if room > 0 { stdout.append(chunk.prefix(room)) }
                    }
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    errDrained.signal()
                } else {
                    lock.withLock {
                        let room = max(0, AgentAntigravityServer.maximumErrorBytes - stderr.count)
                        if room > 0 { stderr.append(chunk.prefix(room)) }
                    }
                }
            }

            defer {
                cancellation.release(process)
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                try? outPipe.fileHandleForReading.close()
                try? errPipe.fileHandleForReading.close()
            }

            process.terminationHandler = { _ in finished.signal() }
            do {
                try cancellation.launch(process)
            } catch {
                return Output(status: -1, stdout: Data(), stderr: Data(), timedOut: false)
            }

            // Close parent's write ends so EOF arrives promptly when the child exits.
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()

            var didFinish = finished.wait(timeout: .now() + max(0, timeout)) == .success
            let timedOut = !didFinish
            if timedOut {
                process.terminate()
                didFinish = finished.wait(timeout: .now() + 0.5) == .success
                if !didFinish {
                    kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + 0.5)
                }
            }
            _ = outDrained.wait(timeout: .now() + 0.2)
            _ = errDrained.wait(timeout: .now() + 0.2)
            let (outData, errData) = lock.withLock { (stdout, stderr) }
            return Output(status: timedOut ? -1 : process.terminationStatus,
                          stdout: outData, stderr: errData, timedOut: timedOut)
        }
    }
}
