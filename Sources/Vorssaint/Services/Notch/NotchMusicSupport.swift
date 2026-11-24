// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A colour taken from the cover art, deepened so it reads as a halo over the
/// notch's black base. Artwork with no real colour of its own returns nothing,
/// which keeps a grey smudge from appearing behind neutral covers. The one
/// exception is `neutral`, which carries only a grey field for the bars.
struct NotchArtworkTint: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    /// How vivid the cover is, from 0 to 1: how colourful and bright its
    /// most colourful part is, raised by strong light and dark contrast. Hot
    /// pink on black is vivid; a pale sky is not. See `vibrance(of:)`.
    var vibrance: Double = 0

    func with(vibrance: Double) -> NotchArtworkTint {
        var tint = self
        tint.vibrance = min(1, max(0, vibrance))
        return tint
    }

    /// The cover blurred down to `fieldColumns` by `fieldRows` colours, red,
    /// green and blue in turn, top row first. The phone's island cuts its
    /// bars out of the cover blurred this way, not out of one colour: a cover
    /// red on the left and cyan on the right gives bars that run from red to
    /// cyan, and the dark foot of a cover darkens the foot of every bar.
    /// Empty when the cover is too grey to give the bars any colour, unless
    /// greys were asked for: see `neutral(field:)`.
    var field: [Double] = []
    /// A cover with no colour at all. It has no halo colour and says so, so
    /// only the bars use it: they run from the darker to the lighter grey of
    /// the cover, as the phone's do, instead of one flat white.
    var isNeutral = false
    static let fieldColumns = 4
    static let fieldRows = 3

    static func neutral(field: [Double]) -> NotchArtworkTint {
        NotchArtworkTint(red: 1, green: 1, blue: 1, isNeutral: true).with(field: field)
    }

    func with(field: [Double]) -> NotchArtworkTint {
        var tint = self
        tint.field = field
        return tint
    }

    /// How bright the music bars and controls are: full on a vivid cover,
    /// a little under it on a soft one.
    var barBrightness: Double { 0.86 + 0.14 * vibrance }

    /// The colour the bars' field comes to as a whole, at the bars' brightness,
    /// for the controls beside them. Nil without a field. The halo's colour is
    /// stretched to full strength, which would turn a faint cast into pure blue.
    var fieldControlColor: (red: Double, green: Double, blue: Double)? {
        guard !field.isEmpty, field.count.isMultiple(of: 3) else { return nil }
        var sum = [0.0, 0.0, 0.0]
        for (index, channel) in field.enumerated() { sum[index % 3] += channel }
        guard let highest = sum.max(), highest > 0 else { return nil }
        let lift = barBrightness / highest
        return (sum[0] * lift, sum[1] * lift, sum[2] * lift)
    }

    /// A cover's field from `side` by `side` of its pixels, top row first.
    /// Each colour is a wide Gaussian average around its point, a fifth of
    /// the cover across, over the middle four fifths of the cover's width
    /// and three fifths of its height: the edges of a cover are mostly
    /// border and lettering. Matched against the phone's bars over a whole
    /// song, this blur and this crop follow them closely in colour and in light.
    static func field(of pixels: [(red: Double, green: Double, blue: Double)], side: Int,
                      vibrance: Double, greyed: Bool = false) -> [Double] {
        guard side > 0, pixels.count == side * side else { return [] }
        let spread = 0.2
        var cells: [(red: Double, green: Double, blue: Double)] = []
        for row in 0..<fieldRows {
            let y = 0.2 + 0.6 * Double(row) / Double(max(1, fieldRows - 1))
            for column in 0..<fieldColumns {
                let x = 0.1 + 0.8 * Double(column) / Double(max(1, fieldColumns - 1))
                var sum = (red: 0.0, green: 0.0, blue: 0.0), total = 0.0
                for (index, pixel) in pixels.enumerated() {
                    let dx = (Double(index % side) + 0.5) / Double(side) - x
                    let dy = (Double(index / side) + 0.5) / Double(side) - y
                    let weight = exp(-(dx * dx + dy * dy) / (2 * spread * spread))
                    sum.red += pixel.red * weight; sum.green += pixel.green * weight; sum.blue += pixel.blue * weight
                    total += weight
                }
                cells.append((sum.red / total, sum.green / total, sum.blue / total))
            }
        }
        return lit(cells, vibrance: vibrance, greyed: greyed)
    }

    /// Lifts a field so the bars read on the black island: its brightest
    /// colour is raised to near full and its darkest kept above a third,
    /// while the light and dark between them keep their order. A vivid cover
    /// is given a little more colour, so hot pink stays hot after the blur
    /// greys it. A field with too little colour anywhere is no field, unless
    /// `greyed` asks for its own light and dark alone, as greys.
    static func lit(_ cells: [(red: Double, green: Double, blue: Double)], vibrance: Double,
                    greyed: Bool = false) -> [Double] {
        let hsb = cells.map { cell -> (hue: Double, saturation: Double, brightness: Double) in
            let highest = max(cell.red, cell.green, cell.blue), lowest = min(cell.red, cell.green, cell.blue)
            let saturation = highest > 0 ? (highest - lowest) / highest : 0
            var hue = 0.0
            if highest > lowest {
                let range = highest - lowest
                if highest == cell.red { hue = (cell.green - cell.blue) / range }
                else if highest == cell.green { hue = 2 + (cell.blue - cell.red) / range }
                else { hue = 4 + (cell.red - cell.green) / range }
                hue = (hue / 6).truncatingRemainder(dividingBy: 1)
                if hue < 0 { hue += 1 }
            }
            return (hue, saturation, highest)
        }
        guard let brightest = hsb.map(\.brightness).max(), brightest > 0 else { return [] }
        let gain = min(4, 0.92 / brightest)
        guard hsb.contains(where: { $0.saturation >= 0.15 && $0.brightness >= 0.1 }) else {
            guard greyed else { return [] }
            // With no hue to lift, the cover's light and dark are all the bars
            // have. Stretch that spread, top to foot and side to side, over
            // the readable range, so a dim cover still shades its bars as
            // richly as a bright one; a cover that is the same grey
            // throughout keeps one flat grey.
            let lowest = hsb.map(\.brightness).min() ?? 0
            let spread = brightest - lowest
            return hsb.flatMap { cell -> [Double] in
                let light = spread >= 0.04
                    ? 0.35 + 0.6 * (cell.brightness - lowest) / spread
                    : 0.35 + 0.65 * min(1, cell.brightness * gain)
                return [light, light, light]
            }
        }
        let boost = 1 + 0.4 * min(1, max(0, vibrance))
        return hsb.flatMap { cell -> [Double] in
            let brightness = 0.35 + 0.65 * min(1, cell.brightness * gain)
            let saturation = min(1, cell.saturation * boost)
            return rgb(hue: cell.hue, saturation: saturation, brightness: brightness)
        }
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> [Double] {
        let sector = hue * 6, index = Int(sector) % 6, fraction = sector - Double(Int(sector))
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        switch index {
        case 0: return [brightness, t, p]
        case 1: return [q, brightness, p]
        case 2: return [p, brightness, t]
        case 3: return [p, q, brightness]
        case 4: return [t, p, brightness]
        default: return [brightness, p, q]
        }
    }

    /// A cover's vividness from a few of its pixels. The colour is the
    /// average of its most colourful sixth; the contrast is how far its
    /// pixels spread between light and dark.
    static func vibrance(of pixels: [(red: Double, green: Double, blue: Double)]) -> Double {
        guard !pixels.isEmpty else { return 0 }
        let scores = pixels.map { pixel -> Double in
            let highest = max(pixel.red, pixel.green, pixel.blue)
            let lowest = min(pixel.red, pixel.green, pixel.blue)
            return highest > 0 ? (highest - lowest) / highest * highest : 0
        }.sorted(by: >)
        let top = scores.prefix(max(1, pixels.count / 6))
        let colour = top.reduce(0, +) / Double(top.count)
        let lights = pixels.map { 0.2126 * $0.red + 0.7152 * $0.green + 0.0722 * $0.blue }
        let mean = lights.reduce(0, +) / Double(lights.count)
        let spread = (lights.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lights.count)).squareRoot()
        return min(1, max(0, colour * (0.7 + 1.5 * spread)))
    }

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

    /// The colour a mostly grey cover still has: the most colourful sixth
    /// of its pixels, averaged. A red jacket on a white slope averages away
    /// into grey, and the island would show plain white for a cover with
    /// colour in it. A cover with no colour at all still gives none; its bars
    /// take the greys of `field(of:side:vibrance:greyed:)` instead.
    static func accent(in pixels: [(red: Double, green: Double, blue: Double)]) -> NotchArtworkTint? {
        let colourful = pixels.compactMap { pixel -> (score: Double, pixel: (red: Double, green: Double, blue: Double))? in
            let highest = max(pixel.red, pixel.green, pixel.blue)
            let lowest = min(pixel.red, pixel.green, pixel.blue)
            guard highest > 0.15 else { return nil }
            let saturation = (highest - lowest) / highest
            guard saturation >= 0.2 else { return nil }
            return (saturation * highest, pixel)
        }.sorted { $0.score > $1.score }
        let picked = colourful.prefix(max(1, pixels.count / 6))
        guard !picked.isEmpty else { return nil }
        let count = Double(picked.count)
        return from(red: picked.map(\.pixel.red).reduce(0, +) / count,
                    green: picked.map(\.pixel.green).reduce(0, +) / count,
                    blue: picked.map(\.pixel.blue).reduce(0, +) / count)
    }
}

