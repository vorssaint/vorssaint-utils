// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os.log

/// Parses `vorssaint://run/<action id>` URLs from external callers. The
/// rules are pinned by `./build.sh --test`.
enum DeepLinkSupport {
    /// A link that runs nothing only beeps, so the reason goes here where
    /// whoever wrote the link can find it.
    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint", category: "deeplink")

    /// One accepted link. `stableKey` matches a CommandBarEntry stable key;
    /// `argument` is an optional number for rows that take one ("brightness").
    struct Request: Equatable {
        let stableKey: String
        let argument: Int?
    }

    static let scheme = "vorssaint"

    private static let runVerb = "run"

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
}
