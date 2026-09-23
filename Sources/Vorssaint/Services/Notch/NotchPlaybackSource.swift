// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchPlaybackSource: Equatable {
    struct Selection: Equatable {
        let pid: Int32
        let bundleIdentifier: String

        var isValid: Bool { pid > 0 && NotchPlaybackCommand.validIdentifier(bundleIdentifier) }
    }

    let pid: Int32
    let bundleIdentifier: String
    let isMusicApp: Bool
    let isPlaying: Bool
    let hasTrack: Bool
    var displayName: String? = nil

    var selection: Selection { Selection(pid: pid, bundleIdentifier: bundleIdentifier) }

    var reply: [String: Any] {
        var value: [String: Any] = ["pid": pid, "bundleIdentifier": bundleIdentifier, "isMusicApp": isMusicApp,
                                   "isPlaying": isPlaying, "hasTrack": hasTrack]
        value["displayName"] = displayName
        return value
    }

    static func decode(_ value: Any?) -> [Self] {
        guard let entries = value as? [[String: Any]], entries.count <= 16 else { return [] }
        var sources: [Self] = []
        for entry in entries {
            guard let number = entry["pid"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let pid = Int32(exactly: number.doubleValue), pid > 0,
                  let bundle = entry["bundleIdentifier"] as? String, NotchPlaybackCommand.validIdentifier(bundle),
                  let music = entry["isMusicApp"] as? Bool, let playing = entry["isPlaying"] as? Bool,
                  entry["hasTrack"] as? Bool == true, !sources.contains(where: { $0.pid == pid }) else { continue }
            let name = (entry["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            sources.append(Self(pid: pid, bundleIdentifier: bundle, isMusicApp: music, isPlaying: playing, hasTrack: true,
                                displayName: name.flatMap { !$0.isEmpty && $0.utf8.count <= 256 ? $0 : nil }))
        }
        return sources.sorted { $0.pid < $1.pid }
    }

    /// Music apps come before browsers, but only among players in the same
    /// state: whatever is actually sounding is what the island is for, and a
    /// music app sitting paused in the background must not leave it blank
    /// while a video plays. Paused music keeps its place once nothing sounds,
    /// so its resume control stays reachable, and an app without a track
    /// never hides anything.
    static func preferred(in sources: [Self], previousPID: Int32?, systemPID: Int32?, selection: Selection? = nil) -> Self? {
        let available = sources.filter { $0.pid > 0 && $0.hasTrack }
        // An explicit choice remains controllable while paused, even if another
        // source is playing. Losing its track releases the choice naturally.
        if let selection, let chosen = available.first(where: { $0.selection == selection }) { return chosen }
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
