// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Points a copied social post link at an embed fixer: a public service that
/// answers a chat app's link preview with the post's media and text, and
/// sends a browser that opens the link on to the original post.
///
/// The table follows the list kept by seriaati/embed-fixer (`fixes.py`),
/// limited to public hosts, without ad-funded mirrors, and checked to answer
/// a Discord preview request when it was written. Fixers come and go, so a
/// choice is stored only where someone moved away from the default here:
/// a better default in a later version still reaches them.
enum EmbedFixing {
    struct Service: Identifiable, Equatable {
        let id: String
        let name: String
        /// The original site's host, as `Source.base` names it, to the fixer's.
        let hosts: [String: String]
    }

    /// One way a post link is spelled on a site.
    struct Source {
        /// Hosts after a leading `www.` is dropped.
        let hosts: Set<String>
        /// The key into `Service.hosts`.
        let base: String
        /// A subdomain the fixers serve too, such as TikTok's `vm.` short
        /// links, kept in front of the fixed host.
        var subdomain = ""
        /// Only a post is rewritten. A profile, a feed or a search keeps its
        /// own address, as fixers answer those badly or not at all.
        let path: NSRegularExpression

        func matches(host: String, path value: String) -> Bool {
            hosts.contains(host)
                && path.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
        }
    }

    struct Platform: Identifiable {
        let id: String
        let name: String
        let sources: [Source]
        let services: [Service]
        /// Off for a site whose own preview already works, or whose fixers
        /// do not answer reliably.
        var enabledByDefault = true

        var defaultService: Service? { enabledByDefault ? services.first : nil }
    }

    /// Platform id to the service id chosen for it, or `off`. Holds only the
    /// choices that differ from the platform's default.
    typealias Choices = [String: String]

    static let off = "off"

    struct Fix: Equatable {
        let url: String
        let service: String
    }

