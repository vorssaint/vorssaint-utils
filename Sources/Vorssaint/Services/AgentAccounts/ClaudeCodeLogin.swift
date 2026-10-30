// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Where Claude Code keeps its login and how to read what is inside. The
/// credential and the identity stay `Data` as Claude Code wrote them; the
/// functions here read the few fields a swap needs and change nothing else.
enum ClaudeCodeLogin {
    /// The Keychain item Claude Code signs in with.
    static let service = "Claude Code-credentials"
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    /// Claude Code's own public client id, which its refresh tokens belong to.
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    /// A token this close to its end is refreshed first, as Claude Code does.
    static let expiryMargin: TimeInterval = 5 * 60
    /// Keys of the credential that belong to this Mac, not to an account: a
    /// swap keeps the live values, or every MCP server would sign out with it.
    static let machineKeys = ["mcpOAuth", "mcpOAuthClientConfig", "mcpXaaIdp", "mcpXaaIdpConfig", "pluginSecrets"]
    static let identityKey = "oauthAccount"

    /// The Keychain account Claude Code files its item under.
    static var keychainAccount: String {
        let user = ProcessInfo.processInfo.environment["USER"] ?? ""
        return user.isEmpty ? NSUserName() : user
    }

    /// `~/.claude.json`, or the file older versions used when it is there.
    static func configURL(home: URL) -> URL {
        let legacy = home.appending(path: ".claude/.config.json", directoryHint: .notDirectory)
        return FileManager.default.fileExists(atPath: legacy.path)
            ? legacy : home.appending(path: ".claude.json", directoryHint: .notDirectory)
    }

    /// Exists only where Claude Code could not use the Keychain. Rewritten
    /// after a swap when it is there, never created.
    static func credentialsFileURL(home: URL) -> URL {
        home.appending(path: ".claude/.credentials.json", directoryHint: .notDirectory)
    }

    static func sessionsURL(home: URL) -> URL {
        home.appending(path: ".claude/sessions", directoryHint: .isDirectory)
    }

    // MARK: Credential

    struct Tokens: Equatable {
        let access: String
        /// Empty for a login that cannot be refreshed.
        let refresh: String
        let expiresAt: Date?
    }

