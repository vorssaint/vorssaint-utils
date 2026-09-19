// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchPlaybackSource: Equatable {
    let pid: Int32
    let bundleIdentifier: String
    let isMusicApp: Bool
    let isPlaying: Bool
    let hasTrack: Bool

    /// Music apps come before browsers, but only among players in the same
    /// state: whatever is actually sounding is what the island is for, and a
    /// music app sitting paused in the background must not leave it blank
    /// while a video plays. Paused music keeps its place once nothing sounds,
    /// so its resume control stays reachable, and an app without a track
    /// never hides anything.
    static func preferred(in sources: [Self], previousPID: Int32?, systemPID: Int32?) -> Self? {
        let available = sources.filter { $0.pid > 0 && $0.hasTrack }
        let music = available.filter(\.isMusicApp)
        // Anything else is taken only where it always was: when the system
        // points at it, or when it is the player already being followed.
        let other = available.filter {
            !$0.isMusicApp && ($0.pid == systemPID || $0.pid == previousPID)
        }
        for candidates in [music.filter(\.isPlaying), other.filter(\.isPlaying), music] {
            if let previous = candidates.first(where: { $0.pid == previousPID }) { return previous }
            if let current = candidates.first(where: { $0.pid == systemPID }) { return current }
            if let first = candidates.sorted(by: { $0.pid < $1.pid }).first { return first }
        }
        return available.first { $0.pid == systemPID }
    }
}
