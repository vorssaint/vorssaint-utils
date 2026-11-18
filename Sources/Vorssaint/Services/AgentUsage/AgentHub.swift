// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A CLIProxyAPI server that pools Claude and Codex subscription accounts.
/// Vorssaint reads each account's limits through the server's management
/// API, with the key the person entered. The server asks Anthropic or
/// OpenAI with the account's own sign-in, so no account token reaches this Mac.
struct AgentHub: Codable, Equatable, Identifiable {
    static let maximum = 4

    /// Scheme, host and port only, as `normalizedURL` returns it.
    let url: String
    let label: String
    /// The server's management key. It also lets whoever holds it change the
    /// server and download its sign-ins, so it stays out of preferences.
    let key: String
    /// The server refused this key. Each wrong key counts toward its ban, so
    /// the key is not sent again, across launches too, until the person adds
    /// the hub again.
    var keyRefused: Bool

    init(url: String, label: String, key: String, keyRefused: Bool = false) {
        self.url = url
        self.label = label
        self.key = key
        self.keyRefused = keyRefused
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        label = try container.decode(String.self, forKey: .label)
        key = try container.decode(String.self, forKey: .key)
        keyRefused = try container.decodeIfPresent(Bool.self, forKey: .keyRefused) ?? false
    }

    var id: String { url }
    var name: String { label.isEmpty ? URLComponents(string: url)?.host ?? url : label }

    func management(_ path: String) -> URL? { URL(string: url + "/v0/management/" + path) }

    /// The address a person typed, cut down to where the server listens. A
    /// missing scheme means https. A pasted path, like the management panel's
    /// own page, is dropped: the API always sits at the root.
    static func normalizedURL(_ text: String) -> String? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2048 else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil else { return nil }
        var result = URLComponents()
        result.scheme = scheme
        result.host = host.lowercased()
        result.port = parts.port
        return result.string
    }

    /// A management key is one line of printable text; a pasted key often
    /// carries a line break.
    static func normalizedKey(_ text: String) -> String? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 1024,
              key.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) else { return nil }
        return key
    }
}

/// One pooled account and its latest reading.
struct AgentHubAccount: Equatable, Identifiable {
    enum Failure: Equatable {
        /// Anthropic or OpenAI refused the hub's sign-in for the account.
        case signIn
        /// No usable answer this time; an earlier reading stays.
        case unavailable
    }

    let hub: String
    /// The hub's handle for the account, which its proxied calls take.
    let index: String
    let provider: AgentProvider
    /// The label the hub gives the account, else its email or file name.
    let name: String
    /// Codex answers for the right workspace only when told which one.
    let chatGPTAccount: String?
    var plan: String?
    var limits: AgentLimits?
    var failure: Failure?

    var id: String { "hub." + hub + "#" + index }

    /// An expired window is unknown, not a freshly replenished allowance.
    func currentLimits(at now: Date) -> AgentLimits? {
        guard var limits else { return nil }
        limits.windows.removeAll { $0.resetsAt.map { $0 <= now } ?? false }
        return limits.windows.isEmpty ? nil : limits
    }
}

/// Where a hub stands, for its row in Settings.
enum AgentHubState: Equatable {
    case checking
    case ready(accounts: Int)
    /// The hub answers management calls from its own machine only.
    case remoteDisabled
    /// The hub refused the key. Each wrong key counts toward its ban.
    case wrongKey
    /// After five wrong keys the hub refuses this Mac for half an hour.
    case blocked
    /// The hub has no management key set, which turns its API off.
    case managementOff
    /// macOS allows plain http only to an IP address or a `.local` name.
    case insecure
    case unreachable
    case failed(status: Int)

    /// Whether the refusal is the hub's rather than one account's. Every
    /// later call would carry the same key and meet the same refusal.
    var refusesHub: Bool {
        switch self {
        case .wrongKey, .blocked, .remoteDisabled, .managementOff, .insecure: return true
        case .checking, .ready, .unreachable, .failed: return false
        }
    }
}