    /// Nil for a credential without an access token, which is no login.
    static func tokens(_ credential: Data) -> Tokens? {
        guard let oauth = object(credential)?["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String, !access.isEmpty else { return nil }
        return Tokens(access: access, refresh: oauth["refreshToken"] as? String ?? "",
                      expiresAt: AgentLogParser.seconds(oauth["expiresAt"]))
    }

    static func isExpired(_ credential: Data, now: Date) -> Bool {
        guard let expires = tokens(credential)?.expiresAt else { return false }
        return now >= expires.addingTimeInterval(-expiryMargin)
    }

    /// `target` with this Mac's own keys taken from `live`; a key the live
    /// credential lacks is removed.
    static func merged(_ target: Data, machineKeysFrom live: Data?) -> Data? {
        guard var result = object(target) else { return nil }
        let current = live.flatMap(object) ?? [:]
        for key in machineKeys { result[key] = current[key] }
        return serialized(result)
    }

    /// `credential` with the tokens a refresh answered. The refresh token is
    /// replaced only when a new one came: the old one is spent then.
    static func refreshed(_ credential: Data, with answer: Data, now: Date) -> Data? {
        guard var root = object(credential), var oauth = root["claudeAiOauth"] as? [String: Any],
              let answer = object(answer), let access = answer["access_token"] as? String, !access.isEmpty
        else { return nil }
        oauth["accessToken"] = access
        if let refresh = answer["refresh_token"] as? String, !refresh.isEmpty { oauth["refreshToken"] = refresh }
        if let seconds = (answer["expires_in"] as? NSNumber)?.doubleValue, seconds.isFinite {
            oauth["expiresAt"] = Int64((now.timeIntervalSince1970 + seconds) * 1_000)
        }
        if let scope = answer["scope"] as? String, !scope.isEmpty {
            oauth["scopes"] = scope.split(separator: " ").map(String.init)
        }
        root["claudeAiOauth"] = oauth
        return serialized(root)
    }

    // MARK: Identity

    struct Identity: Equatable {
        let id: AgentAccount.ID
        let email: String
        let organization: String
    }

    /// Reads an `oauthAccount` object. An account can sit in several
    /// organizations, each with a login of its own, so both name the login.
    static func identity(_ data: Data) -> Identity? {
        guard let json = object(data), let account = json["accountUuid"] as? String, !account.isEmpty else { return nil }
        return Identity(id: "\(account)/\(json["organizationUuid"] as? String ?? "")",
                        email: json["emailAddress"] as? String ?? "",
                        organization: json["organizationName"] as? String ?? "")
    }

    /// The `oauthAccount` object of a config file, byte for byte.
    static func liveIdentity(in config: Data) -> Data? {
        let bytes = [UInt8](config)
        guard let value = member(identityKey, in: bytes)?.value else { return nil }
        return Data(bytes[value])
    }

    /// `config` with its `oauthAccount` replaced by `identity` and every
    /// other byte as it was. The file holds everything Claude Code knows
    /// about this Mac, megabytes of it for some: writing it out again from a
    /// parsed copy would reorder it and round its numbers. Nil when either is
    /// not a JSON object.
    static func replacingIdentity(in config: Data, with identity: Data) -> Data? {
        let bytes = [UInt8](config)
        guard let wanted = object(identity), object(config) != nil, let found = member(identityKey, in: bytes) else { return nil }
        var result = Data()
        if let value = found.value {
            result.append(contentsOf: bytes[..<value.lowerBound])
            result.append(identity)
            result.append(contentsOf: bytes[value.upperBound...])
        } else {
            result.append(contentsOf: bytes[..<found.end])
            result.append(Data("\(found.isEmpty ? "" : ",")\"\(identityKey)\":".utf8))
            result.append(identity)
            result.append(contentsOf: bytes[found.end...])
        }
        // What is written must read back as the object asked for.
        guard let written = object(result)?[identityKey] as? NSDictionary, written.isEqual(wanted) else { return nil }
        return result
    }

    /// Where a top-level member's value sits in a JSON object's text. `value`
    /// is nil when the object has no such key; `end` is then where a new
    /// member goes, right after the last one. Nil when the text is not an
    /// object this can walk.
    private static func member(_ key: String, in bytes: [UInt8]) -> (value: Range<Int>?, end: Int, isEmpty: Bool)? {
        let quote: UInt8 = 0x22, space: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        var index = 0
        func skipSpace() { while index < bytes.count, space.contains(bytes[index]) { index += 1 } }
        /// Leaves `index` after the closing quote and returns what is between.
        func string() -> Range<Int>? {
            guard index < bytes.count, bytes[index] == quote else { return nil }
            index += 1
            let start = index
            while index < bytes.count {
                if bytes[index] == 0x5C { index += 2; continue }
                if bytes[index] == quote { index += 1; return start..<(index - 1) }
                index += 1
            }
            return nil
        }
        func value() -> Bool {
            guard index < bytes.count else { return false }
            switch bytes[index] {
            case quote:
                return string() != nil
            case 0x7B, 0x5B:
                var depth = 0
                while index < bytes.count {
                    switch bytes[index] {
                    case quote:
                        guard string() != nil else { return false }
                        continue
                    case 0x7B, 0x5B: depth += 1
                    case 0x7D, 0x5D: depth -= 1
                    default: break
                    }
                    index += 1
                    if depth == 0 { return true }
                }
                return false
            default:
                let start = index
                while index < bytes.count, !space.contains(bytes[index]), ![0x2C, 0x7D, 0x5D].contains(bytes[index]) {
                    index += 1
                }
                return index > start
            }
        }

        skipSpace()
        guard index < bytes.count, bytes[index] == 0x7B else { return nil }
        index += 1
        var end: Int?
        while true {
            skipSpace()
            guard index < bytes.count else { return nil }
            if bytes[index] == 0x7D { return (nil, end ?? index, end == nil) }
            guard let name = string() else { return nil }
            skipSpace()
            guard index < bytes.count, bytes[index] == 0x3A else { return nil }
            index += 1
            skipSpace()
            let start = index
            guard value() else { return nil }
            if bytes[name].elementsEqual(key.utf8) { return (start..<index, index, false) }
            end = index
            skipSpace()
            if index < bytes.count, bytes[index] == 0x2C { index += 1 }
        }
    }

    // MARK: Usage

    /// The answer of the usage endpoint as limit windows: the session, the
    /// week, and a week of its own for each model that has one. Nil when the
    /// answer is not the object expected or names no window: an answer in a
    /// shape not known here must not read as a login nobody has used.
    static func limits(usage data: Data, now: Date) -> AgentLimits? {
        guard let json = object(data) else { return nil }
        var windows: [AgentLimitWindow] = []
        func add(_ value: Any?, id: String, kind: AgentLimitWindow.Kind, minutes: Int, scope: String?, percent: String) {
            guard let window = value as? [String: Any], let used = (window[percent] as? NSNumber)?.doubleValue,
                  used.isFinite else { return }
            windows.append(AgentLimitWindow(id: id, kind: kind, minutes: minutes, scope: scope,
                                            usedPercent: min(100, max(0, used)),
                                            resetsAt: AgentLogParser.timestamp(window["resets_at"])))
        }
        // The ids are the ones the Claude app's readings carry.
        add(json["five_hour"], id: "claude.fh", kind: .session, minutes: 300, scope: nil, percent: "utilization")
        add(json["seven_day"], id: "claude.sd", kind: .weekly, minutes: 10_080, scope: nil, percent: "utilization")
        for limit in json["limits"] as? [[String: Any]] ?? [] {
            guard let model = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String,
                  !model.isEmpty else { continue }
            add(limit, id: "claude.sd.\(model.lowercased())", kind: .weekly, minutes: 10_080, scope: model, percent: "percent")
        }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .claude, windows: windows, observedAt: now, source: .account)
    }

