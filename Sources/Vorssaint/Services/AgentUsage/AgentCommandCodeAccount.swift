// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Command Code (`cmd`): the plan's 5-hour and weekly limits and this month's
/// credits, from the same requests its own `/usage` makes to
/// `api.commandcode.ai`.
///
/// The key is the one Command Code keeps after `cmd login`: `apiKey` in
/// `~/.commandcode/auth.json`. It does not expire and nothing renews it. It
/// goes to `api.commandcode.ai` only, as a bearer, and never into a log or a
/// reading. Read only: nothing of Command Code's is ever written.
enum AgentCommandCodeAccount {
    enum Failure: Error, Equatable {
        case notFound, signedOut, refused, busy, offline, unreadable
    }

    struct Reply {
        let status: Int
        let body: Data
    }

    struct Summary: Equatable {
        let limits: AgentLimits
        let plan: String?
    }

    /// One request; nil when nothing answered.
    typealias Fetch = (URLRequest) -> Reply?

    static let host = "api.commandcode.ai"
    /// Its numbers move slowly: ask at most this often.
    static let minimumGap: TimeInterval = 300
    static let timeout: TimeInterval = 15

    private static let fiveHourMinutes = 300
    private static let weekMinutes = 7 * 24 * 60
    /// The plan ids it sends, with the names it shows. A plan id carries a
    /// version after the name (`individual-go-v1`), so the longest prefix wins
    /// (`individual-provider` over `individual-pro`).
    private static let plans: [(prefix: String, name: String)] = [
        ("individual-go", "Go"), ("individual-goat", "GOAT"), ("individual-pro", "Pro"),
        ("individual-provider", "Provider"), ("individual-max", "Max"), ("individual-ultra", "Ultra"),
        ("teams-pro", "Teams Pro"),
    ]

    // MARK: Sign-in

    /// The key to ask with, or why there is none. `installed` is whether
    /// `cmd` has written its first-run file, so a Mac with `cmd` but no key
    /// reads as signed out and one without it as not found.
    static func apiKey(authFile: Data?, installed: Bool) -> Result<String, Failure> {
        let key = authFile
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { $0["apiKey"] as? String }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Printable ASCII only, so a mangled key never reaches a header.
        if let key, !key.isEmpty, key.utf8.allSatisfy({ $0 > 0x20 && $0 < 0x7f }) { return .success(key) }
        return authFile != nil || installed ? .failure(.signedOut) : .failure(.notFound)
    }

    // MARK: Asking