    static let platforms: [Platform] = [
        Platform(
            id: "x", name: "X / Twitter",
            sources: [
                Source(hosts: ["x.com", "mobile.x.com"], base: "x.com", path: twitterPost),
                Source(hosts: ["twitter.com", "mobile.twitter.com"], base: "twitter.com", path: twitterPost),
            ],
            services: [
                Service(id: "fxembed", name: "FxEmbed",
                        hosts: ["x.com": "fixupx.com", "twitter.com": "fxtwitter.com"]),
                Service(id: "bettertwitfix", name: "BetterTwitFix",
                        hosts: ["x.com": "fixvx.com", "twitter.com": "vxtwitter.com"]),
            ]),
        Platform(
            id: "instagram", name: "Instagram",
            sources: [Source(hosts: ["instagram.com", "m.instagram.com"], base: "instagram.com",
                             path: pattern(#"^/(?:[\w.]+/)?(?:p|reels?|tv)/[\w-]+|^/share/(?:(?:p|reels?)/)?[\w-]+|^/stories/[\w.]+/\d+"#))],
            services: [
                Service(id: "oginstagram", name: "OGInstagram", hosts: ["instagram.com": "oginstagram.com"]),
                Service(id: "instafix", name: "InstaFix", hosts: ["instagram.com": "eeinstagram.com"]),
                Service(id: "instaembedrouter", name: "InstaEmbedRouter", hosts: ["instagram.com": "zzinstagram.com"]),
            ]),
        Platform(
            id: "tiktok", name: "TikTok",
            sources: [
                Source(hosts: ["tiktok.com", "m.tiktok.com"], base: "tiktok.com",
                       path: pattern(#"^/(?:@[\w.-]+/(?:video|photo)/\d+|t/\w+)"#)),
                Source(hosts: ["vm.tiktok.com"], base: "tiktok.com", subdomain: "vm.", path: shortLink),
                Source(hosts: ["vt.tiktok.com"], base: "tiktok.com", subdomain: "vt.", path: shortLink),
            ],
            services: [
                Service(id: "fxtiktok", name: "fxTikTok", hosts: ["tiktok.com": "tnktok.com"]),
                Service(id: "tiktxk", name: "tiktxk", hosts: ["tiktok.com": "tiktxk.com"]),
            ]),
        Platform(
            id: "reddit", name: "Reddit",
            sources: [Source(hosts: ["reddit.com", "old.reddit.com", "new.reddit.com", "m.reddit.com"],
                             base: "reddit.com",
                             path: pattern(#"^/(?:r|u|user)/[^/]+/(?:comments|s)/\w+"#))],
            services: [
                Service(id: "vxreddit", name: "vxReddit", hosts: ["reddit.com": "vxreddit.com"]),
                Service(id: "fixreddit", name: "FixReddit", hosts: ["reddit.com": "rxddit.com"]),
            ]),
        Platform(
            id: "bluesky", name: "Bluesky",
            sources: [Source(hosts: ["bsky.app"], base: "bsky.app",
                             path: pattern(#"^/profile/[^/]+/post/\w+"#))],
            services: [
                Service(id: "fxembed", name: "FxEmbed", hosts: ["bsky.app": "fxbsky.app"]),
                Service(id: "vixbluesky", name: "VixBluesky", hosts: ["bsky.app": "bskx.app"]),
            ]),
        Platform(
            id: "pixiv", name: "Pixiv",
            sources: [Source(hosts: ["pixiv.net"], base: "pixiv.net",
                             path: pattern(#"^/(?:[a-z]{2}/)?artworks/\d+"#))],
            services: [Service(id: "phixiv", name: "Phixiv", hosts: ["pixiv.net": "phixiv.net"])]),
        Platform(
            id: "tumblr", name: "Tumblr",
            sources: [Source(hosts: ["tumblr.com"], base: "tumblr.com", path: pattern(#"^/[\w-]+/\d+"#))],
            services: [Service(id: "fxtumblr", name: "fxtumblr", hosts: ["tumblr.com": "tpmblr.com"])]),
        Platform(
            id: "deviantart", name: "DeviantArt",
            sources: [Source(hosts: ["deviantart.com"], base: "deviantart.com",
                             path: pattern(#"^/[\w.-]+/art/[\w.-]+"#))],
            services: [Service(id: "fixdeviantart", name: "fxdeviantart",
                               hosts: ["deviantart.com": "fixdeviantart.com"])]),
        Platform(
            id: "bilibili", name: "Bilibili",
            sources: [
                Source(hosts: ["bilibili.com", "m.bilibili.com"], base: "bilibili.com",
                       path: pattern(#"^/(?:video|opus)/\w+"#)),
                Source(hosts: ["b23.tv"], base: "b23.tv", path: shortLink),
            ],
            services: [Service(id: "bilifix", name: "BiliFix",
                               hosts: ["bilibili.com": "vxbilibili.com", "b23.tv": "vxb23.tv"])]),
        // Its fixers answered a preview request with only their own name when
        // this was written, so a Threads link is left alone unless asked.
        Platform(
            id: "threads", name: "Threads",
            sources: [Source(hosts: ["threads.net", "threads.com"], base: "threads",
                             path: pattern(#"^/@[\w.]+/post/[\w-]+"#))],
            services: [Service(id: "fixthreads", name: "FixThreads", hosts: ["threads": "fixthreads.net"])],
            enabledByDefault: false),
        // YouTube's own preview plays the video. Koutube is for someone who
        // wants a plain video player in the chat instead.
        Platform(
            id: "youtube", name: "YouTube",
            sources: [
                Source(hosts: ["youtube.com", "m.youtube.com"], base: "youtube.com",
                       path: pattern(#"^/(?:watch$|shorts/[\w-]+)"#)),
                Source(hosts: ["youtu.be"], base: "youtu.be", path: shortLink),
            ],
            services: [Service(id: "koutube", name: "Koutube",
                               hosts: ["youtube.com": "koutube.com", "youtu.be": "koutu.be"])],
            enabledByDefault: false),
    ]

    /// The service a platform's links go to under these choices, or nil when
    /// they are left alone. A stored id this version no longer knows falls
    /// back to the default rather than switching the site off.
    static func service(for platform: Platform, choices: Choices) -> Service? {
        guard let chosen = choices[platform.id] else { return platform.defaultService }
        if chosen == off { return nil }
        return platform.services.first { $0.id == chosen } ?? platform.defaultService
    }

    /// The fixed spelling of a link, or nil when it is not a post this table
    /// covers or its site is switched off. A fixer's own link is not one of
    /// the hosts above, so fixing twice changes nothing.
    static func fix(_ link: String, choices: Choices) -> Fix? {
        guard let components = URLComponents(string: link),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              // The host is swapped by position in the text, which is only the
              // host when no login or port shares the authority with it.
              components.user == nil, components.password == nil, components.port == nil,
              var host = components.host?.lowercased(),
              let authorityStart = link.range(of: "://")?.upperBound else {
            return nil
        }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = components.percentEncodedPath
        for platform in platforms {
            guard let source = platform.sources.first(where: { $0.matches(host: host, path: path) }) else {
                continue
            }
            guard let service = service(for: platform, choices: choices),
                  let fixedHost = service.hosts[source.base] else { return nil }
            let rest = link[authorityStart...]
            let hostEnd = rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? rest.endIndex
            return Fix(url: "https://" + source.subdomain + fixedHost + String(rest[hostEnd...]),
                       service: service.name)
        }
        return nil
    }

    /// A cleaned link with its embed fix applied, when there is one. Nil
    /// choices mean the fixer is switched off.
    static func apply(to result: URLCleaning.Result, choices: Choices?) -> URLCleaning.Result {
        guard let choices, let fixed = fix(result.url, choices: choices) else { return result }
        return URLCleaning.Result(url: fixed.url, removed: result.removed, embedService: fixed.service)
    }

    /// `platform|service` pairs, comma separated.
    static func choices(from storedValue: String?) -> Choices {
        var choices: Choices = [:]
        for token in (storedValue ?? "").split(separator: ",") {
            let parts = token.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let platform = parts[0].trimmingCharacters(in: .whitespaces)
            let service = parts[1].trimmingCharacters(in: .whitespaces)
            guard !platform.isEmpty, !service.isEmpty else { continue }
            choices[platform] = service
        }
        return choices
    }

    /// Stores a choice, dropping it when it is the platform's default.
    static func storageValue(setting serviceID: String, for platform: Platform, in choices: Choices) -> String {
        var choices = choices
        choices[platform.id] = serviceID == (platform.defaultService?.id ?? off) ? nil : serviceID
        return choices.keys.sorted().map { "\($0)|\(choices[$0]!)" }.joined(separator: ",")
    }

    private static func pattern(_ value: String) -> NSRegularExpression {
        // The patterns are literals above, so a bad one is a programming error
        // the first fix of any link would show.
        try! NSRegularExpression(pattern: value)
    }

    private static let twitterPost = pattern(#"^/(?:\w{1,15}|i(?:/web)?)/status(?:es)?/\d+"#)
    private static let shortLink = pattern(#"^/[\w-]+/?$"#)
}
