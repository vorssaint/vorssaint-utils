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
    /// follows the kick below 80 Hz, its second the bass line, the middle
    /// two the voice, and the last the hi-hats.
    static let bandCount = 6
    static let bandEdgesHz: [Double] = [20, 80, 200, 560, 1600, 4500, 16_000]
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
    static func playbackDelayFrames(deviceLatency: UInt32, safetyOffset: UInt32, bufferFrames: UInt32,
                                    streamLatency: UInt32, sampleRate: Double) -> Int {
        let total = Int(deviceLatency) + Int(safetyOffset) + Int(bufferFrames) + Int(streamLatency)
        let rate = max(0, sampleRate)
        return min(max(0, total - Int(rate * barLag)), Int(rate * longestPlaybackDelay))
    }

    /// How long the bars themselves take to show a sound: half an analysis
    /// block, the wait for the next reading, the glide to it and the spring.
    /// Read that much sooner, so the bars land on the beat rather than after it.
    static let barLag = 0.1

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
    static let bandGainDecibels: [Double] = [-14, -27.5, -11, -7, -2.5, -3.5]

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

    /// Turns band levels into bar heights the way the phone's island moves
    /// its bars. Fitted to a recording of the island lined up frame by frame
    /// with the song it played.
    ///
    /// Every band is read on one scale, `span` decibels deep, whose top sits
    /// at the loudest the music has lately been. A band with nothing in it
    /// lies as a dot: the hi-hats of an intro move only the treble bars, and
    /// the bass bar waits for the kick. The scale is not stretched to each
    /// band, so a quiet band stays short beside a loud one, as on the phone.
    /// The top follows a louder song at once and eases down to a quieter one,
    /// a player turned down included, over some seconds.
    ///
    /// A bar then follows its level on a critically damped spring: it rises
    /// and falls at the same pace and comes to rest without running past it.
    /// The two bass bars are quicker, so a kick lands as a sharp swell.
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
        /// The springs' swings a second, the bass bars' and the others'.
        static let bassFrequency = 12.7
        static let frequency = 6.9
        static let substeps = 4
        private var positions: [Double] = []
        private var velocities: [Double] = []
        private var peak = startingPeak

        init() {}

        /// Where each band stands on the scale, from 0 to 1. Moves the scale.
        mutating func scaled(_ raw: [Double]) -> [Double] {
            peak = max(raw.max() ?? 0, peak - Self.ease)
            let bottom = peak + Self.headroom - Self.span
            return raw.map { min(1, max(0, ($0 - bottom) / Self.span)) }
        }

        static func frequency(band: Int, of bands: Int) -> Double {
            band < max(1, bands / 3) ? bassFrequency : frequency
        }

        mutating func next(_ raw: [Double]) -> [Double] {
            if positions.count != raw.count {
                positions = Array(repeating: 0, count: raw.count)
                velocities = positions
            }
            let targets = scaled(raw)
            let step = 1 / updatesPerSecond / Double(Self.substeps)
            for index in raw.indices {
                let omega = 2 * Double.pi * Self.frequency(band: index, of: raw.count)
                // A few small steps a reading: one step a reading is too coarse
                // for a spring this quick.
                for _ in 0..<Self.substeps {
                    let pull = (targets[index] - positions[index]) * omega * omega - velocities[index] * 2 * omega
                    velocities[index] += pull * step
                    positions[index] += velocities[index] * step
                }
            }
            return positions.map { min(1, max(0, $0)) }
        }
    }
}
