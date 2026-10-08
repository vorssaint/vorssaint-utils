// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where a link opens: a browser, or one of its profiles. A profile is kept
/// by its folder (a Chromium profile directory, or a Firefox profile path),
/// which survives a rename; the name only labels a profile that is gone.
enum BrowserPickerTarget: Codable, Hashable {
    case application(bundleID: String)
    case profile(bundleID: String, id: String, name: String)

    var bundleID: String {
        switch self {
        case .application(let bundleID), .profile(let bundleID, _, _): return bundleID
        }
    }
}

/// Sends links to one site, optionally only below one path, to a fixed target.
struct BrowserPickerRule: Codable, Hashable, Identifiable {
    var id = UUID()
    /// A lowercase ASCII host. It also covers the site's subdomains, so
    /// `github.com` takes `gist.github.com` but never `notgithub.com`.
    var site: String
    /// Empty for the whole site, otherwise a percent-encoded path such as `/team`.
    var path = ""
    var target: BrowserPickerTarget
    var isEnabled = true
    /// How the target was named when the rule was saved, to label it once
    /// the browser is gone.
    var targetName: String?
}

/// The fields of a rule while it is edited, as typed.
struct BrowserPickerRuleDraft {
    var id: UUID?
    var site: String
    var path: String
    var target: BrowserPickerTarget?
    var isEnabled = true

    init(site: String, path: String, target: BrowserPickerTarget?) {
        self.site = site
        self.path = path
        self.target = target
    }

    init(_ rule: BrowserPickerRule) {
        id = rule.id
        site = rule.site
        path = rule.path.removingPercentEncoding ?? rule.path
        target = rule.target
        isEnabled = rule.isEnabled
    }

    /// The rule these fields describe, or nil while they do not describe one.
    /// A path typed into the site field counts when the path field is empty.
    var rule: BrowserPickerRule? {
        guard let target, let parsed = BrowserPickerRules.normalizedSite(site) else { return nil }
        let typedPath = BrowserPickerRules.normalizedPath(path)
        return BrowserPickerRule(id: id ?? UUID(), site: parsed.site,
                                 path: typedPath.isEmpty ? parsed.path : typedPath,
                                 target: target, isEnabled: isEnabled)
    }
}

enum BrowserPickerRules {
    private struct Stored: Codable {
        var version = 1
        var rules: [BrowserPickerRule]
    }

    /// Unreadable or newer data reads as no rules rather than failing, the same
    /// as every other list a backup can carry.
    static func decode(_ data: Data?) -> [BrowserPickerRule] {
        guard let data, let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == 1 else { return [] }
        return stored.rules
    }

    static func encode(_ rules: [BrowserPickerRule]) -> Data {
        (try? JSONEncoder().encode(Stored(rules: rules))) ?? Data()
    }

    /// The first enabled rule that covers the link. Order is the priority.
    static func firstMatch(for url: URL, in rules: [BrowserPickerRule]) -> BrowserPickerRule? {
        guard let host = host(of: url) else { return nil }
        let path = url.path(percentEncoded: true)
        return rules.first { $0.isEnabled && covers($0, host: host, path: path) }
    }

    static func covers(_ rule: BrowserPickerRule, host: String, path: String) -> Bool {
        guard host == rule.site || host.hasSuffix("." + rule.site) else { return false }
        guard !rule.path.isEmpty else { return true }
        // `/team` covers `/team` and `/team/x`, not `/teams`.
        let prefix = rule.path.hasSuffix("/") ? String(rule.path.dropLast()) : rule.path
        return path == prefix || path.hasPrefix(prefix + "/")
    }

    /// The web host of a link, in the same form `normalizedSite` stores.
    static func host(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.encodedHost
        else { return nil }
        return clean(host)
    }

    /// Reads what someone types for a site: `GitHub.com`, `https://github.com/team`
    /// or `*.github.com`. Returns nil when there is no usable host.
    static func normalizedSite(_ input: String) -> (site: String, path: String)? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("*.") { text.removeFirst(2) }
        if !text.contains("://") { text = "https://" + text }
        guard let components = URLComponents(string: text),
              let encodedHost = components.encodedHost,
              let site = clean(encodedHost),
              site.contains(".") || site == "localhost" else { return nil }
        let path = components.percentEncodedPath
        return (site, path == "/" ? "" : path)
    }

    /// A path someone typed, stored the way links carry it so `/my docs` and
    /// `/my%20docs` are the same rule.
    static func normalizedPath(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "/" else { return "" }
        if !text.hasPrefix("/") { text = "/" + text }
        var components = URLComponents()
        components.path = text.removingPercentEncoding ?? text
        return components.percentEncodedPath
    }

    /// The rules after ⌥ remembers `target` for the link's site. A whole-site
    /// rule for that site is repointed and switched on; otherwise a new one is
    /// added. Either way it ends up above the rule that matched the link, whose
    /// target is gone, so the next link to the site no longer asks.
    static func remembering(_ target: BrowserPickerTarget, for url: URL,
                            in rules: [BrowserPickerRule]) -> [BrowserPickerRule] {
        guard let site = suggestedSite(for: url) else { return rules }
        var rules = rules
        let matched = firstMatch(for: url, in: rules).flatMap { match in rules.firstIndex { $0.id == match.id } }
        guard let index = rules.firstIndex(where: { $0.site == site && $0.path.isEmpty }) else {
            rules.insert(BrowserPickerRule(site: site, target: target), at: matched ?? rules.endIndex)
            return rules
        }
        var rule = rules.remove(at: index)
        rule.target = target
        rule.isEnabled = true
        rule.targetName = nil
        rules.insert(rule, at: min(matched ?? index, index))
        return rules
    }

    /// Whether a target can still be opened. `knownProfiles` holds, for each
    /// browser whose list was read, its profile ids; opening a profile that
    /// is gone would make the browser create a new, empty one.
    static func isAvailable(_ target: BrowserPickerTarget, appInstalled: Bool,
                            knownProfiles: [String: Set<String>]) -> Bool {
        guard appInstalled else { return false }
        guard case .profile(let bundleID, let id, _) = target else { return true }
        return knownProfiles[bundleID].map { $0.contains(id) } ?? true
    }

    /// The site a new rule from a link starts with: the link's host without a
    /// leading `www.`, so the rule also covers the site's other subdomains.
    static func suggestedSite(for url: URL) -> String? {
        guard let host = host(of: url) else { return nil }
        let trimmed = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return trimmed.contains(".") ? trimmed : host
    }

    private static func clean(_ host: String) -> String? {
        var host = host.lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, !host.contains("/"), !host.contains(" ") else { return nil }
        return host
    }
}

/// What happens to one incoming link.
enum BrowserPickerRoute: Equatable {
    case open(BrowserPickerTarget)
    /// Show the picker; `missing` names a rule's target that is gone, so the
    /// picker can say why it is asking instead of opening something else.
    case ask(missing: BrowserPickerTarget?)

    static func of(_ url: URL, rules: [BrowserPickerRule],
                   isInstalled: (BrowserPickerTarget) -> Bool) -> BrowserPickerRoute {
        guard let rule = BrowserPickerRules.firstMatch(for: url, in: rules) else { return .ask(missing: nil) }
        return isInstalled(rule.target) ? .open(rule.target) : .ask(missing: rule.target)
    }
}
