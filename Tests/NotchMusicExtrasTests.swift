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
        reply["trackName"] = identity.title + " (Live)"
        suite.expect(decode() == nil, "version qualifiers are not stripped from the lyric match")
        reply["trackName"] = identity.title
        reply["instrumental"] = true
        suite.expect(decode()?.instrumental == true && decode()?.lines.isEmpty == true,
               "instrumental recordings cannot display stray synchronized text")

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
        suite.expect(!NotchLyricsSupport.isEnabled(in: defaults) && !NotchLyricsSupport.onlineEnabled(in: defaults)
               && !NotchQueueSupport.isEnabled(in: defaults), "new music surfaces and online metadata sharing start disabled")
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
            suite.expect(strings.count == 37 && strings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "music extras have complete user-facing strings in \(language.rawValue)")
        }
    }
}
