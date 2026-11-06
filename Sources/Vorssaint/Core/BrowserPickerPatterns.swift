// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A rule that names links by a pattern instead of one site: a wildcard for
/// shapes a site rule cannot say (`jira.*`, `https://meet.google.com/*`), or a
/// regular expression for anything beyond that.
struct BrowserPickerPattern: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Hashable {
        case wildcard
        case regularExpression
    }

    enum Problem: Equatable {
        case empty
        /// A wildcard without a host part, such as `/docs/*`.
        case missingHost
        case invalidRegularExpression
    }

    var kind: Kind
    var text: String

    /// Why the pattern cannot be saved, or nil when it can.
    var problem: Problem? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        switch kind {
        case .wildcard:
            return Self.wildcardParts(text.lowercased()).host.isEmpty ? .missingHost : nil
        case .regularExpression:
            return Self.regularExpression(text) == nil ? .invalidRegularExpression : nil
        }
    }

    func matches(_ url: URL) -> Bool {
        guard problem == nil, let link = Link(url) else { return false }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .wildcard: return Self.wildcardMatches(text, link)
        case .regularExpression: return Self.regularExpressionMatches(text, link)
        }
    }

    // MARK: - Link

    /// A web link in the parts a pattern looks at. The host has the same form
    /// a site rule stores, so both kinds of rule see one host.
    struct Link {
        let scheme: String
        let host: String
        let hostWithPort: String
        /// The percent-encoded path, "/" when the link has none.
        let path: String
        /// Path, query and fragment.
        let pathAndLater: String

        var full: String { "\(scheme)://\(hostWithPort)\(pathAndLater)" }

        init?(_ url: URL) {
            guard let host = BrowserPickerRules.host(of: url),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let scheme = components.scheme?.lowercased() else { return nil }
            self.scheme = scheme
            self.host = host
            hostWithPort = components.port.map { "\(host):\($0)" } ?? host
            let path = components.percentEncodedPath
            self.path = path.isEmpty ? "/" : path
            var later = self.path
            if let query = components.percentEncodedQuery { later += "?" + query }
            if let fragment = components.percentEncodedFragment { later += "#" + fragment }
            pathAndLater = later
        }
    }

    // MARK: - Wildcards

    /// A wildcard reads as `[scheme://]host[/path…]`, where `*` stands for any
    /// text and `?` for one character:
    ///
    /// - The host part follows a site rule: `github.com` also takes its
    ///   subdomains, and `*.zoom.us` takes `zoom.us` itself as well. With a
    ///   wildcard elsewhere (`jira.*`) it is matched as written, anchored at
    ///   both ends. A port in the pattern must match; without one any port does.
    /// - A scheme, when given, must match: `http://*` takes only plain http.
    /// - A path part is matched against the link's path, anchored, with the
    ///   case it is written in, like a site rule's path. It is compared with
    ///   the query and fragment as well only when it names one itself, so a
    ///   tracking parameter never breaks `meet.google.com/abc`.
    static func wildcardMatches(_ text: String, _ link: Link) -> Bool {
        let parts = wildcardParts(text)
        guard !parts.host.isEmpty else { return false }
        if let scheme = parts.scheme, !glob(scheme, link.scheme) { return false }
        guard hostMatches(parts.host, link) else { return false }
        guard !parts.rest.isEmpty else { return true }
        let named = parts.rest.contains("?") || parts.rest.contains("#")
        return glob(parts.rest, named ? link.pathAndLater : link.path, ignoringCase: false)
    }

    /// Splits a wildcard into its scheme, host and the rest. Scheme and host
    /// are lowercased, the rest keeps its case.
    static func wildcardParts(_ text: String) -> (scheme: String?, host: String, rest: String) {
        var remainder = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var scheme: String?
        if let mark = remainder.range(of: "://") {
            scheme = remainder[..<mark.lowerBound].lowercased()
            remainder = remainder[mark.upperBound...]
        }
        let end = remainder.firstIndex(of: "/") ?? remainder.endIndex
        var host = remainder[..<end].lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        return (scheme, host, String(remainder[end...]))
    }

    private static func hostMatches(_ pattern: String, _ link: Link) -> Bool {
        let host = pattern.contains(":") ? link.hostWithPort : link.host
        if pattern.hasPrefix("*.") {
            let base = String(pattern.dropFirst(2))
            if !base.isEmpty, !base.contains("*"), !base.contains("?") {
                return host == base || host.hasSuffix("." + base)
            }
        }
        if pattern.contains("*") || pattern.contains("?") { return glob(pattern, host) }
        return host == pattern || host.hasSuffix("." + pattern)
    }

    /// Anchored glob: `*` is any run of characters, slashes included, `?` is
    /// one character, everything else is literal.
    static func glob(_ pattern: String, _ text: String, ignoringCase: Bool = true) -> Bool {
        var expression = "^"
        for character in pattern {
            switch character {
            case "*": expression += ".*"
            case "?": expression += "."
            default: expression += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        expression += "$"
        guard let regex = try? NSRegularExpression(pattern: expression,
                                                   options: ignoringCase ? [.caseInsensitive] : [])
        else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - Regular expressions

    /// A regular expression is searched for in the whole link, such as
    /// `https://example.com/page?x=1`, ignoring case. It matches anywhere
    /// unless it anchors itself with `^` or `$`.
    static func regularExpressionMatches(_ text: String, _ link: Link) -> Bool {
        guard let expression = regularExpression(text) else { return false }
        let full = link.full
        return expression.firstMatch(in: full, range: NSRange(full.startIndex..., in: full)) != nil
    }

    private static func regularExpression(_ text: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: text, options: [.caseInsensitive])
    }
}
