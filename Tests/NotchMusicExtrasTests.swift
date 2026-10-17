// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO

enum NotchMusicExtrasTests {
    private static func preferredPlayer(_ suite: TestSuite) {
        typealias Player = NotchPreferredPlayer
        let spotify = "com.spotify.client", music = "com.apple.Music", other = "org.example.Player"
        func resolve(_ choice: String, last: String? = nil, installed: Set<String>) -> String? {
            Player.resolve(choice: choice, lastPlayed: last, isInstalled: installed.contains)
        }
        suite.expect(resolve(other, last: spotify, installed: [other, spotify, music]) == other,
                     "a player chosen in Settings is the one that opens, whatever played last")
        suite.expect(resolve(Player.automatic, last: music, installed: [spotify, music]) == music,
                     "automatic opens the music app that played last")
        suite.expect(resolve(Player.automatic, installed: [spotify, music]) == spotify
                     && resolve(Player.automatic, installed: [music]) == music,
                     "with nothing played yet, automatic prefers Spotify and then Apple Music")
        suite.expect(resolve(other, installed: [music]) == music && resolve(Player.automatic, last: other, installed: [spotify]) == spotify,
                     "a chosen or last player that is no longer installed gives way to the automatic order")
        suite.expect(resolve(Player.automatic, last: spotify, installed: []) == nil && resolve(other, installed: []) == nil,
                     "with no music app installed nothing is offered to open")
        let domain = "com.vorssaint.tests.notch-preferred-player"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(Player.choice(in: defaults) == Player.automatic, "the choice starts as automatic")
        defaults.set(spotify, forKey: DefaultsKey.notchPreferredPlayer)
        suite.expect(Player.choice(in: defaults) == spotify, "the choice is the stored bundle identifier")
        defaults.set(String(repeating: "x", count: 300), forKey: DefaultsKey.notchPreferredPlayer)
        suite.expect(Player.choice(in: defaults) == Player.automatic, "an implausible stored value is treated as automatic")

        let saved = Player.lastPlayed
        defer { Player.lastPlayed = saved }
        Player.lastPlayed = nil
        let active = NotchPlaybackSource(pid: 10, bundleIdentifier: music, isMusicApp: true, isPlaying: true, hasTrack: true)
        let paused = NotchPlaybackSource(pid: 20, bundleIdentifier: spotify, isMusicApp: true, isPlaying: false, hasTrack: true)
        func playback(_ source: NotchPlaybackSource?) -> NotchPlayback? {
            source.map {
                let track = RadialNowPlayingSnapshot(title: "Song", artist: nil, album: nil, artworkData: nil,
                                                     appBundleIdentifier: $0.bundleIdentifier, appPID: $0.pid)
                return NotchPlayback(track: track, isPlaying: $0.isPlaying, elapsed: 0, duration: 180,
                                     rate: $0.isPlaying ? 1 : 0, sampledAt: Date(), canSeek: false)
            }
        }
        let selected = NotchPlaybackSource.preferred(in: [active, paused], previousPID: nil, systemPID: active.pid)
        Player.remember(playback(selected), in: [active, paused])
        suite.expect(selected == active && Player.lastPlayed == music, "the active player becomes the last music app that played")
        let fallback = NotchPlaybackSource.preferred(in: [paused], previousPID: active.pid, systemPID: paused.pid)
        Player.remember(playback(fallback), in: [paused])
        suite.expect(fallback == paused && Player.lastPlayed == music,
                     "a paused fallback after the playing app exits cannot replace the last app that played")
        let empty = NotchPlaybackSource.preferred(in: [], previousPID: paused.pid, systemPID: nil)
        Player.remember(playback(empty), in: [])
        suite.expect(resolve(Player.automatic, last: Player.lastPlayed, installed: [music, spotify]) == music,
                     "automatic still opens the last active player after all playback sources disappear")
        let video = NotchPlaybackSource(pid: 30, bundleIdentifier: "org.example.Video", isMusicApp: false, isPlaying: true, hasTrack: true)
        Player.remember(playback(video), in: [video])
        suite.expect(Player.lastPlayed == music, "a playing video does not replace the remembered music app")
        let custom = NotchPlaybackSource(pid: 40, bundleIdentifier: other, isMusicApp: true, isPlaying: true, hasTrack: true)
        Player.remember(playback(custom), in: [custom])
        suite.expect(Player.lastPlayed == other, "an active custom app classified as music is remembered")

        let installed: [Player.Choice] = [(spotify, "Spotify"), (music, "Music")]
        suite.expect(Player.choices(in: installed, including: Player.automatic).map(\.bundleID) == [spotify, music]
                     && Player.choices(in: installed, including: music).map(\.bundleID) == [spotify, music],
                     "automatic adds no empty choice and an installed choice is not duplicated")
        suite.expect(Player.choices(in: [], including: other).map(\.bundleID) == [other]
                     && Player.choices(in: installed, including: other).map(\.bundleID) == [spotify, music, other],
                     "the current choice stays listed before loading and when absent from the installed snapshot")
    }

