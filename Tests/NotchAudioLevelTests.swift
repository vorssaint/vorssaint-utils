// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

enum NotchAudioLevelTests {
    static func run(expect: (Bool, String) -> Void) {
        let bands = NotchAudioLevelSupport.bandRanges(sampleRate: 48_000, size: 1024)
        expect(bands.count == 7 && bands.allSatisfy { !$0.isEmpty && $0.lowerBound >= 1 && $0.upperBound <= 512 }
               && zip(bands, bands.dropFirst()).allSatisfy { $0.upperBound <= $1.lowerBound },
               "seven ordered bands cover the usable spectrum without the DC bin")
        let narrow = NotchAudioLevelSupport.bandRanges(sampleRate: 8_000, size: 64)
        expect(narrow.count == 7 && narrow.allSatisfy { !$0.isEmpty && $0.upperBound <= 32 },
               "a narrow spectrum still gives every band at least one bin")
        var magnitudes = [Float](repeating: 0, count: 512)
        expect(NotchAudioLevelSupport.bandLevels(magnitudes: magnitudes, bands: bands).allSatisfy { $0 == 0 },
               "silence is flat")
        magnitudes[Int(700 / (48_000 / 1024.0))] = 0.5
        let levels = NotchAudioLevelSupport.bandLevels(magnitudes: magnitudes, bands: bands)
        expect(levels.count == 7 && levels[3] > 0 && levels.enumerated().allSatisfy { $0.offset == 3 || $0.element == 0 },
               "a 700 Hz tone lights only the band that holds it")
        var smoother = NotchAudioLevelSupport.Smoother()
        let first = smoother.next([0, 0, 0, 1, 0, 0, 0])
        let second = smoother.next([0, 0, 0, 1, 0, 0, 0])
        expect(first[3] > 0.4 && second[3] > first[3] && second[3] <= 1, "bars rise quickly toward their target")
        let released = smoother.next([0, 0, 0, 0, 0, 0, 0])
        expect(released[3] < second[3] && released[3] > second[3] * 0.7, "bars fall more slowly than they rise")
        var quiet = NotchAudioLevelSupport.Smoother()
        var scaled: [Double] = []
        for _ in 0..<12 { scaled = quiet.next([0.1, 0.2, 0.3, 0.3, 0.2, 0.1, 0.05]) }
        expect(scaled.max().map { $0 > 0.8 } == true, "a quiet source still fills the meter")
        expect(NotchAudioLevelSupport.barIndex(0, of: 3, bands: 7) == 1 && NotchAudioLevelSupport.barIndex(1, of: 3, bands: 7) == 3
               && NotchAudioLevelSupport.barIndex(2, of: 3, bands: 7) == 5 && NotchAudioLevelSupport.barIndex(6, of: 7, bands: 7) == 6,
               "fewer bars sample the bands evenly")
        expect(!NotchAudioLevelSupport.fallsBack(heard: false, elapsed: 1) && !NotchAudioLevelSupport.fallsBack(heard: true, elapsed: 10)
               && NotchAudioLevelSupport.fallsBack(heard: false, elapsed: NotchAudioLevelSupport.silenceGrace),
               "a tap that only ever delivers silence hands the bars back to their synthetic motion")
        let domain = "com.vorssaint.tests.audio-levels"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        expect(!NotchAudioLevelSupport.isEnabled(in: defaults),
                "the live equalizer stays off until chosen")
        expect(NotchAudioLevelSupport.silenceGrace >= 5,
               "a tap outlasts a permission prompt being read and a player that buffers before it sounds")
        silenceMemoryContracts(expect: expect)
        tapChangeContracts(expect: expect)
        NotchAudioLevelLifecycleContract.run(expect: expect)
    }

    /// What the player's audio processes moving asks of the tap. A browser
    /// opens and closes the process that makes its sound as tabs come and
    /// go, and the tap is deaf to every one it was not built from.
    private static func tapChangeContracts(expect: (Bool, String) -> Void) {
        let built: Set<Int> = [10, 11]
        expect(NotchAudioLevelSupport.tapChange(tapped: built, current: built) == .none,
               "a process list that stirs around the player leaves its tap alone")
        expect(NotchAudioLevelSupport.tapChange(tapped: built, current: [10, 11, 12]) == .rebuild,
               "a process the player adds is heard by building the tap again around all of them")
        expect(NotchAudioLevelSupport.tapChange(tapped: built, current: [10]) == .restart,
               "a process that leaves takes the tap's ears with it, so the player is read anew")
        expect(NotchAudioLevelSupport.tapChange(tapped: built, current: [10, 12]) == .restart,
               "one leaving while another arrives still counts as leaving")
        expect(NotchAudioLevelSupport.tapChange(tapped: built, current: []) == .restart,
               "a player with no audio process left is read from scratch, not rebuilt around nothing")
        expect(NotchAudioLevelSupport.processSettle > 0 && NotchAudioLevelSupport.processSettle < 1,
               "the player's processes are read once a burst has settled, and within the same play")
    }

