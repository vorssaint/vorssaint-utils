// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The arithmetic behind the island's live music bars, kept free of Core
/// Audio so the tests can exercise it: which spectrum bins form each band,
/// how a band's energy becomes a bar height, and how heights move over time.
enum NotchAudioLevelSupport {
    /// One band for each of the island's six bars, each a little under
    /// three times the last. Found by lining a recording of the phone's
    /// island up with the song it played, frame by frame: its first bar
    /// follows the kick below 100 Hz, its second the bass line, the middle
    /// two the voice, and the last the hi-hats.
    static let bandCount = 6
    static let bandEdgesHz: [Double] = [20, 100, 200, 560, 1600, 4500, 16_000]
    /// Levels below this many decibels under full scale read as silence.
    /// Deep enough for a quiet passage, or a player turned well down, to
    /// still move the bars, which scale to each band's own recent peak.
    static let floorDecibels = 80.0
    /// Updates per second. Enough for motion, few enough to stay cheap.
    static let updatesPerSecond = 30.0
    /// How long a playing tap may stay silent before the bars go back to
    /// their synthetic motion for the rest of this play. Without the system
    /// audio recording permission a tap is created but only ever delivers
    /// silence, and there is no direct way to ask; the absence of sound is
    /// the answer. Long enough to outlast a permission prompt being read and
    /// a player that buffers before it sounds, and free to be: the bars keep
    /// their usual motion the whole time either way.
    static let silenceGrace = 8.0

    /// How long the player's own processes are left to settle before they
    /// are read again. One app launching stirs the whole list, and reading a
    /// process list is not free.
    static let processSettle = 0.25

    /// The longest the bars hold back what the tap heard. Bluetooth outputs
    /// report a few hundred milliseconds; a figure past this is a device
    /// misreporting rather than a real wait.
    static let longestPlaybackDelay = 0.75

    /// Frames between the tap hearing a sample and the output playing it: the
    /// device's latency, its safety offset, one IO buffer and the stream's
    /// latency, as Core Audio reports them for the output. The tap hears the
    /// player as it renders, so without this the bars run ahead of the sound,
    /// by a few hundred milliseconds on Bluetooth headphones.
    static func outputFrames(deviceLatency: UInt32, safetyOffset: UInt32, bufferFrames: UInt32,
                             streamLatency: UInt32) -> Int {
        Int(deviceLatency) + Int(safetyOffset) + Int(bufferFrames) + Int(streamLatency)
    }

    /// How far behind the newest sample to read: what the output takes to play
    /// it, less what the bars take to show it.
    static func playbackDelayFrames(outputFrames: Int, sampleRate: Double, paintLag: Double = 0) -> Int {
        let rate = max(0, sampleRate)
        return min(max(0, outputFrames - Int(rate * (barLag + paintLag))), Int(rate * longestPlaybackDelay))
    }

    /// Notices a tap that has stopped hearing a player it has already heard.
    /// A tap can go deaf without a word, as when headphones are switched off
    /// and on again: its device keeps running and delivers pure silence, which
    /// looks the same as a quiet moment in a song. A new tap costs nothing the
    /// silence has not already lost, so it is tried soon, then less often,
    /// for a player that really has gone quiet.
    struct TapWatch: Equatable {
        static let firstWait = 3.0
        static let longestWait = 30.0

        private var quietSince: TimeInterval?
        private var wait = firstWait

        /// Whether to build the tap again, given whether any sound has
        /// arrived since the last time of asking.
        mutating func shouldRebuild(heard: Bool, at now: TimeInterval) -> Bool {
            if heard { wait = Self.firstWait }
            guard !heard, let quietSince else {
                self.quietSince = now
                return false
            }
            guard now - quietSince >= wait else { return false }
            self.quietSince = now
            wait = min(wait * 2, Self.longestWait)
            return true
        }
    }

    /// How long the bars' motion takes to show a sound: half an analysis
    /// block, the wait for the next reading, the glide to it and the spring.
    /// Read that much sooner, so the bars land on the beat rather than after it.
    /// Getting a reading to the screen is measured instead: see `PaintLag`.
    static let barLag = 0.125

