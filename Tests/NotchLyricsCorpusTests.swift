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
            let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
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
                let recovered = canonical ?? NotchLyricsSupport.bestLyrics(in: candidates)
                let recoveredWider = canonical ?? NotchLyricsSupport.bestLyrics(in: widerCandidates)
                before += exact == nil ? 0 : 1
                after += recovered == nil ? 0 : 1
                wider += recoveredWider == nil ? 0 : 1
                suite.expect((exact != nil) == (row["expectedBefore"] as? Bool)
                             && (recovered != nil) == (row["expectedAfter"] as? Bool),
                             "captured corpus retains its reviewed match decision: " + track.title)
                suite.expect(exact == nil || recovered == exact, "exact matches retain their original lyrics")
                if index >= 80 {
                    suite.expect(recovered != nil, "all seven desktop samples have a matching fallback or exact record")
                }
            }
            suite.expect(rows.count == 87 && before == 60 && after == 79,
                         "corpus replay recovers 19 previously unavailable tracks without losing exact matches")
            suite.expect(wider == after, "five seconds provides no additional resolved matches in this corpus")
        } catch {
            suite.expect(false, "lyrics corpus fixture failed: \(error)")
        }
    }
}
