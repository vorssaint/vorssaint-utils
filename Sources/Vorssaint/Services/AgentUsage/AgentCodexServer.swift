// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// A banked reset: one renewal of the Codex session and weekly limits at
/// once, kept on the account until it is used or expires.
struct AgentCodexReset: Equatable, Identifiable {
    let id: String
    let expiresAt: Date?
}

/// The account's banked resets, as Codex reads them.
struct AgentCodexResetSummary: Equatable {
    let available: Int
    /// Soonest to expire first. The account can list fewer than it has, or
    /// none when only the count is known.
    let resets: [AgentCodexReset]
    /// The limits read in the same request, newer than any log.
    let limits: AgentLimits?
    let checkedAt: Date

    var nextExpiry: Date? { resets.lazy.compactMap(\.expiresAt).min() }
}

/// Codex's own server, started for one short conversation at a time, answers
/// for the account. It signs in with Codex's credentials, which Vorssaint
/// never reads, and hears only the questions asked here.
enum AgentCodexServer {
    enum Failure: Error, Equatable {
        /// Neither the Codex app nor its command-line tool is on this Mac.
        case missing
        /// Codex is signed out, or signed in with a key or a cloud account,
        /// which have no plan and so no resets.
        case needsSignIn
        /// A Codex from before resets could be read from outside it.
        case outdated
        /// No answer that says what happened: it stopped, ran out of time or
        /// answered in words this version does not know.
        case unreachable
        /// It answered with an error of its own. For a use, that includes its
        /// request to the account timing out, which may still have spent one.
        case refused
    }

    /// What using a reset did, in the server's words.
    enum Outcome: String, Equatable {
        case reset, nothingToReset, noCredit, alreadyRedeemed
    }

    /// The maker's desktop apps, which carry the tool inside and keep it current.
    static let appIdentifiers = ["com.openai.codex", "com.openai.chat"]
    static let checkTimeout: TimeInterval = 20
    static let redeemTimeout: TimeInterval = 30

