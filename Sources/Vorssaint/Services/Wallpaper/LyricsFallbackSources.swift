// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Extra lyric catalogs for songs the strict lookup misses: regional music
/// (Hindi, Telugu, Tamil, Punjabi and others) whose titles and credits are
/// spelled differently, or written in another script, from one catalog to the
/// next. Matching leans on the recording's length, which no spelling changes,
/// plus a loose name overlap. Every request carries only title and artist.
enum LyricsFallbackSources {
    private static let maximumBytes = 1024 * 1024
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Vorssaint",
            "Referer": "https://music.163.com/"]
        return URLSession(configuration: configuration)
    }()

    /// Tries each source in turn and returns the first synced result.
    static func find(for track: NotchMusicIdentity) async -> NotchLyrics? {
        if let result = await relaxedLRCLIB(track) { return result }
        if let result = await netEase(track) { return result }
        return nil
    }

    // MARK: Matching

    private static func tokens(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 }
        return Set(words)
    }

    /// A name overlap, or an exact-enough length when the scripts differ and
    /// no word can match.
    private static func plausible(title: String, artist: String, duration: Double, for track: NotchMusicIdentity) -> Bool {
        let distance = abs(duration - track.duration)
        guard distance <= 1.6 else { return false }
        let wanted = tokens(track.title).union(tokens(track.artist))
        let found = tokens(title).union(tokens(artist))
        if !wanted.isDisjoint(with: found) { return true }
        return distance <= 1.0
    }

    private static func fetch(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= maximumBytes else { return nil }
        return data
    }

    private static func lyrics(from synced: String, for track: NotchMusicIdentity) -> NotchLyrics? {
        let lines = NotchLyricsSupport.parse(synced, duration: max(track.duration, 60))
        guard lines.count >= 3 else { return nil }
        return NotchLyrics(lines: lines, plain: "", instrumental: false)
    }

    // MARK: LRCLIB, free text

    private static func relaxedLRCLIB(_ track: NotchMusicIdentity) async -> NotchLyrics? {
        let primaryArtist = track.artist.components(separatedBy: CharacterSet(charactersIn: ",&;/")).first ?? track.artist
        let queries = ["\(track.title) \(primaryArtist)", track.title]
        for query in queries where !query.trimmingCharacters(in: .whitespaces).isEmpty {
            var components = URLComponents(string: "https://lrclib.net/api/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            guard let url = components.url, let data = await fetch(url),
                  let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            let best = objects.compactMap { object -> (Double, NotchLyrics)? in
                guard let duration = object["duration"] as? Double,
                      plausible(title: object["trackName"] as? String ?? "", artist: object["artistName"] as? String ?? "",
                                duration: duration, for: track),
                      let synced = object["syncedLyrics"] as? String,
                      let result = lyrics(from: synced, for: track) else { return nil }
                return (abs(duration - track.duration), result)
            }.min { $0.0 < $1.0 }
            if let best { return best.1 }
        }
        return nil
    }

    // MARK: NetEase Cloud Music

    private static func netEase(_ track: NotchMusicIdentity) async -> NotchLyrics? {
        let primaryArtist = track.artist.components(separatedBy: CharacterSet(charactersIn: ",&;/")).first ?? track.artist
        var search = URLComponents(string: "https://music.163.com/api/search/get")!
        search.queryItems = [URLQueryItem(name: "s", value: "\(track.title) \(primaryArtist)"),
                             URLQueryItem(name: "type", value: "1"), URLQueryItem(name: "limit", value: "10")]
        guard let url = search.url, let data = await fetch(url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let songs = (root["result"] as? [String: Any])?["songs"] as? [[String: Any]] else { return nil }
        let candidates = songs.compactMap { song -> (Int, Double)? in
            guard let id = song["id"] as? Int, let ms = song["duration"] as? Double else { return nil }
            let artists = (song["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: " ") ?? ""
            guard plausible(title: song["name"] as? String ?? "", artist: artists, duration: ms / 1000, for: track) else { return nil }
            return (id, abs(ms / 1000 - track.duration))
        }.sorted { $0.1 < $1.1 }.prefix(3)
        for (id, _) in candidates {
            var lyric = URLComponents(string: "https://music.163.com/api/song/lyric")!
            lyric.queryItems = [URLQueryItem(name: "id", value: String(id)), URLQueryItem(name: "lv", value: "1")]
            guard let url = lyric.url, let data = await fetch(url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let synced = (object["lrc"] as? [String: Any])?["lyric"] as? String,
                  let result = lyrics(from: synced, for: track) else { continue }
            return result
        }
        return nil
    }
}