struct NotchPlayback: Equatable {
    /// How long a song stays shown after a reading finds nothing playing,
    /// which a player moving on to its next song can report for a moment.
    static let gapGracePeriod: TimeInterval = 1.5

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

    /// The same recording from the same player. Readings without a name
    /// share no recording, so only their player tells them apart.
    static func sameRecording(_ first: NotchPlayback?, _ second: NotchPlayback?) -> Bool {
        first?.commandContext == second?.commandContext && first?.track.appPID == second?.track.appPID
    }

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
        guard let playback, let player = Self.player(of: playback), let song = Self.song(of: playback) else { return false }
        guard !first else { songs[player] = song; return false }
        guard playback.isPlaying else { return false }
        guard let previous = songs.updateValue(song, forKey: player) else { return false }
        return !previous.matches(song)
    }

    /// Whether `next`, read after `current`, can be a player between songs:
    /// nothing playing, or a song that is not playing and is not the one that
    /// played, such as another player's paused song standing in or the next
    /// song reported before it starts. The same song paused is a pause. So is
    /// another player's song while the player that played still lists a song
    /// in `sources`, since that player was paused and automatic playback moved
    /// to the other.
    static func isBetweenSongs(_ next: NotchPlayback?, after current: NotchPlayback,
                               sources: [NotchPlaybackSource] = []) -> Bool {
        guard let next else { return true }
        guard current.isPlaying, !next.isPlaying else { return false }
        guard let player = Self.player(of: next), player == Self.player(of: current) else {
            return !sources.contains { $0.pid == current.track.appPID && $0.hasTrack }
        }
        guard let song = Self.song(of: next), let played = Self.song(of: current) else { return true }
        return !song.matches(played)
    }

    mutating func reset() { songs = [:] }

    private static func player(of playback: NotchPlayback) -> String? {
        playback.track.appBundleIdentifier ?? playback.track.appPID.map(String.init)
    }

    private static func song(of playback: NotchPlayback) -> Song? {
        cleaned(playback.track.title).map { Song(title: $0, artist: cleaned(playback.track.artist)) }
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
