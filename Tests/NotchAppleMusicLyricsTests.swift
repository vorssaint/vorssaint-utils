// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

enum NotchAppleMusicLyricsTests {
    @MainActor class TokenCacheFixture {
        static let log = Logger(subsystem: "vorssaint.tests", category: "AppleMusicTokenCache")
        var subscriberToken: String?
        var subscriberDeveloperToken: String?
        var requestSubscriberToken: @MainActor (String) async throws -> String = { "mock-\($0)" }
    }

    static func run(_ suite: TestSuite) {
        func ttml(_ body: String, timing: String = "Line") -> String {
            "<tt xmlns=\"http://www.w3.org/ns/ttml\" xmlns:itunes=\"http://itunes.apple.com/lyric-ttml-extensions\" xmlns:ttm=\"http://www.w3.org/ns/ttml#metadata\" itunes:timing=\"\(timing)\"><head><metadata><title>Not lyrics</title></metadata></head><body><div>\(body)</div></body></tt>"
        }
        func decode(_ source: String) -> NotchLyrics? { NotchAppleMusicLyricsSupport.decode(source, duration: 30) }
        let lyrics = decode(ttml("""
        <p begin="00:02.125" end="00:04.750"><span begin="00:02.125" end="00:03.000">Star</span><span begin="00:03.000" end="00:04.750">light</span> &amp; sky</p>
        <p begin="00:06.000" end="00:08.000">Second line</p>
        """))
        suite.expect(lyrics?.lines.map(\.time) == [2.125, 4.75, 6, 8]
            && lyrics?.lines.first?.text == "Starlight & sky", "Apple TTML preserves adjoining syllables, XML escapes and exact line timing")
        suite.expect(lyrics?.activeIndex(at: 2.124) == nil && lyrics?.activeIndex(at: 2.125) == 0
            && lyrics?.lines[lyrics!.activeIndex(at: 5)!].text == "", "TTML clears highlighting during instrumental gaps")
        suite.expect(lyrics?.lines.first?.syllables.map(\.range) == [NSRange(location: 0, length: 4), NSRange(location: 4, length: 5)]
            && lyrics?.lines.first?.syllables.map(\.begin) == [2.125, 3]
            && lyrics?.lines.first?.syllables.map(\.end) == [3, 4.75],
                     "TTML retains separate syllable timing and exact text ranges inside adjoining words")
        let unicode = decode(ttml("<p begin=\"1s\" end=\"5s\"><span begin=\"1s\" end=\"2s\">🌙</span> <span begin=\"2s\" end=\"3s\">café</span> <span begin=\"3s\" end=\"5s\">星</span></p>"))
        suite.expect(unicode?.lines.first?.syllables.map(\.range) == [NSRange(location: 0, length: 2), NSRange(location: 3, length: 4), NSRange(location: 8, length: 1)],
                     "native glyph ranges retain emoji, accents and CJK positions")
        let broken = decode(ttml("<p begin=\"1\" end=\"3\"><span begin=\"1\" end=\"2\">🌙</span><br/>\n <span begin=\"2\" end=\"3\">星</span></p>"))
        suite.expect(broken?.lines.first?.text == "🌙\n星" && broken?.lines.first?.voices.first?.text == "🌙\n星"
            && broken?.lines.first?.syllables.map(\.range) == [NSRange(location: 0, length: 2), NSRange(location: 3, length: 1)],
                     "explicit TTML breaks retain line layout, singer text and UTF-16 timed ranges")
        suite.expect(decode(ttml("<p><br/>First<br/><br/>Second<br/></p>", timing: "None"))?.plain == "First\n\nSecond"
            && decode(ttml("<p begin=\"1\" end=\"2\"><br/></p>")) == nil,
                     "explicit internal breaks survive without introducing empty-only or leading/trailing lyric rows")
        let background = decode(ttml("<p begin=\"1s\" end=\"3s\"><span ttm:role=\"x-bg\"><span begin=\"1s\" end=\"3s\">Background</span></span></p>"))
        suite.expect(background?.lines.first?.syllables.first?.background == true, "background-vocal timing survives nested spans")
        let syllable = NotchLyricSyllable(range: NSRange(location: 0, length: 4), begin: 2, end: 4)
        suite.expect(syllable.progress(at: 1) == 0 && syllable.progress(at: 3) == 0.5 && syllable.progress(at: 5) == 1,
                     "native karaoke progress clamps before and after the sung syllable")
        let plain = decode(ttml("<p>First plain verse</p><p>Another verse</p>", timing: "None"))
        suite.expect(plain?.lines.isEmpty == true && plain?.plain == "First plain verse\nAnother verse",
                     "untimed Apple lyrics stay readable without fabricated timestamps or metadata text")
        suite.expect(decode(ttml("<p begin=\"1s\" end=\"2s\">Timed</p><p>Untimed</p>"))?.lines.isEmpty == true,
                     "partially timed documents fall back to complete plain lyrics")
        suite.expect(decode(ttml("<p><span begin=\"2000ms\" end=\"3s\">Span timing</span></p>"))?.lines.first?.time == 2,
                     "paragraphs can derive their timing from spans")
        let duet = decode(ttml("<p begin=\"2s\" end=\"5s\">First voice</p><p begin=\"2s\" end=\"4s\">Second voice</p><p begin=\"4s\" end=\"6s\">Overlap</p>"))
        suite.expect(duet?.lines.map(\.time) == [2, 4, 6] && duet?.lines.first?.text == "First voice\nSecond voice",
                     "simultaneous voices share a stable row and overlapping endings do not create false gaps")
        for invalid in ["<tt>", "<html><p>Wrong format</p></html>",
            ttml("<p begin=\"NaN\" end=\"2s\">Invalid</p>"),
            ttml("<p begin=\"3s\" end=\"2s\">Reversed</p>"),
            ttml("<p begin=\"00:99\" end=\"2s\">Invalid clock</p>"),
            ttml("<p begin=\"1s\" end=\"2s\"><span begin=\"3s\" end=\"4s\">Outside parent</span></p>"),
            "<!DOCTYPE tt [<!ENTITY test 'expanded'>]>" + ttml("<p>&test;</p>"),
            String(repeating: "x", count: NotchLyricsSupport.maximumBytes + 1),
            ttml(String(repeating: "<p>many</p>", count: NotchLyricsSupport.maximumLines + 1))] {
            suite.expect(decode(invalid) == nil, "invalid, oversized or entity-bearing TTML is rejected")
        }
        suite.expect(decode("[00:01.50]Apple LRC")?.lines.first?.time == 1.5,
                     "LRC supplied by Apple retains its existing timing semantics")
        suite.expect(NotchAppleMusicLyricsSupport.time("01:02:03.456") == 3723.456
            && NotchAppleMusicLyricsSupport.time("1e9s") == nil,
                     "Apple clock times support hours and reject nonliteral numeric forms")
        let webLyrics = decode(ttml("<p begin=\"2.125\" end=\"4.750\"><span begin=\"2.125\" end=\"3.000\">Web</span> <span begin=\"3.000\" end=\"4.750\">timing</span></p>", timing: "Word"))
        suite.expect(webLyrics?.lines.first?.time == 2.125 && webLyrics?.lines.first?.text == "Web timing"
            && webLyrics?.lines.last?.time == 4.75,
                     "bare decimal seconds from the live Apple web service decode at paragraph and syllable level")
        suite.expect(NotchAppleMusicLyricsSupport.time("0") == 0
            && NotchAppleMusicLyricsSupport.time("1e9") == nil
            && NotchAppleMusicLyricsSupport.time("Infinity") == nil
            && NotchAppleMusicLyricsSupport.time("-0.5") == nil,
                     "bare Apple times accept zero and reject scientific notation, infinity and negatives")
        for value in ["", "0", "000", "-1", "abc", "123/lyrics", String(repeating: "1", count: 21)] {
            suite.expect(NotchAppleMusicLyricsSupport.validCatalogID(value) == nil, "only bounded positive decimal catalog IDs enter Apple URLs")
        }
        let data = Data("{\"catalogIdentifier\":\"1851140680\",\"itemIdentifier\":\"library-item\"}".utf8)
        suite.expect(RadialNowPlayingSupport.adapterReply(from: data)?.info["catalogIdentifier"] as? String == "1851140680",
                     "catalog IDs survive the adapter without replacing the player's queue identifier")
        let domain = "com.vorssaint.tests.apple-music-lyrics"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchLyricsProvider.selected(in: defaults) == .lrclib, "existing installations retain LRCLIB")
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set("unknown-provider", forKey: DefaultsKey.notchLyricsProvider)
        suite.expect(NotchLyricsProvider.selected(in: defaults) == .lrclib, "an unknown restored provider falls back to LRCLIB")
        defaults.set(NotchLyricsProvider.appleMusic.rawValue, forKey: DefaultsKey.notchLyricsProvider)
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchLyricsEnabled)
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        let track = RadialNowPlayingSnapshot(title: "Song", artist: "Artist", album: nil, artworkData: nil,
                                            appBundleIdentifier: "com.apple.Music", appPID: 42)
        let playback = NotchPlayback(track: track, isPlaying: true, elapsed: 0, duration: 30,
                                     rate: 1, sampledAt: .now, canSeek: false)
        suite.expect(!NotchAppleMusicLyricsSupport.canLoad(NotchMusicIdentity(playback), in: defaults),
                     "choosing Apple Music alone does not authorize online requests")
        defaults.set(true, forKey: DefaultsKey.notchLyricsOnline)
        suite.expect(NotchAppleMusicLyricsSupport.canLoad(NotchMusicIdentity(playback), in: defaults),
                     "Apple lyrics require both online consent and playback from Music.app")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchLyricsProvider),
                     "the provider preference participates in settings backup")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchLyricsAppleMusicConnected),
                     "native account connection is machine state and never restored as an authorization grant")
        var song: [String: Any] = ["id": "123", "attributes": ["name": "Song", "artistName": "Artist", "albumName": "Release", "durationInMillis": 30000]]
        suite.expect(NotchAppleMusicLyricsSupport.matches(song, track: NotchMusicIdentity(playback), searching: true),
                     "native catalog matching accepts the exact recording")
        song["attributes"] = ["name": "Song", "artistName": "Other", "durationInMillis": 30000]
        suite.expect(!NotchAppleMusicLyricsSupport.matches(song, track: NotchMusicIdentity(playback), searching: true),
                     "native catalog search rejects a different artist")
        func jwt(_ issuer: String, expires: Double) -> String {
            let data = try! JSONSerialization.data(withJSONObject: ["iss": issuer, "exp": expires])
            return "eyJfake." + data.base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") + ".signature"
        }
        let now = Date(timeIntervalSince1970: 1_000_000)
        suite.expect(NotchAppleMusicLyricsSupport.publicTokenExpiration(jwt("AMPWebPlay", expires: 1_010_000), now: now) != nil
            && NotchAppleMusicLyricsSupport.publicTokenExpiration(jwt("OtherIssuer", expires: 1_010_000), now: now) == nil
            && NotchAppleMusicLyricsSupport.publicTokenExpiration(jwt("AMPWebPlay", expires: 999_999), now: now) == nil,
                     "native bootstrap selects only the unexpired public Apple developer token")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.notchAppleMusicLyrics(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            suite.expect(values.count == 18 && values.allSatisfy { !$0.isEmpty },
                         "every supported language supplies Apple Music lyrics controls and explanations")
        }
        lifecycle(suite)
        duetAndMotion(suite)
        fileEncodingAndGaps(suite)
        tokenCache(suite)
    }

    private static func tokenCache(_ suite: TestSuite) {
        var finished = false
        Task { @MainActor in await tokenCacheChecks(suite); finished = true }
        let deadline = Date().addingTimeInterval(5)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        suite.expect(finished, "native subscriber-token lifecycle checks finish")
    }

    @MainActor private static func tokenCacheChecks(_ suite: TestSuite) async {
        let cache = TokenCache()
        var reply: CheckedContinuation<String, Error>?
        cache.requestSubscriberToken = { _ in
            try await withCheckedThrowingContinuation { reply = $0 }
        }
        let pending = Task { @MainActor in try await cache.loadSubscriberToken(for: "developer-a") }
        for _ in 0..<500 {
            if reply != nil { break }
            await Task.yield()
        }
        guard let reply else { pending.cancel(); suite.expect(false, "subscriber request reaches its pending reply"); return }
        // Disconnect clears the cache while MusicKit's request is still pending.
        pending.cancel()
        cache.subscriberToken = nil
        cache.subscriberDeveloperToken = nil
        reply.resume(returning: "late-mock-subscriber")
        do {
            _ = try await pending.value
            suite.expect(false, "a late subscriber reply fails after cancellation")
        } catch {
            suite.expect(error is CancellationError && cache.subscriberToken == nil && cache.subscriberDeveloperToken == nil,
                         "a cancelled native subscriber request cannot refill the disconnected token cache")
        }
        var requests = 0
        cache.requestSubscriberToken = { developer in requests += 1; return "mock-\(developer)" }
        do {
            let first = try await cache.loadSubscriberToken(for: "developer-a")
            let repeated = try await cache.loadSubscriberToken(for: "developer-a")
            suite.expect(first == repeated && cache.subscriberToken == first && requests == 1,
                         "an active native subscriber request caches and reuses its token")
            let renewed = try await cache.loadSubscriberToken(for: "developer-b")
            suite.expect(renewed != first && requests == 2 && cache.subscriberDeveloperToken == "developer-b",
                         "a changed developer token requests a matching new subscriber token")
        } catch { suite.expect(false, "uncancelled subscriber requests remain available") }
    }

    private static func fileEncodingAndGaps(_ suite: TestSuite) {
        let xml = """
        <tt xmlns="http://www.w3.org/ns/ttml"><body><div>
        <p begin="12" end="14"><span begin="12" end="13">Local</span> <span begin="13" end="14">file</span></p>
        <p begin="26" end="28">Next</p></div></body></tt>
        """
        let original = NotchAppleMusicLyricsSupport.decode(xml, duration: 40)
        let utf8 = Data([0xEF, 0xBB, 0xBF]) + Data(xml.utf8)
        let utf16 = ("<?xml version=\"1.0\" encoding=\"UTF-16\"?>" + xml).data(using: .utf16)!
        suite.expect(NotchAppleMusicLyricsSupport.decode(utf8, duration: 40) == original
            && NotchAppleMusicLyricsSupport.decode(utf16, duration: 40) == original,
                     "local TTML byte decoding respects UTF-8 and UTF-16 BOMs and declarations")
        suite.expect(NotchAppleMusicLyricsSupport.decode(Data("[00:01]LRC file".utf8), duration: 40)?.lines.first?.text == "LRC file",
                     "the unified file decoder preserves ordinary LRC imports")
        guard let lyrics = original else { suite.expect(false, "TTML gap fixture decoded"); return }
        suite.expect(lyrics.instrumentalGap(at: 2, duration: 40)?.begin == 0
            && lyrics.instrumentalGap(at: 2, duration: 40)?.end == 12, "a long intro has a three-dot waiting interval")
        suite.expect(lyrics.instrumentalGap(at: 13, duration: 40) == nil, "no dots appear while a voice is singing")
        let gap = lyrics.instrumentalGap(at: 20, duration: 40)
        suite.expect(gap?.begin == 14 && gap?.end == 26 && gap?.progress(at: 20) == 0.5,
                     "the indicator progresses through a known silent interval")
        suite.expect(lyrics.instrumentalGap(at: 30, duration: 40)?.nextIndex == nil
            && lyrics.instrumentalGap(at: 40, duration: 40) == nil, "a known outro shows dots only until playback ends")
        suite.expect(lyrics.instrumentalGap(at: 21, offset: 1, duration: 40) == gap,
                     "gap indicators follow the same user timing adjustment as lyrics")
        let lrc = NotchLyrics(lines: NotchLyricsSupport.parse("[00:01]Verse\n[00:10]Next", duration: 40), plain: "", instrumental: false)
        suite.expect(lrc.instrumentalGap(at: 13, duration: 40) == nil, "LRC without end cues does not invent an instrumental break")
        let short = NotchLyrics(lines: [.init(time: 0, text: "Verse", end: 2), .init(time: 2, text: ""), .init(time: 4, text: "Next")], plain: "", instrumental: false)
        suite.expect(short.instrumentalGap(at: 3, duration: 40) == nil, "short pauses do not clutter the lyric list with dots")
        suite.expect(short.activeIndices(at: 3, duration: 40) == [0], "a short end cue keeps the completed verse readable")
        let middle = NotchLyrics(lines: [.init(time: 39.115, text: "Verse", end: 42.114), .init(time: 42.114, text: ""),
            .init(time: 53.781, text: "Next", end: 57.958)], plain: "", instrumental: false)
        suite.expect(middle.instrumentalGap(at: 44, duration: 189)?.begin == 42.114
            && middle.scrollTarget(at: 44, duration: 189) == .gap(42.114)
            && middle.activeIndices(at: 44, duration: 189).isEmpty,
                     "an eleven-second middle-song pause displays dots and becomes the scroll target")
        let track = RadialNowPlayingSnapshot(title: "Middle pause", artist: nil, album: nil, artworkData: nil, appBundleIdentifier: nil, appPID: nil)
        let playback = NotchPlayback(track: track, isPlaying: true, elapsed: 40, duration: 189, rate: 1, sampledAt: .now, canSeek: false)
        suite.expect(middle.changeDates(for: playback, offset: 0, from: playback.sampledAt)
            .contains { abs($0.timeIntervalSince(playback.sampledAt) - 2.114) < 0.0001 },
                     "the display schedules the middle-song dots at the actual end cue")
        let credits = """
        <tt xmlns="http://www.w3.org/ns/ttml" xmlns:itunes="http://music.apple.com/lyric-ttml-internal">
        <head><metadata><itunes:iTunesMetadata><itunes:songwriters><itunes:songwriter>Writer One</itunes:songwriter>
        <itunes:songwriter>Writer Two</itunes:songwriter><itunes:songwriter>Writer One</itunes:songwriter>
        </itunes:songwriters></itunes:iTunesMetadata></metadata></head>
        <body><div><p begin="1" end="2">Words</p></div></body></tt>
        """
        suite.expect(NotchAppleMusicLyricsSupport.decode(credits, duration: 10)?.writers == ["Writer One", "Writer Two"],
                     "Written By credits preserve source names and remove duplicate metadata entries")
        suite.expect(lyrics.instrumentalGaps(duration: 40).map(\.begin) == [0, 14, 28],
                     "waiting rows have stable identities independent of current playback")
        suite.expect(lyrics.scrollTarget(at: 11.5, duration: 40) == .gap(0)
            && lyrics.scrollTarget(at: 11.8, duration: 40) == .line(0)
            && lyrics.scrollTarget(at: 12.1, duration: 40) == .line(0),
                     "handoff scroll starts before vocals and keeps the same target at the boundary")
        suite.expect(NotchKaraokeMotion.gapOpacity(at: 11.6, begin: 0, end: 12, discrete: false) == 1
            && NotchKaraokeMotion.gapOpacity(at: 11.85, begin: 0, end: 12, discrete: false) < 0.6
            && NotchKaraokeMotion.gapOpacity(at: 12, begin: 0, end: 12, discrete: false) == 0,
                     "the dots fade out while their layout slot remains in place")
    }

    private static func duetAndMotion(_ suite: TestSuite) {
        let source = """
        <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
        <head><metadata><ttm:agent xml:id="lead" type="person"/><ttm:agent xml:id="guest" type="person"/>
        <ttm:agent xml:id="both" type="group"/><ttm:agent xml:id="other" type="other"/></metadata></head>
        <body><div ttm:agent="lead">
        <p begin="1" end="5"><span begin="1" end="5">Lead</span><span ttm:role="x-bg" ttm:agent="guest"><span begin="3" end="5"> echo</span></span></p>
        <p begin="3" end="7" ttm:agent="guest"><span begin="3" end="7">Answer</span></p>
        <p begin="8" end="9" ttm:agent="both">Together</p>
        <p begin="10" end="11" ttm:agent="other">Another voice</p>
        </div></body></tt>
        """
        guard let lyrics = NotchAppleMusicLyricsSupport.decode(source, duration: 12) else {
            suite.expect(false, "duet TTML decodes"); return
        }
        let visible = lyrics.lines.filter { !$0.text.isEmpty }
        suite.expect(visible[0].voices.first?.agent == "lead" && visible[0].voices.first?.side == .leading
            && visible[1].voices.first?.side == .trailing,
                     "inherited and explicit singer agents retain independent left/right alignment")
        suite.expect(visible[0].voices.count == 2 && visible[0].voices[1].background
            && visible[0].voices[1].side == .trailing && visible[0].voices[1].text == "echo"
            && visible[0].voices[1].syllables.first?.range == NSRange(location: 0, length: 4),
                     "inline background vocals become their own smaller voice with local glyph ranges")
        suite.expect(visible[2].voices.first?.side == .center && visible[3].voices.first?.side == .trailing,
                     "group and other-agent metadata are distinct from the main singer")
        suite.expect(lyrics.activeIndices(at: 4) == [0, 1] && lyrics.focusIndex(at: 4) == 0
            && lyrics.activeIndices(at: 6) == [1], "overlapping singers stay highlighted until their individual ends")
        suite.expect(lyrics.activeIndices(at: 7.5) == [1] && lyrics.focusIndex(at: 7.5) == 1,
                     "a short pause holds the preceding verse highlighted instead of jumping or inventing interlude dots")
        let track = RadialNowPlayingSnapshot(title: "Duet", artist: nil, album: nil, artworkData: nil, appBundleIdentifier: nil, appPID: nil)
        let playback = NotchPlayback(track: track, isPlaying: true, elapsed: 0, duration: 12, rate: 1, sampledAt: .now, canSeek: false)
        let boundaries = lyrics.changeDates(for: playback, offset: 0, from: playback.sampledAt)
            .filter { $0 != .distantFuture }.map { $0.timeIntervalSince(playback.sampledAt) }
        suite.expect(boundaries.contains { abs($0 - 5) < 0.0001 } && boundaries.contains { abs($0 - 7.45) < 0.0001 },
                     "voice endings and animation tails are scheduled even during overlaps and silence")
        let before = NotchKaraokeMotion.word(at: 0, begin: 1, end: 4, background: false, discrete: false)
        let during = NotchKaraokeMotion.word(at: 2, begin: 1, end: 4, background: false, discrete: false)
        let after = NotchKaraokeMotion.word(at: 5, begin: 1, end: 4, background: false, discrete: false)
        suite.expect(before.lift == 0 && during.lift < 0 && during.scale > 1 && abs(after.lift) < 0.0001 && after.scale == 1,
                     "sustained words rise and breathe, then settle without changing text layout")
        let reduced = NotchKaraokeMotion.word(at: 2, begin: 1, end: 4, background: false, discrete: true)
        suite.expect(reduced.lift == 0 && reduced.scale == 1 && reduced.glow == 0,
                     "Reduced Motion disables word and emphasis transforms")
        suite.expect(!NotchKaraokeMotion.needsClock(at: 7.5, begin: 3, end: 7),
                     "finished voices stop their display clock after the visual transition")
        let resting = NotchKaraokeMotion.gap(at: 0, begin: 0, end: 15, discrete: false)
        let expanded = NotchKaraokeMotion.gap(at: 2.5, begin: 0, end: 15, discrete: false)
        let nextCycle = NotchKaraokeMotion.gap(at: 5, begin: 0, end: 15, discrete: false)
        suite.expect(resting.scale < 0.2 && abs(expanded.scale - 1.2) < 0.0001 && nextCycle.scale == 1,
                     "the dots spawn small and then share a repeating five-second heartbeat")
        let peak = NotchKaraokeMotion.gap(at: 14.4, begin: 0, end: 15, discrete: false)
        let ending = NotchKaraokeMotion.gap(at: 14.95, begin: 0, end: 15, discrete: false)
        suite.expect(peak.scale > 1.39 && ending.scale < 1.05 && ending.opacities[0] == 1 && ending.opacities[1] == 1,
                     "the final pulse grows then shrinks smoothly before vocals while completed dots remain lit")
        let approach = (0...90).map { NotchKaraokeMotion.gap(at: 13.5 + Double($0) / 60, begin: 0, end: 15, discrete: false).scale }
        suite.expect(zip(approach, approach.dropFirst()).allSatisfy { abs($1 - $0) < 0.03 },
                     "the final grow-and-shrink pulse has no discontinuous scale reset")
        suite.expect(NotchKaraokeMotion.gapSlotHeight(at: 20, begin: 20, end: 32, discrete: false) == 0
            && NotchKaraokeMotion.gapSlotHeight(at: 20.2, begin: 20, end: 32, discrete: false) > 20
            && NotchKaraokeMotion.gapSlotHeight(at: 20.4, begin: 20, end: 32, discrete: false) == 42,
                     "the middle-song indicator's row opens smoothly instead of spawning a sudden gap")
        let reducedGap = NotchKaraokeMotion.gap(at: 7, begin: 0, end: 15, discrete: true)
        suite.expect(reducedGap.scale == 1 && reducedGap.opacities == [1, 1, 0.3],
                     "Reduced Motion keeps the dots stationary with discrete progress")
        suite.expect(NotchKaraokeMotion.gap(at: .nan, begin: 0, end: 15, discrete: false).scale == 1,
                     "invalid clock samples cannot deform the waiting indicator")
    }

    private static func lifecycle(_ suite: TestSuite) {
        typealias Context = NotchLyricsContract
        Context.Preferences.enabled = true
        Context.Preferences.online = true
        Context.Preferences.appleMusic = false
        let provider = Context.NotchAppleMusicLyricsProvider.shared
        provider.replies = []
        defer { Context.Preferences.online = false; Context.Preferences.appleMusic = false; provider.replies = [] }
        func playback(_ name: String, bundle: String = "com.apple.Music") -> NotchPlayback {
            let track = RadialNowPlayingSnapshot(title: name, artist: "Artist", album: nil, artworkData: nil,
                                                appBundleIdentifier: bundle, appPID: 42)
            return NotchPlayback(track: track, isPlaying: true, elapsed: 0, duration: 30, rate: 1,
                                 sampledAt: .now, canSeek: false)
        }
        let song = playback("First"), next = playback("Next")
        let service = Context.Service()
        service.update(playback: song, visible: true)
        let lyrics = NotchLyrics(lines: [.init(time: 1, text: "LRCLIB")], plain: "", instrumental: false)
        service.memory.replace(lyrics, for: NotchMusicIdentity(song))
        Context.Preferences.appleMusic = true
        service.update(playback: song, visible: true)
        suite.expect(service.lyrics == nil && service.usesAppleMusic && service.loads.count == 1 && provider.replies.count == 1,
                     "switching to Apple clears LRCLIB lyrics and issues only an Apple request")
        let old = provider.replies[0]
        service.playbackChanged(next)
        old(.ready(lyrics))
        suite.expect(service.lyrics == nil && service.track == NotchMusicIdentity(next), "late Apple replies cannot replace the next song")
        provider.replies.last?(.unavailable)
        suite.expect(service.state == .unavailable && service.loads.count == 1, "missing Apple lyrics do not fall back to LRCLIB")
        service.update(playback: playback("Other", bundle: "com.spotify.client"), visible: true)
        suite.expect(service.state == .appleMusicOnly && provider.replies.count == 2 && service.loads.count == 1,
                     "Apple provider does not query Apple or LRCLIB for another player's song")
        service.playbackChanged(song)
        let hidden = provider.replies.last!
        service.hide()
        hidden(.ready(lyrics))
        suite.expect(service.lyrics == nil, "hiding invalidates Apple replies still in flight")
        service.disconnectAppleMusic()
        suite.expect(service.state == .appleMusicSignIn, "disabling access marks a hidden Lyrics view as requiring access")
        service.connectAppleMusic()
        suite.expect(service.state == .idle && service.lyrics == nil && provider.replies.count == 3,
                     "enabling access from Settings clears a stale access error without pretending lyrics were fetched")
        Context.Preferences.online = false
        service.update(playback: next, visible: true)
        suite.expect(service.state == .consent && provider.replies.count == 3, "disabling online lookup prevents further Apple requests")
    }
}
