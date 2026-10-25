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

/// A server-side lookup failure may still have working search results. Network
/// failures and client/rate-limit responses must not fan out into more requests.
enum NotchLyricsDownloadResult {
    case payload(Data), missing, serviceUnavailable, failed
    var data: Data? { if case let .payload(data) = self { return data }; return nil }
    var failed: Bool {
        switch self { case .failed, .serviceUnavailable: return true; default: return false }
    }
    var canSearch: Bool { if case .failed = self { return false }; return true }
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
        let album = catalogAlbum(track.album)
        guard [track.title, track.artist].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 1024 }),
              album.isEmpty || album.utf8.count <= 1024,
              track.duration.isFinite, (1...3600).contains(track.duration) else { return nil }
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        // The release only separates two recordings of one song, and a player
        // that reports none has nothing to send: the request leaves the field
        // out rather than naming a release the service has no record of. A
        // reported album stays inside the same byte bound as the other fields.
        var items = [URLQueryItem(name: "track_name", value: track.title),
                     URLQueryItem(name: "artist_name", value: track.artist)]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        items.append(URLQueryItem(name: "duration", value: String(track.duration)))
        url.queryItems = items
        return url.url
    }

    static func decode(_ data: Data, for track: NotchMusicIdentity) -> NotchLyrics? {
        guard data.count <= maximumBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              equal(object["trackName"] as? String, track.title),
              equal(object["artistName"] as? String, track.artist),
              albumMatches(object["albumName"] as? String, track.album),
              let duration = object["duration"] as? Double, duration.isFinite,
              abs(duration - track.duration) <= 2 else { return nil }
        let plain = (object["plainLyrics"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let instrumental = object["instrumental"] as? Bool == true
        let parsed = parse(object["syncedLyrics"] as? String ?? "", duration: track.duration)
        guard instrumental || !plain.isEmpty || !parsed.isEmpty else { return nil }
        return NotchLyrics(lines: instrumental ? [] : parsed, plain: instrumental ? "" : plain,
                           instrumental: instrumental)
    }

    /// /get can return canonical punctuation and credit separators even for an
    /// exact query. Accept those cosmetic differences without relaxing its album
    /// or recording-length constraints.
    static func decodeCatalogMatch(_ data: Data, for track: NotchMusicIdentity) -> NotchLyrics? {
        guard data.count <= maximumBytes,
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = object["trackName"] as? String,
              let artist = object["artistName"] as? String,
              let album = object["albumName"] as? String,
              !titleKey(track.title).isEmpty, titlesMatch(title, track),
              !key(track.artist).isEmpty, creditsMatch(artist, track.artist),
              track.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || key(catalogAlbum(album)) == key(catalogAlbum(track.album)) else { return nil }
        object["trackName"] = track.title
        object["artistName"] = track.artist
        object["albumName"] = track.album
        guard let canonical = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return decode(canonical, for: track)
    }

    // Search replies contain up to twenty complete lyric records, rather than
    // the single record returned by /get. Bound both the envelope and each entry.
    static let maximumSearchBytes = 1024 * 1024

    struct Candidate {
        let lyrics: NotchLyrics
        let score: Int
        let distance: Double
        let recordID: Int?
        let stableKey: String
    }

    /// Keep the player's exact credits first. Fallbacks name the primary artist
    /// and normalize punctuation/Latin accents and Russian е/ё for catalog search.
    /// Never remove recording qualifiers (live, remix, acoustic, etc.).
    static func searchURLs(for track: NotchMusicIdentity) -> [URL] {
        guard lookupURL(for: track) != nil else { return [] }
        let primary = artistNames(track.artist).first ?? track.artist
        let variants = [(track.title, track.artist), (track.title, primary),
                        (searchText(track.title), searchText(primary))]
        var urls: [URL] = []
        var seen: Set<String> = []
        for (title, artist) in variants {
            guard !title.isEmpty, !artist.isEmpty, seen.insert(title.lowercased() + "\n" + artist.lowercased()).inserted else { continue }
            var url = URLComponents(string: "https://lrclib.net/api/search")!
            url.queryItems = [URLQueryItem(name: "track_name", value: title),
                              URLQueryItem(name: "artist_name", value: artist)]
            if let value = url.url, !urls.contains(value) { urls.append(value) }
        }
        return urls
    }

    static func searchCandidates(_ data: Data, for track: NotchMusicIdentity, durationTolerance: Double = 2,
                                 verifiedArtistAliases: [String] = []) -> [Candidate] {
        let aliases = Set(verifiedArtistAliases.map(key))
        guard data.count <= maximumSearchBytes,
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              objects.count <= 20 else { return [] }
        return objects.compactMap { object in
            guard let title = object["trackName"] as? String,
                  let artist = object["artistName"] as? String,
                  let album = object["albumName"] as? String,
                  titlesMatch(title, track), !titleKey(title).isEmpty,
                  searchCreditsMatch(artist, track, aliases: aliases),
                  recordingKinds(album) == recordingKinds(track.album),
                  let duration = object["duration"] as? Double, duration.isFinite,
                  abs(duration - track.duration) <= durationTolerance,
                  let encoded = try? JSONSerialization.data(withJSONObject: object),
                  encoded.count <= maximumBytes else { return nil }
            // Reuse the bounded parser and payload validation only after recording
            // matching. The strict /get decoder remains unchanged.
            let plain = (object["plainLyrics"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let instrumental = object["instrumental"] as? Bool == true
            let lines = catalogLines(object["syncedLyrics"] as? String ?? "", duration: track.duration)
            guard instrumental || !plain.isEmpty || !lines.isEmpty else { return nil }
            let lyrics = NotchLyrics(lines: instrumental ? [] : lines, plain: instrumental ? "" : plain,
                                     instrumental: instrumental)
            let score = (key(catalogAlbum(album)) == key(catalogAlbum(track.album)) ? 8 : 0)
                + (equal(title, track.title) ? 2 : 0)
                + (creditsMatch(artist, track.artist) || (artistNames(track.artist).count == 1 && aliases.contains(key(artist))) ? 4 : 0)
                + (!lines.isEmpty && !instrumental ? 1 : 0)
            return Candidate(lyrics: lyrics, score: score, distance: abs(duration - track.duration),
                             recordID: (object["id"] as? Int).flatMap { $0 > 0 ? $0 : nil },
                             stableKey: plain + "\n" + lines.map { "\($0.time):\($0.text)" }.joined(separator: "\n"))
        }
    }

    /// A known artist/title with the wrong recording length cannot be repaired
    /// by renaming the artist. Avoid metadata requests in that case.
    static func containsCatalogRecording(_ data: Data, for track: NotchMusicIdentity) -> Bool {
        guard data.count <= maximumSearchBytes,
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], objects.count <= 20 else { return false }
        return objects.contains { object in
            guard let title = object["trackName"] as? String, titlesMatch(title, track),
                  let artist = object["artistName"] as? String,
                  let album = object["albumName"] as? String,
                  recordingKinds(album) == recordingKinds(track.album) else { return false }
            return searchCreditsMatch(artist, track)
        }
    }

    /// Incorrect catalog durations can accompany a full-length LRC. Keep its
    /// plain text instead of presenting a truncated timeline as synchronized.
    private static func catalogLines(_ source: String, duration: Double) -> [NotchLyricLine] {
        let lines = parse(source, duration: max(duration, 604_800))
        guard (lines.last?.time ?? 0) <= duration + 2 else { return [] }
        return lines.filter { $0.time <= duration }
    }

    /// All candidates already passed recording checks. Resolve ties consistently
    /// rather than hiding available lyrics or depending on API response order.
    static func bestLyrics(in candidates: [Candidate]) -> NotchLyrics? {
        candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.recordID != $1.recordID { return ($0.recordID ?? Int.max) < ($1.recordID ?? Int.max) }
            return $0.stableKey < $1.stableKey
        }.first?.lyrics
    }

    /// Featured credits are artist metadata, and Original Mix is the default
    /// version. Preserve all other title qualifiers for candidate validation.
    private static func catalogTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"\s*[\(\[]\s*(?:feat\.?|ft\.?|featuring)\s+[^\)\]]+[\)\]]"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*(?:[\(\[]\s*original mix\s*[\)\]]|[-–—]\s*original mix)\s*$"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func featuredNames(_ title: String) -> [String] {
        let pattern = #"[\(\[]\s*(?:feat\.?|ft\.?|featuring)\s+([^\)\]]+)[\)\]]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: title, range: NSRange(title.startIndex..., in: title)).flatMap { match -> [String] in
            guard let range = Range(match.range(at: 1), in: title) else { return [] }
            return artistNames(String(title[range]))
        }
    }

    private static func titlesMatch(_ title: String, _ track: NotchMusicIdentity) -> Bool {
        guard !titleKey(track.title).isEmpty, titleKey(title) == titleKey(track.title) else { return false }
        let expected = featuredNames(track.title) + Array(artistNames(track.artist).dropFirst())
        return featuredNames(title).allSatisfy { guest in
            expected.contains { name in
                key(guest) == key(name) || (searchText(guest).split(separator: " ").count == 1
                    && searchText(name).split(separator: " ").first.map(String.init) == searchText(guest))
            }
        }
    }

    private static func titleKey(_ title: String) -> String { key(catalogTitle(title)) }

    /// One broader query, only after precise searches have no eligible result.
    /// Query text may omit qualifiers; candidate validation still retains them.
    static func prefersDiscovery(for track: NotchMusicIdentity) -> Bool {
        catalogTitle(track.title) != track.title
    }

    static func discoveryURLs(for track: NotchMusicIdentity) -> [URL] {
        let primary = artistNames(track.artist).first ?? track.artist
        guard !key(primary).isEmpty, lookupURL(for: track) != nil else { return [] }
        let base = catalogTitle(track.title).replacingOccurrences(
            of: #"\s*[\(\[][^\)\]]*(?:mix|edit|version|live|acoustic|instrumental|karaoke)[^\)\]]*[\)\]]"#,
            with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespacesAndNewlines)
        // An artist-only full-text query can discover word-boundary variants
        // without a language-specific word splitter or song-name mapping.
        var url = URLComponents(string: "https://lrclib.net/api/search")!
        url.queryItems = base == track.title ? [URLQueryItem(name: "q", value: primary)]
            : [URLQueryItem(name: "track_name", value: base), URLQueryItem(name: "artist_name", value: primary)]
        return url.url.map { [$0] } ?? []
    }

    private static func folded(_ text: String) -> String {
        // Fold Latin accents without turning Cyrillic й into и.
        let latin = text.precomposedStringWithCanonicalMapping.map { character -> String in
            let value = String(character)
            return character.unicodeScalars.allSatisfy { $0.value < 0x0250 }
                ? value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                : value.lowercased()
        }.joined()
        return latin.replacingOccurrences(of: "ё", with: "е")
    }

    private static func searchText(_ text: String) -> String {
        folded(text).components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func key(_ text: String) -> String {
        searchText(text).replacingOccurrences(of: " ", with: "")
    }

    private static func artistNames(_ text: String) -> [String] {
        let separated = text.replacingOccurrences(
            of: #"[,;，、]|\s+[/&•]\s+|\s+(?:feat\.?|ft\.?|featuring)\s+"#,
            with: "\n", options: [.regularExpression, .caseInsensitive])
        return separated.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^группа\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        }.filter { !$0.isEmpty }
    }

    /// Catalog credits may omit contributors or reorder known names, but
    /// matching one performer does not establish an unrelated collaboration.
    private static func searchCreditsMatch(_ artist: String, _ track: NotchMusicIdentity,
                                           aliases: Set<String> = []) -> Bool {
        guard let primary = artistNames(track.artist).first else { return false }
        if key(artist) == key(track.artist) || aliases.contains(key(artist)) { return true }
        let names = Set(artistNames(artist).map(key))
        let expected = Set((artistNames(track.artist) + featuredNames(track.title)).map(key)).union(aliases)
        return (names.contains(key(primary)) || !names.isDisjoint(with: aliases)) && names.isSubset(of: expected)
    }

    private static func creditsMatch(_ first: String, _ second: String) -> Bool {
        key(first) == key(second) || Set(artistNames(first).map(key)) == Set(artistNames(second).map(key))
    }

    private static func recordingKinds(_ album: String) -> Set<String> {
        let words = Set(searchText(album).components(separatedBy: " "))
        return Set(["live", "concert", "концерт", "концертная", "remix", "remixes", "ремикс",
                    "acoustic", "акустика", "instrumental", "karaoke"].filter { words.contains($0) })
    }

    /// Apple Music names singles and EPs "Title - Single" and "Title - EP",
    /// while LRCLIB stores the release title alone. Other qualifiers still count.
    static func catalogAlbum(_ album: String) -> String {
        let trimmed = album.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" - Single", " - EP"] {
            guard let range = trimmed.range(of: suffix, options: [.anchored, .backwards, .caseInsensitive]),
                  range.lowerBound > trimmed.startIndex else { continue }
            return String(trimmed[..<range.lowerBound])
        }
        return trimmed
    }

    /// A player that reports no album cannot disagree about one: the request
    /// leaves the field out and the service answers with the first record it
    /// holds for that title, artist and length, so the reply names a release
    /// the track never mentioned. A release both sides do carry still has to
    /// be the same one.
    private static func albumMatches(_ value: String?, _ expected: String) -> Bool {
        guard !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return equal(value.map(catalogAlbum), catalogAlbum(expected))
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

extension NotchLyricsSupport {
    struct ArtistIdentity {
        let id: UUID
        let names: [String]
        let queryNames: [String]
    }

    static func artistCacheKey(for track: NotchMusicIdentity) -> String {
        key(artistNames(track.artist).first ?? track.artist) + "|" + key(catalogAlbum(track.album))
    }

    private static func quotedQuery(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func artistIdentityURL(for track: NotchMusicIdentity) -> URL? {
        guard let primary = artistNames(track.artist).first, !key(primary).isEmpty, primary.utf8.count <= 256 else { return nil }
        var url = URLComponents(string: "https://musicbrainz.org/ws/2/artist/")!
        let phrase = quotedQuery(primary)
        url.queryItems = [URLQueryItem(name: "query", value: "artist:\(phrase) OR alias:\(phrase)"),
                          URLQueryItem(name: "fmt", value: "json"), URLQueryItem(name: "limit", value: "5")]
        return url.url
    }

    /// Exact name/alias membership identifies candidates; search scores alone
    /// cannot establish identity. Reject truncated or overly broad results.
    static func artistIdentities(_ data: Data, for track: NotchMusicIdentity, allowTruncated: Bool = false) -> [ArtistIdentity] {
        guard data.count <= maximumBytes, let primary = artistNames(track.artist).first, !key(primary).isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let count = object["count"] as? Int, count >= 0, (count <= 5 || allowTruncated),
              let artists = object["artists"] as? [[String: Any]], artists.count <= 5 else { return [] }
        var identities: [UUID: ArtistIdentity] = [:]
        for artist in artists {
            guard let name = artist["name"] as? String, name.utf8.count <= 256,
                  let rawID = artist["id"] as? String, let id = UUID(uuidString: rawID) else { continue }
            let aliases = artist["aliases"] as? [[String: Any]] ?? []
            guard aliases.count <= 100 else { continue }
            let names = ([name, artist["sort-name"] as? String ?? ""] + aliases.compactMap { $0["name"] as? String })
                .filter { !$0.isEmpty && $0.utf8.count <= 256 }
            guard names.contains(where: { key($0) == key(primary) }) else { continue }
            let english = aliases.filter { ($0["locale"] as? String) == "en" && ($0["primary"] as? Bool) == true }
                .compactMap { $0["name"] as? String }.sorted()
            var queryNames: [String] = []
            for value in english + [name] where value.utf8.count <= 256 && key(value) != key(primary) {
                if !queryNames.contains(where: { key($0) == key(value) }) { queryNames.append(value) }
            }
            identities[id] = ArtistIdentity(id: id, names: names, queryNames: Array(queryNames.prefix(2)))
        }
        return identities.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    static func artistRecordingURL(for track: NotchMusicIdentity, candidates: [ArtistIdentity]) -> URL? {
        guard candidates.count == 1, track.title.utf8.count <= 256 else { return nil }
        var url = URLComponents(string: "https://musicbrainz.org/ws/2/recording/")!
        url.queryItems = [URLQueryItem(name: "query", value: "recording:\(quotedQuery(catalogTitle(track.title))) AND arid:\(candidates[0].id.uuidString.lowercased())"),
                          URLQueryItem(name: "fmt", value: "json"), URLQueryItem(name: "limit", value: "5")]
        return url.url
    }

    static func recordingArtistIdentity(_ data: Data, for track: NotchMusicIdentity,
                                        candidates: [ArtistIdentity]) -> ArtistIdentity? {
        guard candidates.count == 1, data.count <= maximumBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let count = object["count"] as? Int, count >= 0,
              let recordings = object["recordings"] as? [[String: Any]], recordings.count <= 5 else { return nil }
        let source = candidates[0]
        var names = source.names
        var queries = source.queryNames
        for recording in recordings {
            guard let title = recording["title"] as? String, titlesMatch(title, track),
                  let length = recording["length"] as? Double, length.isFinite,
                  abs(length / 1000 - track.duration) <= 2,
                  let credits = recording["artist-credit"] as? [[String: Any]], credits.count == 1,
                  let artist = credits[0]["artist"] as? [String: Any],
                  let id = artist["id"] as? String, UUID(uuidString: id) == source.id,
                  let credited = credits[0]["name"] as? String, !key(credited).isEmpty, credited.utf8.count <= 256 else { continue }
            if !names.contains(where: { key($0) == key(credited) }) { names.append(credited) }
            if key(credited) != key(artistNames(track.artist).first ?? track.artist),
               !queries.contains(where: { key($0) == key(credited) }) { queries.append(credited) }
        }
        guard !queries.isEmpty else { return nil }
        return ArtistIdentity(id: source.id, names: names, queryNames: Array(queries.prefix(2)))
    }

    static func artistAlbumURL(for track: NotchMusicIdentity) -> URL? {
        let album = catalogAlbum(track.album).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !album.isEmpty, album.utf8.count <= 256 else { return nil }
        var url = URLComponents(string: "https://musicbrainz.org/ws/2/release-group/")!
        url.queryItems = [URLQueryItem(name: "query", value: quotedQuery(album)),
                          URLQueryItem(name: "fmt", value: "json"), URLQueryItem(name: "limit", value: "5")]
        return url.url
    }

    /// An ambiguous short artist name needs an independently matching album
    /// credited to exactly one of its identities. Never choose by API order.
    static func artistIdentity(_ data: Data, for track: NotchMusicIdentity, candidates: [ArtistIdentity]) -> ArtistIdentity? {
        guard data.count <= maximumBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let count = object["count"] as? Int, count <= 5,
              let groups = object["release-groups"] as? [[String: Any]], groups.count <= 5 else { return nil }
        var identities: [UUID: ArtistIdentity] = [:]
        for group in groups {
            guard let title = group["title"] as? String, key(title) == key(catalogAlbum(track.album)),
                  let credits = group["artist-credit"] as? [[String: Any]], credits.count == 1,
                  let artist = credits[0]["artist"] as? [String: Any],
                  let rawID = artist["id"] as? String, let id = UUID(uuidString: rawID) else { continue }
            let nested = try? JSONSerialization.data(withJSONObject: ["count": 1, "artists": [artist]])
            if let identity = candidates.first(where: { $0.id == id })
                ?? nested.flatMap({ artistIdentities($0, for: track).first }) {
                identities[id] = identity
            }
        }
        guard identities.count == 1 else { return nil }
        return identities.values.first
    }

    static func aliasSearchURLs(for track: NotchMusicIdentity, identity: ArtistIdentity) -> [URL] {
        identity.queryNames.compactMap { name in
            var url = URLComponents(string: "https://lrclib.net/api/search")!
            url.queryItems = [URLQueryItem(name: "track_name", value: track.title),
                              URLQueryItem(name: "artist_name", value: name)]
            return url.url
        }
    }
}
