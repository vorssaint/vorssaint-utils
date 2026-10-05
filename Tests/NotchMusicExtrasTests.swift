// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchMusicExtrasTests {
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

    static func run(_ suite: TestSuite) {
        lyricScheduleContracts(suite)
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
                                                                 DefaultsKey.notchQueueEnabled, DefaultsKey.notchLiveEqualizer, AppFeature.notchLyrics.availabilityKey,
                                                                 AppFeature.notchQueue.availabilityKey]),
               "music feature choices and online consent are accounted for by settings backup")
        for language in AppLanguage.allCases {
            let strings = Mirror(reflecting: FeatureStrings.notchMusicExtras(language)).children.compactMap { $0.value as? String }
            suite.expect(strings.count == 38 && strings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "music extras have complete user-facing strings in \(language.rawValue)")
        }
    }
}