    /// Giving up on a silent tap must cost one play, never the session.
    private static func silenceMemoryContracts(expect: (Bool, String) -> Void) {
        func playback(_ title: String, pid: pid_t) -> NotchPlayback {
            let track = RadialNowPlayingSnapshot(title: title, artist: "Artist", album: "Album",
                                                 artworkData: nil, appBundleIdentifier: "org.example.player",
                                                 appPID: pid)
            return NotchPlayback(track: track, isPlaying: true, elapsed: 0, duration: 180, rate: 1,
                                 sampledAt: Date(timeIntervalSinceReferenceDate: 0), canSeek: false,
                                 itemIdentifier: title, canSendCommandsDirectly: true)
        }
        let first = NotchMusicIdentity(playback("First", pid: 42))
        let second = NotchMusicIdentity(playback("Second", pid: 42))
        let other = NotchMusicIdentity(playback("First", pid: 43))
        var memory = NotchAudioLevelSupport.SilenceMemory()
        expect(memory.reads(first), "a player is read before anything is known about it")
        memory.giveUp(on: first)
        expect(!memory.reads(first), "the play a tap stayed silent on keeps the synthetic motion")
        expect(memory.reads(second) && memory.reads(other),
               "another track, or another player, is still read")
        memory.giveUp(on: first)
        memory.rearm()
        expect(memory.reads(first), "pressing play again reads the same track once more")
    }
}


/// The production service is extracted here; only its preference inputs,
/// playback publisher and asynchronous hardware reader are replaced.
typealias NotchAudioTestSilenceMemory = NotchAudioLevelSupport.SilenceMemory

enum NotchAudioLevelLifecycleContract {
    enum AppFeature {
        case notchLiveEqualizer
        var isAvailable: Bool { true }
    }
    enum NotchSupport { static func isEnabled() -> Bool { true } }
    enum NotchAudioLevelSupport {
        typealias SilenceMemory = NotchAudioTestSilenceMemory
        static let isSupported = true
        static var enabled = false
        static func isEnabled() -> Bool { enabled }
    }
    final class NotchMusicService {
        static let shared = NotchMusicService()
        @Published var playback: NotchPlayback?
    }
    final class NotchAudioLevelReader {
        static var instances: [NotchAudioLevelReader] = []
        let onLevels: ([Double]) -> Void
        let onSilence: () -> Void
        let onUnavailable: () -> Void
        let onProcessesLeft: () -> Void
        private(set) var stopped = false

        init(pid: pid_t, onLevels: @escaping ([Double]) -> Void,
             onSilence: @escaping () -> Void, onUnavailable: @escaping () -> Void,
             onProcessesLeft: @escaping () -> Void) {
            self.onLevels = onLevels
            self.onSilence = onSilence
            self.onUnavailable = onUnavailable
            self.onProcessesLeft = onProcessesLeft
            Self.instances.append(self)
        }
        func start() {}
        func stop() { stopped = true }
    }

