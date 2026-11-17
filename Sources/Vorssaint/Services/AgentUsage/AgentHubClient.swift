// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads a hub's accounts and their limits. Every request goes to the hub
/// the person added and carries its management key; no redirect is followed,
/// so the key goes nowhere else.
enum AgentHubClient {
    struct Reading: Equatable {
        let state: AgentHubState
        /// Nil when the hub could not list its accounts.
        let accounts: [AgentHubAccount]?
    }

    struct Response {
        let status: Int
        let body: Data
    }

    enum Outcome {
        case success(Response)
        case failure(AgentHubState)
    }

    /// Sends one management request with the hub's key. Tests pass their
    /// own to script a hub's answers.
    typealias Sender = @Sendable (URLRequest, String) async -> Outcome

    static let claudeUsage = "https://api.anthropic.com/api/oauth/usage"
    static let codexUsage = "https://chatgpt.com/backend-api/wham/usage"
    /// Accounts read at once, so a large pool does not flood the hub.
    static let concurrency = 4
    private static let maximumSize = 4 << 20

    /// Lists the hub's accounts, then reads their limits a few at a time. A
    /// refusal of the hub itself, like a key revoked after the listing, ends
    /// the reading: every later call would carry the same key, and wrong keys
    /// count toward the hub's ban. A cancelled reading starts no request.
    static func read(_ hub: AgentHub,
                     send: @escaping Sender = { await AgentHubClient.send($0, key: $1) }) async -> Reading {
        guard let url = hub.management("auth-files") else { return Reading(state: .failed(status: 0), accounts: nil) }
        // Stopped before it began: nothing was sent, so nothing was learned.
        if Task.isCancelled { return Reading(state: .checking, accounts: nil) }
        let listing: Response
        switch await finishing(URLRequest(url: url), hub.key, send) {
        case .failure(let state): return Reading(state: state, accounts: nil)
        case .success(let response): listing = response
        }
        guard listing.status == 200 else {
            return Reading(state: AgentHubParser.state(status: listing.status, body: listing.body), accounts: nil)
        }
        guard var accounts = AgentHubParser.accounts(listing.body, hub: hub.id) else {
            return Reading(state: .failed(status: listing.status), accounts: nil)
        }
        var start = 0
        while start < accounts.count {
            if Task.isCancelled { return Reading(state: .checking, accounts: nil) }
            let end = min(accounts.count, start + concurrency)
            var refusal: AgentHubState?
            await withTaskGroup(of: (Int, AccountOutcome).self) { group in
                for position in start..<end {
                    let account = accounts[position]
                    group.addTask { (position, await limits(of: account, hub: hub, send: send)) }
                }
                for await (position, outcome) in group {
                    switch outcome {
                    case .account(let account): accounts[position] = account
                    case .refused(let state):
                        refusal = refusal ?? state
                        group.cancelAll()
                    }
                }
            }
            if let refusal { return Reading(state: refusal, accounts: nil) }
            start = end
        }
        if Task.isCancelled { return Reading(state: .checking, accounts: nil) }
        return Reading(state: .ready(accounts: accounts.count), accounts: accounts)
    }

    /// Sends a request that finishes even when the reading is stopped. The
    /// hub may already have counted a wrong key, and the reading must see its
    /// answer so the key is not sent again. A stopped reading only starts no
    /// further request.
    private static func finishing(_ request: URLRequest, _ key: String, _ send: @escaping Sender) async -> Outcome {
        await Task { await send(request, key) }.value
    }

    private enum AccountOutcome {
        case account(AgentHubAccount)
        /// The management API refused the hub's key or this Mac.
        case refused(AgentHubState)
    }

    /// One account's limits through the hub's `api-call`, which puts the
    /// account's token where `$TOKEN$` stands. A 401 from the hub refuses the
    /// management key; a 401 inside the proxied answer belongs to the account.
    private static func limits(of account: AgentHubAccount, hub: AgentHub, send: @escaping Sender) async -> AccountOutcome {
        var result = account
        result.failure = .unavailable
        guard !Task.isCancelled else { return .account(result) }
        var header = ["Authorization": "Bearer $TOKEN$"]
        switch account.provider {
        case .claude:
            header["anthropic-beta"] = "oauth-2025-04-20"
        case .codex:
            header["OpenAI-Beta"] = "codex-1"
            header["Originator"] = "Codex Desktop"
            if let workspace = account.chatGPTAccount { header["Chatgpt-Account-Id"] = workspace }
        case .opencode, .copilot:
            return .account(result)
        }
        let call: [String: Any] = ["auth_index": account.index, "method": "GET",
                                   "url": account.provider == .claude ? claudeUsage : codexUsage, "header": header]
        guard let url = hub.management("api-call"), let body = try? JSONSerialization.data(withJSONObject: call) else {
            return .account(result)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard case .success(let response) = await finishing(request, hub.key, send) else { return .account(result) }
        guard response.status == 200 else {
            let state = AgentHubParser.state(status: response.status, body: response.body)
            return state.refusesHub ? .refused(state) : .account(result)
        }
        guard let proxied = AgentHubParser.proxied(response.body) else { return .account(result) }
        if proxied.status == 401 { result.failure = .signIn }
        guard (200..<300).contains(proxied.status) else { return .account(result) }
        let now = Date()
        switch account.provider {
        case .claude:
            guard let limits = AgentHubParser.claudeLimits(proxied.body, observed: now) else { return .account(result) }
            result.limits = limits
        case .codex:
            guard let reading = AgentHubParser.codexLimits(proxied.body, observed: now) else { return .account(result) }
            result.limits = reading.limits
            result.plan = reading.plan
        case .opencode, .copilot:
            return .account(result)
        }
        result.failure = nil
        return .account(result)
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func send(_ request: URLRequest, key: String) async -> Outcome {
        var request = request
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Vorssaint/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        do {
            // Read as it arrives, so an oversized answer stops at the limit.
            let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirects.shared)
            guard let http = response as? HTTPURLResponse, http.expectedContentLength <= Int64(maximumSize) else {
                return .failure(.failed(status: 0))
            }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maximumSize { return .failure(.failed(status: 0)) }
            }
            return .success(Response(status: http.statusCode, body: data))
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            return .failure(.insecure)
        } catch {
            return .failure(.unreachable)
        }
    }

    /// A redirect would carry the management key to wherever it points, so
    /// the client stops at the redirect itself.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        static let shared = NoRedirects()

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
