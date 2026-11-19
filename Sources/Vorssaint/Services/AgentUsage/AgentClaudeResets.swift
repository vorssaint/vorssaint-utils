// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One grant of banked Claude resets: a few renewals of the limits it
/// clears, kept on the account until they are used or the grant ends.
struct AgentClaudeResetGrant: Equatable, Identifiable {
    let id: String
    let left: Int
    let endsAt: Date?
    let paused: Bool
    /// The account allows using it now: some plans keep a reset for when a
    /// limit is reached.
    let usableNow: Bool
}

/// The account's banked resets, as claude.ai reports them to Claude Code.
struct AgentClaudeResetSummary: Equatable {
    let eligible: Bool
    /// Soonest to end first, only those with resets left.
    let grants: [AgentClaudeResetGrant]
    /// The grant the account would use next.
    let nextGrant: String?
    /// The limits read in the same request.
    let limits: AgentLimits?
    let checkedAt: Date

    var available: Int { grants.reduce(0) { $0 + $1.left } }
    var nextExpiry: Date? { grants.lazy.compactMap(\.endsAt).min() }
    /// The grant a use spends, when the account allows one now.
    var usable: AgentClaudeResetGrant? {
        grants.first { $0.id == nextGrant && $0.usableNow && !$0.paused && $0.left > 0 }
    }
}

/// Reads and uses Claude's banked resets through claude.ai, the way Claude
/// Code does. Claude Code exposes neither to other apps, so this signs in
/// with the access token Claude Code keeps in the login keychain. The token
/// is read through macOS's `security` tool, which Claude Code's keychain item
/// already trusts, held only for the request and never stored or refreshed
/// here: an expired one is renewed by starting Claude Code itself.
enum AgentClaudeResets {
    enum Failure: Error, Equatable {
        /// Claude Code is not on this Mac, or has never signed in here.
        case missing
        /// Claude Code is signed out, or with a key or a sign-in that cannot
        /// read the plan's usage.
        case needsSignIn
        /// claude.ai asked to wait before asking again.
        case busy(until: Date)
        /// No answer this version can read.
        case unreachable
    }

    /// What using a reset did, in claude.ai's words.
    enum Outcome: String, Equatable {
        case reset
        case alreadyUsed = "already_used"
        case notLimited = "not_limited"
        case cooldown, ineligible, unavailable
    }

    static let host = URL(string: "https://api.anthropic.com")!
    static let keychainService = "Claude Code-credentials"
    static let program = "cedar_ember"
    static let checkTimeout: TimeInterval = 20
    static let redeemTimeout: TimeInterval = 30

    // MARK: Answers

    /// Nil for an answer without the resets block, which an account outside
    /// the program, or an older server, leaves out.
    static func summary(_ result: [String: Any], now: Date) -> AgentClaudeResetSummary? {
        guard let block = result["cedar_ember"] as? [String: Any], let eligible = block["eligible"] as? Bool else { return nil }
        let grants = (block["grants"] as? [[String: Any]] ?? []).compactMap { grant -> AgentClaudeResetGrant? in
            guard let id = grant["id"] as? String, valid(grant: id),
                  let left = (grant["resets_left"] as? NSNumber)?.intValue, left > 0 else { return nil }
            let ends = (grant["ends_at"] as? String).flatMap(AgentTimestamp.parse)
            if let ends, ends <= now { return nil }
            return AgentClaudeResetGrant(id: id, left: left, endsAt: ends, paused: grant["paused"] as? Bool ?? false,
                                         usableNow: grant["usable_now"] as? Bool ?? false)
        }.sorted { ($0.endsAt ?? .distantFuture) < ($1.endsAt ?? .distantFuture) }
        let next = block["next_grant_id"] as? String
        return AgentClaudeResetSummary(eligible: eligible, grants: eligible ? grants : [],
                                       nextGrant: grants.contains { $0.id == next } ? next : nil,
                                       limits: AgentClaudeServer.limits(["rate_limits_available": true, "rate_limits": result],
                                                                        observed: now),
                                       checkedAt: now)
    }

    static func outcome(_ result: [String: Any]) -> Outcome? {
        (result["result"] as? String).flatMap(Outcome.init(rawValue:))
    }

