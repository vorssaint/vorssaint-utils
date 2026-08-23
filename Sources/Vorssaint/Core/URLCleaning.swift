// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

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
        // `%24…`, but only the decoded spelling is listed: names arrive here
        // from `URLComponents.queryItems`, which has already decoded them.
        // ClearURLs lists both because it matches the raw query with regex.
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
            "shareRedId", "share_id", "exSource", "app_version", "app_platform",
            "apptime", "appuid",
        ],
    ]

    static func cleanedString(from text: String, customParameters: Set<String> = []) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = components.host else {
            return nil
        }

        if let items = components.queryItems {
            let hostParameters = Self.hostParameters(for: host)
            let kept = items.filter { item in
                !shouldRemove(parameter: item.name,
                              customParameters: customParameters,
                              hostParameters: hostParameters)
            }
            components.queryItems = kept.isEmpty ? nil : kept
        }

        return components.url?.absoluteString
    }

    static func customParameters(from storedValue: String?) -> Set<String> {
        Set((storedValue ?? "")
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }

    /// Site rules are additive: `open.spotify.com` picks up the `spotify.com`
    /// set, and a host that matches nothing keeps only the global rules.
    private static func hostParameters(for host: String) -> Set<String> {
        let normalized = host.lowercased()
        var names: Set<String> = []
        for (suffix, parameters) in hostParameters
        where normalized == suffix || normalized.hasSuffix("." + suffix) {
            names.formUnion(parameters)
        }
        return Set(names.map { $0.lowercased() })
    }

    private static func shouldRemove(parameter name: String,
                                     customParameters: Set<String>,
                                     hostParameters: Set<String>) -> Bool {
        let normalized = name.lowercased()
        return trackedParameters.contains(normalized)
            || normalized.hasPrefix("utm_")
            || hostParameters.contains(normalized)
            || customParameters.contains(normalized)
    }
}