    /// How long a bar takes to glide to a new reading. A little over the wait
    /// for the next one, which catches it still moving, so it never rests
    /// between readings and turns each one's corner more softly.
    static let glide = 1.25 / updatesPerSecond

    /// How long a reading takes from the analysis to the display frame it
    /// shows in, as measured while the bars run. The display's own response
    /// after that frame cannot be read and is not counted.
    ///
    /// Each sample moves the figure a small step toward itself, which settles
    /// on the middle of the samples: a main thread that stalls once costs the
    /// bars one step, not a jump in what they read.
    struct PaintLag: Equatable {
        /// Where it stands before the first sample: about two frames at 120 Hz.
        static let starting = 0.02
        /// The most one sample counts for. A stall past this is not the usual wait.
        static let longest = 0.1
        static let step = 0.002

        private(set) var seconds = starting

        mutating func record(_ sample: Double) {
            guard sample.isFinite, sample >= 0 else { return }
            let change = min(sample, Self.longest) - seconds
            seconds += min(max(change, -Self.step), Self.step)
        }
    }

    static func fallsBack(heard: Bool, elapsed: TimeInterval) -> Bool {
        !heard && elapsed >= silenceGrace
    }

    /// What a change in the player's audio processes asks of its tap.
    enum TapChange: Equatable {
        /// Nothing the tap was built from moved.
        case none
        /// Only new processes. The ones already heard are still playing, so
        /// the tap is built again around all of them and what has been heard
        /// is kept, which spares the bars a drop to their usual motion.
        case rebuild
        /// Something left, taking the tap's ears with it: no buffer arrives
        /// again and the ring would keep answering with the last samples it
        /// heard, freezing the bars on those levels. The player is read from
        /// scratch instead, waiting for sound anew.
        case restart
    }

    static func tapChange<Process: Hashable>(tapped: Set<Process>, current: Set<Process>) -> TapChange {
        if current == tapped { return .none }
        if !tapped.isSubset(of: current) { return .restart }
        return .rebuild
    }

    /// Remembers the single play a silent tap was given up on. A refused
    /// permission, a prompt still on screen and a player that buffers before
    /// it sounds are indistinguishable from here, so only that play keeps the
    /// synthetic motion: the next track, or the next time play is pressed,
    /// reads again rather than holding the player for the whole session.
    struct SilenceMemory: Equatable {
        private var givenUp: NotchMusicIdentity?

        func reads(_ identity: NotchMusicIdentity) -> Bool { identity != givenUp }
        mutating func giveUp(on identity: NotchMusicIdentity) { givenUp = identity }
        /// A pause, a stop or switching the feature off arms the next play.
        mutating func rearm() { givenUp = nil }
    }