    /// claude.ai names grants and requests with these characters only.
    static func valid(grant: String) -> Bool { grant.range(of: #"^[a-z0-9_-]{1,40}$"#, options: .regularExpression) != nil }
    static func valid(request: String) -> Bool { request.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil }

    /// A refusal that only waiting fixes, for as long as the server asks:
    /// two minutes at least, half an hour at most.
    static func busyUntil(retryAfter: String?, now: Date) -> Date {
        let seconds = retryAfter.flatMap(TimeInterval.init) ?? 5 * 60
        return now.addingTimeInterval(min(max(seconds, 2 * 60), 30 * 60))
    }

    // MARK: Sign-in

    struct Credentials: Equatable {
        let token: String
        let expiresAt: Date?
        /// The plan's usage needs the profile scope, which a token made for
        /// inference alone lacks.
        let readsUsage: Bool

        func current(at now: Date) -> Bool { (expiresAt ?? .distantFuture) > now.addingTimeInterval(60) }
    }

    static func credentials(_ data: Data) -> Credentials? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expires = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        let scopes = oauth["scopes"] as? [String]
        return Credentials(token: token, expiresAt: expires, readsUsage: scopes?.contains("user:profile") ?? true)
    }

    /// The keychain item Claude Code writes, then the file it uses where no
    /// keychain is available.
    static func storedCredentials(home: URL) -> Credentials? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-a", NSUserName(), "-w"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0, let found = credentials(data) { return found }
        }
        return (try? Data(contentsOf: home.appending(path: ".claude/.credentials.json"))).flatMap(credentials)
    }

    /// The installed Claude Code's version, which claude.ai reads from the
    /// user agent to tell which resets this Claude Code can use.
    static func version(of executable: URL, environment: [String: String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: timer)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        return version(String(decoding: data, as: UTF8.self))
    }

    static func version(_ text: String) -> String? {
        text.split(whereSeparator: \.isWhitespace).first.map(String.init)
            .flatMap { $0.range(of: #"^\d+(\.\d+){1,3}$"#, options: .regularExpression) != nil ? $0 : nil }
    }

    /// Claude Code's own form, naming Vorssaint as the app that asks. claude.ai
    /// offers resets only to the command-line surface, so that is the one named.
    static func userAgent(version: String) -> String {
        "claude-cli/\(version) (external, cli, client-app/Vorssaint)"
    }

    // MARK: Requests

    static func check(_ credentials: Credentials, version: String,
                      now: @escaping () -> Date = Date.init) -> Result<AgentClaudeResetSummary, Failure> {
        var request = URLRequest(url: host.appending(path: "api/oauth/usage")
            .appending(queryItems: [URLQueryItem(name: "cedar_ember", value: "1"), URLQueryItem(name: "skip_spend", value: "1")]),
                                 timeoutInterval: checkTimeout)
        authorize(&request, credentials, version: version)
        return send(request).flatMap { json in
            // An account outside the program reads as one without resets.
            .success(summary(json, now: now())
                     ?? AgentClaudeResetSummary(eligible: false, grants: [], nextGrant: nil,
                                                limits: AgentClaudeServer.limits(["rate_limits_available": true,
                                                                                  "rate_limits": json], observed: now()),
                                                checkedAt: now()))
        }
    }

    /// Uses one reset of `grant`. The same `key` for a second try of one use
    /// never spends two.
    static func redeem(_ credentials: Credentials, version: String, organization: String, grant: String,
                       key: String) -> Result<Outcome, Failure> {
        guard valid(grant: grant), valid(request: key),
              organization.range(of: #"^[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil else { return .failure(.unreachable) }
        var request = URLRequest(url: host.appending(path: "api/organizations/\(organization)/reset_rate_limits"),
                                 timeoutInterval: redeemTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["program": program, "grant_id": grant, "request_id": key])
        authorize(&request, credentials, version: version)
        return send(request).flatMap { json in
            guard let outcome = outcome(json) else { return .failure(.unreachable) }
            return .success(outcome)
        }
    }

    private static func authorize(_ request: inout URLRequest, _ credentials: Credentials, version: String) {
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent(version: version), forHTTPHeaderField: "User-Agent")
    }

    /// Blocks its caller: run it on a work queue of its own.
    private static func send(_ request: URLRequest) -> Result<[String: Any], Failure> {
        let call = AgentClaudeCall()
        call.run(request)
        guard let response = call.response else { return .failure(.unreachable) }
        switch response.statusCode {
        case 200..<300:
            guard let json = (try? JSONSerialization.jsonObject(with: call.data)) as? [String: Any] else { return .failure(.unreachable) }
            return .success(json)
        case 401, 403: return .failure(.needsSignIn)
        case 429: return .failure(.busy(until: busyUntil(retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
                                                         now: Date())))
        default: return .failure(.unreachable)
        }
    }
}

/// One request that keeps nothing: no cookies, no cache, and no redirect,
/// which could carry the sign-in somewhere else.
private final class AgentClaudeCall: NSObject, URLSessionDataDelegate {
    private static let limit = 1 << 20
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var received = Data()
    private var answer: HTTPURLResponse?

    var data: Data { lock.withLock { received } }
    var response: HTTPURLResponse? { lock.withLock { answer } }

    func run(_ request: URLRequest) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session.dataTask(with: request).resume()
        done.wait()
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.withLock { answer = response as? HTTPURLResponse }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let over = lock.withLock { () -> Bool in
            received.append(chunk)
            return received.count > Self.limit
        }
        if over { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil { lock.withLock { answer = nil } }
        done.signal()
    }
}
