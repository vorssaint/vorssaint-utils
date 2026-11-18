// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import UniformTypeIdentifiers

enum URLCleaning {
    private static let trackedParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_name", "utm_reader", "utm_viz_id", "utm_pubreferrer",
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid",
        "mc_cid", "mc_eid", "igshid", "twclid", "ttclid", "li_fat_id",
        "mkt_tok", "_hsenc", "_hsmi", "__twitter_impression",
        "fb_action_ids", "fb_action_types", "fb_source", "mibextid",
    ]

    /// Trackers that only one site uses. A global list cannot hold these: `si`
    /// is a share token on YouTube but a real parameter elsewhere, and `t` is a
    /// tracker on X while it is the playback position on YouTube. Matching on
    /// the host is what keeps removing one from breaking the other.
    ///
    /// Keys match the host itself or any subdomain of it.
    private static let hostParameters: [String: Set<String>] = [
        "youtube.com": ["si", "pp", "feature", "kw"],
        "youtu.be": ["si", "pp", "feature", "kw"],
        "twitter.com": ["s", "t", "cn", "src", "refsrc", "ref_src", "ref_url"],
        "x.com": ["s", "t", "cn", "src", "refsrc", "ref_src", "ref_url"],
        "instagram.com": ["igsh"],
        "spotify.com": ["si"],
        // Reddit's share sheet routes through branch.io, whose deep link fields
        // start with a literal `$`. Links often carry them percent-encoded as
        // `%24…`, but only the decoded spelling is listed: `decodedName` decodes
        // the name half of each pair before the rules see it. ClearURLs lists
        // both because it matches the raw query with regex.
        "reddit.com": [
            "correlation_id", "ref_campaign", "ref_source", "rdt", "share_id",
            "_branch_match_id", "$deep_link", "$3p", "$original_url",
        ],
        "tiktok.com": [
            "u_code", "preview_pb", "_d", "_t", "_r", "timestamp", "user_id",
            "share_app_name", "share_iid",
        ],
        "bilibili.com": [
            "spm_id_from", "from_spmid", "from_source", "share_source", "share_from",
            "share_medium", "share_plat", "share_tag", "share_session_id", "msource",
            "refer_from", "seid", "unique_k", "vd_source", "plat_id", "buvid", "bbid",
            "up_id", "is_story_h5", "timestamp", "ts", "visit_id", "session_id",
            "broadcast_type", "is_room_feed",
        ],
        "xiaohongshu.com": [
            "xhsshare", "author_share", "xsec_source", "share_from_user_hidden",
            "shareredid", "share_id", "exsource", "app_version", "app_platform",
            "apptime", "appuid",
        ],
        // Search position, recommendation widgets and the search that led to
        // the product. `th` and `psc` stay: they pick the variant on the page.
        "amazon.com": [
            "ref", "ref_", "crid", "dib", "dib_tag", "keywords", "qid", "sprefix", "sr", "srs",
            "content-id", "_encoding", "pd_rd_i", "pd_rd_p", "pd_rd_r", "pd_rd_w", "pd_rd_wg",
            "pf_rd_i", "pf_rd_m", "pf_rd_p", "pf_rd_r", "pf_rd_s", "pf_rd_t",
        ],
    ]

    /// Sites that run one copy of themselves per country with the same
    /// parameters. Each regional domain reads the rules of the key it maps
    /// to, so Settings shows one row for Amazon rather than twenty identical
    /// ones, and switching a name off there applies to every storefront.
    private static let siteAliases: [String: String] = Dictionary(uniqueKeysWithValues: [
        "amazon.ae", "amazon.ca", "amazon.cn", "amazon.co.jp", "amazon.co.uk", "amazon.com.au",
        "amazon.com.be", "amazon.com.br", "amazon.com.mx", "amazon.com.tr", "amazon.de",
        "amazon.eg", "amazon.es", "amazon.fr", "amazon.ie", "amazon.in", "amazon.it",
        "amazon.nl", "amazon.pl", "amazon.sa", "amazon.se", "amazon.sg",
    ].map { ($0, "amazon.com") })

    /// Amazon serves a product at `/dp/<ASIN>` whatever comes before it. The
    /// title in front only repeats the page, so it goes; `/gp/product/` is
    /// left spelled as it is, since cleaning only ever deletes.
    private static let amazonProductPath = try? NSRegularExpression(
        pattern: #"^/[^/]+(/(?:dp|gp/product)/[A-Z0-9]{10}/?)$"#)

    /// A cleaned link and the names taken out of it, so every surface that
    /// cleans can say what it removed instead of only that something changed.
    struct Result: Equatable {
        let url: String
        let removed: [String]
    }

    /// What the user changed about the tables above: names they added, and
    /// built-in names they switched off. Stored as a difference rather than a
    /// copy of the tables, so names added in a later version of the app still
    /// reach someone who has already edited their rules.
    ///
    /// Both maps are keyed the way `hostParameters` is, with `allSites` for
    /// the rules that apply everywhere.
    struct Rules: Equatable {
        var added: [String: Set<String>] = [:]
        var disabled: [String: Set<String>] = [:]

        static let none = Rules()
    }

    /// One row of a site's rules, as Settings shows it.
    struct RuleGroup: Identifiable, Equatable {
        let site: String
        let entries: [Entry]

        var id: String { site }
        var enabledCount: Int { entries.filter(\.isEnabled).count }

        struct Entry: Identifiable, Equatable {
            let name: String
            let isBuiltIn: Bool
            let isEnabled: Bool

            var id: String { name }
        }
    }

    /// The key the global rules live under. Empty so a stored token reads as
    /// `|ref` for a global name and `youtube.com|si` for a site one.
    static let allSites = ""

    /// The single row standing for every `utm_` name. The cleaner matches the
    /// prefix, so listing `utm_source` and its siblings separately would show
    /// rows that cannot be switched off on their own.
    static let utmWildcard = "utm_*"

    /// The global list as Settings shows it: the wildcard row, then the names
    /// the prefix does not already cover.
    static var globalBuiltInNames: [String] {
        [utmWildcard] + trackedParameters.filter { !$0.hasPrefix("utm_") }.sorted()
    }

    /// What a surface says after cleaning. The choice lives here so the
    /// Settings page, the menu panel and the Command Bar action cannot drift
    /// apart, and so it can be pinned without a view.
    enum Outcome: Equatable {
        case notAURL
        case unchanged
        case rewritten
        case removed([String])
    }

    static func outcome(for result: Result?, input: String) -> Outcome {
        guard let result else { return .notAURL }
        guard result.removed.isEmpty else { return .removed(result.removed) }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.url == trimmed ? .unchanged : .rewritten
    }

    /// Reads the three stored strings into one value. The global additions
    /// keep the plain comma-separated key they have always used, so nothing
    /// has to be migrated when site rules arrive.
    static func rules(globalNames: String?, siteNames: String?, disabledNames: String?) -> Rules {
        var added = tokens(from: siteNames)
        added[allSites] = customParameters(from: globalNames)
        added = added.filter { !$0.value.isEmpty }
        return Rules(added: added, disabled: tokens(from: disabledNames).filter { !$0.value.isEmpty })
    }

    static func clean(_ text: String, rules: Rules = .none) -> Result? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = components.host,
              components.url != nil else {
            return nil
        }

        // URLComponents validates the link and supplies its host, but can
        // re-encode existing escapes when a query also contains literal Unicode.
        // Slice the original text by scalars so combining marks cannot hide
        // a query delimiter inside a Character.
        let scalars = trimmed.unicodeScalars
        let fragmentStart = scalars.firstIndex(of: "#") ?? scalars.endIndex
        let queryStart = scalars[..<fragmentStart].firstIndex(of: "?")
        let siteKeys = Self.siteKeys(matching: host, rules: rules)
        let matcher = Self.matcher(siteKeys: siteKeys, rules: rules)
        var removed: [String] = []
        let head = String(scalars[..<(queryStart ?? fragmentStart)])
        let cleanedHead = siteKeys.contains("amazon.com")
            ? Self.cleanedAmazonHead(head, matcher: matcher, removed: &removed)
            : head

        var tail = String(scalars[(queryStart ?? fragmentStart)...])
        if let queryStart {
            let query = scalars[scalars.index(after: queryStart)..<fragmentStart]
            var removedFromQuery = false
            let kept = query.split(separator: "&", omittingEmptySubsequences: false)
                .filter { pair in
                    let name = Self.decodedName(ofRawPair: pair)
                    guard matcher.matches(name) else { return true }
                    removedFromQuery = true
                    if !removed.contains(name) { removed.append(name) }
                    return false
                }
            if removedFromQuery {
                let survivingQuery = kept.map { String($0) }.joined(separator: "&")
                tail = (kept.isEmpty ? "" : "?" + survivingQuery) + String(scalars[fragmentStart...])
            }
        }
        guard cleanedHead != head || !removed.isEmpty else {
            return Result(url: trimmed, removed: [])
        }
        return Result(url: cleanedHead + tail, removed: removed)
    }

    /// Takes Amazon's trailing `/ref=…` segment and a product's title out of
    /// the path. The segment is the `ref` parameter spelled into the path, so
    /// it answers to the same rule. The title is not a tracker and is not
    /// reported: when it is all a link carries, the automatic rewrite leaves
    /// the copy alone, as it does any copy with nothing to remove.
    private static func cleanedAmazonHead(_ head: String, matcher: Matcher, removed: inout [String]) -> String {
        let scalars = head.unicodeScalars
        guard let authority = head.range(of: "://"),
              let pathStart = scalars[authority.upperBound...].firstIndex(of: "/") else {
            return head
        }
        let origin = String(scalars[..<pathStart])
        var path = String(scalars[pathStart...])

        if let lastSlash = path.unicodeScalars.lastIndex(of: "/"),
           path.unicodeScalars[path.unicodeScalars.index(after: lastSlash)...].starts(with: "ref=".unicodeScalars),
           matcher.matches("ref") {
            // A path of only the segment keeps its slash.
            path = lastSlash == path.unicodeScalars.startIndex ? "/" : String(path.unicodeScalars[..<lastSlash])
            removed.append("ref")
        }
        if let product = amazonProductPath?.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
           let kept = Range(product.range(at: 1), in: path) {
            path = String(path[kept])
        }
        return origin + path
    }

    static func ruleGroups(rules: Rules) -> [RuleGroup] {
        let sites = Set(hostParameters.keys)
            .union(rules.added.keys)
            .union(rules.disabled.keys)
            .subtracting([allSites])
        let groups = [group(for: allSites, builtIn: globalBuiltInNames, rules: rules)]
            + sites.sorted().map {
                group(for: $0, builtIn: (hostParameters[$0] ?? []).sorted(), rules: rules)
            }
        return groups.filter { !$0.entries.isEmpty }
    }

    /// Comma-separated names, the format the global custom list has always
    /// been stored in.
    static func customParameters(from storedValue: String?) -> Set<String> {
        Set(split(storedValue).map { $0.lowercased() })
    }

    static func storageValue(forNames names: Set<String>) -> String {
        names.sorted().joined(separator: ", ")
    }

    /// `host|name` tokens, used by both the site additions and the switched
    /// off built-ins.
    static func tokens(from storedValue: String?) -> [String: Set<String>] {
        var map: [String: Set<String>] = [:]
        for token in split(storedValue) {
            let parts = token.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = String(parts[1]).lowercased()
            guard !name.isEmpty else { continue }
            map[String(parts[0]).lowercased(), default: []].insert(name)
        }
        return map
    }

    static func storageValue(forTokens map: [String: Set<String>]) -> String {
        map.keys.sorted()
            .flatMap { site in (map[site] ?? []).sorted().map { "\(site)|\($0)" } }
            .joined(separator: ",")
    }

    /// Accepts what someone is likely to paste into the site field — a bare
    /// host, a `www.` host or a whole link — and answers with the host key the
    /// rules are stored under, or nil when it is not a host at all.
    static func siteKey(from text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = value.range(of: "://") {
            value = String(value[scheme.upperBound...])
        }
        if let end = value.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            value = String(value[..<end])
        }
        // `URLComponents.host` carries neither a login nor a port, so a key
        // that kept them would never match the link it was written for.
        if let login = value.lastIndex(of: "@") {
            value = String(value[value.index(after: login)...])
        }
        // Colons inside a bracketed IPv6 host belong to the address.
        let portSearchStart = value.hasPrefix("[")
            ? value.firstIndex(of: "]") ?? value.endIndex
            : value.startIndex
        if let port = value[portSearchStart...].firstIndex(of: ":") {
            value = String(value[..<port])
        }
        if value.hasPrefix("www.") {
            value = String(value.dropFirst(4))
        }
        guard value.contains("."), !value.hasPrefix("."), !value.hasSuffix("."),
              value.allSatisfy({ !$0.isWhitespace && $0 != "|" && $0 != "," }) else {
            return nil
        }
        return value
    }

    /// A name is a single query parameter, so anything a query cannot carry as
    /// one name is rejected rather than silently stored.
    static func parameterName(from text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty,
              value.allSatisfy({ !$0.isWhitespace && $0 != "|" && $0 != "," && $0 != "&" && $0 != "=" }) else {
            return nil
        }
        return value
    }

    /// The name half of one percent-encoded `name=value` pair, decoded so a
    /// tracker a link spells as `%75tm_source` or `%24deep_link` is still the
    /// name the rules list. A pair carrying no `=` is a bare flag, so the
    /// whole pair is its name and is matched like any other: a lone
    /// `utm_source` goes, which is what the link dropping the pair meant. Only
    /// an escape that will not decode at all falls back to the raw text, and
    /// even that is matched as written — `utm_%ff` still answers to the
    /// `utm_` prefix.
    private static func decodedName(ofRawPair pair: String.UnicodeScalarView.SubSequence) -> String {
        let raw = String(pair.prefix { $0 != "=" })
        guard raw.contains("%") else { return raw }
        return raw.removingPercentEncoding ?? raw
    }

    private struct Matcher {
        let names: Set<String>
        let matchesUTMPrefix: Bool

        func matches(_ name: String) -> Bool {
            let normalized = name.lowercased()
            return names.contains(normalized) || (matchesUTMPrefix && normalized.hasPrefix("utm_"))
        }
    }

    private static func matcher(siteKeys: [String], rules: Rules) -> Matcher {
        let disabledGlobally = rules.disabled[allSites] ?? []
        var names = trackedParameters.filter {
            !$0.hasPrefix("utm_") && !disabledGlobally.contains($0)
        }
        names.formUnion((rules.added[allSites] ?? []).subtracting(disabledGlobally))
        for site in siteKeys {
            let disabled = rules.disabled[site] ?? []
            names.formUnion((hostParameters[site] ?? []).filter { !disabled.contains($0) })
            names.formUnion((rules.added[site] ?? []).subtracting(disabled))
        }
        return Matcher(names: names, matchesUTMPrefix: !disabledGlobally.contains(utmWildcard))
    }

    /// Site rules are additive: `open.spotify.com` picks up the `spotify.com`
    /// set, and a host that matches nothing keeps only the global rules. A
    /// regional domain also picks up the set it is an alias of.
    private static func siteKeys(matching host: String, rules: Rules) -> [String] {
        let normalized = host.lowercased()
        func matches(_ site: String) -> Bool {
            !site.isEmpty && (normalized == site || normalized.hasSuffix("." + site))
        }
        let aliased = siteAliases.filter { matches($0.key) }.map(\.value)
        return Set(hostParameters.keys).union(rules.added.keys).union(rules.disabled.keys)
            .filter(matches)
            .union(aliased)
            .sorted()
    }

    private static func group(for site: String, builtIn: [String], rules: Rules) -> RuleGroup {
        let disabled = rules.disabled[site] ?? []
        let added = (rules.added[site] ?? []).subtracting(builtIn)
        let entries = builtIn.map {
            RuleGroup.Entry(name: $0, isBuiltIn: true, isEnabled: !disabled.contains($0))
        } + added.sorted().map {
            RuleGroup.Entry(name: $0, isBuiltIn: false, isEnabled: !disabled.contains($0))
        }
        return RuleGroup(site: site, entries: entries)
    }

    private static func split(_ storedValue: String?) -> [String] {
        (storedValue ?? "")
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Automatic rewrite

    /// Whether the clipboard can be rewritten with a cleaned link without
    /// losing anything the user copied. The rewrite keeps the text, the URL
    /// and a supported link preview. Other types must be text, a link, or an
    /// app's private note about the copy. Refuse a pasteboard that also carries
    /// content of its own: a picture, a file or a
    /// promise to deliver one, a document. A link next to such content is only
    /// its textual fallback (a browser's "Copy Image" also carries the image
    /// URL as text). A copy an app marked concealed or transient is not an
    /// ordinary copy either, and is left alone.
    static func canRewritePasteboard(types: [String]) -> Bool {
        guard !types.isEmpty else { return false }
        return types.allSatisfy(typeSurvivesRewrite)
    }

    private static let plainPasteboardTypes: Set<String> = [
        "public.utf8-plain-text", "public.url", "public.url-name",
        "NSStringPboardType", "NSURLPboardType",
    ]

    /// Marks from the nspasteboard.org convention: concealed is a password
    /// manager handing over a secret, transient is content about to be put
    /// back by whoever placed it.
    private static let untouchablePasteboardTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
    ]

    /// A file being copied or promised, under the names that are not types
    /// the system knows and would otherwise pass as private notes.
    private static let filePasteboardTypes: Set<String> = [
        "NSFilenamesPboardType",
        "com.apple.NSFilePromiseItemMetaData",
        "Apple files promise pasteboard type",
    ]

    private static func typeSurvivesRewrite(_ rawValue: String) -> Bool {
        if plainPasteboardTypes.contains(rawValue) { return true }
        // Safari's preview is declared data, not text or a URL. Its navigation
        // addresses are rewritten separately before the copy is replaced.
        if rawValue == "com.apple.linkpresentation.metadata" { return true }
        if untouchablePasteboardTypes.contains(rawValue) || filePasteboardTypes.contains(rawValue) {
            return false
        }
        // Unknown to the system, or a dynamic stand-in for a legacy name: an
        // app's private note about the copy, such as a browser's source page
        // or a messaging app's reference to the message. The text does not
        // depend on it, and real content always comes with a type of its own
        // next to it.
        guard let type = UTType(rawValue), type.isDeclared else { return true }
        if type.conforms(to: .fileURL) { return false }
        // Formatted text of the same link: dropped by the rewrite, and
        // nothing is lost that the cleaned link does not say better. An RTFD
        // with an attachment would put an attachment mark in the plain text,
        // which is then no longer a link to clean.
        return type.conforms(to: .text) || type.conforms(to: .url)
            || type.conforms(to: .rtfd) || type.conforms(to: .flatRTFD)
    }
}
