// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation

/// Reads account-wide Antigravity quota buckets through `agy -p /usage`.
/// No prompt, workspace context, MCP server or model generation runs: `/usage`
/// is an instant local CLI slash command against the signed-in account.
enum AgentAntigravityServer {
    enum Failure: Error, Equatable {
        case missing, needsSignIn, outdated, unreachable
    }

    struct Summary: Equatable {
        let limits: AgentLimits
    }

    static let timeout: TimeInterval = 25
    /// While the AI page is on screen a reading this old is asked again.
    static let freshness: TimeInterval = 60
    /// Otherwise Antigravity CLI starts at most this often.
    static let backgroundFreshness: TimeInterval = 5 * 60
    static let retryAfter: TimeInterval = 5 * 60
    /// Only the person can install, update or sign in to Antigravity.
    static let settledRetry: TimeInterval = 30 * 60
    static let minimumVersion = [1, 1, 11]
    static let appBundleIdentifiers = [
        "com.google.antigravity",
        "com.google.antigravity-ide",
        "com.google.antigravity.ide",
    ]

    private static let inheritedKeys = [
        "USER", "LOGNAME", "TMPDIR", "LANG",
        "SSL_CERT_FILE", "SSL_CERT_DIR", "NODE_EXTRA_CA_CERTS",
        "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY",
        "https_proxy", "http_proxy", "all_proxy", "no_proxy",
    ]

    private struct VersionKey: Hashable {
        let path: String
        let inode: UInt64
        let size: UInt64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
    }

    private static let versionLock = NSLock()
    private static var versionCache: [VersionKey: Result<Void, Failure>] = [:]

    static func interval(after failure: Failure?, repeated: Int = 0, pageVisible: Bool) -> TimeInterval {
        switch failure {
        case nil: return pageVisible ? freshness : backgroundFreshness
        case .unreachable?: return min(settledRetry, retryAfter * Double(1 << min(3, max(0, repeated - 1))))
        case .missing?, .needsSignIn?, .outdated?: return settledRetry
        }
    }

    /// Expires each window without inventing zero usage after a reset. Idle
    /// windows without a scheduled reset expire after their window length (or five hours).
    static func current(_ reading: AgentLimits?, now: Date) -> AgentLimits? {
        guard var reading else { return nil }
        let age = now.timeIntervalSince(reading.observedAt)
        reading.windows.removeAll { window in
            if let resets = window.resetsAt { return resets <= now }
            return age >= max(5 * 3_600, Double(window.minutes ?? 300) * 60)
        }
        return reading.windows.isEmpty ? nil : reading
    }