    // MARK: JSON

    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func serialized(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }
}

/// Claude Code's lock folders. It guards its login and its config file the
/// way npm's `proper-lockfile` does: making a folder is taking the lock, the
/// holder touches it while it works, and a folder nobody touched for a while
/// was left behind by a process that died and may be taken over.
final class ClaudeLocks {
    struct Lock {
        let url: URL
        /// Untouched for this long, the lock belongs to nobody.
        let stale: TimeInterval
    }

    /// Guards a refresh of the live login's tokens.
    static func refresh(home: URL) -> Lock {
        Lock(url: home.appending(path: ".claude/.oauth_refresh.lock", directoryHint: .isDirectory), stale: 60)
    }

    /// Every lock a write to the live login or the config file takes, in the
    /// order Claude Code takes them; another order could wait on it forever.
    static func all(home: URL) -> [Lock] {
        [refresh(home: home),
         Lock(url: home.appending(path: ".claude.lock", directoryHint: .isDirectory), stale: 60),
         Lock(url: home.appending(path: ".claude.json.lock", directoryHint: .isDirectory), stale: 10)]
    }

    static let timeout: TimeInterval = 9
    private static let touchInterval: TimeInterval = 3

    private let guardLock = NSLock()
    private var held: [String] = []
    private var keeper: DispatchSourceTimer?

    /// Takes each lock in turn, waiting `timeout` in all. Throws `.busy` when
    /// one stays taken; the caller releases whatever was taken before it.
    func take(_ locks: [Lock], timeout: TimeInterval = ClaudeLocks.timeout) throws {
        let deadline = Date().addingTimeInterval(timeout)
        for lock in locks {
            let path = lock.url.path
            while mkdir(path, 0o755) != 0 {
                guard errno == EEXIST else { throw AgentLoginError.unreadable("lock: \(String(cString: strerror(errno)))") }
                var info = stat()
                // Gone again already: try at once.
                guard stat(path, &info) == 0 else { continue }
                let touched = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
                if Date().timeIntervalSince(touched) > lock.stale, rmdir(path) == 0 { continue }
                let left = deadline.timeIntervalSinceNow
                guard left > 0 else { throw AgentLoginError.busy }
                Thread.sleep(forTimeInterval: min(left, .random(in: 0.25...0.5)))
            }
            guardLock.withLock { held.append(path) }
            keepFresh()
        }
    }

    func release() {
        let paths: [String] = guardLock.withLock {
            keeper?.cancel()
            keeper = nil
            defer { held = [] }
            return held
        }
        paths.reversed().forEach { rmdir($0) }
    }

