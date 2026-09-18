// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A colour taken from the cover art, deepened so it reads as a halo over the
/// notch's black base. Artwork with no real colour of its own returns nothing,
/// which keeps a grey smudge from appearing behind neutral covers.
struct NotchArtworkTint: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    static func from(red: Double, green: Double, blue: Double) -> NotchArtworkTint? {
        let channels = [red, green, blue]
        guard channels.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
              let highest = channels.max(), let lowest = channels.min(),
              highest > 0.05 else { return nil }
        let range = highest - lowest
        guard range / highest >= 0.12 else { return nil }
        // Stretch the channels onto a fixed range so every cover glows with the
        // same strength instead of following its own exposure.
        let stretched = channels.map { min(1, max(0, ($0 - lowest) / range * 0.86 + 0.06)) }
        return NotchArtworkTint(red: stretched[0], green: stretched[1], blue: stretched[2])
    }
}

struct NotchPlayback: Equatable {
    let track: RadialNowPlayingSnapshot
    let isPlaying: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    let rate: Double
    let sampledAt: Date
    let canSeek: Bool
    var hasPosition: Bool = true
    var itemIdentifier: String? = nil
    var commandContext: NotchPlaybackContext? = nil
    var canSendCommandsDirectly = false

    func position(at date: Date) -> TimeInterval {
        min(duration, max(0, elapsed + (isPlaying ? max(0, date.timeIntervalSince(sampledAt)) * rate : 0)))
    }

    func seekPosition(_ proposed: Double, allowed: Bool? = nil) -> Double? {
        guard allowed ?? canSeek, duration > 0, proposed.isFinite else { return nil }
        return min(duration, max(0, proposed))
    }

    static func decode(_ data: Data, now: Date = Date(), previousArtwork: Data? = nil,
                       commandContext: NotchPlaybackContext? = nil,
                       canSendCommandsDirectly: Bool = false) -> NotchPlayback? {
        guard let reply = RadialNowPlayingSupport.adapterReply(from: data) else { return nil }
        var info = reply.info
        if info["artworkUnchanged"] as? Bool == true {
            info[RadialNowPlayingSupport.artworkDataKey] = previousArtwork
        }
        guard let track = RadialNowPlayingSupport.snapshot(
                info: info, isPlaying: true,
                appBundleIdentifier: reply.displayID, appPID: reply.pid) else { return nil }
        func seconds(_ key: String) -> Double {
            guard let value = (reply.info[key] as? NSNumber)?.doubleValue,
                  value.isFinite, value >= 0 else { return 0 }
            return min(value, 7 * 24 * 60 * 60)
        }
        let rawRate = (reply.info[RadialNowPlayingSupport.playbackRateKey] as? NSNumber)?.doubleValue
        let rate: Double
        if let rawRate, rawRate.isFinite { rate = min(16, max(0, rawRate)) }
        else { rate = 1 }
        return NotchPlayback(track: track,
                             isPlaying: RadialNowPlayingSupport.playbackIsActive(
                                remoteIsPlaying: reply.isPlaying, info: reply.info),
                             elapsed: seconds("kMRMediaRemoteNowPlayingInfoElapsedTime"),
                             duration: seconds("kMRMediaRemoteNowPlayingInfoDuration"),
                             rate: rate, sampledAt: now,
                             canSeek: reply.info["canSeek"] as? Bool == true,
                             hasPosition: (reply.info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)
                                .map { $0.doubleValue.isFinite && $0.doubleValue >= 0 } == true,
                             itemIdentifier: reply.info["itemIdentifier"] as? String,
                             commandContext: commandContext?.pid == track.appPID ? commandContext : nil,
                             canSendCommandsDirectly: canSendCommandsDirectly)
    }
}
