// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The links a recognised song opens, kept apart so they can be checked without a network or an app.
enum MusicRecognitionLinks {
    private static func encoded(_ text: String) -> String? {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
    }

    static func spotifyApp(_ query: String) -> URL? {
        encoded(query).flatMap { URL(string: "spotify:search:\($0)") }
    }

    static func spotifyWeb(_ query: String) -> URL? {
        encoded(query).flatMap { URL(string: "https://open.spotify.com/search/\($0)") }
    }

    static func youTube(_ query: String) -> URL? {
        encoded(query).flatMap { URL(string: "https://www.youtube.com/results?search_query=\($0)") }
    }

    /// The Chrome profile folder whose name or signed-in account matches
    /// `wanted`, ignoring case. Nil when nothing is chosen or nothing matches,
    /// so Chrome opens the profile it last used.
    static func chromeProfileDirectory(matching wanted: String, localState: Data?) -> String? {
        let wanted = wanted.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty, let localState,
              let object = try? JSONSerialization.jsonObject(with: localState) as? [String: Any],
              let profiles = (object["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]]
        else { return nil }
        let match = { (key: String) in
            profiles.first { _, info in (info[key] as? String)?.lowercased() == wanted }?.key
        }
        // The signed-in account names one person; a display name may be shared.
        return match("user_name") ?? match("name")
    }
}
