// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Keeps boosted audio inside the output's range without chopping the tops
/// off the waveform.
///
/// A boost above 100% pushes loud material past full scale, and clamping the
/// overshoot sample by sample flattens every peak into a burst of harsh
/// crackle for as long as the sound stays loud (issue #326). What a booster
/// needs instead is a peak limiter: quiet passages get the full boost, and
/// when a peak would not fit, the whole signal is momentarily turned down by
/// just enough, which the ear reads as loudness rather than distortion.
///
/// The envelope rises instantly, so no sample ever lands above the ceiling,
/// and it falls back exponentially, so the gain does not chatter between two
/// nearby peaks. All channels of a frame share one gain: reducing them
/// together keeps the stereo image where it was.
///
/// One instance belongs to one audio stream. `process` runs on the realtime
/// audio thread; it allocates nothing and touches only this value.
struct BoostLimiter {
    /// Loudest sample the limiter lets out, about half a decibel below full
    /// scale so the device never receives a sample at the very edge.
    static let ceiling: Float = 0.944

    /// How long the gain takes to recover after a peak, chosen so speech and
    /// music breathe naturally instead of pumping.
    static let releaseMilliseconds: Double = 160

    private var envelope: Float = 0
    private let releaseCoefficient: Float

    init(sampleRate: Double) {
        let rate = sampleRate.isFinite && sampleRate >= 8000 ? sampleRate : 48000
        releaseCoefficient = Float(exp(-1000.0 / (rate * Self.releaseMilliseconds)))
    }

    /// Limits `frames` frames of `channels` interleaved channels in place.
    /// Samples already inside the ceiling pass through bit-identical.
    mutating func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        guard frames > 0, channels > 0 else { return }
        var envelope = self.envelope
        let release = releaseCoefficient
        let ceiling = Self.ceiling
        var base = 0
        for _ in 0..<frames {
            var peak: Float = 0
            for channel in 0..<channels {
                let magnitude = abs(samples[base + channel])
                if magnitude > peak { peak = magnitude }
            }
            // Instant attack, exponential decay toward the current level.
            envelope = peak > envelope ? peak : peak + (envelope - peak) * release
            if envelope > ceiling {
                let gain = ceiling / envelope
                for channel in 0..<channels {
                    samples[base + channel] *= gain
                }
            }
            base += channels
        }
        self.envelope = envelope
    }
}
