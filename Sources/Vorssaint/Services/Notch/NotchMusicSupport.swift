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
    /// Nil when the player's commands could not be read.
    var canSkipNext: Bool? = nil
    var canSkipPrevious: Bool? = nil

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
                             canSendCommandsDirectly: canSendCommandsDirectly,
                             canSkipNext: reply.info["canSkipNext"] as? Bool,
                             canSkipPrevious: reply.info["canSkipPrevious"] as? Bool)
    }
}

/// Keeps one decoded cover in memory. Metadata-only updates of the same song
/// retain it; a new song gets a short grace period while its artwork arrives.
/// The deadline never moves with repeated missing-artwork replies.
/// A player can report a new song before replacing the old cover. The same
/// bytes on a new song stay visible, but become its own cover only if no
/// missing-artwork reply follows within that song's grace period.
struct NotchArtworkCache<Artwork> {
    static var transitionDuration: TimeInterval { 1.5 }
    private struct Identity: Equatable {
        let pid: Int32?
        let bundle: String?
        let item: String?
        let title: String?
        let artist: String?
        let album: String?

        init(_ playback: NotchPlayback) {
            pid = playback.track.appPID
            bundle = playback.track.appBundleIdentifier
            item = playback.itemIdentifier
            title = playback.track.title
            artist = playback.track.artist
            album = playback.track.album
        }
    }

    private var identity: Identity?
    private var artworkData: Data?
    private var inheritedUntil: Date?
    private(set) var artwork: Artwork?
    private(set) var expiresAt: Date?

    mutating func update(_ incoming: Artwork?, for playback: NotchPlayback?, now: Date = Date()) {
        guard let playback else { self = Self(); return }
        let next = Identity(playback)
        if identity?.pid != next.pid || identity?.bundle != next.bundle { self = Self() }
        if identity != next || inheritedUntil.map({ now >= $0 }) == true { inheritedUntil = nil }
        if let incoming {
            if artworkData == nil || playback.track.artworkData != artworkData {
                inheritedUntil = nil
            } else if identity != next {
                inheritedUntil = now.addingTimeInterval(Self.transitionDuration)
            }
            artwork = incoming
            identity = next
            artworkData = playback.track.artworkData
            expiresAt = nil
        } else if identity == next, inheritedUntil == nil {
            expiresAt = nil
        } else if artwork != nil {
            if expiresAt == nil { expiresAt = inheritedUntil ?? now.addingTimeInterval(Self.transitionDuration) }
            expire(at: now)
        }
    }

    mutating func expire(at now: Date = Date()) {
        guard let expiresAt, now >= expiresAt else { return }
        self = Self()
    }
}

/// Tells a new song from the updates a playing one keeps sending. A player
/// reports its song again for every pause, seek and cover, can fill in the
/// artist a moment after the title, and a reader that starts or changes source
/// first reports what was already on; none of that is a new song. Each player
/// keeps its own song, so another one standing in between tracks changes
/// nothing, and a song counts once it plays: some players report the next one
/// paused for a moment before it starts.
struct NotchTrackChange {
    private struct Song {
        let title: String
        let artist: String?

        /// A reading without the artist still names the same song.
        func matches(_ other: Song) -> Bool {
            title == other.title && (artist == nil || other.artist == nil || artist == other.artist)
        }
    }

    private var songs: [String: Song] = [:]

    /// Whether `playback` is a player moving on to another song. `first` marks
    /// the first reading since the reader started or changed source, which
    /// only sets where each player is.
    mutating func isNewSong(_ playback: NotchPlayback?, first: Bool) -> Bool {
        guard let playback,
              let player = playback.track.appBundleIdentifier ?? playback.track.appPID.map(String.init),
              let title = Self.cleaned(playback.track.title) else { return false }
        let song = Song(title: title, artist: Self.cleaned(playback.track.artist))
        guard !first else { songs[player] = song; return false }
        guard playback.isPlaying else { return false }
        guard let previous = songs.updateValue(song, forKey: player) else { return false }
        return !previous.matches(song)
    }

    mutating func reset() { songs = [:] }

    private static func cleaned(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
