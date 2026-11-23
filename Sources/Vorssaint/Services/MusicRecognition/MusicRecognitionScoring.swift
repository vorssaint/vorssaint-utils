// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A song recognised from what the Mac or the room is playing.
struct RecognisedSong: Equatable, Identifiable {
    let title: String
    let artist: String
    let artworkURL: URL?

    var id: String { MusicRecognitionScoring.key(title: title, artist: artist) }
    /// What the song is searched for by, in Spotify and on YouTube.
    var query: String { [title, artist].filter { !$0.isEmpty }.joined(separator: " ") }
}

/// Another song close to what was heard, as Google lists them under its best guess.
struct NearbyMatch: Equatable, Identifiable {
    let song: RecognisedSong
    /// The match score when an engine heard this song; nil for another version found by search.
    let percent: Int?
    var id: String { song.id }
}

/// Gathers every engine's answers and turns them into a score per song: the
/// percentage shown beside it. A song heard in more windows of sound, by more
/// engines, and lined up more cleanly with its recording scores higher.
struct MusicRecognitionScoring {
    struct Candidate: Equatable {
        var song: RecognisedSong
        var engines: Set<String> = []
        var hits = 0
        var bestSkew: Double?

        /// From 50 to 99: one answer starts at 62, each further window adds 10 up to three,
        /// a second engine family adds 10, and a clean alignment adds up to 12.
        var percent: Int {
            let families = Set(engines.map { $0.split(separator: "-").first.map(String.init) ?? $0 })
            var score = 62 + 10 * min(max(hits - 1, 0), 3) + (families.count > 1 ? 10 : 0)
            if let bestSkew { score += bestSkew < 0.002 ? 12 : bestSkew < 0.01 ? 6 : 0 }
            return min(99, max(50, score))
        }
    }

    private(set) var candidates: [String: Candidate] = [:]

    static func key(title: String, artist: String) -> String {
        func clean(_ text: String) -> String {
            // "Song (feat. X)" and "Song - Remastered" are the same song heard.
            let cut = text.lowercased().components(separatedBy: CharacterSet(charactersIn: "([-")).first ?? text
            return cut.filter { $0.isLetter || $0.isNumber }
        }
        return clean(title) + "|" + clean(artist)
    }

    mutating func add(_ song: RecognisedSong, engine: String, skew: Double?) {
        var candidate = candidates[song.id] ?? Candidate(song: song)
        candidate.engines.insert(engine)
        candidate.hits += 1
        if let skew { candidate.bestSkew = min(candidate.bestSkew ?? skew, skew) }
        // Keep the answer that brought artwork, when another did not.
        if candidate.song.artworkURL == nil, song.artworkURL != nil { candidate.song = song }
        candidates[song.id] = candidate
    }

    var best: Candidate? { ranked.first }

    var ranked: [Candidate] {
        candidates.values.sorted { $0.percent != $1.percent ? $0.percent > $1.percent : $0.hits > $1.hits }
    }

    func others(than id: String) -> [Candidate] { ranked.filter { $0.song.id != id } }

    /// Whether there is sound worth fingerprinting, not silence or a faint hum.
    static func isAudible(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        let power = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        return power.squareRoot() > 0.003
    }

    /// 16 kHz mono sound as a 16-bit WAV file.
    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(Data("RIFF".utf8)); u32(36 + bytes); data.append(Data("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(16_000); u32(32_000); u16(2); u16(16)
        data.append(Data("data".utf8)); u32(bytes)
        for sample in samples { u16(UInt16(bitPattern: Int16(max(-32768, min(32767, (sample * 32767).rounded()))))) }
        return data
    }

    /// What to search for other versions by: the title without "(Remix)" or "- Remastered", with the
    /// first artist named, then the bare title alone.
    static func searchTerms(for song: RecognisedSong) -> [String] {
        let title = (song.title.components(separatedBy: CharacterSet(charactersIn: "([")).first ?? song.title)
            .components(separatedBy: " - ").first?.trimmingCharacters(in: .whitespaces) ?? song.title
        let artist = song.artist.components(separatedBy: CharacterSet(charactersIn: "&,"))
            .first?.components(separatedBy: " feat").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return [[title, artist].filter { !$0.isEmpty }.joined(separator: " "), title]
            .reduce(into: [String]()) { if !$0.contains($1), !$1.isEmpty { $0.append($1) } }
    }

    /// Other versions of a song from an iTunes Search reply: covers, remixes, live takes.
    static func versions(from data: Data, excluding song: RecognisedSong) -> [RecognisedSong] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]] else { return [] }
        var seen: Set<String> = [song.id]
        return results.compactMap { item -> RecognisedSong? in
            guard let title = item["trackName"] as? String, let artist = item["artistName"] as? String else { return nil }
            let artwork = (item["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100", with: "300x300")
            let found = RecognisedSong(title: title, artist: artist, artworkURL: artwork.flatMap(URL.init(string:)))
            guard seen.insert(found.id).inserted else { return nil }
            return found
        }
    }
}