    /// Where the tool can be: inside the desktop app, in its current layout
    /// and its earlier one, then where the official installer, Homebrew and
    /// npm put it, then along a shell's PATH when one was asked for.
    static func candidates(apps: [URL], home: URL, searchPath: String? = nil) -> [URL] {
        let bundled = apps.flatMap { app in
            ["Contents/Resources/codex-cli/bin/codex", "Contents/Resources/codex"].map {
                app.appending(path: $0, directoryHint: .notDirectory)
            }
        }
        let folders = [home.appending(path: ".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
            + (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return bundled + folders.map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "codex") }
    }

    static func executable(apps: [URL], home: URL, searchPath: String? = nil) -> URL? {
        candidates(apps: apps, home: home, searchPath: searchPath).first { url in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    /// An app opened from Finder has only the system folders on its PATH,
    /// and a tool installed with npm needs `node`, which sits beside it or
    /// on the shell's PATH.
    static func environment(for executable: URL, searchPath: String?,
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        let folders = [executable.deletingLastPathComponent().path]
            + (searchPath.map { [$0] } ?? ["/opt/homebrew/bin", "/usr/local/bin"])
            + [base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
        environment["PATH"] = folders.joined(separator: ":")
        return environment
    }

    // MARK: Conversations

    /// The account's resets and limits. An account without a plan has no
    /// resets, so its limits are not asked for either.
    static func check(_ executable: URL, environment: [String: String]) -> Result<AgentCodexResetSummary, Failure> {
        guard let conversation = AgentCodexConversation(executable, environment: environment,
                                                        timeout: checkTimeout) else { return .failure(.unreachable) }
        defer { conversation.end() }
        return conversation.start()
            .flatMap { _ in conversation.ask("account/read") }
            .flatMap { account -> Result<Void, Failure> in
                if let failure = signInFailure(account) { return .failure(failure) }
                return .success(())
            }
            .flatMap { _ in conversation.summary() }
    }

    /// Uses one reset, the one `credit` names or else the account's next,
    /// and reads the account again, which a lost reply may have changed too.
    /// The same `key` for a second try of one use never spends two.
    static func redeem(_ executable: URL, environment: [String: String], credit: String?,
                       key: String) -> (outcome: Result<Outcome, Failure>, summary: AgentCodexResetSummary?) {
        guard let conversation = AgentCodexConversation(executable, environment: environment,
                                                        timeout: redeemTimeout) else { return (.failure(.unreachable), nil) }
        defer { conversation.end() }
        var params: [String: Any] = ["idempotencyKey": key]
        if let credit { params["creditId"] = credit }
        let outcome = conversation.start()
            .flatMap { _ in conversation.ask("account/rateLimitResetCredit/consume", params) }
            .flatMap { result -> Result<Outcome, Failure> in
                guard let outcome = Self.outcome(result) else { return .failure(.unreachable) }
                return .success(outcome)
            }
        return (outcome, try? conversation.summary().get())
    }

    // MARK: Answers

    /// Nil while the account has a plan.
    static func signInFailure(_ result: [String: Any]) -> Failure? {
        (result["account"] as? [String: Any])?["type"] as? String == "chatgpt" ? nil : .needsSignIn
    }

    /// Nil for a Codex that does not report resets at all; one that reports
    /// none leaves the count at zero.
    static func summary(_ result: [String: Any], now: Date) -> AgentCodexResetSummary? {
        guard result.keys.contains("rateLimitResetCredits") else { return nil }
        let credits = result["rateLimitResetCredits"] as? [String: Any]
        let listed = (credits?["credits"] as? [[String: Any]] ?? []).compactMap { credit -> AgentCodexReset? in
            guard let id = credit["id"] as? String, !id.isEmpty,
                  (credit["status"] as? String ?? "available") == "available" else { return nil }
            let expires = AgentLogParser.seconds(credit["expiresAt"])
            if let expires, expires <= now { return nil }
            return AgentCodexReset(id: id, expiresAt: expires)
        }
        let resets = listed.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        let count = max(resets.count, AgentLogParser.int(credits?["availableCount"]))
        return AgentCodexResetSummary(available: count, resets: resets, limits: limits(result, observed: now),
                                      checkedAt: now)
    }

    /// The main allowance's windows, as a log names them.
    static func limits(_ result: [String: Any], observed: Date) -> AgentLimits? {
        var snapshot = (result["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any]
        if snapshot == nil, let single = result["rateLimits"] as? [String: Any],
           AgentLogParser.isMainBucket(["limit_id": single["limitId"] as? String ?? ""]) {
            snapshot = single
        }
        guard let snapshot,
              let windows = AgentLogParser.codexWindows(snapshot, observed: observed,
                                                        keys: ("usedPercent", "windowDurationMins", "resetsAt",
                                                               "individualLimit", "remainingPercent")),
              !windows.isEmpty else { return nil }
        return AgentLimits(provider: .codex, windows: windows, observedAt: observed, source: .account)
    }

    static func outcome(_ result: [String: Any]) -> Outcome? {
        (result["outcome"] as? String).flatMap(Outcome.init(rawValue:))
    }

    /// The server words its refusals: a question it does not know is an
    /// unknown variant to it, and a signed-out account needs authentication.
    static func failure(_ error: Any?) -> Failure {
        let error = error as? [String: Any]
        let message = (error?["message"] as? String ?? "").lowercased()
        if (error?["code"] as? NSNumber)?.intValue == -32601 || message.contains("unknown variant")
            || message.contains("method not found") { return .outdated }
        if message.contains("authentication") || message.contains("not logged in") { return .needsSignIn }
        return .refused
    }
}

/// One conversation with Codex's server over its standard input and output,
/// a JSON message a line. Every answer waits on one deadline, so a server
/// that stalls costs the conversation's time at most. Blocks its caller:
/// run it on a work queue of its own.
final class AgentCodexConversation {
    /// Far above any answer here; a server that writes more is not one.
    private static let maximumBuffer = 4 << 20

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let deadline: DispatchTime
    private let arrived = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var buffer = Data()
    private var closed = false
    private var lastID = 0

    init?(_ executable: URL, environment: [String: String], timeout: TimeInterval) {
        deadline = .now() + timeout
        process.executableURL = executable
        // As it starts, Codex's server brings its plugins up to date, which
        // runs Git against each plugin marketplace added to Codex. Nothing
        // asked here needs a plugin, so they stay off for this server.
        process.arguments = ["-c", "features.plugins=false", "app-server"]
        process.environment = environment
        // Nothing here needs a folder; the root keeps a project's files, or
        // a protected folder the app was opened from, out of the server's way.
        process.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // A server that exits early fails a write instead of ending the app.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return nil }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil }
            self?.receive(chunk)
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
    }

    /// Introduces the app, as every conversation must begin.
    func start() -> Result<Void, AgentCodexServer.Failure> {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let client: [String: Any] = ["name": "vorssaint", "title": "Vorssaint", "version": version]
        return ask("initialize", ["clientInfo": client, "capabilities": NSNull()])
            .flatMap { _ -> Result<Void, AgentCodexServer.Failure> in
                send(["method": "initialized"]) ? .success(()) : .failure(.unreachable)
            }
    }

    func ask(_ method: String, _ params: [String: Any] = [:]) -> Result<[String: Any], AgentCodexServer.Failure> {
        lastID += 1
        let id = lastID
        guard send(["id": id, "method": method, "params": params]) else { return .failure(.unreachable) }
        while let message = next() {
            // Notifications and the server's own requests are not the answer.
            guard message["method"] == nil, (message["id"] as? NSNumber)?.intValue == id else { continue }
            if let result = message["result"] as? [String: Any] { return .success(result) }
            return .failure(AgentCodexServer.failure(message["error"]))
        }
        return .failure(.unreachable)
    }

    func summary(now: Date = Date()) -> Result<AgentCodexResetSummary, AgentCodexServer.Failure> {
        ask("account/rateLimits/read").flatMap { result -> Result<AgentCodexResetSummary, AgentCodexServer.Failure> in
            guard let summary = AgentCodexServer.summary(result, now: now) else { return .failure(.outdated) }
            return .success(summary)
        }
    }

    /// Closing its input ends the server; one that lingers is stopped.
    func end() {
        try? input.fileHandleForWriting.close()
        let child = process
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            guard child.isRunning else { return }
            child.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }

    private func send(_ message: [String: Any]) -> Bool {
        guard JSONSerialization.isValidJSONObject(message),
              var line = try? JSONSerialization.data(withJSONObject: message, options: .withoutEscapingSlashes)
        else { return false }
        line.append(0x0A)
        do {
            try input.fileHandleForWriting.write(contentsOf: line)
            return true
        } catch {
            return false
        }
    }

    private func receive(_ chunk: Data) {
        lock.withLock {
            if chunk.isEmpty || buffer.count + chunk.count > Self.maximumBuffer { closed = true }
            else { buffer.append(chunk) }
        }
        arrived.signal()
    }

    /// The next message, or nil once the server has ended or time is up.
    private func next() -> [String: Any]? {
        while true {
            let (line, ended): (Data?, Bool) = lock.withLock {
                guard let newline = buffer.firstIndex(of: 0x0A) else { return (nil, closed) }
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                return (line, false)
            }
            if let line {
                if let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { return message }
                continue
            }
            if ended || arrived.wait(timeout: deadline) == .timedOut { return nil }
        }
    }
}
