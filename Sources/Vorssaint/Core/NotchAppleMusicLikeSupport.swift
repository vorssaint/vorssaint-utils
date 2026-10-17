// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The scripts behind the Apple Music heart. Music's scripting dictionary has a
/// `favorited` property on every track, the same one its own heart sets. Each
/// script asks first whether Music is running, since addressing a closed app
/// would open it.
enum NotchAppleMusicLikeSupport {
    static let bundleIdentifier = "com.apple.Music"

    private static func guarded(_ body: String) -> String {
        """
        if application id "\(bundleIdentifier)" is running then
            tell application id "\(bundleIdentifier)"
                \(body)
            end tell
        else
            return "unavailable"
        end if
        """
    }

    static let readScript = guarded("return (favorited of current track) as text")

    static func writeScript(_ liked: Bool) -> String {
        guarded("set favorited of current track to \(liked)\n                return (favorited of current track) as text")
    }

    /// Only a plain true or false is a state; a closed app, a stream without a
    /// library track or anything else leaves it unknown.
    static func state(in output: String) -> Bool? {
        switch output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }
}
