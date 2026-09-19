// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchMusicIdentity: Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let bundle: String?
    let pid: Int32?
    let itemIdentifier: String?

    init(_ playback: NotchPlayback) {
        title = playback.track.title ?? ""
        artist = playback.track.artist ?? ""
        album = playback.track.album ?? ""
        duration = playback.duration.rounded()
        bundle = playback.track.appBundleIdentifier
        pid = playback.track.appPID
        itemIdentifier = playback.itemIdentifier
    }
}

struct NotchLyricLine: Equatable, Identifiable {
    let time: Double
    let text: String
    var id: Double { time }
}

struct NotchLyrics: Equatable {
    let lines: [NotchLyricLine]
    let plain: String
    let instrumental: Bool

    /// Highlighting changes only at lyric boundaries. Rebuild this schedule
    /// when playback or the user's offset changes, with no clock while paused.
    func changeDates(for playback: NotchPlayback, offset: Double, from now: Date) -> [Date] {
        var dates = [now]
        guard playback.isPlaying, playback.hasPosition, playback.rate.isFinite, playback.rate > 0,
              offset.isFinite else { return dates }
        let position = playback.position(at: now)
        for line in lines {
            let target = line.time + offset
            guard target > position, target <= playback.duration else { continue }
            let time = playback.sampledAt.timeIntervalSinceReferenceDate
                + (target - playback.elapsed) / playback.rate
            guard time.isFinite else { continue }
            // Round toward the new verse: inverse rate/date arithmetic must
            // not leave the highlight just before its boundary until the next verse.
            dates.append(Date(timeIntervalSinceReferenceDate: max(now.timeIntervalSinceReferenceDate, time).nextUp))
        }
        // SwiftUI can omit the last entry of a finite explicit timeline.
        // Leave a terminal entry beyond playback so the final verse is delivered,
        // without recurring wakeups or any scheduled work while paused.
        if dates.count > 1 { dates.append(.distantFuture) }
        return dates
    }

    func activeIndex(at position: Double, offset: Double = 0) -> Int? {
        guard position.isFinite, offset.isFinite else { return nil }
        let time = position - offset
        var lower = 0
        var upper = lines.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if lines[middle].time <= time { lower = middle + 1 } else { upper = middle }
        }
        return lower == 0 ? nil : lower - 1
    }
}

/// At most one recording's lyrics and adjustment remain in memory. Hiding the
/// view does not alter this cache; a different or absent playback clears it.
struct NotchLyricsMemory {
    private(set) var track: NotchMusicIdentity?
    private(set) var lyrics: NotchLyrics?
    private(set) var offset = 0.0

    mutating func select(_ next: NotchMusicIdentity?) {
        guard next != track else { return }
        track = next
        lyrics = nil
        offset = 0
    }

    @discardableResult mutating func replace(_ lyrics: NotchLyrics?, for expected: NotchMusicIdentity) -> Bool {
        guard track == expected else { return false }
        self.lyrics = lyrics
        offset = 0
        return true
    }

    mutating func adjustOffset(by amount: Double) {
        guard track != nil, amount.isFinite else { return }
        offset = min(10, max(-10, ((offset + amount) * 4).rounded() / 4))
    }

    mutating func resetOffset() { offset = 0 }
    mutating func clear() { self = Self() }
}