    /// A lock held longer than its stale time would be taken from under us.
    private func keepFresh() {
        guardLock.withLock {
            guard keeper == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + Self.touchInterval, repeating: Self.touchInterval)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.guardLock.withLock { self.held }.forEach { utimes($0, nil) }
            }
            timer.resume()
            keeper = timer
        }
    }

    deinit { release() }
}

/// Claude Code's login on this Mac: the Keychain item it signs in with and
/// the `oauthAccount` of its config file, which says whose login that is.
struct ClaudeLoginAdapter: AgentLoginAdapter {
    let provider = AgentProvider.claude
    let home: URL
    /// Holds the live login; the real one is the Keychain through `security`.
    let secrets: ClaudeSecretStore
    var account = ClaudeCodeLogin.keychainAccount
    var transport: AgentHTTPTransport = AgentHTTP.send
    var lockTimeout = ClaudeLocks.timeout
    var now: () -> Date = Date.init
    /// Writes a file of the login; a test makes one fail to see the rest put back.
    var write: (Data, URL) throws -> Void = AgentLoginFiles.write

    func readLive() throws -> AgentLiveLogin? {
        guard let credential = try liveCredential(), ClaudeCodeLogin.tokens(credential) != nil,
              let config = try? Data(contentsOf: ClaudeCodeLogin.configURL(home: home)),
              let identity = ClaudeCodeLogin.liveIdentity(in: config),
              let who = ClaudeCodeLogin.identity(identity) else { return nil }
        return AgentLiveLogin(id: who.id, provider: .claude, email: who.email, organization: who.organization,
                              identity: identity, credential: credential)
    }

    func withLocks<T>(_ body: () throws -> T) throws -> T {
        let locks = ClaudeLocks()
        defer { locks.release() }
        try locks.take(ClaudeLocks.all(home: home), timeout: lockTimeout)
        return try body()
    }

    func activate(_ credential: Data, identity: Data) throws {
        let configURL = ClaudeCodeLogin.configURL(home: home)
        let fileURL = ClaudeCodeLogin.credentialsFileURL(home: home)
        let before = try liveCredential()
        // Everything is worked out before the first write, so a file that
        // cannot be read stops the swap with nothing changed.
        guard let config = try? Data(contentsOf: configURL),
              let nextConfig = ClaudeCodeLogin.replacingIdentity(in: config, with: identity) else {
            throw AgentLoginError.unreadable("\(configURL.lastPathComponent) is not a JSON object")
        }
        guard let next = ClaudeCodeLogin.merged(credential, machineKeysFrom: before),
              ClaudeCodeLogin.tokens(next) != nil else {
            throw AgentLoginError.unreadable("the saved login is not a Claude Code credential")
        }
        let fileBefore = try? Data(contentsOf: fileURL)
        do {
            try writeLive(next)
            try write(nextConfig, configURL)
        } catch {
            // Half a swap is a login whose tokens and name disagree.
            if let before { try? writeLive(before) }
            if let fileBefore { try? write(fileBefore, fileURL) }
            try? write(config, configURL)
            throw error
        }
    }

    func fetchUsage(_ account: AgentAccount, credential: Data,
                    isActive: Bool) -> (limits: Result<AgentLimits, AgentUsageFailure>, rotated: Data?) {
        var rotated: Data?
        do {
            return (.success(try usage(account, credential: credential, isActive: isActive, rotated: &rotated)), rotated)
        } catch let failure as AgentUsageFailure {
            return (.failure(failure), rotated)
        } catch {
            return (.failure(.unavailable("\(error)")), rotated)
        }
    }

    func runningSessions() -> Int {
        AgentSessionRegistry.read([ClaudeCodeLogin.sessionsURL(home: home)]).running.count
    }

    // MARK: Live login

    private func liveCredential() throws -> Data? {
        do {
            return try secrets.read(service: ClaudeCodeLogin.service, account: account).map { Data($0.utf8) }
        } catch {
            throw AgentLoginError.unreadable("\(error)")
        }
    }