    static func parseVersion(_ text: String) -> [Int]? {
        // Accept the CLI's bare version or its named banner. A dependency
        // version in an error or diagnostic must never authorize print mode.
        var version = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Antigravity CLI ", "agy "] where version.hasPrefix(prefix) {
            version.removeFirst(prefix.count)
            break
        }
        guard let token = version.split(separator: " ").first else { return nil }
        let release = token.hasPrefix("v") ? token.dropFirst() : token[...]
        let parts = release.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        return [major, minor, patch]
    }

    static func isSupportedVersion(_ version: [Int]) -> Bool {
        guard !version.isEmpty else { return false }
        let count = max(version.count, minimumVersion.count)
        let lhs = version + Array(repeating: 0, count: count - version.count)
        let rhs = minimumVersion + Array(repeating: 0, count: count - minimumVersion.count)
        return !lhs.lexicographicallyPrecedes(rhs)
    }

    static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           searchPath: String? = ProcessInfo.processInfo.environment["PATH"],
                           appURLs: [URL]? = nil) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        func add(_ candidate: URL) {
            let path = candidate.standardizedFileURL.path
            if seen.insert(path).inserted { urls.append(URL(fileURLWithPath: path)) }
        }

        for relative in [".local/bin/agy", ".antigravity/bin/agy", "bin/agy"] {
            add(home.appending(path: relative))
        }
        for fixed in ["/opt/homebrew/bin/agy", "/usr/local/bin/agy"] {
            add(URL(fileURLWithPath: fixed))
        }
        let pathEntries = (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        for folder in pathEntries {
            add(URL(fileURLWithPath: folder, isDirectory: true).appending(path: "agy"))
        }
        let managed = AgentClaudeServer.searchPath(after: "", home: home)
            .split(separator: ":").map(String.init).filter { !$0.isEmpty && $0.hasPrefix("/") }
        for folder in managed {
            add(URL(fileURLWithPath: folder, isDirectory: true).appending(path: "agy"))
        }
        let bundles = appURLs ?? appBundleIdentifiers.compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
        for bundle in bundles {
            add(bundle.appending(path: "Contents/Resources/app/bin/agy"))
            add(bundle.appending(path: "Contents/Resources/bin/agy"))
        }
        return urls
    }

    static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           searchPath: String? = ProcessInfo.processInfo.environment["PATH"],
                           appURLs: [URL]? = nil) -> URL? {
        candidates(home: home, searchPath: searchPath, appURLs: appURLs).first {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    /// Clean minimal environment so parent Antigravity/IDE session overrides
    /// or API keys never leak into the account quota check.
    static func environment(_ inherited: [String: String],
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String: String] {
        var env: [String: String] = [
            "HOME": home.path,
            "PATH": inherited["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "NO_COLOR": "1",
            "TERM": "dumb",
        ]
        for key in inheritedKeys {
            if let value = inherited[key] { env[key] = value }
        }
        return env
    }

    static func limits(_ data: Data, observed: Date) -> AgentLimits? {
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let parsed = limits(json, observed: observed) {
            return parsed
        }
        let lines = data.split(separator: 0x0A)
        for slice in lines.reversed() {
            guard slice.first(where: { ![9, 10, 13, 32].contains($0) }) == 0x7B,
                  let json = (try? JSONSerialization.jsonObject(with: Data(slice))) as? [String: Any] else { continue }
            if let status = json["status"] as? String, status != "SUCCESS" { return nil }
            if let parsed = limits(json, observed: observed) { return parsed }
        }
        return nil
    }

    static func limits(_ json: [String: Any], observed: Date) -> AgentLimits? {
        if let status = json["status"] as? String, status != "SUCCESS" { return nil }
        guard let command = json["command"] as? [String: Any],
              command["name"] as? String == "usage",
              let dataObj = command["data"] as? [String: Any],
              let groups = dataObj["groups"] as? [[String: Any]] else { return nil }
        var windows: [AgentLimitWindow] = []
        var seenIDs = Set<String>()
        for group in groups {
            if group["disabled"] as? Bool == true || group["enabled"] as? Bool == false { continue }
            let groupName = (group["name"] as? String ?? group["id"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let (scope, groupSlug) = groupIdentity(groupName)
            let buckets = group["buckets"] as? [[String: Any]] ?? []
            for bucket in buckets {
                if bucket["disabled"] as? Bool == true || bucket["enabled"] as? Bool == false { continue }
                let windowName = (bucket["window"] as? String ?? bucket["kind"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard let (kind, minutes, code) = parseWindow(windowName) else { continue }
                let used: Double
                if let remaining = finiteNumber(bucket["remaining_fraction"]) {
                    used = min(100, max(0, (1.0 - remaining) * 100.0))
                } else if let direct = finiteNumber(bucket["used_percent"]) ?? finiteNumber(bucket["utilization"]) {
                    used = min(100, max(0, direct))
                } else {
                    continue
                }
                let rawReset = bucket["reset_time"] ?? bucket["resets_at"]
                let end: Date?
                if rawReset == nil || rawReset is NSNull || (rawReset as? String)?.isEmpty == true {
                    end = nil
                } else if let resetText = rawReset as? String,
                          let parsed = AgentTimestamp.parse(resetText), parsed > observed {
                    end = parsed
                } else {
                    continue
                }
                let bucketID = (bucket["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let slug = bucketID.isEmpty ? groupSlug : slugify(bucketID, fallback: groupSlug)
                var id = "antigravity.\(slug).\(code)"
                if !seenIDs.insert(id).inserted {
                    var ordinal = 2
                    while !seenIDs.insert("antigravity.\(slug).\(code).\(ordinal)").inserted { ordinal += 1 }
                    id = "antigravity.\(slug).\(code).\(ordinal)"
                }
                windows.append(AgentLimitWindow(id: id, kind: kind, minutes: minutes,
                                                scope: scope, usedPercent: used, resetsAt: end))
            }
        }
        return windows.isEmpty ? nil : AgentLimits(provider: .antigravity, windows: windows,
                                                   observedAt: observed, source: .account)
    }

    private static func parseWindow(_ raw: String) -> (kind: AgentLimitWindow.Kind, minutes: Int, code: String)? {
        switch raw {
        case "5h", "session", "five_hour":
            return (.session, 300, "5h")
        case "weekly", "7d", "week", "seven_day":
            return (.weekly, 10_080, "wk")
        case "daily", "24h", "1d":
            return (.other, 1_440, "24h")
        default:
            if raw.hasSuffix("h"), let hours = Int(raw.dropLast()), (1...720).contains(hours) {
                if hours == 5 { return (.session, 300, "5h") }
                if hours == 168 { return (.weekly, 10_080, "wk") }
                return (.other, hours * 60, "\(hours)h")
            }
            if raw.hasSuffix("d"), let days = Int(raw.dropLast()), (1...60).contains(days) {
                if days == 7 { return (.weekly, 10_080, "wk") }
                return (.other, days * 1_440, "\(days)d")
            }
            if raw.hasSuffix("m"), let mins = Int(raw.dropLast()), (1...100_800).contains(mins) {
                if mins == 300 { return (.session, 300, "5h") }
                if mins == 10_080 { return (.weekly, 10_080, "wk") }
                return (.other, mins, "\(mins)m")
            }
            return nil
        }
    }

    private static func groupIdentity(_ groupName: String) -> (scope: String?, slug: String) {
        let lower = groupName.lowercased()
        if lower.contains("claude") && lower.contains("gpt") {
            return ("Claude/GPT", "claude-gpt")
        }
        var shortened = groupName
        if shortened.lowercased().hasSuffix(" models") {
            shortened = String(shortened.dropLast(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if shortened.isEmpty || shortened.lowercased() == "gemini" {
            return (nil, "gemini")
        }
        return (shortened, slugify(shortened, fallback: "other"))
    }

    private static func slugify(_ text: String, fallback: String) -> String {
        var slug = ""
        var previousDash = false
        for scalar in text.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                slug.unicodeScalars.append(scalar)
                previousDash = false
            } else if !slug.isEmpty, !previousDash {
                slug.append("-")
                previousDash = true
            }
        }
        if slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? fallback : slug
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    private static func versionKey(for executable: URL) -> VersionKey? {
        var info = stat()
        guard stat(executable.path, &info) == 0 else { return nil }
        return VersionKey(path: executable.path, inode: UInt64(info.st_ino),
                          size: UInt64(max(0, info.st_size)),
                          modifiedSeconds: info.st_mtimespec.tv_sec,
                          modifiedNanoseconds: info.st_mtimespec.tv_nsec)
    }

    /// A cancellable, bounded CLI invocation; pause/stop terminates any child immediately.
    final class Request {
        private let lock = NSLock()
        private var cancelled = false
        private var activeProcess: Process?

        func cancel() {
            let child = lock.withLock { () -> Process? in
                guard !cancelled else { return nil }
                cancelled = true
                return activeProcess
            }
            guard let child, child.isRunning else { return }
            child.terminate()
            let pid = child.processIdentifier
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                if child.isRunning { kill(pid, SIGKILL) }
            }
        }

        private var isCancelled: Bool { lock.withLock { cancelled } }

        func run(_ executable: URL,
                 home: URL = FileManager.default.homeDirectoryForCurrentUser,
                 environment: [String: String] = ProcessInfo.processInfo.environment,
                 timeout: TimeInterval = AgentAntigravityServer.timeout) -> Result<Summary, Failure> {
            guard !isCancelled else { return .failure(.unreachable) }
            let env = AgentAntigravityServer.environment(environment, home: home)
            let deadline = Date().addingTimeInterval(max(0.1, timeout))

            let key = AgentAntigravityServer.versionKey(for: executable)
            let cached = key.flatMap { k in AgentAntigravityServer.versionLock.withLock { AgentAntigravityServer.versionCache[k] } }
            if let cached {
                if case .failure(let failure) = cached { return .failure(failure) }
            } else {
                let probe = execute(executable, arguments: ["--version"], environment: env,
                                    maxStdout: 16 << 10, maxStderr: 16 << 10,
                                    timeout: min(5, max(0.1, deadline.timeIntervalSinceNow)))
                guard !probe.cancelled, !probe.timedOut else { return .failure(.unreachable) }
                let combined = (String(decoding: probe.stdout, as: UTF8.self) + "\n"
                    + String(decoding: probe.stderr, as: UTF8.self))
                if let parsed = AgentAntigravityServer.parseVersion(combined) {
                    if !AgentAntigravityServer.isSupportedVersion(parsed) {
                        if let key {
                            AgentAntigravityServer.versionLock.withLock {
                                AgentAntigravityServer.versionCache[key] = .failure(.outdated)
                            }
                        }
                        return .failure(.outdated)
                    }
                    guard probe.status == 0 else { return .failure(.unreachable) }
                    if let key {
                        AgentAntigravityServer.versionLock.withLock {
                            AgentAntigravityServer.versionCache[key] = .success(())
                        }
                    }
                } else {
                    let lower = combined.lowercased()
                    if Self.hasOutdatedMarker(lower) || lower.contains("--version") {
                        if let key {
                            AgentAntigravityServer.versionLock.withLock {
                                AgentAntigravityServer.versionCache[key] = .failure(.outdated)
                            }
                        }
                        return .failure(.outdated)
                    }
                    return .failure(.unreachable)
                }
            }

            let remaining = deadline.timeIntervalSinceNow
            guard !isCancelled, remaining > 0 else { return .failure(.unreachable) }
            let usage = execute(executable,
                                arguments: ["-p", "/usage", "--output-format", "json", "--print-timeout", "20s"],
                                environment: env, maxStdout: 256 << 10, maxStderr: 256 << 10, timeout: remaining)
            guard !usage.cancelled, !usage.timedOut else { return .failure(.unreachable) }

            if usage.status == 0, let limits = AgentAntigravityServer.limits(usage.stdout, observed: Date()) {
                return .success(Summary(limits: limits))
            }

            let diagnostics = Self.diagnosticText(stdout: usage.stdout, stderr: usage.stderr)
            if Self.hasOutdatedMarker(diagnostics) {
                return .failure(.outdated)
            }
            if Self.hasAuthMarker(diagnostics) {
                return .failure(.needsSignIn)
            }
            if let limits = AgentAntigravityServer.limits(usage.stdout, observed: Date()) {
                return .success(Summary(limits: limits))
            }
            return .failure(.unreachable)
        }

        private static func hasAuthMarker(_ lower: String) -> Bool {
            ["sign in", "signed out", "not logged in", "login",
             "unauthenticated", "auth", "credential", "oauth"].contains { lower.contains($0) }
        }

        private static func hasOutdatedMarker(_ lower: String) -> Bool {
            ["unknown option", "unknown flag", "--output-format", "--print-timeout",
             "unknown command", "unrecognized"].contains { lower.contains($0) }
        }

        private static func diagnosticText(stdout: Data, stderr: Data) -> String {
            var parts: [String] = [String(decoding: stderr, as: UTF8.self)]
            func collect(_ dict: [String: Any]) {
                for key in ["error", "message", "detail", "reason"] {
                    if let text = dict[key] as? String { parts.append(text) }
                    else if let nested = dict[key] as? [String: Any] { collect(nested) }
                }
                if let command = dict["command"] as? [String: Any] { collect(command) }
            }
            if let json = (try? JSONSerialization.jsonObject(with: stdout)) as? [String: Any] {
                collect(json)
            } else {
                for slice in stdout.split(separator: 0x0A) {
                    if let json = (try? JSONSerialization.jsonObject(with: Data(slice))) as? [String: Any] {
                        collect(json)
                    } else {
                        parts.append(String(decoding: slice, as: UTF8.self))
                    }
                }
            }
            return parts.joined(separator: "\n").lowercased()
        }

        private final class BoundedBuffer: @unchecked Sendable {
            private let lock = NSLock()
            private let limit: Int
            private var data = Data()
            init(limit: Int) { self.limit = max(0, limit) }
            func append(_ chunk: Data) {
                lock.lock()
                defer { lock.unlock() }
                let room = max(0, limit - data.count)
                if room > 0 { data.append(chunk.prefix(room)) }
            }
            func value() -> Data { lock.withLock { data } }
        }

        private func execute(_ executable: URL, arguments: [String], environment: [String: String],
                             maxStdout: Int, maxStderr: Int, timeout: TimeInterval)
            -> (status: Int32, stdout: Data, stderr: Data, timedOut: Bool, cancelled: Bool) {
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

            let outBuffer = BoundedBuffer(limit: maxStdout)
            let errBuffer = BoundedBuffer(limit: maxStderr)
            let outDrained = DispatchSemaphore(value: 0)
            let errDrained = DispatchSemaphore(value: 0)

            let outReader = outPipe.fileHandleForReading
            outReader.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    outDrained.signal()
                } else {
                    outBuffer.append(chunk)
                }
            }
            let errReader = errPipe.fileHandleForReading
            errReader.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    errDrained.signal()
                } else {
                    errBuffer.append(chunk)
                }
            }

            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }

            let launched: Bool = lock.withLock {
                guard !cancelled else { return false }
                do {
                    try process.run()
                    activeProcess = process
                    return true
                } catch {
                    return false
                }
            }
            defer {
                lock.withLock { if activeProcess === process { activeProcess = nil } }
            }
            guard launched else {
                outReader.readabilityHandler = nil
                errReader.readabilityHandler = nil
                try? outReader.close()
                try? errReader.close()
                return (-1, Data(), Data(), false, isCancelled)
            }

            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()

            var didFinish = finished.wait(timeout: .now() + max(0, timeout)) == .success
            let timedOut = !didFinish
            if timedOut {
                process.terminate()
                let pid = process.processIdentifier
                didFinish = finished.wait(timeout: .now() + 0.5) == .success
                if !didFinish {
                    kill(pid, SIGKILL)
                    _ = finished.wait(timeout: .now() + 0.5)
                }
            }

            _ = outDrained.wait(timeout: .now() + 0.2)
            _ = errDrained.wait(timeout: .now() + 0.2)
            outReader.readabilityHandler = nil
            errReader.readabilityHandler = nil
            try? outReader.close()
            try? errReader.close()

            let wasCancelled = isCancelled
            return (timedOut ? -1 : process.terminationStatus,
                    outBuffer.value(), errBuffer.value(), timedOut, wasCancelled)
        }
    }
}
