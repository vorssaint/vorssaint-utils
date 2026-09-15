// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchPlaybackSource: Equatable {
    let pid: Int32
    let bundleIdentifier: String
    let isMusicApp: Bool
    let isPlaying: Bool
    let hasTrack: Bool

    /// Keep paused music reachable while its app still owns a track. Opening a
    /// music app without a track must not hide a browser's playback.
    static func preferred(in sources: [Self], previousPID: Int32?, systemPID: Int32?) -> Self? {
        let available = sources.filter { $0.pid > 0 && $0.hasTrack }
        let music = available.filter(\.isMusicApp)
        let playing = music.filter(\.isPlaying)
        for candidates in [playing, music] {
            if let previous = candidates.first(where: { $0.pid == previousPID }) { return previous }
            if let current = candidates.first(where: { $0.pid == systemPID }) { return current }
            if let first = candidates.sorted(by: { $0.pid < $1.pid }).first { return first }
        }
        return available.first { $0.pid == systemPID }
    }
}
