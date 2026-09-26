// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A CLIProxyAPI server that pools Claude and Codex accounts. The person adds
/// it with the server's management key, and Vorssaint asks it for the plan
/// limits of every account it holds. The hub makes the provider requests with
/// its own credentials, so no account token ever reaches this Mac.
struct AgentHub: Codable, Equatable, Identifiable {
    /// Scheme, host and port only, as `normalizedURL` returns it.
    let url: String
    let label: String
    let key: String
    /// Names the person gave accounts, by the hub's handle for each.
    var names: [String: String]

    init(url: String, label: String, key: String, names: [String: String] = [:]) {
        self.url = url
        self.label = label
        self.key = key
        self.names = names
    }

    /// Files saved before accounts could be renamed have no names.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        label = try container.decode(String.self, forKey: .label)
        key = try container.decode(String.self, forKey: .key)
        names = try container.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
    }

    var id: String { url }

    /// The same server with the same key. Renaming an account keeps it the same hub.
    func sameConnection(as other: AgentHub) -> Bool { url == other.url && key == other.key }
    var name: String { label.isEmpty ? URLComponents(string: url)?.host ?? url : label }

    func management(_ path: String) -> URL? { URL(string: url + "/v0/management/" + path) }

    /// The address a person typed, cut down to where the server listens. A
    /// missing scheme means https. It drops a pasted path, like the management
    /// panel's own address, because the API always sits at the root.
    static func normalizedURL(_ text: String) -> String? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        var result = URLComponents()
        result.scheme = scheme
        result.host = host.lowercased()
        result.port = parts.port
        return result.string
    }
}

/// One pooled account and its latest reading.
struct AgentHubAccount: Equatable, Identifiable {
    let hub: String
    let hubName: String
    /// The hub's handle for the account, which its proxy calls take.
    let index: String
    let provider: AgentProvider
    /// The email the account signs in with, else the hub's label or file name.
    let name: String
    let email: String?
    /// Codex answers for the right workspace only when told which one.
    let chatGPTAccount: String?
    var plan: AgentPlan?
    var limits: AgentLimits?
    /// The last attempt to read its limits failed. Earlier readings stay.
    var failed = false

    var id: String { hub + "#" + index }
}

/// Where a hub stands, for its row in Settings.
enum AgentHubState: Equatable {
    case checking
    case ready(accounts: Int)
    /// The hub answers management calls from its own machine only.
    case remoteDisabled
    case wrongKey
    /// After too many wrong keys, the hub refuses this Mac for half an hour.
    case blocked
    /// The hub has no management key set, which turns its API off.
    case managementOff
    /// macOS refuses plain http to a host name.
    case insecure
    case unreachable
    case failed(status: Int)
}

enum AgentHubParser {
    /// The hub answers a wrong key with 401 and bans the address after five.
    static let banLength: TimeInterval = 30 * 60

    /// What a management response that is not a success means.
    static func state(status: Int, body: Data) -> AgentHubState {
        let message = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? String ?? ""
        switch status {
        case 401: return .wrongKey
        case 404: return .managementOff
        case 403:
            let text = message.lowercased()
            if text.contains("remote management disabled") { return .remoteDisabled }
            if text.contains("banned") { return .blocked }
            if text.contains("not set") { return .managementOff }
            return .failed(status: status)
        default: return .failed(status: status)
        }
    }

