// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Parses `vorssaint://run/<action id>` URLs from external callers. Depends
/// on Foundation and the Settings page list; the rules are pinned by
/// `./build.sh --test`.
enum DeepLinkSupport {
    /// One accepted link. `stableKey` matches a CommandBarEntry stable key;
    /// `argument` is an optional number for rows that take one ("brightness").
    struct Request: Equatable {
        let stableKey: String
        let argument: Int?
    }

    static let scheme = "vorssaint"

    private static let runVerb = "run"

    private static let settingsPrefix = "settings."

    /// The scheme and verb are matched case-insensitively. The path supplies the
    /// case-sensitive stable key, and the optional `v` query parameter supplies
    /// the action's integer argument.
    static func parse(_ url: URL) -> Request? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == runVerb else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1 else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let argument = query.first { $0.name == "v" }?.value.flatMap(Int.init)
        return Request(stableKey: parts[0], argument: argument)
    }

    /// Resolves a `settings.<page>` link key against the Settings page list,
    /// for links that need no bar row. The name must match a `SettingsPage`
    /// case exactly, so an unknown page stays an unknown ID and beeps like
    /// one. Whether the page is currently visible is the caller's call.
    static func settingsPage(from key: String) -> SettingsPage? {
        guard key.hasPrefix(settingsPrefix), key.count > settingsPrefix.count else { return nil }
        let name = key.dropFirst(settingsPrefix.count)
        guard !name.contains(".") else { return nil }
        return SettingsPage.allCases.first { String(describing: $0) == name }
    }
}