    static func run(expect: (Bool, String) -> Void) {
        typealias Reader = NotchAudioLevelReader
        let service = NotchAudioLevelService.shared
        let music = NotchMusicService.shared
        func playback(playing: Bool = true) -> NotchPlayback {
            let track = RadialNowPlayingSnapshot(title: "Track", artist: "Artist", album: "Album",
                                                artworkData: nil, appBundleIdentifier: "org.example.player",
                                                appPID: 42)
            return NotchPlayback(track: track, isPlaying: playing, elapsed: 0, duration: 180, rate: 1,
                                 sampledAt: Date(timeIntervalSinceReferenceDate: 0), canSeek: false,
                                 itemIdentifier: "track", canSendCommandsDirectly: true)
        }
        // A barrier behind the service's callbacks drains only the main queue;
        // it neither creates a device nor depends on a player's timing.
        func drain() {
            var reached = false
            DispatchQueue.main.async { reached = true }
            let deadline = Date().addingTimeInterval(1)
            while !reached && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.001))
            }
            expect(reached, "the audio lifecycle fixture drains its callback queue")
        }
        func enable(_ value: Bool) {
            NotchAudioLevelSupport.enabled = value
            service.syncWithPreferences()
            drain()
        }
        defer {
            enable(false)
            music.playback = nil
            Reader.instances.removeAll()
            drain()
        }
        music.playback = playback()
        enable(true)
        guard let first = Reader.instances.last else {
            expect(false, "playing starts an audio reader")
            return
        }
        var current = first
        let lateCallbacks: [(String, (Reader) -> Void)] = [
            ("levels", { $0.onLevels([0.1]) }),
            ("silence", { $0.onSilence() }),
            ("unavailable", { $0.onUnavailable() }),
            ("departing processes", { $0.onProcessesLeft() })
        ]
        for (name, callback) in lateCallbacks {
            let previous = current
            enable(false)
            enable(true)
            guard let replacement = Reader.instances.last else { return }
            current = replacement
            expect(previous.stopped && previous !== current && !current.stopped,
                   "reenabling the equalizer replaces the reader for the same player")
            let count = Reader.instances.count
            current.onLevels([0.75])
            drain()
            callback(previous)
            drain()
            expect(!current.stopped && Reader.instances.count == count && service.levels == [0.75],
                   "late \(name) from a stopped reader cannot change its replacement")
        }
        let previous = current
        let beforeRestart = Reader.instances.count
        current.onProcessesLeft()
        drain()
        expect(previous.stopped && Reader.instances.count == beforeRestart + 1 && service.levels == nil,
               "the current reader's departing processes still restart its tap")
        guard let restarted = Reader.instances.last else { return }
        current = restarted
        current.onLevels([0.6])
        drain()
        previous.onUnavailable()
        drain()
        expect(!current.stopped && service.levels == [0.6],
               "an old route failure cannot stop a reader created by process recovery")
        current.onSilence()
        drain()
        let afterSilence = Reader.instances.count
        music.playback = playback()
        drain()
        expect(current.stopped && service.levels == nil && Reader.instances.count == afterSilence,
               "a silent current reader falls back for this play without immediately retrying")
        music.playback = playback(playing: false)
        drain()
        music.playback = playback()
        drain()
        expect(Reader.instances.count == afterSilence + 1,
               "pausing and playing rearms the same track after silence")
        guard let resumed = Reader.instances.last else { return }
        music.playback = playback(playing: false)
        drain()
        resumed.onSilence()
        drain()
        let afterPausedSilence = Reader.instances.count
        music.playback = playback()
        drain()
        expect(resumed.stopped && Reader.instances.count == afterPausedSilence + 1,
               "silence heard during the pause grace does not write the next play off")
        guard let replayed = Reader.instances.last else { return }
        replayed.onUnavailable()
        drain()
        let afterFailure = Reader.instances.count
        music.playback = playback()
        drain()
        expect(replayed.stopped && Reader.instances.count == afterFailure + 1,
               "a current device failure releases the reader but permits the next playback update to retry")

        guard let waiting = Reader.instances.last else { return }
        music.playback = playback(playing: false)
        drain()
        music.playback = playback()
        drain()
        guard let fresh = Reader.instances.last else { return }
        let afterResume = Reader.instances.count
        expect(waiting.stopped && fresh !== waiting && !fresh.stopped,
               "resuming before any sound gives the new play a fresh reader")
        waiting.onSilence()
        waiting.onUnavailable()
        waiting.onProcessesLeft()
        waiting.onLevels([0.1])
        drain()
        expect(!fresh.stopped && Reader.instances.count == afterResume && service.levels == nil,
               "a delayed silence report from the pause cannot write off the resumed play")
        fresh.onSilence()
        drain()
        music.playback = playback()
        drain()
        expect(fresh.stopped && Reader.instances.count == afterResume,
               "the resumed play can still give up once if its fresh reader also stays silent")

        music.playback = playback(playing: false)
        drain()
        music.playback = playback()
        drain()
        guard let audible = Reader.instances.last else { return }
        audible.onLevels([0.8])
        drain()
        let beforeAudiblePause = Reader.instances.count
        music.playback = playback(playing: false)
        drain()
        music.playback = playback()
        drain()
        expect(!audible.stopped && Reader.instances.count == beforeAudiblePause && service.levels == [0.8],
               "a short pause preserves a reader that already delivered sound")
    }
}