enum NotchLyricsSupport {
    static let maximumBytes = 128 * 1024
    static let maximumLines = 2000

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchLyrics.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchLyricsEnabled)
            && NotchSupport.modules(in: defaults).contains(.music)
    }

    static func onlineEnabled(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchLyricsOnline)
    }

    static func lookupURL(for track: NotchMusicIdentity) -> URL? {
        guard [track.title, track.artist, track.album].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
              track.duration.isFinite, (1...3600).contains(track.duration) else { return nil }
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: track.title),
                          URLQueryItem(name: "artist_name", value: track.artist),
                          URLQueryItem(name: "album_name", value: track.album),
                          URLQueryItem(name: "duration", value: String(track.duration))]
        return url.url
    }

    static func decode(_ data: Data, for track: NotchMusicIdentity) -> NotchLyrics? {
        guard data.count <= maximumBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              equal(object["trackName"] as? String, track.title),
              equal(object["artistName"] as? String, track.artist),
              equal(object["albumName"] as? String, track.album),
              let duration = object["duration"] as? Double, duration.isFinite,
              abs(duration - track.duration) <= 2 else { return nil }
        let plain = (object["plainLyrics"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let instrumental = object["instrumental"] as? Bool == true
        let parsed = parse(object["syncedLyrics"] as? String ?? "", duration: track.duration)
        guard instrumental || !plain.isEmpty || !parsed.isEmpty else { return nil }
        return NotchLyrics(lines: instrumental ? [] : parsed, plain: instrumental ? "" : plain,
                           instrumental: instrumental)
    }

    private static func equal(_ value: String?, _ expected: String) -> Bool {
        guard let value, !expected.isEmpty else { return false }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(expected.trimmingCharacters(in: .whitespacesAndNewlines), options: [.caseInsensitive],
                     locale: Locale(identifier: "en_US_POSIX")) == .orderedSame
    }

    static func parse(_ source: String, duration: Double) -> [NotchLyricLine] {
        guard source.utf8.count <= maximumBytes, duration.isFinite, duration > 0 else { return [] }
        var entries: [NotchLyricLine] = []
        var expandedBytes = 0
        var fileOffset = 0.0
        for rawLine in source.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
            if line.lowercased().hasPrefix("[offset:"), line.hasSuffix("]"),
               let value = Double(line.dropFirst(8).dropLast()), value.isFinite, abs(value) <= 60_000 {
                fileOffset = value / 1000
                continue
            }
            var text = line[...]
            var times: [Double] = []
            while text.first == "[", let end = text.firstIndex(of: "]") {
                let value = text[text.index(after: text.startIndex)..<end]
                guard let time = timestamp(value) else { break }
                guard times.count < maximumLines else { return [] }
                times.append(time)
                text = text[text.index(after: end)...]
            }
            let words = text.trimmingCharacters(in: .whitespaces)
            // Repeated time tags expand one input string into many displayed
            // verses. Bound that expansion before storing or joining any copies.
            let bytesPerEntry = words.utf8.count + (words.isEmpty ? 0 : 1)
            // Empty timed lines end the preceding verse during an instrumental passage.
            for time in times {
                guard entries.count < maximumLines,
                      bytesPerEntry <= maximumBytes - expandedBytes else { return [] }
                expandedBytes += bytesPerEntry
                entries.append(NotchLyricLine(time: time, text: words))
            }
        }
        var adjusted: [(index: Int, line: NotchLyricLine)] = []
        for (index, line) in entries.enumerated() {
            let time = max(0, line.time - fileOffset)
            if time <= duration { adjusted.append((index, NotchLyricLine(time: time, text: line.text))) }
        }
        adjusted.sort { first, second in
            if first.line.time == second.line.time { return first.index < second.index }
            return first.line.time < second.line.time
        }
        var result: [NotchLyricLine] = []
        var groupTime: Double?
        var groupWords: [String] = []
        func finishGroup() {
            guard let groupTime else { return }
            result.append(NotchLyricLine(time: groupTime, text: groupWords.joined(separator: "\n")))
            groupWords.removeAll(keepingCapacity: true)
        }
        for (_, line) in adjusted {
            if line.time != groupTime { finishGroup(); groupTime = line.time }
            if !line.text.isEmpty { groupWords.append(line.text) }
        }
        finishGroup()
        return result.contains(where: { !$0.text.isEmpty }) ? result : []
    }

    private static func timestamp(_ value: Substring) -> Double? {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2, !components[0].isEmpty,
              components[0].allSatisfy(\.isNumber), let minutes = Double(components[0]),
              let seconds = Double(components[1]), seconds.isFinite, (0..<60).contains(seconds),
              components[1].allSatisfy({ $0.isNumber || $0 == "." }),
              minutes <= 10_080 else { return nil }
        return minutes * 60 + seconds
    }
}