    private final class ScanSignal: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func signal() { lock.withLock { value = true } }
        var isSignalled: Bool { lock.withLock { value } }
    }

    private static func preferredPlayerLoading(_ suite: TestSuite) {
        typealias Player = NotchPreferredPlayer
        var finished = false
        Task { @MainActor in
            let loaded = await Player.loadInstalled {
                [("org.example.Music", Thread.isMainThread ? "main" : "background")]
            }
            suite.expect(loaded?.first?.name == "background", "the installed music app scan runs off the main thread")

            let started = ScanSignal(), release = DispatchSemaphore(value: 0)
            let old = Task {
                await Player.loadInstalled {
                    started.signal()
                    _ = release.wait(timeout: .now() + 5)
                    return [("org.example.Old", "Old")]
                }
            }
            let deadline = Date().addingTimeInterval(2)
            var didStart = false
            while !didStart, Date() < deadline {
                didStart = started.isSignalled
                if !didStart { try? await Task.sleep(nanoseconds: 1_000_000) }
            }
            old.cancel()
            let current = await Player.loadInstalled { [("org.example.New", "New")] }
            release.signal()
            let stale = await old.value
            suite.expect(didStart && stale == nil && current?.first?.bundleID == "org.example.New",
                         "a cancelled screen load discards its late result while a reopened screen can load new choices")

            let scanned = ScanSignal()
            let cancelled = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await Player.loadInstalled { scanned.signal(); return [] }
            }
            let result = await cancelled.value
            suite.expect(result == nil && !scanned.isSignalled,
                         "a task cancelled before loading does not start an app scan")
            finished = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !finished, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        suite.expect(finished, "preferred player loading contracts finish")
    }

    private static func lyricScheduleContracts(_ suite: TestSuite) {
        let track = RadialNowPlayingSnapshot(title: "Timed verses", artist: nil, album: nil,
                                            artworkData: nil, appBundleIdentifier: nil, appPID: nil)
        let sampledAt = Date(timeIntervalSinceReferenceDate: 811_234_567.123)
        let lyrics = NotchLyrics(lines: [0.0, 2.25, 6.625, 12.0, 18.5].map {
            NotchLyricLine(time: $0, text: "Verse \($0)")
        }, plain: "", instrumental: false)
        func playback(elapsed: Double = 1, rate: Double = 1, playing: Bool = true,
                      hasPosition: Bool = true) -> NotchPlayback {
            NotchPlayback(track: track, isPlaying: playing, elapsed: elapsed, duration: 20,
                          rate: rate, sampledAt: sampledAt, canSeek: false, hasPosition: hasPosition)
        }
        for rate in [0.25, 0.75, 1, 1.25, 2, 16] {
            for offset in [-10.0, -0.25, 0, 0.25, 10] {
                for elapsed in [0.0, 1, 7, 19, 20] {
                    let playback = playback(elapsed: elapsed, rate: rate)
                    let now = sampledAt.addingTimeInterval(0.123)
                    let position = playback.position(at: now)
                    let upcoming = lyrics.lines.enumerated().filter {
                        $0.element.time + offset > position && $0.element.time + offset <= playback.duration
                    }
                    let dates = lyrics.changeDates(for: playback, offset: offset, from: now)
                        .filter { $0 != .distantFuture }
                    suite.expect(dates.first == now && dates.count == upcoming.count + 1,
                           "lyrics refresh immediately after a seek or timing change and only at reachable future verses")
                    suite.expect(zip(dates, dates.dropFirst()).allSatisfy { $0 < $1 },
                           "lyric deadlines stay ordered at every supported rate and timing offset")
                    for (date, line) in zip(dates.dropFirst(), upcoming) {
                        suite.expect(lyrics.activeIndex(at: playback.position(at: date), offset: offset) == line.offset,
                               "scheduled lyric dates highlight the new verse despite floating-point rate and date rounding")
                        suite.expect(abs(playback.position(at: date) - (line.element.time + offset)) < 0.0001,
                               "verse updates retain sub-millisecond precision when playback speed changes")
                    }
                }
            }
        }
        for stopped in [playback(playing: false), playback(rate: 0), playback(rate: .nan),
                        playback(rate: .infinity), playback(hasPosition: false), playback(elapsed: 20)] {
            suite.expect(lyrics.changeDates(for: stopped, offset: 0, from: sampledAt) == [sampledAt],
                   "paused, completed or unpositioned playback leaves no recurring lyric updates")
        }
        suite.expect(lyrics.changeDates(for: playback(), offset: .nan, from: sampledAt) == [sampledAt],
               "an invalid lyric offset cannot schedule a wakeup")
        let resumed = lyrics.changeDates(for: playback(elapsed: 6), offset: 0, from: sampledAt)
            .filter { $0 != .distantFuture }
        suite.expect(resumed.count == 4 && resumed[1].timeIntervalSince(sampledAt) < 0.626,
               "resuming or seeking back schedules the next verse from the new playback position")
    }

    private static func lyricSearchContracts(_ suite: TestSuite) {
        func identity(_ title: String, _ artist: String, _ album: String, _ duration: Double) -> NotchMusicIdentity {
            NotchMusicIdentity(NotchPlayback(
                track: RadialNowPlayingSnapshot(title: title, artist: artist, album: album, artworkData: nil,
                                               appBundleIdentifier: nil, appPID: nil),
                isPlaying: true, elapsed: 0, duration: duration, rate: 1, sampledAt: .now, canSeek: false))
        }
        func record(_ title: String, _ artist: String, _ album: String, _ duration: Double,
                    _ words: String = "Fixture verse") -> [String: Any] {
            ["trackName": title, "artistName": artist, "albumName": album, "duration": duration,
             "syncedLyrics": "[00:01]" + words, "plainLyrics": words, "instrumental": false]
        }
        func candidates(_ records: [[String: Any]], _ track: NotchMusicIdentity) -> [NotchLyricsSupport.Candidate] {
            NotchLyricsSupport.searchCandidates(try! JSONSerialization.data(withJSONObject: records), for: track)
        }
        // Metadata reproduced from the desktop and seeded corpus; lyric text is synthetic.
        let fixtures: [(NotchMusicIdentity, [String: Any])] = [
            (identity("Режиссёр", "группа Градусы", "Градусы", 219),
             record("Режиссер", "Градусы", "Самые модные хиты", 219)),
            (identity("Чужое горе", "Порнофильмы, Котляров Владимир Андреевич", "Это пройдёт", 205),
             record("Чужое горе", "Порнофильмы", "Это пройдёт", 205)),
            (identity("Not A Lullaby", "The Weepies, Deb Talan, Steve Tannen", "Be My Thrill", 158),
             record("Not a Lullaby", "The Weepies", "Be My Thrill", 158)),
            (identity("Jai Ho! (You Are My Destiny)", "A. R. Rahman, The Pussycat Dolls, Nicole Scherzinger",
                      "Jai Ho! (You Are My Destiny)", 222),
             record("Jai Ho! (You Are My Destiny)", "A. R. Rahman & The Pussycat Dolls feat. Nicole Scherzinger",
                    "Jai Ho! (You Are My Destiny)", 222)),
            (identity("Солдат", "5'nizza, Serhii Babkin, Andrii Zaporozhets", "Пятница", 191),
             record("Солдат", "5nizza", "Compilation", 190)),
            (identity("Secrets", "Tiësto, KSHMR, Vassy", "Secrets", 268),
             record("Secrets", "Tiesto / KSHMR", "Secrets", 268))
        ]
        for (track, reply) in fixtures {
            suite.expect(NotchLyricsSupport.bestLyrics(in: candidates([reply], track))?.lines.count == 1,
                         "fallback recovers observed artist, punctuation, album and е/ё variants: " + track.title)
            let urls = NotchLyricsSupport.searchURLs(for: track)
            suite.expect(!urls.isEmpty && urls.count <= 3 && Set(urls).count == urls.count
                         && urls.allSatisfy { $0.host == "lrclib.net" && $0.path == "/api/search" },
                         "fallback queries stay bounded, deduplicated and on the consented host")
        }
        let track = identity("Example Song", "Main Artist, Guest Artist", "Studio Album", 180)
        let preferred = record("Example Song", "Main Artist", "Studio Album", 180)
        let compilation = record("Example Song", "Main Artist", "Compilation", 180, "Other verse")
        suite.expect(NotchLyricsSupport.bestLyrics(in: candidates([compilation, preferred], track))?.plain == "Fixture verse",
                     "album agreement ranks above a compilation without depending on provider order")
        for wrong in [record("Example Song (Live)", "Main Artist", "Studio Album", 180),
                      record("Example Song (Remix)", "Main Artist", "Studio Album", 180),
                      record("Example Song", "Guest Artist", "Studio Album", 180),
                      record("Example Song", "Unrelated Artist", "Studio Album", 180),
                      record("Example Song", "Main Artist", "Live at the Theatre", 180),
                      record("Example Song", "Main Artist", "Studio Album", 183)] {
            suite.expect(candidates([wrong], track).isEmpty,
                         "search never substitutes a different title, version, primary artist or recording length")
        }
        let conflict = record("Example Song", "Main Artist", "Studio Album", 180, "Conflicting verse")
        suite.expect(NotchLyricsSupport.bestLyrics(in: candidates([preferred, conflict], track))
                     == NotchLyricsSupport.bestLyrics(in: candidates([conflict, preferred], track)),
                     "equally ranked conflicting lyrics resolve consistently in either response order")
        suite.expect(NotchLyricsSupport.bestLyrics(in: candidates([preferred, preferred], track)) != nil,
                     "the same lyric returned by multiple queries is not an ambiguity")
        var identifiedFirst = preferred; identifiedFirst["id"] = 20
        var identifiedSecond = conflict; identifiedSecond["id"] = 10
        suite.expect(NotchLyricsSupport.bestLyrics(in: candidates([identifiedFirst, identifiedSecond], track))?.plain == "Conflicting verse",
                     "stable catalog ID breaks otherwise equal candidate ties")
        let studio = identity("Example Song", "Main Artist", "Studio Album", 180)
        suite.expect(!candidates([record("Example Song (Original Mix)", "Main Artist", "Studio Album", 180)], studio).isEmpty,
                     "original mix is compatible with the unqualified studio title")
        suite.expect(candidates([record("Example Song (feat. Unknown Guest)", "Main Artist", "Studio Album", 180)], studio).isEmpty,
                     "unmentioned featured performers cannot be silently substituted")
        for artist in ["Other Artist, Main Artist", "Main Artist, Unknown Guest"] {
            suite.expect(candidates([record("Example Song", artist, "Studio Album", 180)], studio).isEmpty,
                         "artist credits cannot introduce an unknown lead or guest")
            suite.expect(!NotchLyricsSupport.containsCatalogRecording(
                try! JSONSerialization.data(withJSONObject: [record("Example Song", artist, "Studio Album", 180)]), for: studio),
                         "conflicting artist credits cannot stop verified alias lookup")
        }
        suite.expect(!candidates([record("Example Song", "Guest Artist & Main Artist", "Studio Album", 180)], track).isEmpty,
                     "known collaboration credits may be reordered")
        let titleGuest = identity("Example Song (feat. Guest Artist)", "Main Artist", "Studio Album", 180)
        suite.expect(!candidates([record("Example Song", "Main Artist, Guest Artist", "Studio Album", 180)], titleGuest).isEmpty,
                     "known featured credits may move from the title into the artist field")
        let extended = identity("Example Song (feat. Guest Person) (Extended Mix)", "Main Artist, Guest Person", "Studio Album", 180)
        suite.expect(!candidates([record("Example Song (featuring Guest) (Extended Mix)", "Main Artist", "Studio Album", 180)], extended).isEmpty
                     && candidates([record("Example Song (featuring Other) (Extended Mix)", "Main Artist", "Studio Album", 180)], extended).isEmpty
                     && candidates([record("Example Song (featuring Guest)", "Main Artist", "Studio Album", 180)], extended).isEmpty,
                     "featured credits normalize separately while preserving extended-version identity")
        var badTiming = record("Example Song", "Main Artist", "Studio Album", 180)
        badTiming["syncedLyrics"] = "[00:01]Synthetic verse\n[04:00]Synthetic ending"
        suite.expect(NotchLyricsSupport.bestLyrics(in: candidates([badTiming], studio))?.lines.isEmpty == true,
                     "out-of-recording timestamps fall back to available plain text instead of a truncated timeline")
        let precise = NotchLyricsSupport.searchURLs(for: extended)
        suite.expect(precise.contains { url in
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains {
                $0.name == "track_name" && $0.value == "example song feat guest person extended mix"
            } == true
        }, "normalized precise title search survives the addition of broader discovery")
        let discovery = NotchLyricsSupport.discoveryURLs(for: extended)
        suite.expect(discovery.count == 1 && discovery[0].host == "lrclib.net",
                     "broader title discovery remains bounded to the existing lyric provider")
        let collaboration = identity("Jai Ho!", "A. R. Rahman, The Pussycat Dolls, Nicole Scherzinger", "Single", 222)
        suite.expect(NotchLyricsSupport.bestLyrics(in: candidates([
            record("Jai Ho!", "A. R. Rahman", "Single", 222, "Incomplete credits"),
            record("Jai Ho!", "A.R. Rahman & The Pussycat Dolls feat. Nicole Scherzinger", "Single", 222)
        ], collaboration))?.plain == "Fixture verse", "complete artist credits rank above primary-only credits")
        let cyrillic = identity("Мой", "Artist", "Album", 180)
        suite.expect(candidates([record("Мои", "Artist", "Album", 180)], cyrillic).isEmpty,
                     "Latin accent normalization does not collapse Cyrillic й into и")
        suite.expect(candidates(Array(repeating: preferred, count: 21), track).isEmpty
                     && NotchLyricsSupport.searchCandidates(Data(repeating: 32, count: NotchLyricsSupport.maximumSearchBytes + 1), for: track).isEmpty,
                     "search envelopes have byte and result-count limits")
        var oversized = preferred
        oversized["plainLyrics"] = String(repeating: "x", count: NotchLyricsSupport.maximumBytes + 1)
        suite.expect(candidates([oversized], track).isEmpty,
                     "each lyric inside a larger search reply retains the original per-record bound")
        var missingDuration = preferred
        missingDuration["duration"] = NSNull()
        var emptyLyrics = preferred
        emptyLyrics["plainLyrics"] = ""
        emptyLyrics["syncedLyrics"] = ""
        suite.expect(candidates([missingDuration, emptyLyrics], track).isEmpty,
                     "missing durations and empty lyric records cannot become fallback matches")
    }

    private static func artistIdentity(_ suite: TestSuite) {
        let track = NotchMusicIdentity(NotchPlayback(
            track: RadialNowPlayingSnapshot(title: "Fictional Song", artist: "架空乐队", album: "Fictional Album",
                                           artworkData: nil, appBundleIdentifier: nil, appPID: nil),
            isPlaying: true, elapsed: 0, duration: 180, rate: 1, sampledAt: .now, canSeek: false))
        let id = UUID(), otherID = UUID()
        func encode(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
        let artist: [String: Any] = ["id": id.uuidString, "name": "架空乐队", "score": 100,
            "aliases": [["name": "Fictional Artist", "locale": "en", "primary": true]]]
        let reply: [String: Any] = ["count": 1, "artists": [artist]]
        let identities = NotchLyricsSupport.artistIdentities(encode(reply), for: track)
        suite.expect(identities.count == 1 && identities[0].names.contains("Fictional Artist"),
                     "generic identity verification accepts an exact name with a different-script alias")
        let urls = identities.flatMap { NotchLyricsSupport.aliasSearchURLs(for: track, identity: $0) }
        suite.expect(urls.count == 1 && urls[0].host == "lrclib.net"
                     && NotchLyricsSupport.artistIdentityURL(for: track)?.host == "musicbrainz.org",
                     "artist metadata and alias queries stay bounded on disclosed providers")
        let record: [String: Any] = ["trackName": track.title, "artistName": "Fictional Artist",
            "albumName": track.album, "duration": 180, "syncedLyrics": "[00:01]Synthetic verse"]
        suite.expect(NotchLyricsSupport.searchCandidates(encode([record]), for: track).isEmpty
                     && NotchLyricsSupport.searchCandidates(encode([record]), for: track,
                                 verifiedArtistAliases: identities[0].names).count == 1,
                     "different artist names require verified identity rather than title and duration alone")
        for credit in ["Other Artist, Fictional Artist", "Fictional Artist, Unknown Guest"] {
            var conflicting = record; conflicting["artistName"] = credit
            suite.expect(NotchLyricsSupport.searchCandidates(encode([conflicting]), for: track,
                                     verifiedArtistAliases: identities[0].names).isEmpty,
                         "a verified artist alias does not authorize unrelated collaborators")
        }
        var wrong = record; wrong["duration"] = 183
        suite.expect(NotchLyricsSupport.searchCandidates(encode([wrong]), for: track,
                                 verifiedArtistAliases: identities[0].names).isEmpty,
                     "verified aliases never bypass the recording-length check")
        var unrelated = artist; unrelated["name"] = "Unrelated artist"; unrelated["aliases"] = []
        suite.expect(NotchLyricsSupport.artistIdentities(encode(["count": 1, "artists": [unrelated]]), for: track).isEmpty,
                     "a perfect metadata search score does not prove artist identity")
        var duplicate = artist; duplicate["id"] = otherID.uuidString
        let sameSource = NotchLyricsSupport.ArtistIdentity(id: id, names: ["架空乐队"], queryNames: [])
        let recordingProof: [String: Any] = ["count": 7, "recordings": [[
            "title": "Fictional Song", "length": 180000,
            "artist-credit": [["name": "Earlier Artist Name", "artist": ["id": id.uuidString]]]
        ]]]
        let verifiedCredit = NotchLyricsSupport.recordingArtistIdentity(encode(recordingProof), for: track, candidates: [sameSource])
        suite.expect(verifiedCredit?.names.contains("Earlier Artist Name") == true,
                     "exact title and duration tie a historical recording credit to the known artist ID")
        var wrongProof = recordingProof
        wrongProof["recordings"] = [["title": "Different Song", "length": 180000,
                                     "artist-credit": [["name": "Earlier Artist Name", "artist": ["id": id.uuidString]]]]]
        suite.expect(NotchLyricsSupport.recordingArtistIdentity(encode(wrongProof), for: track, candidates: [sameSource]) == nil,
                     "a historical credit needs independent song agreement, not merely an artist search score")
        suite.expect(NotchLyricsSupport.artistRecordingURL(for: track, candidates: [sameSource])?.host == "musicbrainz.org"
                     && NotchLyricsSupport.artistRecordingURL(for: track, candidates: [sameSource, sameSource]) == nil,
                     "recording-credit lookup is bounded to one exact source artist ID")
        let ambiguous = NotchLyricsSupport.artistIdentities(encode(["count": 2, "artists": [artist, duplicate]]), for: track)
        let group: [String: Any] = ["title": track.album, "artist-credit": [["artist": ["id": id.uuidString]]]]
        suite.expect(ambiguous.count == 2
                     && NotchLyricsSupport.artistIdentity(encode(["count": 1, "release-groups": [group]]),
                                        for: track, candidates: ambiguous)?.id == id,
                     "an ambiguous name needs independent exact album credit evidence")
        var otherGroup = group; otherGroup["artist-credit"] = [["artist": ["id": otherID.uuidString]]]
        suite.expect(NotchLyricsSupport.artistIdentity(encode(["count": 2, "release-groups": [group, otherGroup]]),
                                        for: track, candidates: ambiguous) == nil,
                     "conflicting album identities cannot be resolved by response order")
        suite.expect(NotchLyricsSupport.artistIdentities(encode(["count": 6, "artists": [artist]]), for: track).isEmpty
                     && NotchLyricsSupport.artistIdentities(Data(repeating: 32, count: NotchLyricsSupport.maximumBytes + 1), for: track).isEmpty,
                     "truncated broad identity searches and oversized metadata are refused")
    }

    /// Zen and Firefox publish no cover, so the island reads the saved session
    /// for the playing tab and derives YouTube's thumbnail from its address.
    private static func browserArtworkContracts(_ suite: TestSuite) {
        let session = Data("""
            {"windows":[{"tabs":[
              {"index":2,"entries":[{"url":"https://www.youtube.com/watch?v=aaaaaaaaaaa","title":"Old video - YouTube"},
                                    {"url":"https://www.youtube.com/watch?v=1PxhTfmEyQ8&t=42","title":"(3) My favorite browser is (kind of) dead - YouTube"}]},
              {"index":1,"entries":[{"url":"https://www.google.com/search?q=browser","title":"My favorite browser is (kind of) dead - Google Search"}]},
              {"index":1,"entries":[{"url":"https://music.youtube.com/watch?v=8_fkyx42kL0&list=RDAMVM","title":"she likes spring, I prefer winter | YouTube Music"}]},
              {"index":1,"entries":[{"url":"https://www.youtube.com/watch?v=bbbbbbbbbbb","title":"Went back - YouTube"},
                                    {"url":"https://www.youtube.com/watch?v=ccccccccccc","title":"Forward page - YouTube"}]}
            ]}]}
            """.utf8)
        // One LZ4 sequence of literals only. Its token says 15, the extra
        // length bytes carry the rest, and the bytes themselves follow.
        let literals = [UInt8](session)
        var block: [UInt8] = [0xF0]
        var remaining = literals.count - 15
        while remaining >= 255 { block.append(255); remaining -= 255 }
        block.append(UInt8(remaining))
        block += literals
        let size = UInt32(literals.count)
        let container = Data(Array("mozLz40\0".utf8) + (0..<4).map { UInt8(truncatingIfNeeded: size >> (8 * $0)) } + block)
        suite.expect(NotchBrowserArtworkSupport.decodeMozLZ4(container) == session,
               "a Mozilla session container decodes to its JSON")
        suite.expect(NotchBrowserArtworkSupport.decodeMozLZ4(Data("mozLz40\0".utf8) + Data([0, 0, 0, 0, 0])) == nil
                && NotchBrowserArtworkSupport.decodeMozLZ4(Data("not a session".utf8)) == nil
                && NotchBrowserArtworkSupport.decodeMozLZ4(container.dropLast(4)) == nil,
               "an empty, foreign or truncated session reads as nothing")
        // "abcd", then a match four bytes back for eight bytes, then twelve
        // closing literals, as every LZ4 block ends.
        let repeating: [UInt8] = [0x44] + Array("abcd".utf8) + [4, 0, 0xC0] + Array("0123456789AB".utf8)
        let header = Array("mozLz40\0".utf8) + [24, 0, 0, 0]
        suite.expect(NotchBrowserArtworkSupport.decodeMozLZ4(Data(header + repeating))
                    == Data("abcdabcdabcd0123456789AB".utf8),
               "a session block that repeats earlier bytes decodes them")
        var reachesBack = repeating
        reachesBack[5] = 16
        suite.expect(NotchBrowserArtworkSupport.decodeMozLZ4(Data(header + reachesBack)) == nil,
               "a block that reaches before its start reads as nothing")
        // Half a megabyte that would fill one byte past the cap: "a", a match
        // one byte back that repeats it, then the twelve closing literals.
        let oversized = NotchBrowserArtworkSupport.maximumSessionBytes + 1
        let extra = oversized - 1 - 12 - 4 - 15
        let flood: [UInt8] = [0x1F, 0x61, 1, 0] + [UInt8](repeating: 255, count: extra / 255) + [UInt8(extra % 255)]
            + [0xC0] + Array("0123456789AB".utf8)
        let floodHeader = Array("mozLz40\0".utf8) + (0..<4).map { UInt8(truncatingIfNeeded: oversized >> (8 * $0)) }
        suite.expect(NotchBrowserArtworkSupport.decodeMozLZ4(Data(floodHeader + flood)) == nil,
               "a session that would decode past its size cap reads as nothing")

        let tabs = NotchBrowserArtworkSupport.openTabs(inSession: session)
        suite.expect(tabs.count == 4 && tabs[0].title.hasPrefix("(3) My favorite") && tabs[3].title == "Went back - YouTube",
               "each tab reads as the page it shows now, not its back history or the page it went back from")
        let watching = { (title: String) in
            NotchBrowserArtworkSupport.SessionTab(title: title, url: URL(string: "https://www.youtube.com/watch?v=1PxhTfmEyQ8")!)
        }
        suite.expect(NotchBrowserArtworkSupport.artworkURLs(forTrack: "Home", in: [watching("Homeland trailer - YouTube"),
                                                                                    watching("Coming Home live - YouTube")]).isEmpty
                && !NotchBrowserArtworkSupport.artworkURLs(forTrack: "Home", in: [watching("(2) Home - YouTube")]).isEmpty
                && !NotchBrowserArtworkSupport.artworkURLs(forTrack: "Home", artist: "Artist",
                                                            in: [watching("Home • Artist - YouTube Music")]).isEmpty
                && NotchBrowserArtworkSupport.artworkURLs(forTrack: "Home", artist: "Artist",
                                                           in: [watching("Home • Someone Else - YouTube Music")]).isEmpty
                && NotchBrowserArtworkSupport.artworkURLs(forTrack: "Stay", artist: "The Kid LAROI",
                                                           in: [watching("Stay - Rihanna ft. Mikky Ekko - YouTube")]).isEmpty,
               "a short song title takes only the tab that names it whole, never one that starts with or mentions it")
        suite.expect(!NotchBrowserArtworkSupport.artworkURLs(forTrack: "Home  Again ", in: [watching("Home Again - YouTube")]).isEmpty,
               "a song title with doubled spaces still finds the tab the browser saved with them collapsed")
        let searchTab = NotchBrowserArtworkSupport.SessionTab(title: "Search", url: URL(string: "https://www.google.com/search?q=x")!)
        let musicHome = NotchBrowserArtworkSupport.SessionTab(title: "keshi - YouTube Music",
                                                              url: URL(string: "https://music.youtube.com/channel/UC123")!)
        let began = Date(timeIntervalSinceReferenceDate: 1_000)
        suite.expect(NotchBrowserArtworkSupport.youTubeTabs([searchTab, musicHome, watching("Video - YouTube")]).count == 2
                && NotchBrowserArtworkSupport.asksAppleMusic(tabs: [musicHome], savedAt: began + 3, lookupStarted: began)
                && !NotchBrowserArtworkSupport.asksAppleMusic(tabs: [musicHome], savedAt: began - 3, lookupStarted: began)
                && !NotchBrowserArtworkSupport.asksAppleMusic(tabs: [watching("Video - YouTube")],
                                                              savedAt: began + 3, lookupStarted: began),
               "only YouTube tabs stay after reading, and only a session saved since the lookup began that shows YouTube Music lets Apple be asked")
        suite.expect(NotchBrowserArtworkSupport.artworkURLs(forTrack: "My favorite browser is (kind of) dead", in: tabs)
                .map(\.absoluteString) == ["https://i.ytimg.com/vi/1PxhTfmEyQ8/maxresdefault.jpg",
                                           "https://i.ytimg.com/vi/1PxhTfmEyQ8/mqdefault.jpg"],
               "the playing video's tab gives its full thumbnail first, ahead of a search for the same title")
        suite.expect(NotchBrowserArtworkSupport.artworkURLs(forTrack: "she likes spring, I prefer winter", in: tabs)
                .first?.absoluteString == "https://i.ytimg.com/vi/8_fkyx42kL0/maxresdefault.jpg"
                && NotchBrowserArtworkSupport.artworkURLs(forTrack: "Midnight City", in: tabs).isEmpty,
               "YouTube Music tabs give their song's cover and an unknown track gives none")

        let page = { (address: String) in
            NotchBrowserArtworkSupport.thumbnailURLs(forPage: URL(string: address)!).first?.absoluteString
        }
        suite.expect(page("https://youtu.be/1PxhTfmEyQ8?si=x") == "https://i.ytimg.com/vi/1PxhTfmEyQ8/maxresdefault.jpg"
                && page("https://m.youtube.com/shorts/1PxhTfmEyQ8") != nil
                && page("https://www.youtube.com/live/1PxhTfmEyQ8") != nil
                && page("https://www.youtube.com/watch?v=short") == nil
                && page("https://www.youtube.com/watch?v=1PxhTfmEy/8") == nil
                && page("https://www.youtube.com/@channel") == nil
                && page("https://evil.example/watch?v=1PxhTfmEyQ8") == nil
                && page("file:///watch?v=1PxhTfmEyQ8") == nil,
               "only a well-formed YouTube video address yields a thumbnail address")

        suite.expect(NotchBrowserArtworkSupport.centreSquare(width: 1280, height: 720)
                    == CGRect(x: 280, y: 0, width: 720, height: 720)
                && NotchBrowserArtworkSupport.centreSquare(width: 640, height: 480)
                    == CGRect(x: 80, y: 0, width: 480, height: 480)
                && NotchBrowserArtworkSupport.centreSquare(width: 300, height: 400)
                    == CGRect(x: 0, y: 50, width: 300, height: 300),
               "a YouTube Music thumbnail crops to its square album art without the side bars")
        let search = NotchBrowserArtworkSupport.appleMusicSearchURL(title: "less of you", artist: "keshi", country: "PH")
        let searchItems = search.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        suite.expect(search?.host == "itunes.apple.com"
                && searchItems.contains(URLQueryItem(name: "term", value: "keshi less of you"))
                && searchItems.contains(URLQueryItem(name: "country", value: "PH"))
                && NotchBrowserArtworkSupport.appleMusicSearchURL(title: "less of you", artist: nil, country: nil) == nil
                && NotchBrowserArtworkSupport.appleMusicSearchURL(title: "x", artist: "y", country: "bogus")
                    .map { $0.absoluteString.contains("country=US") } == true,
               "the Apple search names the artist and the song, and never runs on a title alone")
        let appleReply = Data("""
            {"resultCount":3,"results":[
              {"trackName":"Skeletons (Piano Version)","artistName":"thepianokid",
               "artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/piano.jpg/100x100bb.jpg"},
              {"trackName":"less of you","artistName":"thepianokid",
               "artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/cover.jpg/100x100bb.jpg"},
              {"trackName":"Less Of You","artistName":"keshi",
               "artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/83/20UMGIM13994.rgb.jpg/100x100bb.jpg"}
            ]}
            """.utf8)
        suite.expect(NotchBrowserArtworkSupport.appleMusicArtworkURL(inSearch: appleReply, title: "less of you", artist: "keshi")?
                    .absoluteString == "https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/83/20UMGIM13994.rgb.jpg/600x600bb.jpg",
               "the Apple result with the same song and artist gives its 600-pixel album art")
        suite.expect(NotchBrowserArtworkSupport.appleMusicArtworkURL(inSearch: appleReply, title: "skeletons", artist: "keshi") == nil
                && NotchBrowserArtworkSupport.appleMusicArtworkURL(
                    inSearch: appleReply, title: "My favorite browser is (kind of) dead", artist: "Theo - t3.gg") == nil
                && NotchBrowserArtworkSupport.appleMusicArtworkURL(inSearch: Data("{}".utf8), title: "a", artist: "b") == nil,
               "a piano version, a cover by someone else or a YouTube video never borrows an album's art")
        let namesake = Data("""
            {"results":[
              {"trackName":"Hello","artistName":"Jeremias",
               "artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/jeremias.jpg/100x100bb.jpg"},
              {"trackName":"Hello","artistName":"Adele",
               "artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/adele.jpg/100x100bb.jpg"},
              {"trackName":"Hello","artistName":"Mia & Jay",
               "artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/mia.jpg/100x100bb.jpg"}
            ]}
            """.utf8)
        suite.expect(NotchBrowserArtworkSupport.appleMusicArtworkURL(inSearch: namesake, title: "Hello", artist: "Mia")?
                    .lastPathComponent == "600x600bb.jpg"
                && NotchBrowserArtworkSupport.appleMusicArtworkURL(inSearch: namesake, title: "Hello", artist: "Mia")?
                    .absoluteString.contains("/mia.jpg/") == true
                && NotchBrowserArtworkSupport.appleMusicArtworkURL(inSearch: namesake, title: "Hello", artist: "A") == nil
                && NotchBrowserArtworkSupport.appleMusicArtworkURL(inSearch: namesake, title: "Hello", artist: "Jay & Mia & Zoe") == nil
                && NotchBrowserArtworkSupport.appleMusicArtworkURL(
                    inSearch: Data(#"{"results":[{"trackName":"Hello","artistName":"रामा","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/a/r.jpg/100x100bb.jpg"}]}"#.utf8),
                    title: "Hello", artist: "राम") == nil,
               "an artist matches whole names in the credit, never letters inside another artist's name")
        let elsewhere = Data(#"{"results":[{"trackName":"Less Of You","artistName":"keshi","artworkUrl100":"https://images.example/thumb/a.jpg/100x100bb.jpg"}]}"#.utf8)
        suite.expect(NotchBrowserArtworkSupport.appleMusicArtworkURL(inSearch: elsewhere, title: "less of you", artist: "keshi") == nil,
               "album art loads only from Apple's image servers, whatever the reply names")
        func jpeg(side: Int) -> Data {
            let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            let output = NSMutableData()
            let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            CGImageDestinationFinalize(destination)
            return output as Data
        }
        suite.expect(NotchBrowserArtworkSupport.needsCover(nil)
                && NotchBrowserArtworkSupport.needsCover(jpeg(side: 60))
                && NotchBrowserArtworkSupport.needsCover(Data("not an image".utf8))
                && !NotchBrowserArtworkSupport.needsCover(jpeg(side: 720)),
               "the 60-pixel cover Zen sends for YouTube Music gets replaced, a full-size one stays")
        let track = RadialNowPlayingSnapshot(title: "Song", artist: "Artist", album: nil, artworkData: nil,
                                            appBundleIdentifier: "app.zen-browser.zen", appPID: 7)
        let playback = NotchPlayback(track: track, isPlaying: true, elapsed: 12, duration: 180, rate: 1,
                                     sampledAt: Date(timeIntervalSinceReferenceDate: 0), canSeek: true,
                                     itemIdentifier: "item", canSkipNext: true)
        let covered = playback.withArtwork(Data([1, 2, 3]))
        suite.expect(covered.track.artworkData == Data([1, 2, 3])
                && covered.track.title == "Song" && covered.track.appPID == 7
                && covered.elapsed == 12 && covered.canSeek && covered.itemIdentifier == "item"
                && covered.canSkipNext == true
                && NotchMusicIdentity(covered) == NotchMusicIdentity(playback),
               "a cover found from the tab changes nothing else about the playback")
        let folders = NotchBrowserArtworkSupport.profileFolders
        suite.expect(folders["app.zen-browser.zen"] == "zen/Profiles"
                && folders["org.mozilla.firefox"] == "Firefox/Profiles"
                && ["com.apple.Music", "com.spotify.client", "com.google.Chrome", "com.apple.Safari"]
                    .allSatisfy { folders[$0] == nil }
                && folders.values.allSatisfy { $0.hasSuffix("/Profiles") },
               "the cover lookup only reads the sessions of Firefox-family browsers")
    }

    static func run(_ suite: TestSuite) {
        artistIdentity(suite)
        preferredPlayer(suite)
        preferredPlayerLoading(suite)
        lyricScheduleContracts(suite)
        lyricSearchContracts(suite)
        NotchLyricsCorpusTests.run(suite)
        browserArtworkContracts(suite)
        NotchMusicHardeningTests.run(suite)
        let track = RadialNowPlayingSnapshot(title: "A & B + C", artist: "Artist / Example", album: "Studio Recording",
                                            artworkData: nil, appBundleIdentifier: "org.example.player", appPID: 42)
        var playback = NotchPlayback(track: track, isPlaying: true, elapsed: 0, duration: 180, rate: 1,
                                     sampledAt: Date(timeIntervalSinceReferenceDate: 0), canSeek: false,
                                     itemIdentifier: "current-item", canSendCommandsDirectly: true)
        let identity = NotchMusicIdentity(playback)
        let lines = NotchLyricsSupport.parse("""
        [ar:Example]
        [00:12.5]First verse
        [00:20.125][00:30.25]Repeated verse
        [00:25.0]
        [00:30.25]Second voice
        [00:65.2]Invalid seconds
        [100:00]Outside the recording
        [offset:250]
        """, duration: 180)
        suite.expect(lines.map(\.time) == [12.25, 19.875, 24.75, 30],
               "lyrics accept decimal precision, repeated time tags and an offset, and reject invalid time tags")
        suite.expect(lines.last?.text == "Repeated verse\nSecond voice" && lines[2].text.isEmpty,
               "simultaneous voices share one stable line and blank timed lines end a verse")
        let lyrics = NotchLyrics(lines: lines, plain: "", instrumental: false)
        suite.expect(lyrics.activeIndex(at: 0) == nil && lyrics.activeIndex(at: 12.249) == nil
               && lyrics.activeIndex(at: 12.25) == 0 && lyrics.activeIndex(at: 19.875) == 1,
               "lyrics wait for the first timestamp and switch exactly at each line boundary")
        suite.expect(lyrics.activeIndex(at: 19.875, offset: 0.5) == 0
               && lyrics.activeIndex(at: 19.375, offset: -0.5) == 1,
               "positive timing adjustment delays the lyric and a negative adjustment advances it")
        suite.expect(lyrics.activeIndex(at: .nan) == nil && lyrics.activeIndex(at: 12, offset: .infinity) == nil,
               "invalid playback timing never highlights a lyric")
        suite.expect(NotchLyricsSupport.parse("[00:02]later\n[00:01]earlier", duration: 3).map(\.text) == ["earlier", "later"],
               "out-of-order lyric entries are sorted before following playback")
        suite.expect(NotchLyricsSupport.parse("[00:01]line\n[offset:-500]", duration: 2).first?.time == 1.5,
               "a negative file offset delays its lyric timestamps")
        suite.expect(NotchLyricsSupport.parse(String(repeating: "x", count: NotchLyricsSupport.maximumBytes + 1), duration: 10).isEmpty
               && NotchLyricsSupport.parse(String(repeating: "[00:01]line\n", count: 2001), duration: 10).isEmpty,
               "untrusted lyric files have strict byte and entry limits")
        suite.expect(NotchLyricsSupport.parse("unmarked words", duration: 20).isEmpty,
               "a plain text import never invents synchronized positions")

        let query = URLComponents(url: NotchLyricsSupport.lookupURL(for: identity)!, resolvingAgainstBaseURL: false)!
        suite.expect(query.host == "lrclib.net" && query.path == "/api/get"
               && query.queryItems?.first(where: { $0.name == "track_name" })?.value == track.title
               && query.queryItems?.first(where: { $0.name == "artist_name" })?.value == track.artist,
               "song metadata is encoded as query data without broad search or parameter injection")
        var reply: [String: Any] = ["trackName": identity.title, "artistName": identity.artist,
                                    "albumName": identity.album, "duration": 180.0,
                                    "syncedLyrics": "[00:01]Test verse", "instrumental": false]
        func decode() -> NotchLyrics? {
            (try? JSONSerialization.data(withJSONObject: reply)).flatMap { NotchLyricsSupport.decode($0, for: identity) }
        }
        suite.expect(decode()?.lines.count == 1, "an exact recording match can provide synchronized lyrics")
        reply["duration"] = 183.0
        suite.expect(decode() == nil, "a different recording length is not treated as the same synchronized lyric")
        reply["duration"] = 180.0
        reply["albumName"] = "Concert Recording"
        suite.expect(decode() == nil, "a matching title and artist never substitute a different album or live recording")
        reply["albumName"] = identity.album
        let release = RadialNowPlayingSnapshot(title: track.title, artist: track.artist, album: "Studio Recording - EP",
                                               artworkData: nil, appBundleIdentifier: nil, appPID: nil)
        let releaseIdentity = NotchMusicIdentity(NotchPlayback(track: release, isPlaying: true, elapsed: 0, duration: 180,
                                                               rate: 1, sampledAt: playback.sampledAt, canSeek: false))
        let releaseQuery = URLComponents(url: NotchLyricsSupport.lookupURL(for: releaseIdentity)!, resolvingAgainstBaseURL: false)!
        suite.expect(releaseQuery.queryItems?.first(where: { $0.name == "album_name" })?.value == identity.album
               && (try? JSONSerialization.data(withJSONObject: reply)).flatMap { NotchLyricsSupport.decode($0, for: releaseIdentity) } != nil
               && NotchLyricsSupport.catalogAlbum("Single - Single") == "Single"
               && NotchLyricsSupport.catalogAlbum(" - EP") == "- EP",
               "Apple Music's Single and EP album suffixes still find the release's lyrics")
        reply["trackName"] = identity.title + " (Live)"
        suite.expect(decode() == nil, "version qualifiers are not stripped from the lyric match")
        reply["trackName"] = identity.title
        reply["instrumental"] = true
        suite.expect(decode()?.instrumental == true && decode()?.lines.isEmpty == true,
               "instrumental recordings cannot display stray synchronized text")

        // A player that reports no album: the request leaves the field out, and
        // the lyrics service answers with the first record it holds for that
        // title, artist and length, so the reply names a release the track
        // never mentioned.
        let noAlbum = RadialNowPlayingSnapshot(title: "Evening Signal", artist: "Example Artist", album: nil,
                                               artworkData: nil, appBundleIdentifier: nil, appPID: nil)
        let noAlbumIdentity = NotchMusicIdentity(NotchPlayback(track: noAlbum, isPlaying: true, elapsed: 0, duration: 210,
                                                               rate: 1, sampledAt: playback.sampledAt, canSeek: false))
        let noAlbumQuery = URLComponents(url: NotchLyricsSupport.lookupURL(for: noAlbumIdentity)!, resolvingAgainstBaseURL: false)!
        suite.expect(noAlbumQuery.queryItems?.first(where: { $0.name == "album_name" }) == nil,
               "a recording the player reports without an album is still looked up, and names no release")
        let oversized = NotchMusicIdentity(NotchPlayback(
                track: RadialNowPlayingSnapshot(title: "Evening Signal", artist: "Example Artist",
                                                album: String(repeating: "x", count: 1025),
                                                artworkData: nil, appBundleIdentifier: nil, appPID: nil),
                isPlaying: true, elapsed: 0, duration: 210, rate: 1, sampledAt: playback.sampledAt, canSeek: false))
        suite.expect(NotchLyricsSupport.lookupURL(for: oversized) == nil,
               "an album the player does report is still refused past the 1024 byte query limit")
        var noAlbumReply: [String: Any] = ["trackName": "Evening Signal", "artistName": "Example Artist",
                                            "albumName": "Example Release", "duration": 210.0, "instrumental": false,
                                            "plainLyrics": "First line",
                                            "syncedLyrics": "[00:12.30]First line\n[00:16.10]Second line"]
        func decodeNoAlbum() -> NotchLyrics? {
            (try? JSONSerialization.data(withJSONObject: noAlbumReply))
                .flatMap { NotchLyricsSupport.decode($0, for: noAlbumIdentity) }
        }
        suite.expect(decodeNoAlbum()?.lines.count == 2 && decodeNoAlbum()?.lines.first?.text == "First line",
               "lyrics the lyrics service names a release for are kept when the player reports no album")
        noAlbumReply["duration"] = 213.0
        suite.expect(decodeNoAlbum() == nil,
               "a recording the player reports without an album is still matched on its length")
        noAlbumReply["duration"] = 210.0
        noAlbumReply["trackName"] = "Evening Signal (Live)"
        suite.expect(decodeNoAlbum() == nil,
               "a recording the player reports without an album is still matched on its title")
        var named = noAlbumReply
        named["trackName"] = identity.title
        named["artistName"] = identity.artist
        named["albumName"] = "Concert Recording"
        named["duration"] = 180.0
        suite.expect((try? JSONSerialization.data(withJSONObject: named))
               .flatMap { NotchLyricsSupport.decode($0, for: identity) } == nil,
               "an album the player does report still has to name the same release")

        let request = UUID()
        var queue: [String: Any] = ["queueRequest": request.uuidString, "queueAvailable": true,
                                    "currentIdentifier": "current-item", "pid": Int32(42), "queueCanPlay": true,
                                    "queueItems": [["id": "second-item", "offset": 2, "title": "Next known title"]]]
        func decodeQueue() -> NotchQueueSnapshot? { NotchQueueSupport.decode(queue, requestID: request, playback: playback) }
        suite.expect(decodeQueue()?.items.first?.offset == 2 && decodeQueue()?.canPlay == true,
               "omitting an incomplete native queue item never renumbers a later playback action")
        playback.canSendCommandsDirectly = false
        suite.expect(decodeQueue()?.items.count == 1 && decodeQueue()?.canPlay == false,
               "a cached queue preserves its songs but revokes actions when native routing becomes unavailable")
        playback.canSendCommandsDirectly = true
        let cover = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        queue["queueItems"] = [["id": "second-item", "offset": 2, "title": "Next known title",
                                "artworkBase64": cover.base64EncodedString()]]
        suite.expect(decodeQueue()?.items.first?.artwork == cover, "a queued song carries the cover its player gave")
        for invalidCover in ["not base64", "", Data(count: NotchQueueSupport.maximumArtworkBytes + 1).base64EncodedString()] {
            queue["queueItems"] = [["id": "second-item", "offset": 2, "title": "Next known title",
                                    "artworkBase64": invalidCover]]
            suite.expect(decodeQueue()?.items.map(\.title) == ["Next known title"] && decodeQueue()?.items.first?.artwork == nil,
                   "a malformed or oversized cover leaves its song in the queue without a picture")
        }
        queue["queueItems"] = [["id": "second-item", "offset": 2, "title": "Next known title"]]
        queue["currentArtworkBase64"] = cover.base64EncodedString()
        suite.expect(decodeQueue()?.currentArtwork == cover, "a queue carries the playing song's cover for the next list")
        queue["currentArtworkBase64"] = "not base64"
        suite.expect(decodeQueue()?.items.count == 1 && decodeQueue()?.currentArtwork == nil,
               "a malformed playing cover leaves the queue intact")
        queue["currentArtworkBase64"] = nil
        var moved = playback
        moved.itemIdentifier = "second-item"
        func awaits(_ reply: [String: Any], _ playback: NotchPlayback) -> Bool {
            NotchQueueSupport.awaitsSongQueue(reply, requestID: request, playback: playback)
        }
        suite.expect(awaits(queue, moved) && !awaits(queue, playback),
               "a queue anchored to the same player's previous song awaits the new song's queue")
        var elsewhere = queue
        elsewhere["pid"] = 43
        var old = queue
        old["queueRequest"] = UUID().uuidString
        let unavailable: [String: Any] = ["queueRequest": request.uuidString, "queueAvailable": false]
        suite.expect(!awaits(elsewhere, moved) && !awaits(old, moved) && !awaits(unavailable, moved),
               "another player's, an old or an unavailable queue never holds the previous rows")
        func coverQueue(pid: Int32 = 42, current: String = "current-item", currentCover: Data? = nil,
                        _ rows: [(String, Data?)]) -> NotchQueueSnapshot {
            NotchQueueSnapshot(requestID: request, currentIdentifier: current, pid: pid,
                items: rows.enumerated().map { NotchQueueItem(id: $1.0, offset: $0 + 1, title: $1.0, artist: "",
                                                              duration: 0, artwork: $1.1) },
                canPlay: true, currentArtwork: currentCover)
        }
        var decodes = 0
        var covers = NotchQueueCovers<Data>()
        func show(_ queue: NotchQueueSnapshot?) { covers.update(queue) { decodes += 1; return $0 } }
        let firstCover = Data([1]), secondCover = Data([2])
        show(coverQueue([("a", firstCover), ("b", secondCover)]))
        show(coverQueue([("b", nil), ("c", nil)]))
        suite.expect(covers.images == ["b": secondCover] && decodes == 2,
               "the plain list after a song change keeps the covers already shown")
        show(coverQueue([("b", secondCover), ("c", firstCover)]))
        suite.expect(covers.images == ["b": secondCover, "c": firstCover] && decodes == 3,
               "an unchanged cover keeps its decoded image; only a new one is decoded")
        show(nil)
        suite.expect(covers.images.isEmpty, "a missing queue shows no covers")
        show(coverQueue([("b", nil), ("c", nil)]))
        suite.expect(covers.images == ["b": secondCover, "c": firstCover] && decodes == 3,
               "a list shown again reuses its covers without decoding them")
        let playingCover = Data([3])
        show(coverQueue(current: "b", currentCover: playingCover, [("c", nil)]))
        show(coverQueue(current: "a", [("b", nil), ("c", nil)]))
        suite.expect(covers.images == ["b": playingCover, "c": firstCover] && decodes == 4,
               "going back a song shows the cover it had while playing")
        show(coverQueue(pid: 43, [("b", nil)]))
        show(coverQueue([("b", nil)]))
        suite.expect(covers.images.isEmpty,
               "covers belong to one player's queue: another player's song never shows them")
        queue["queueRequest"] = UUID().uuidString
        suite.expect(decodeQueue() == nil, "an old queue request cannot overwrite a reopened surface")
        queue["queueRequest"] = request.uuidString
        queue["currentIdentifier"] = "previous-item"
        suite.expect(decodeQueue() == nil, "queue data must be anchored to the observed current song")
        queue["currentIdentifier"] = "current-item"
        queue["pid"] = 43
        suite.expect(decodeQueue() == nil, "identical song metadata in a different player cannot inherit a queue action")
        queue["pid"] = 42
        let invalidPIDs: [Any] = [true, 42.5, -1, Double.nan, Double(Int32.max) + 1]
        for invalidPID in invalidPIDs {
            queue["pid"] = invalidPID
            suite.expect(decodeQueue() == nil, "a queue rejects malformed or truncated player identities")
        }
        queue["pid"] = 42
        queue["queueItems"] = [] as [[String: Any]]
        suite.expect(decodeQueue()?.items.isEmpty == true, "a genuinely empty queue differs from an unsupported queue")
        queue["queueAvailable"] = false
        suite.expect(decodeQueue() == nil, "a player without a native queue cannot be represented as an empty playlist")
        for invalidRows in [
            [["id": "bad\0item", "offset": 1, "title": "Wrong"]],
            [["id": "second-item", "offset": 0, "title": "Wrong"]],
            [["id": "current-item", "offset": 1, "title": "Already playing"]],
            [["id": "same", "offset": 1, "title": "One"], ["id": "same", "offset": 2, "title": "Two"]]
        ] {
            queue["queueAvailable"] = true
            queue["queueItems"] = invalidRows
            suite.expect(decodeQueue() == nil, "ambiguous or invalid native queue identities fail closed")
        }
        func selection(_ item: String) -> NotchQueueSelection {
            NotchQueueSelection(requestID: request, pid: 42, currentIdentifier: "current-item", itemIdentifier: item, offset: 1)
        }
        for command in [NotchPlaybackCommand.queue(request), .queueStop, .queuePlay(selection("item with spaces\n& unicode 音楽"))] {
            suite.expect(command.message.flatMap(NotchPlaybackCommand.init(message:)) == command,
                   "queue commands round-trip through a bounded data protocol")
        }
        suite.expect(NotchPlaybackCommand.queuePlay(selection(String(repeating: "x", count: 513))).message == nil
               && NotchPlaybackCommand(message: "queue-play \(request.uuidString) invalid-base64") == nil
               && NotchPlaybackCommand.queuePlay(selection("bad\0item")).message == nil,
               "queue identifiers cannot add commands or escape the protocol bound")
        let noPosition = Data(#"{"kMRMediaRemoteNowPlayingInfoTitle":"Example","kMRMediaRemoteNowPlayingInfoDuration":180,"isPlaying":true}"#.utf8)
        suite.expect(NotchPlayback.decode(noPosition)?.hasPosition == false,
               "missing player position never masquerades as a synchronized lyric clock")

        let domain = "com.vorssaint.tests.notch-music-extras"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchLyricsSupport.isEnabled(in: defaults) && !NotchLyricsSupport.onlineEnabled(in: defaults)
               && NotchQueueSupport.isEnabled(in: defaults), "installed music surfaces start enabled while online lyrics stay off")
        let zenSong = { (artist: String, bundle: String) in
            NotchPlayback(track: RadialNowPlayingSnapshot(title: "Stay", artist: artist, album: nil, artworkData: nil,
                                                          appBundleIdentifier: bundle, appPID: 7),
                          isPlaying: true, elapsed: 0, duration: 180, rate: 1, sampledAt: Date(), canSeek: true)
        }
        let rihanna = zenSong("Rihanna", "app.zen-browser.zen")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchBrowserCovers] as? Bool == false
               && !NotchBrowserArtworkSupport.isEnabled(in: defaults)
               && NotchBrowserArtworkSupport.lookupKey(for: rihanna, defaults: defaults) == nil,
               "browser covers stay off until their option is turned on")
        defaults.set(true, forKey: DefaultsKey.notchBrowserCovers)
        let browserCoversOn = NotchBrowserArtworkSupport.isEnabled(in: defaults)
        let rihannaKey = NotchBrowserArtworkSupport.lookupKey(for: rihanna, defaults: defaults)
        suite.expect(rihannaKey != nil
               && rihannaKey != NotchBrowserArtworkSupport.lookupKey(for: zenSong("The Kid LAROI", "app.zen-browser.zen"),
                                                                    defaults: defaults)
               && NotchBrowserArtworkSupport.lookupKey(for: zenSong("Rihanna", "com.apple.Safari"), defaults: defaults) == nil,
               "only a Firefox-family song is looked up, and two songs that share a title keep their own covers")
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(browserCoversOn && !NotchBrowserArtworkSupport.isEnabled(in: defaults)
               && NotchBrowserArtworkSupport.lookupKey(for: rihanna, defaults: defaults) == nil,
               "browser covers follow their own option and stop with the island")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(false, forKey: DefaultsKey.notchLyricsEnabled)
        defaults.set(false, forKey: DefaultsKey.notchQueueEnabled)
        suite.expect(!NotchLyricsSupport.isEnabled(in: defaults) && !NotchQueueSupport.isEnabled(in: defaults),
               "local lyrics and the queue can be turned off")
        defaults.set(true, forKey: DefaultsKey.notchLyricsEnabled)
        defaults.set(true, forKey: DefaultsKey.notchQueueEnabled)
        suite.expect(NotchLyricsSupport.isEnabled(in: defaults) && !NotchLyricsSupport.onlineEnabled(in: defaults)
               && NotchQueueSupport.isEnabled(in: defaults), "local lyrics and the native queue do not grant online lookup")
        defaults.set(true, forKey: DefaultsKey.notchLyricsOnline)
        suite.expect(NotchLyricsSupport.onlineEnabled(in: defaults), "online lyrics require a separate explicit choice")
        defaults.set(false, forKey: AppFeature.notchLyrics.availabilityKey)
        defaults.set(false, forKey: AppFeature.notchQueue.availabilityKey)
        suite.expect(!NotchLyricsSupport.onlineEnabled(in: defaults) && !NotchQueueSupport.isEnabled(in: defaults),
               "feature removal stops native queue reading and lyric metadata sharing")
        defaults.set(true, forKey: AppFeature.notchLyrics.availabilityKey)
        defaults.set(true, forKey: AppFeature.notchQueue.availabilityKey)
        defaults.set("music", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchLyricsSupport.onlineEnabled(in: defaults) && !NotchQueueSupport.isEnabled(in: defaults),
               "hidden music does not retain an optional lyrics or queue subscription")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchLyricsEnabled, DefaultsKey.notchLyricsOnline,
                                                                 DefaultsKey.notchBrowserCovers,
                                                                 DefaultsKey.notchQueueEnabled, DefaultsKey.notchLiveEqualizer, AppFeature.notchLyrics.availabilityKey,
                                                                 AppFeature.notchQueue.availabilityKey]),
               "music feature choices and online consent are accounted for by settings backup")
        for language in AppLanguage.allCases {
            let strings = Mirror(reflecting: FeatureStrings.notchMusicExtras(language)).children.compactMap { $0.value as? String }
            suite.expect(strings.count == 44 && strings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "music extras have complete user-facing strings in \(language.rawValue)")
        }
    }
}
