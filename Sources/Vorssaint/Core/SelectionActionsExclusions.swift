// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Websites Selection Actions never offers itself on, matched against the
/// frontmost browser window's current page. One domain per line; "reddit.com"
/// matches "reddit.com" and any subdomain ("old.reddit.com"), the same way a
/// cookie or a hosts-file entry would.
enum SelectionActionsExcludedDomains {
    static func decode(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func encode(_ domains: [String]) -> String {
        domains.joined(separator: "\n")
    }

    static func matches(host: String?, domains: [String]) -> Bool {
        guard let host = host?.lowercased(), !domains.isEmpty else { return false }
        return domains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }
}