    /// The Claude and Codex accounts in an `auth-files` listing, leaving out
    /// disabled ones. Nil for a body in another shape.
    static func accounts(_ data: Data, hub: AgentHub) -> [AgentHubAccount]? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { return nil }
        return files.compactMap { file -> AgentHubAccount? in
            let kind = (file["provider"] as? String ?? file["type"] as? String ?? "").lowercased()
            guard let provider = AgentProvider(rawValue: kind), (file["disabled"] as? Bool) != true,
                  let index = text(file["auth_index"]) else { return nil }
            let email = text(file["email"])
            let fileName = text(file["name"]).map { $0.hasSuffix(".json") ? String($0.dropLast(5)) : $0 }
            let claims = file["id_token"] as? [String: Any]
            let plan = provider == .codex ? AgentPlans.codex(planType: claims?["chatgpt_plan_type"] as? String) : nil
            return AgentHubAccount(hub: hub.id, hubName: hub.name, index: index, provider: provider,
                                   name: email ?? text(file["label"]) ?? fileName ?? index, email: email,
                                   chatGPTAccount: text(claims?["chatgpt_account_id"]), plan: plan)
        }
        .sorted { $0.provider != $1.provider ? $0.provider == .claude : $0.name < $1.name }
    }

    /// The upstream answer inside an `api-call` response. It holds the
    /// provider's status and its body, which the hub hands back as a string.
    static func proxied(_ data: Data) -> (status: Int, body: Data)? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let status = (json["status_code"] as? NSNumber)?.intValue else { return nil }
        return (status, Data((json["body"] as? String ?? "").utf8))
    }

    /// Anthropic's usage answer for a Claude subscription. It gives
    /// percentages from 0 to 100 with ISO reset times.
    static func claudeWindows(_ body: Data) -> [AgentLimitWindow]? {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        var windows: [AgentLimitWindow] = []
        for (key, kind, minutes) in [("five_hour", AgentLimitWindow.Kind.session, 300), ("seven_day", .weekly, 10_080)] {
            guard let window = json[key] as? [String: Any], let used = percent(window["utilization"]) else { continue }
            windows.append(AgentLimitWindow(id: "hub.claude.\(key)", kind: kind, minutes: minutes, scope: nil,
                                            usedPercent: used, resetsAt: date(window["resets_at"])))
        }
        for limit in json["limits"] as? [[String: Any]] ?? [] where limit["kind"] as? String == "weekly_scoped" {
            guard let model = ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String,
                  let used = percent(limit["percent"]) else { continue }
            windows.append(AgentLimitWindow(id: "hub.claude.weekly.\(model.lowercased())", kind: .weekly,
                                            minutes: 10_080, scope: model, usedPercent: used,
                                            resetsAt: date(limit["resets_at"])))
        }
        return windows.isEmpty ? nil : windows
    }

    /// ChatGPT's usage answer for a Codex account. Windows are told apart by
    /// their length, as in Codex's own logs, never by their slot.
    static func codexUsage(_ body: Data, observed: Date) -> (windows: [AgentLimitWindow], plan: AgentPlan?)? {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        let rates = json["rate_limit"] as? [String: Any] ?? [:]
        var windows: [AgentLimitWindow] = []
        for slot in ["primary_window", "secondary_window"] {
            guard let window = rates[slot] as? [String: Any], let used = percent(window["used_percent"]) else { continue }
            let minutes = (window["limit_window_seconds"] as? NSNumber).map { $0.intValue / 60 }
            var resets = AgentLogParser.seconds(window["reset_at"])
            if resets == nil, let delay = (window["reset_after_seconds"] as? NSNumber)?.doubleValue, delay.isFinite {
                resets = observed.addingTimeInterval(max(0, delay))
            }
            windows.append(AgentLimitWindow(id: "hub.codex.\(minutes.map(String.init) ?? slot)",
                                            kind: AgentLogParser.kind(minutes: minutes), minutes: minutes, scope: nil,
                                            usedPercent: used, resetsAt: resets))
        }
        guard !windows.isEmpty else { return nil }
        return (windows.sorted { ($0.minutes ?? .max) < ($1.minutes ?? .max) },
                AgentPlans.codex(planType: json["plan_type"] as? String))
    }

    private static func text(_ value: Any?) -> String? {
        let string = (value as? String ?? (value as? NSNumber)?.stringValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return string?.isEmpty == false ? string : nil
    }

    private static func percent(_ value: Any?) -> Double? {
        guard let number = (value as? NSNumber)?.doubleValue, number.isFinite else { return nil }
        return min(100, max(0, number))
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return AgentLogParser.seconds(value) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
