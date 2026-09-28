// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads a hub's accounts and their limits. Every request goes to the hub
/// the person added and carries its management key. The hub then asks
/// Anthropic or OpenAI with the account's own credentials, so no provider
/// token ever reaches this Mac.
enum AgentHubClient {
    struct Reading {
        let state: AgentHubState
        /// Nil when the hub could not list its accounts.
        let accounts: [AgentHubAccount]?
    }

    private static let claudeUsage = "https://api.anthropic.com/api/oauth/usage"
    private static let codexUsage = "https://chatgpt.com/backend-api/wham/usage"
    /// Accounts read at once, so a large pool does not flood the hub.
    private static let concurrency = 4
    private static let maximumSize = 8 << 20

    /// Reads the hub's accounts, a few at a time. A refusal of the hub itself,
    /// like a key revoked after the listing, ends the reading there. Every
    /// later call would carry the same key, and wrong keys count toward the
    /// hub's ban. A cancelled reading starts no further request.
    /// Sends one management request with the hub's key. Tests pass their
    /// own to script a hub's answers.
    typealias Sender = @Sendable (URLRequest, String) async -> Outcome

    static func read(_ hub: AgentHub, send: @escaping Sender = { await AgentHubClient.send($0, key: $1) }) async -> Reading {
        guard let url = hub.management("auth-files") else { return Reading(state: .failed(status: 0), accounts: nil) }
        let listing: Response
        switch await send(URLRequest(url: url), hub.key) {
        case .failure(let state): return Reading(state: state, accounts: nil)
        case .success(let response): listing = response
        }
        guard listing.status == 200 else {
            return Reading(state: AgentHubParser.state(status: listing.status, body: listing.body), accounts: nil)
        }
        guard var accounts = AgentHubParser.accounts(listing.body, hub: hub) else {
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
                    group.addTask { (position, await read(account, hub: hub, send: send)) }
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

    private enum AccountOutcome {
        case account(AgentHubAccount)
        /// The management API refused the hub's key or address.
        case refused(AgentHubState)
    }

    /// One account's limits, then the models the hub serves with it.
    private static func read(_ account: AgentHubAccount, hub: AgentHub, send: Sender) async -> AccountOutcome {
        var result = account
        switch await limits(of: account, hub: hub, send: send) {
        case .refused(let state): return .refused(state)
        case .account(let read): result = read
        }
        guard let file = account.file, !Task.isCancelled,
              var parts = hub.management("auth-files/models").flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        else { return .account(result) }
        parts.queryItems = [URLQueryItem(name: "name", value: file)]
        guard let url = parts.url else { return .account(result) }
        switch await send(URLRequest(url: url), hub.key) {
        case .success(let response) where response.status == 200:
            if let models = AgentHubParser.models(response.body) { result.models = models }
        case .success(let response):
            let state = AgentHubParser.state(status: response.status, body: response.body)
            if AgentHubParser.refusesHub(state) { return .refused(state) }
        case .failure:
            break
        }
        return .account(result)
    }

    /// One account's limits through the hub's `api-call`, which puts the
    /// account's token where `$TOKEN$` stands. A 401 from the hub refuses the
    /// management key. A 401 inside a proxied answer belongs to the account.
    private static func limits(of account: AgentHubAccount, hub: AgentHub, send: Sender) async -> AccountOutcome {
        var result = account
        result.failed = true
        guard !Task.isCancelled else { return .account(result) }
        var header = ["Authorization": "Bearer $TOKEN$"]
        switch account.provider {
        case .claude:
            header["anthropic-beta"] = "oauth-2025-04-20"
        case .codex:
            header["OpenAI-Beta"] = "codex-1"
            header["Originator"] = "Codex Desktop"
            if let workspace = account.chatGPTAccount { header["Chatgpt-Account-Id"] = workspace }
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
        guard case .success(let response) = await send(request, hub.key) else { return .account(result) }
        guard response.status == 200 else {
            let state = AgentHubParser.state(status: response.status, body: response.body)
            return AgentHubParser.refusesHub(state) ? .refused(state) : .account(result)
        }
        guard let proxied = AgentHubParser.proxied(response.body), (200..<300).contains(proxied.status) else {
            return .account(result)
        }
        let now = Date()
        switch account.provider {
        case .claude:
            guard let windows = AgentHubParser.claudeWindows(proxied.body) else { return .account(result) }
            result.limits = AgentLimits(provider: .claude, windows: windows, observedAt: now, source: .hub)
        case .codex:
            guard let usage = AgentHubParser.codexUsage(proxied.body, observed: now) else { return .account(result) }
            result.limits = AgentLimits(provider: .codex, windows: usage.windows, observedAt: now, source: .hub)
            if let plan = usage.plan { result.plan = plan }
        }
        result.failed = false
        return .account(result)
    }

    struct Response {
        let status: Int
        let body: Data
    }

    enum Outcome {
        case success(Response)
        case failure(AgentHubState)
    }

    private static func send(_ request: URLRequest, key: String) async -> Outcome {
        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("Vorssaint/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request, delegate: NoRedirects.shared)
            guard data.count <= maximumSize, let http = response as? HTTPURLResponse else {
                return .failure(.failed(status: 0))
            }
            return .success(Response(status: http.statusCode, body: data))
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            return .failure(.insecure)
        } catch {
            return .failure(.unreachable)
        }
    }

    /// A redirect would carry the management key to wherever it points, so
    /// the client follows none.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        static let shared = NoRedirects()

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}

/// The hubs a person added, in an owner-only file in the app's own folder.
/// The management key lives there too. Settings backups cover preferences
/// only, so the key never ends up in an exported file.
enum AgentHubStore {
    private static let fileName = "agent-hubs.json"

    private static var fileURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent(fileName, isDirectory: false)
    }

    static func load() -> [AgentHub] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AgentHub].self, from: data)) ?? []
    }

    @discardableResult
    static func save(_ hubs: [AgentHub]) -> Bool {
        guard let container = PrivateFileStore.containerURL, let url = fileURL else { return false }
        if hubs.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return true
        }
        guard PrivateFileStore.createDirectory(at: container),
              let data = try? JSONEncoder().encode(hubs) else { return false }
        return PrivateFileStore.write(data, to: url)
    }
}