    static var isSupported: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchLiveEqualizer)
    }

    /// The bins of a real spectrum with `size / 2` usable bins that belong to
    /// each band. Every band keeps at least one bin, no two share one, and
    /// bin 0, the DC offset, belongs to none.
    static func bandRanges(sampleRate: Double, size: Int) -> [Range<Int>] {
        let usable = max(2, size / 2)
        let binWidth = sampleRate > 0 && size > 0 ? sampleRate / Double(size) : 1
        var ranges: [Range<Int>] = []
        for band in 0..<bandCount {
            var lower = Int((bandEdgesHz[band] / binWidth).rounded(.down))
            var upper = Int((bandEdgesHz[band + 1] / binWidth).rounded(.down))
            // A coarse spectrum puts the narrow bass bands in the same bin.
            lower = max(lower, ranges.last?.upperBound ?? 1)
            lower = min(max(lower, 1), usable - 1)
            upper = min(max(upper, lower + 1), usable)
            ranges.append(lower..<upper)
        }
        return ranges
    }

    /// What each band is given or taken, in decibels, before it is read, as
    /// fitted to the phone's island. Music loses energy as it rises, so the
    /// bass is lowered and the treble left nearly as it is. The bass line is
    /// lowered the most: on the phone its bar seldom stands more than half
    /// tall, even under a loud bass.
    static let bandGainDecibels: [Double] = [-14, -27.5, -11.5, -7.75, -3.25, -4.5]

    /// Each band's energy, the sum of its bins' power, on a decibel scale
    /// with a floor, as a value from 0 to 1. Magnitudes are relative to full
    /// scale. The sum counts all of a band's sound, so a wide treble band is
    /// not read as quieter than it is. Each band is given its gain first.
    static func bandLevels(magnitudes: [Float], bands: [Range<Int>]) -> [Double] {
        bands.enumerated().map { index, band in
            let clipped = band.clamped(to: 0..<magnitudes.count)
            guard !clipped.isEmpty else { return 0 }
            var power: Float = 0
            for bin in clipped { power += magnitudes[bin] * magnitudes[bin] }
            guard power > 0 else { return 0 }
            let decibels = 10 * log10(Double(power)) + gain(band: index)
            return min(1, max(0, (decibels + floorDecibels) / floorDecibels))
        }
    }

    static func gain(band: Int) -> Double {
        band >= 0 && band < bandGainDecibels.count ? bandGainDecibels[band] : 0
    }

    /// Which band a bar reads, the bass at the left and the treble at the
    /// right, as the phone's island draws them. With fewer bars than bands
    /// the bars sample the bands evenly rather than all crowding into the bass.
    static func barIndex(_ bar: Int, of bars: Int, bands: Int) -> Int {
        guard bars > 0, bands > 0 else { return 0 }
        let position = (Double(bar) + 0.5) / Double(bars) * Double(bands)
        return min(bands - 1, max(0, Int(position.rounded(.down))))
    }

    /// How tall to draw a bar at a level from 0 to 1. The level is measured up
    /// from the dot, as it was on the phone, so a low level still shows.
    static func barHeight(level: Double, barWidth: CGFloat, height: CGFloat) -> CGFloat {
        barWidth + max(0, height - barWidth) * CGFloat(level)
    }

    /// The row's proportions in dots, measured on recordings of the phone's
    /// island: the bars stand a fixed distance apart, and one at full height
    /// is this much wider than the dot it grew from, which leaves it a narrow
    /// margin where the dots have plenty of room.
    static let barPitch: CGFloat = 2.13
    static let widestBar: CGFloat = 1.44

    /// How wide to draw a bar this tall. On the phone a bar widens quickly as
    /// it leaves the dot and has nearly finished by two thirds of its height.
    static func barWidth(forHeight drawn: CGFloat, barWidth: CGFloat, height: CGFloat) -> CGFloat {
        guard height > barWidth else { return barWidth }
        let rest = 1 - min(1, max(0, (drawn - barWidth) / (height - barWidth)))
        return barWidth * (1 + (widestBar - 1) * (1 - rest * rest))
    }

    /// The width a row needs so its end bars have room at their widest.
    static func barRowWidth(bars: Int, barWidth: CGFloat) -> CGFloat {
        barWidth * (widestBar + CGFloat(max(0, bars - 1)) * barPitch)
    }

    /// Turns band levels into bar heights the way the phone's island moves
    /// its bars. Fitted to a recording of the island lined up frame by frame
    /// with the song it played.
    ///
    /// Every band is read on one scale, `span` decibels deep, whose top sits
    /// at the loudest the music has lately been. Its floor is soft, as on the
    /// phone: a faint bass line still lifts its bar a little, and only a band
    /// with next to nothing in it lies as a dot, so the bass bar still waits
    /// for the kick under the hi-hats of an intro. The scale is not stretched to
    /// each band, so a quiet band stays short beside a loud one, as on the phone.
    /// The top follows a louder song at once and eases down to a quieter one,
    /// a player turned down included, over some seconds.
    ///
    /// A bar then follows its level on a critically damped spring: it rises
    /// and falls at the same pace and comes to rest without running past it.
    /// Every bar has the same spring, so a quick voice lands like a kick.
    ///
    /// A little slack comes before the spring. A level turning back by less
    /// than `slack` leaves the bar where it is, which stills the flutter of a
    /// held note, finer than a pixel, and takes nothing from a real change.
    struct Smoother {
        /// How deep the scale is, as a share of the level scale: 44 dB.
        static let span = 44 / floorDecibels
        /// How far above the music's loudest the top of the scale sits: 2 dB.
        static let headroom = 2 / floorDecibels
        /// How fast the loudest eases down once the music is quieter, a share
        /// of the level scale a reading: half a decibel a second.
        static let ease = 0.5 / floorDecibels / updatesPerSecond
        /// Where the loudest starts before the music has said otherwise: 20 dB
        /// under full scale, where the phone's scale stood for this recording.
        static let startingPeak = 0.75
        /// How far to either side of the scale's bottom its floor bends, as a
        /// share of the scale: about 26 dB. Above that a bar stands as the scale says.
        static let softFloor = 0.6
        /// How much further each bar swings than the scale says, and where that
        /// leaves it. The phone's bars swing about 1.4 times as far from the same
        /// sound; going all the way there moves them faster than the phone's.
        static let barStretch = [1.4, 1.32, 1.51, 1.42, 1.52, 1.57]
        static let barShift = [-0.34, -0.055, -0.37, -0.325, -0.41, -0.415]
        /// How far a level may turn back before a bar follows, as a share of
        /// its height: under a pixel at the island's tallest.
        static let slack = 0.025
        /// The spring's swings a second. Past 14 the substeps below let a bar
        /// run past its level, and by 16 they no longer hold it at all.
        static let frequency = 12.7
        static let substeps = 4
        private var held: [Double] = []
        private var positions: [Double] = []
        private var velocities: [Double] = []
        private var peak = startingPeak

        init() {}

        /// Where each band stands on the scale, from 0 to 1. Moves the scale.
        mutating func scaled(_ raw: [Double]) -> [Double] {
            peak = max(raw.max() ?? 0, peak - Self.ease)
            let bottom = peak + Self.headroom - Self.span
            // Silence stays flat however far the scale has eased down: a level
            // of nothing would otherwise rise with it, every band alike.
            return raw.indices.map { index in
                guard raw[index] > 0 else { return 0 }
                let place = (raw[index] - bottom) / Self.span
                guard Self.barStretch.indices.contains(index) else { return min(1, Self.softened(place)) }
                return min(1, Self.softened(Self.barShift[index] + Self.barStretch[index] * place))
            }
        }

        /// A place on the scale with its floor bent into a curve.
        static func softened(_ place: Double) -> Double {
            if place >= softFloor { return place }
            if place <= -softFloor { return 0 }
            return (place + softFloor) * (place + softFloor) / (4 * softFloor)
        }

        /// What a bar follows, given what it followed last. The ends take no
        /// slack, so a bar still reaches its full height and lies as a dot.
        static func slackened(_ target: Double, from held: Double) -> Double {
            if target <= 0 || target >= 1 { return target }
            return min(target + slack, max(target - slack, held))
        }

        mutating func next(_ raw: [Double]) -> [Double] {
            if positions.count != raw.count {
                held = Array(repeating: 0, count: raw.count)
                positions = held
                velocities = held
            }
            let targets = scaled(raw)
            let omega = 2 * Double.pi * Self.frequency
            let step = 1 / updatesPerSecond / Double(Self.substeps)
            for index in raw.indices {
                held[index] = Self.slackened(targets[index], from: held[index])
                // A few small steps a reading: one step a reading is too coarse
                // for a spring this quick.
                for _ in 0..<Self.substeps {
                    let pull = (held[index] - positions[index]) * omega * omega - velocities[index] * 2 * omega
                    velocities[index] += pull * step
                    positions[index] += velocities[index] * step
                }
            }
            return positions.map { min(1, max(0, $0)) }
        }
    }
}
