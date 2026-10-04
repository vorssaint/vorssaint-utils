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

    static func isMusicApplication(bundleIdentifier: String?, parentBundleIdentifier: String?, category: String?) -> Bool {
        let knownMusicApps: Set<String> = ["com.apple.Music", "com.apple.iTunes", "com.spotify.client"]
        return category == "public.app-category.music"
            || [bundleIdentifier, parentBundleIdentifier].compactMap { $0 }.contains(where: knownMusicApps.contains)
    }

    var reply: [String: Any] {
        var value: [String: Any] = ["pid": pid, "bundleIdentifier": bundleIdentifier, "isMusicApp": isMusicApp,
                                   "isPlaying": isPlaying, "hasTrack": hasTrack]
        value["displayName"] = displayName
        return value
    }

    /// A process identifier from the adapter: a positive whole number, never a Boolean.
    static func decodePID(_ value: Any?) -> Int32? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let pid = Int32(exactly: number.doubleValue), pid > 0 else { return nil }
        return pid
    }

    /// Only the chosen source is listed without a track: it stays chosen for
    /// a moment while it waits for its next one.
    static func decode(_ value: Any?, selectedPID: Int32? = nil) -> [Self] {
        guard let entries = value as? [[String: Any]], entries.count <= 16 else { return [] }
        var sources: [Self] = []
        for entry in entries {
            guard let pid = decodePID(entry["pid"]),
                  let bundle = entry["bundleIdentifier"] as? String, NotchPlaybackCommand.validIdentifier(bundle),
                  let music = entry["isMusicApp"] as? Bool, let playing = entry["isPlaying"] as? Bool,
                  let track = entry["hasTrack"] as? Bool, track || pid == selectedPID,
                  !sources.contains(where: { $0.pid == pid }) else { continue }
            let name = (entry["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            sources.append(Self(pid: pid, bundleIdentifier: bundle, isMusicApp: music, isPlaying: playing, hasTrack: track,
                                displayName: name.flatMap { !$0.isEmpty && $0.utf8.count <= 256 ? $0 : nil }))
        }
        return sources.sorted { $0.pid < $1.pid }
    }

    /// Automatic playback follows music apps unless the user includes other
    /// players. A manual source choice always takes precedence. Paused music
    /// keeps its resume control when nothing eligible is playing.
    static func preferred(in sources: [Self], previousPID: Int32?, systemPID: Int32?, selection: Selection? = nil,
                          includeOtherPlayers: Bool = false) -> Self? {
        let available = sources.filter { $0.pid > 0 && $0.hasTrack }
        // An explicit choice remains controllable while paused, even if another
        // source is playing. Without a track, the automatic order fills in.
        if let selection, let chosen = available.first(where: { $0.selection == selection }) { return chosen }
        let music = available.filter(\.isMusicApp)
        // Registered clients can be playing while macOS still remembers a
        // paused music app as its system player. The opt-in follows their live
        // playback too; ownership only breaks a tie between eligible clients.
        let other = includeOtherPlayers ? available.filter { !$0.isMusicApp } : []
        for candidates in [music.filter(\.isPlaying), other.filter(\.isPlaying), music] {
            if let previous = candidates.first(where: { $0.pid == previousPID }) { return previous }
            if let current = candidates.first(where: { $0.pid == systemPID }) { return current }
            if let first = candidates.sorted(by: { $0.pid < $1.pid }).first { return first }
        }
        return includeOtherPlayers ? available.first { $0.pid == systemPID } : nil
    }
}