    /// The Keychain item, then the file beside it when Claude Code keeps
    /// one: running sessions watch that file to load a login again.
    private func writeLive(_ credential: Data) throws {
        guard let text = String(data: credential, encoding: .utf8) else {
            throw AgentLoginError.unreadable("the credential is not text")
        }
        try secrets.write(text, service: ClaudeCodeLogin.service, account: account)
        let fileURL = ClaudeCodeLogin.credentialsFileURL(home: home)
        if FileManager.default.fileExists(atPath: fileURL.path) { try write(credential, fileURL) }
    }

    // MARK: Usage

    /// `rotated` is set as soon as new tokens exist, so a failure after a
    /// refresh still hands them back: the old ones are spent by then.
    private func usage(_ account: AgentAccount, credential: Data, isActive: Bool,
                       rotated: inout Data?) throws -> AgentLimits {
        var current = credential
        // The live login may be someone else's by now; only its own tokens
        // are taken from it.
        let live = isActive ? (try? readLive()) : nil
        let active = live?.id == account.id
        if let live, active, live.credential != credential {
            current = live.credential
            rotated = current
        }
        if ClaudeCodeLogin.isExpired(current, now: now()) {
            if active { current = try refreshLive(account.id, rotated: &rotated) } else { current = try refresh(current) }
            rotated = current
        }
        var answer = try ask(current)
        // A copy's token can end before its time, as after a sign-in elsewhere.
        if answer.status == 401, !active, rotated == nil {
            current = try refresh(current)
            rotated = current
            answer = try ask(current)
        }
        switch answer.status {
        case 200:
            guard let limits = ClaudeCodeLogin.limits(usage: answer.body, now: now()) else {
                throw AgentUsageFailure.unavailable("the usage answer was not understood")
            }
            return limits
        case 429:
            throw AgentUsageFailure.rateLimited(retryAfter: answer.retryAfter)
        default:
            throw AgentUsageFailure.unavailable("usage answered \(answer.status)")
        }
    }

    private func ask(_ credential: Data) throws -> AgentHTTPResponse {
        guard let tokens = ClaudeCodeLogin.tokens(credential) else { throw AgentUsageFailure.needsLogin }
        var request = AgentHTTP.request(ClaudeCodeLogin.usageURL)
        request.setValue("Bearer \(tokens.access)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let answer = transport(request) else { throw AgentUsageFailure.unavailable("usage did not answer") }
        return answer
    }

    /// New tokens for a credential. The refresh token is used up by asking,
    /// so whatever comes back has to be stored.
    private func refresh(_ credential: Data) throws -> Data {
        guard let tokens = ClaudeCodeLogin.tokens(credential), !tokens.refresh.isEmpty else {
            throw AgentUsageFailure.needsLogin
        }
        var request = AgentHTTP.request(ClaudeCodeLogin.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token", "refresh_token": tokens.refresh, "client_id": ClaudeCodeLogin.clientID])
        guard let answer = transport(request) else { throw AgentUsageFailure.unavailable("refresh did not answer") }
        if answer.status == 200, let fresh = ClaudeCodeLogin.refreshed(credential, with: answer.body, now: now()) {
            return fresh
        }
        if ClaudeCodeLogin.object(answer.body)?["error"] as? String == "invalid_grant" { throw AgentUsageFailure.needsLogin }
        if answer.status == 429 { throw AgentUsageFailure.rateLimited(retryAfter: answer.retryAfter) }
        throw AgentUsageFailure.unavailable("refresh answered \(answer.status)")
    }

    /// Refreshes the login Claude Code is using, the way it does itself:
    /// holding its refresh lock, and looking again once the lock is held,
    /// since a running session may have refreshed while this waited.
    private func refreshLive(_ id: AgentAccount.ID, rotated: inout Data?) throws -> Data {
        let locks = ClaudeLocks()
        defer { locks.release() }
        do { try locks.take([ClaudeLocks.refresh(home: home)], timeout: lockTimeout) } catch {
            throw AgentUsageFailure.unavailable("Claude Code is refreshing its login")
        }
        guard let live = try? readLive(), live.id == id else {
            throw AgentUsageFailure.unavailable("the live login changed")
        }
        guard ClaudeCodeLogin.isExpired(live.credential, now: now()) else { return live.credential }
        let fresh = try refresh(live.credential)
        rotated = fresh
        do { try writeLive(fresh) } catch {
            throw AgentUsageFailure.unavailable("the refreshed login could not be stored: \(error)")
        }
        return fresh
    }
}
