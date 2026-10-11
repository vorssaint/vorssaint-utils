// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Offline replay of captured LRCLIB metadata. Lyrics are synthetic fingerprints;
/// equal/different payloads remain equal/different without redistributing lyrics.
enum NotchLyricsCorpusTests {
    static func run(_ suite: TestSuite) {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/NotchLyricsCorpus.json")
        do {
            let cohorts: [(URL, Int, Int, Int, Int)] = [
                (url, 87, 60, 85, 85),
                (url.deletingLastPathComponent().appendingPathComponent("NotchLyricsLessMainstreamCorpus.json"), 50, 25, 39, 39),
                (url.deletingLastPathComponent().appendingPathComponent("NotchLyricsMultilingualCorpus.json"), 59, 32, 55, 56),
            ]
            for (fixture, expectedCount, expectedBefore, expectedAfter, expectedWider) in cohorts {
                let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [[String: Any]]
                var before = 0, after = 0, wider = 0
                for (index, row) in rows.enumerated() {
                    let metadata = row["track"] as! [String: Any]
                    let track = NotchMusicIdentity(NotchPlayback(
                        track: RadialNowPlayingSnapshot(title: metadata["title"] as? String,
                                                       artist: metadata["artist"] as? String,
                                                       album: metadata["album"] as? String,
                                                       artworkData: nil, appBundleIdentifier: nil, appPID: nil),
                        isPlaying: true, elapsed: 0, duration: metadata["duration"] as! Double,
                        rate: 1, sampledAt: .now, canSeek: false))
                    let exactData = try JSONSerialization.data(withJSONObject: row["exact"]!)
                    let exact = NotchLyricsSupport.decode(exactData, for: track)
                    let canonical = exact ?? NotchLyricsSupport.decodeCatalogMatch(exactData, for: track)
                    var candidates: [NotchLyricsSupport.Candidate] = []
                    var widerCandidates: [NotchLyricsSupport.Candidate] = []
                    for search in row["searches"] as! [[String: Any]] {
                        let data = try JSONSerialization.data(withJSONObject: search["response"]!)
                        candidates += NotchLyricsSupport.searchCandidates(data, for: track)
                        widerCandidates += NotchLyricsSupport.searchCandidates(data, for: track, durationTolerance: 5)
                    }
                    for search in row["discoverySearches"] as? [[String: Any]] ?? [] {
                        let data = try JSONSerialization.data(withJSONObject: search["response"]!)
                        candidates += NotchLyricsSupport.searchCandidates(data, for: track)
                        widerCandidates += NotchLyricsSupport.searchCandidates(data, for: track, durationTolerance: 5)
                    }
                    var aliasCandidates: [NotchLyricsSupport.Candidate] = []
                    var aliasWider: [NotchLyricsSupport.Candidate] = []
                    if let metadata = row["artistMetadata"] {
                        let broad = ((metadata as? [String: Any])?["count"] as? Int ?? 0) > 5
                        let artists = NotchLyricsSupport.artistIdentities(try JSONSerialization.data(withJSONObject: metadata),
                                                           for: track, allowTruncated: broad)
                        var identity = artists.count == 1 && !broad ? artists.first : nil
                        if artists.count == 1 && artists[0].queryNames.isEmpty, let recording = row["recordingMetadata"] {
                            identity = NotchLyricsSupport.recordingArtistIdentity(try JSONSerialization.data(withJSONObject: recording), for: track, candidates: artists)
                        } else if (artists.count > 1 || broad), let album = row["albumMetadata"] {
                            identity = NotchLyricsSupport.artistIdentity(try JSONSerialization.data(withJSONObject: album),
                                                                        for: track, candidates: artists)
                        }
                        if let identity {
                            for search in row["aliasSearches"] as? [[String: Any]] ?? [] {
                                let data = try JSONSerialization.data(withJSONObject: search["response"]!)
                                aliasCandidates += NotchLyricsSupport.searchCandidates(data, for: track,
                                                                            verifiedArtistAliases: identity.names)
                                aliasWider += NotchLyricsSupport.searchCandidates(data, for: track, durationTolerance: 5,
                                                                            verifiedArtistAliases: identity.names)
                            }
                        }
                    }
                    let recovered = canonical ?? NotchLyricsSupport.bestLyrics(in: candidates)
                        ?? (candidates.isEmpty ? NotchLyricsSupport.bestLyrics(in: aliasCandidates) : nil)
                    let recoveredWider = canonical ?? NotchLyricsSupport.bestLyrics(in: widerCandidates)
                        ?? (widerCandidates.isEmpty ? NotchLyricsSupport.bestLyrics(in: aliasWider) : nil)
                    before += exact == nil ? 0 : 1
                    after += recovered == nil ? 0 : 1
                    wider += recoveredWider == nil ? 0 : 1
                    suite.expect((exact != nil) == (row["expectedBefore"] as? Bool)
                                 && (recovered != nil) == (row["expectedAfter"] as? Bool)
                                 && (recoveredWider != nil) == (row["expectedAfterFive"] as? Bool),
                                 "captured corpus retains its reviewed match decision: " + track.title)
                    suite.expect((row["expectedPrevious"] as? Bool) != true || recovered != nil,
                                 "previously resolved corpus records remain available: " + track.title)
                    suite.expect(exact == nil || recovered == exact, "exact matches retain their original lyrics")
                    if expectedCount == 87 && index >= 80 {
                        suite.expect(recovered != nil, "all seven desktop samples have a matching fallback or exact record")
                    }
                }
                suite.expect(rows.count == expectedCount && before == expectedBefore && after == expectedAfter,
                             "captured cohort retains its reviewed before/after totals: " + fixture.lastPathComponent)
                suite.expect(wider == expectedWider, "duration experiment retains its reviewed cohort total")
            }
        } catch {
            suite.expect(false, "lyrics corpus fixture failed: \(error)")
        }
    }
}