    static func request(_ path: String, query: [(String, String)], key: String) -> URLRequest {
        var text = "https://\(host)\(path)"
        for (index, pair) in query.enumerated() {
            // A time's colons are the only thing to escape: values are checked.
            text += (index == 0 ? "?" : "&") + pair.0 + "=" + pair.1.replacingOccurrences(of: ":", with: "%3A")
        }
        var request = URLRequest(url: URL(string: text)!, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Four requests: who, the limits, the plan and what the period spent.
    /// Only the limits matter; the last two are best effort.
    static func check(key: String, now: Date, fetch: Fetch) -> Result<Summary, Failure> {
        let who: [String: Any]
        switch json(fetch(request("/alpha/whoami", query: [("limits", "1")], key: key))) {
        case .failure(let failure): return .failure(failure)
        case .success(let value): who = value
        }
        let organization = (who["org"] as? [String: Any])?["id"] as? String
        let scope = organization.flatMap { safe($0, extra: "-_") }.map { [("orgId", $0)] } ?? []

        let credits: [String: Any]
        switch json(fetch(request("/alpha/billing/credits", query: scope, key: key))) {
        case .failure(let failure): return .failure(failure)
        case .success(let value): credits = value
        }
        let subscription = try? json(fetch(request("/alpha/billing/subscriptions", query: scope, key: key))).get()
        var summaryQuery = scope
        if let start = period(subscription, "currentPeriodStart") { summaryQuery.append(("since", start)) }
        let summary = try? json(fetch(request("/alpha/usage/summary", query: summaryQuery, key: key))).get()

        guard let limits = limits(credits: credits, subscription: subscription, summary: summary, observed: now)
        else { return .failure(.unreadable) }
        let plan = ((subscription?["data"] as? [String: Any])?["planId"] as? String).flatMap(planName)
        return .success(Summary(limits: limits, plan: plan))
    }

    private static func json(_ reply: Reply?) -> Result<[String: Any], Failure> {
        guard let reply else { return .failure(.offline) }
        switch reply.status {
        case 200: break
        case 401, 403: return .failure(.refused)
        case 429: return .failure(.busy)
        default: return .failure(.unreadable)
        }
        guard let value = (try? JSONSerialization.jsonObject(with: reply.body)) as? [String: Any]
        else { return .failure(.unreadable) }
        return .success(value)
    }

    // MARK: Reading

    static func planName(_ id: String) -> String? {
        let id = id.lowercased().replacingOccurrences(of: "_", with: "-")
        return plans.filter { id.hasPrefix($0.prefix) }.max { $0.prefix.count < $1.prefix.count }?.name
    }

    /// The 5-hour and weekly limits, in dollars of use against their cap, and
    /// the month's credits as a pool of what is left plus what was spent.
    static func limits(credits: [String: Any], subscription: [String: Any]?, summary: [String: Any]?,
                       observed: Date) -> AgentLimits? {
        var windows: [AgentLimitWindow] = []
        let limits = credits["windowLimits"] as? [String: Any]
        for (field, id, kind, minutes) in [("fiveHour", "commandcode.fh", AgentLimitWindow.Kind.session, fiveHourMinutes),
                                           ("weekly", "commandcode.wk", .weekly, weekMinutes)] {
            guard let window = limits?[field] as? [String: Any],
                  let cap = number(window["cap"]), cap > 0 else { continue }
            let used = max(0, number(window["used"]) ?? 0)
            // 0 is how it says "not running".
            let reset = number(window["resetAt"]).flatMap { $0 > 0 ? AgentLogParser.seconds(NSNumber(value: $0)) : nil }
            windows.append(AgentLimitWindow(id: id, kind: kind, minutes: minutes, scope: nil,
                                            usedPercent: min(100, used / cap * 100), resetsAt: reset))
        }
        let spent = number(summary?["totalMonthlyCredits"])
        let left = number((credits["credits"] as? [String: Any])?["monthlyCredits"])
        let status = (subscription?["data"] as? [String: Any])?["status"] as? String
        if let spent, let left, status == nil || status == "active" {
            let pool = max(0, spent) + max(0, left)
            if pool > 0 {
                let end = period(subscription, "currentPeriodEnd").flatMap(AgentTimestamp.parse)
                windows.append(AgentLimitWindow(id: "commandcode.cr", kind: .other, minutes: nil, scope: "Credits",
                                                usedPercent: min(100, max(0, spent) / pool * 100), resetsAt: end))
            }
        }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .commandcode, windows: windows, observedAt: observed, source: .account)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    /// Letters, digits and what `extra` allows: a value that goes into an
    /// address only if it cannot change it.
    private static func safe(_ text: String, extra: String) -> String? {
        guard !text.isEmpty, text.utf8.count <= 80,
              text.unicodeScalars.allSatisfy({ ($0.isASCII && $0.properties.isAlphabetic) || ("0"..."9").contains(Character($0))
                                              || extra.unicodeScalars.contains($0) }) else { return nil }
        return text
    }

    /// A period time from the subscription ("2026-10-22T09:31:07.000Z"), only
    /// if it looks like one.
    private static func period(_ subscription: [String: Any]?, _ field: String) -> String? {
        (subscription?["data"] as? [String: Any])?[field].flatMap { $0 as? String }.flatMap { safe($0, extra: "-:.") }
    }
}
