// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreAudio
import Foundation

enum NotchAudioLevelTests {
    static func run(expect: (Bool, String) -> Void) {
        let bands = NotchAudioLevelSupport.bandRanges(sampleRate: 48_000, size: 1024)
        expect(bands.count == 6 && bands.allSatisfy { !$0.isEmpty && $0.lowerBound >= 1 && $0.upperBound <= 512 }
               && zip(bands, bands.dropFirst()).allSatisfy { $0.upperBound <= $1.lowerBound },
               "six ordered bands, one a bar, cover the usable spectrum without the DC bin")
        let narrow = NotchAudioLevelSupport.bandRanges(sampleRate: 8_000, size: 64)
        expect(narrow.count == 6 && narrow.allSatisfy { !$0.isEmpty && $0.upperBound <= 32 },
               "a narrow spectrum still gives every band at least one bin")
        var magnitudes = [Float](repeating: 0, count: 512)
        expect(NotchAudioLevelSupport.bandLevels(magnitudes: magnitudes, bands: bands).allSatisfy { $0 == 0 },
               "silence is flat")
        magnitudes[Int(700 / (48_000 / 1024.0))] = 0.5
        let levels = NotchAudioLevelSupport.bandLevels(magnitudes: magnitudes, bands: bands)
        expect(levels.count == 6 && levels[3] > 0 && levels.enumerated().allSatisfy { $0.offset == 3 || $0.element == 0 },
               "a 700 Hz tone lights only the band that holds it")
        typealias Smoother = NotchAudioLevelSupport.Smoother
        let quietRow = [0.3, 0.3, 0.6, 0.6, 0.6, 0.6]
        var beat = quietRow; beat[3] = 0.75
        var smoother = Smoother()
        for _ in 0..<30 { _ = smoother.next(quietRow) }
        var rising: [Double] = []
        for _ in 0..<12 { rising.append(smoother.next(beat)[3]) }
        expect(rising[0] < rising[2] && rising[2] < rising[6] && rising[6] > 0.9,
               "a beat carries a bar to the top over a few readings, a smooth swell rather than a jump")
        expect(zip(rising, rising.dropFirst()).allSatisfy { $1 >= $0 - 1e-9 } && rising.max()! <= 1.0001,
               "a bar comes to rest on its level without running past it")
        var falling: [Double] = []
        for _ in 0..<12 { falling.append(smoother.next(quietRow)[3]) }
        let settled = falling.last!, top = rising.last!
        let risen = rising.firstIndex { $0 > (settled + top) / 2 } ?? 99
        let fallen = falling.firstIndex { $0 < (settled + top) / 2 } ?? 99
        expect(abs(risen - fallen) <= 1, "a bar falls away from a beat at the pace it rose")
        var kick = Smoother(), voice = Smoother()
        var bassRise = 0, midRise = 0
        for frame in 0..<12 {
            if kick.next([0.75, 0, 0, 0, 0, 0])[0] < 0.8 { bassRise = frame + 1 }
            if voice.next([0, 0, 0.75, 0, 0, 0])[2] < 0.8 { midRise = frame + 1 }
        }
        expect(bassRise < midRise, "the bass bars swell quicker than the others, so a kick lands sharp")
        var intro = Smoother()
        var bass: [Double] = []
        for frame in 0..<90 {
            let hit = frame % 4 == 0 ? 0.1 : 0
            bass.append(intro.next([0.1 + 0.01 * Double(frame % 3), 0.15, 0.55, 0.6 + hit, 0.62 + hit, 0.6 + hit])[0])
        }
        expect(bass.max()! < 0.02, "a band with nothing in it lies as a dot while the others play, its own noise not scaled up")
        var row = Smoother()
        var heights: [Double] = []
        for _ in 0..<60 { heights = row.next([0.7, 0.55, 0.7, 0.7, 0.7, 0.7]) }
        expect(heights[1] < heights[0] - 0.25 && heights[1] > 0.2,
               "a quieter band stands shorter beside a loud one instead of being stretched to the same height")
        var turnedDown = Smoother()
        for _ in 0..<30 { _ = turnedDown.next([0.75, 0.5, 0.75, 0.75, 0.75, 0.75]) }
        var before = 0.0
        for _ in 0..<15 { before = turnedDown.next([0.5, 0.3, 0.5, 0.5, 0.5, 0.5])[2] }
        for _ in 0..<(30 * 40) { _ = turnedDown.next([0.5, 0.3, 0.5, 0.5, 0.5, 0.5]) }
        let after = turnedDown.next([0.5, 0.3, 0.5, 0.5, 0.5, 0.5])[2]
        expect(before < 0.6 && after > 0.9, "a player turned down fills the bars again within some seconds")
        var louder = Smoother()
        for _ in 0..<30 { _ = louder.next([0.95, 0.8, 0.95, 0.95, 0.95, 0.95]) }
        expect(louder.next([0.95, 0.8, 0.95, 0.95, 0.95, 0.95])[2] < 1.0001
               && louder.next([0.6, 0.6, 0.6, 0.6, 0.6, 0.6])[2] < 0.95,
               "a loud song lifts the top of the scale at once, so the bars do not stand flat at the top")
        expect(NotchAudioLevelSupport.gain(band: 5) > NotchAudioLevelSupport.gain(band: 0)
               && NotchAudioLevelSupport.gain(band: 1) < NotchAudioLevelSupport.gain(band: 0)
               && NotchAudioLevelSupport.gain(band: 9) == 0,
               "the bass is lowered more than the treble, the bass line most of all")
        expect((0..<6).map { NotchAudioLevelSupport.barIndex($0, of: 6, bands: 6) } == [0, 1, 2, 3, 4, 5],
               "the bass stands at the left and the treble at the right, as on the phone")
        expect(NotchAudioLevelSupport.barIndex(0, of: 3, bands: 7) == 1 && NotchAudioLevelSupport.barIndex(1, of: 3, bands: 7) == 3
               && NotchAudioLevelSupport.barIndex(2, of: 3, bands: 7) == 5 && NotchAudioLevelSupport.barIndex(6, of: 7, bands: 7) == 6,
               "fewer bars sample the bands evenly")
        expect(!NotchAudioLevelSupport.fallsBack(heard: false, elapsed: 1) && !NotchAudioLevelSupport.fallsBack(heard: true, elapsed: 10)
               && NotchAudioLevelSupport.fallsBack(heard: false, elapsed: NotchAudioLevelSupport.silenceGrace),
               "a tap that only ever delivers silence hands the bars back to their synthetic motion")
        func delay(_ latency: UInt32, _ safety: UInt32, _ buffer: UInt32, _ stream: UInt32, paintLag: Double = 0) -> Int {
            let frames = NotchAudioLevelSupport.outputFrames(deviceLatency: latency, safetyOffset: safety,
                                                             bufferFrames: buffer, streamLatency: stream)
            return NotchAudioLevelSupport.playbackDelayFrames(outputFrames: frames, sampleRate: 48_000, paintLag: paintLag)
        }
        expect(delay(0, 0, 0, 0) == 0, "an output that reports no latency keeps the bars on the newest sound")
        expect(delay(9_600, 144, 512, 0) == 10_256 - 4_800,
               "Bluetooth headphones hold the bars back by what the output takes to play, less the bars' own lag")
        expect(delay(9_600, 144, 512, 0, paintLag: 0.025) == 10_256 - 4_800 - 1_200,
               "the time a reading takes to reach the screen is read that much sooner")
        expect(delay(256, 0, 256, 0) == 0, "an output faster than the bars themselves is read without a delay")
        expect(delay(.max, .max, .max, .max) == 36_000,
               "an output misreporting its latency cannot hold the bars back without end")
        typealias PaintLag = NotchAudioLevelSupport.PaintLag
        var paint = PaintLag()
        paint.record(0.09)
        expect(abs(paint.seconds - (PaintLag.starting + PaintLag.step)) < 1e-9, "one slow frame moves the paint lag one step")
        var steady = PaintLag()
        for _ in 0..<40 { steady.record(0.03) }
        expect(abs(steady.seconds - 0.03) <= PaintLag.step, "the paint lag settles on what it keeps measuring")
        for _ in 0..<3 { steady.record(5) }
        expect(steady.seconds <= 0.03 + 4 * PaintLag.step, "a main thread that stalls barely moves the paint lag")
        var odd = PaintLag()
        odd.record(-1)
        odd.record(.nan)
        expect(odd == PaintLag(), "a frame that cannot be right is ignored")
        var longest = PaintLag()
        for _ in 0..<200 { longest.record(9) }
        expect(longest.seconds <= PaintLag.longest + PaintLag.step, "a long run of slow frames cannot hold the paint lag past its limit")
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
        NotchAudioRingContract.run(expect: expect)
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

/// The real ring receives memory-backed audio buffers, without a device or
/// an audio thread. Its declaration is extracted on every test build.
enum NotchAudioRingContract {
    static func run(expect: (Bool, String) -> Void) {
        let ring = NotchAudioRing(capacity: 2)
        expect(!ring.hasHeard(gain: 1) && !ring.hasHeard(gain: 4),
               "an empty ring is silent even with multichannel compensation")
        var samples: [Float] = [0.0005, 0.0005]
        samples.withUnsafeMutableBufferPointer { buffer in
            ring.write(AudioBuffer(mNumberChannels: 2,
                                   mDataByteSize: UInt32(buffer.count * MemoryLayout<Float>.size),
                                   mData: buffer.baseAddress))
        }
        expect(!ring.hasHeard(gain: 1), "quiet uncorrected samples stay below the sound threshold")
        expect(ring.hasHeard(gain: 4), "corrected quiet samples prove the tap has sound")
        let heardAfterDrop = ring.hasHeard(gain: 1)
        expect(heardAfterDrop, "a correction drop cannot undo sound the ring already heard")
        expect(!NotchAudioLevelSupport.fallsBack(heard: heardAfterDrop, elapsed: 9),
               "a correction drop after the grace period does not abandon a proven audio reader")
        samples = [0, 0]
        samples.withUnsafeMutableBufferPointer { buffer in
            ring.write(AudioBuffer(mNumberChannels: 2,
                                   mDataByteSize: UInt32(buffer.count * MemoryLayout<Float>.size),
                                   mData: buffer.baseAddress))
        }
        expect(ring.hasHeard(gain: 1), "later silence does not revoke the ring's proof of sound")
        expect(!NotchAudioRing(capacity: 2).hasHeard(gain: 4),
               "a new ring still has to prove its own sound")
        delayContracts(expect: expect)
    }

    /// The bars read what the output is playing, not what was just handed to it.
    private static func delayContracts(expect: (Bool, String) -> Void) {
        let ring = NotchAudioRing(capacity: 8)
        var ramp: [Float] = (1...6).map(Float.init)
        ramp.withUnsafeMutableBufferPointer { buffer in
            ring.write(AudioBuffer(mNumberChannels: 1,
                                   mDataByteSize: UInt32(buffer.count * MemoryLayout<Float>.size),
                                   mData: buffer.baseAddress))
        }
        var block = [Float](repeating: 0, count: 2)
        expect(ring.latest(into: &block) && block == [5, 6], "without a delay the newest samples are read")
        expect(ring.latest(into: &block, delay: 3) && block == [2, 3],
               "a delay reads the samples the output is playing now")
        expect(!ring.latest(into: &block, delay: 5), "a delay waits until the output has that much to play")
        ramp = (7...12).map(Float.init)
        ramp.withUnsafeMutableBufferPointer { buffer in
            ring.write(AudioBuffer(mNumberChannels: 1,
                                   mDataByteSize: UInt32(buffer.count * MemoryLayout<Float>.size),
                                   mData: buffer.baseAddress))
        }
        expect(ring.latest(into: &block, delay: 3) && block == [8, 9], "a delayed read follows the ring around")
        expect(ring.latest(into: &block, delay: 100) && block == [5, 6],
               "a delay past what the ring holds reads as far back as it can")
    }
}


/// The production service is extracted here; only its preference inputs,
/// playback publisher and asynchronous hardware reader are replaced.
typealias NotchAudioTestSilenceMemory = NotchAudioLevelSupport.SilenceMemory
typealias NotchAudioTestPaintLag = NotchAudioLevelSupport.PaintLag

enum NotchAudioLevelLifecycleContract {
    final class NSWorkspace {
        static let shared = NSWorkspace()
        var accessibilityDisplayShouldReduceMotion = false
    }
    enum AppFeature {
        case notchLiveEqualizer
        var isAvailable: Bool { true }
    }
    enum NotchSupport { static func isEnabled() -> Bool { true } }
    enum NotchAudioLevelSupport {
        typealias SilenceMemory = NotchAudioTestSilenceMemory
        typealias PaintLag = NotchAudioTestPaintLag
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
        private let deliver: ([Double], CFTimeInterval) -> Void
        private(set) var latencyReads = 0
        private(set) var paintLag = 0.0
        let onSilence: () -> Void
        let onUnavailable: () -> Void
        let onProcessesLeft: () -> Void
        private(set) var stopped = false

        init(pid: pid_t, onLevels: @escaping ([Double], CFTimeInterval) -> Void,
             onSilence: @escaping () -> Void, onUnavailable: @escaping () -> Void,
             onProcessesLeft: @escaping () -> Void) {
            deliver = onLevels
            self.onSilence = onSilence
            self.onUnavailable = onUnavailable
            self.onProcessesLeft = onProcessesLeft
            Self.instances.append(self)
        }
        func start() {}
        func stop() { stopped = true }
        func onLevels(_ levels: [Double], readAt: CFTimeInterval = 1) { deliver(levels, readAt) }
        func readOutputLatency() { latencyReads += 1 }
        func setPaintLag(_ seconds: Double) { paintLag = seconds }
    }

    static func run(expect: (Bool, String) -> Void) {
        typealias Reader = NotchAudioLevelReader
        let service = NotchAudioLevelService.shared
        let music = NotchMusicService.shared
        func playback(playing: Bool = true, item: String = "track") -> NotchPlayback {
            let track = RadialNowPlayingSnapshot(title: "Track", artist: "Artist", album: "Album",
                                                artworkData: nil, appBundleIdentifier: "org.example.player",
                                                appPID: 42)
            return NotchPlayback(track: track, isPlaying: playing, elapsed: 0, duration: 180, rate: 1,
                                 sampledAt: Date(timeIntervalSinceReferenceDate: 0), canSeek: false,
                                 itemIdentifier: item, canSendCommandsDirectly: true)
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
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = false
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
        var publications: [[Double]?] = []
        let observation = service.$levels.dropFirst().sink { publications.append($0) }
        first.onLevels([0, 0, 0, 0, 0, 0, 0])
        drain()
        for _ in 0..<10 { first.onLevels([0, 0, 0, 0, 0, 0, 0]) }
        drain()
        expect(publications.count == 1 && service.levels == [0, 0, 0, 0, 0, 0, 0],
               "identical audio samples do not invalidate the island again")
        first.onLevels([0, 0, 0.25, 0, 0, 0, 0])
        drain()
        first.onLevels([0, 0, 0, 0, 0, 0, 0])
        drain()
        expect(publications.count == 3,
               "a changed spectrum and its return to silence are both published")
        enable(false)
        expect(publications.count == 4 && publications.last! == nil,
               "stopping still publishes the transition from silent levels to no reader")
        observation.cancel()
        enable(true)
        guard let active = Reader.instances.last else { return }
        var current = active
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
        expect(service.hearsNothing,
               "a play this Mac hears nothing from lays the bars flat instead of faking motion")
        music.playback = playback(playing: false)
        drain()
        music.playback = playback()
        drain()
        expect(!service.hearsNothing, "pausing and playing again clears the flat bars to listen anew")
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
        expect(resumed.stopped && Reader.instances.count == afterPausedSilence + 1 && !service.hearsNothing,
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
        expect(audible.latencyReads == 1, "playing again after a short pause asks the output its latency again")
        music.playback = playback()
        drain()
        expect(audible.latencyReads == 1, "a playback update within the same play does not ask again")
        music.playback = playback(item: "next")
        drain()
        expect(!audible.stopped && audible.latencyReads == 2, "the next track asks again without a new reader")

        audible.onLevels([0.7], readAt: 5)
        drain()
        expect(service.levelsReadAt == 5, "the bars can tell when the levels they show were read")
        let startingPaint = NotchAudioTestPaintLag.starting
        service.painted(readAt: 0, shownAt: 5)
        expect(audible.paintLag == startingPaint, "a frame with no reading behind it says nothing about the paint lag")
        service.painted(readAt: 5, shownAt: 5.05)
        expect(audible.paintLag > startingPaint, "a timed frame reaches the reader")

        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = true
        service.syncWithPreferences()
        drain()
        expect(service.levelsReadAt == 0, "a stopped reader leaves no reading to time")
        expect(audible.stopped && service.levels == nil,
               "Reduce Motion stops audio analysis because the bars cannot use its levels")
        music.playback = playback()
        drain()
        expect(Reader.instances.count == beforeAudiblePause,
               "playback updates do not restart the live equalizer while motion is reduced")
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = false
        service.syncWithPreferences()
        drain()
        expect(Reader.instances.count == beforeAudiblePause + 1 && Reader.instances.last?.stopped == false,
               "restoring motion resumes the chosen live equalizer on the current player")
    }
}