enum AgentHubParser {
    /// What a management response that is not a success means. CLIProxyAPI
    /// words its refusals; a hub with no key set has no management routes.
    static func state(status: Int, body: Data) -> AgentHubState {
        let message = (((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? String ?? "")
            .lowercased()
        switch status {
        case 401: return .wrongKey
        case 404: return .managementOff
        case 403:
            if message.contains("banned") { return .blocked }
            if message.contains("remote management disabled") { return .remoteDisabled }
            if message.contains("key not set") { return .managementOff }
            return .failed(status: status)
        default: return .failed(status: status)
        }
    }

    /// The enabled Claude and Codex subscription accounts in an `auth-files`
    /// listing. Nil for a body in another shape.
    static func accounts(_ data: Data, hub: String) -> [AgentHubAccount]? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { return nil }
        var seen = Set<String>()
        return files.compactMap { file -> AgentHubAccount? in
            let kind: String = (text(file["provider"]) ?? text(file["type"]) ?? "").lowercased()
            guard let provider = AgentProvider(rawValue: kind), provider == .claude || provider == .codex else { return nil }
            // An API key has no plan limits to read.
            let disabled = file["disabled"] as? Bool ?? false
            guard !disabled, (text(file["account_type"]) ?? "oauth") == "oauth" else { return nil }
            guard let index = text(file["auth_index"]), seen.insert(index).inserted else { return nil }
            let fileName = text(file["name"]).map { $0.hasSuffix(".json") ? String($0.dropLast(5)) : $0 }
            let claims = file["id_token"] as? [String: Any]
            return AgentHubAccount(hub: hub, index: index, provider: provider,
                                   name: text(file["label"]) ?? text(file["email"]) ?? fileName ?? index,
                                   chatGPTAccount: provider == .codex ? text(claims?["chatgpt_account_id"]) : nil)
        }
        .sorted { $0.provider != $1.provider ? $0.provider == .claude : $0.name < $1.name }
    }

    /// The upstream answer inside an `api-call` response: the provider's
    /// status, and its body, which the hub hands back as a string.
    static func proxied(_ data: Data) -> (status: Int, body: Data)? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let status = (json["status_code"] as? NSNumber)?.intValue else { return nil }
        return (status, Data((json["body"] as? String ?? "").utf8))
    }

    /// Anthropic's usage answer for a Claude subscription, the same windows
    /// Claude Code reports.
    static func claudeLimits(_ body: Data, observed: Date) -> AgentLimits? {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        let windows = AgentClaudeServer.windows(json, observed: observed)
        return windows.isEmpty ? nil : AgentLimits(provider: .claude, windows: windows, observedAt: observed, source: .account)
    }

    /// ChatGPT's usage answer for a Codex account, in the shape Codex logs
    /// its own limits, so windows are told apart by their length as there.
    static func codexLimits(_ body: Data, observed: Date) -> (limits: AgentLimits, plan: String?)? {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let rates = json["rate_limit"] as? [String: Any] else { return nil }
        var slots: [String: Any] = [:]
        for (slot, key) in [("primary", "primary_window"), ("secondary", "secondary_window")] {
            guard let window = rates[key] as? [String: Any], let used = window["used_percent"] as? NSNumber else { continue }
            var entry: [String: Any] = ["used_percent": used]
            if let seconds = (window["limit_window_seconds"] as? NSNumber)?.intValue, seconds > 0 {
                entry["window_minutes"] = seconds / 60
            }
            if let resets = window["reset_at"] as? NSNumber { entry["resets_at"] = resets }
            if let delay = window["reset_after_seconds"] as? NSNumber { entry["resets_in_seconds"] = delay }
            slots[slot] = entry
        }
        guard let windows = AgentLogParser.codexWindows(slots, observed: observed), !windows.isEmpty else { return nil }
        return (AgentLimits(provider: .codex, windows: windows, observedAt: observed, source: .account),
                CodexAccountUsageReader.knownPlan(text(json["plan_type"])))
    }

    private static func text(_ value: Any?) -> String? {
        let string = (value as? String ?? (value as? NSNumber)?.stringValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return string?.isEmpty == false ? string : nil
    }
}

/// The hubs a person added, in an owner-only file in the app's own folder,
/// key included. Settings exports cover preferences only, so the key never
/// leaves this Mac in one.
enum AgentHubStore {
    private static let fileName = "agent-hubs.json"
    private static let maximumSize = 64 * 1024

    static func load(from container: URL? = PrivateFileStore.containerURL) -> [AgentHub] {
        guard let url = container?.appendingPathComponent(fileName, isDirectory: false),
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= maximumSize,
              let data = try? Data(contentsOf: url),
              let hubs = try? JSONDecoder().decode([AgentHub].self, from: data) else { return [] }
        var ids = Set<String>()
        return hubs.prefix(AgentHub.maximum).filter {
            AgentHub.normalizedURL($0.url) == $0.url && AgentHub.normalizedKey($0.key) == $0.key && ids.insert($0.id).inserted
        }
    }

    @discardableResult
    static func save(_ hubs: [AgentHub], to container: URL? = PrivateFileStore.containerURL) -> Bool {
        guard let container else { return false }
        let url = container.appendingPathComponent(fileName, isDirectory: false)
        if hubs.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return !FileManager.default.fileExists(atPath: url.path)
        }
        guard PrivateFileStore.createDirectory(at: container, container: container),
              let data = try? JSONEncoder().encode(hubs) else { return false }
        return PrivateFileStore.write(data, to: url)
    }
}
