// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
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

    /// How much of the previous level survives one sample, so that the
    /// recovery lasts the same fraction of a second whatever the rate.
    ///
    /// This lives outside the limiter on purpose. A device can change its
    /// rate while the audio path stays up, which is exactly what a headset
    /// does when a call takes the microphone, and the engine has to be able
    /// to hand the limiter a new figure without reaching into the state the
    /// audio thread is using. An unreadable rate falls back to the common one.
    static func release(sampleRate: Double) -> Float {
        let rate = sampleRate.isFinite && sampleRate >= 8000 ? sampleRate : 48000
        return Float(exp(-1000.0 / (rate * releaseMilliseconds)))
    }

    private var envelope: Float = 0

    /// Limits `frames` frames of `channels` interleaved channels in place.
    /// Samples already inside the ceiling pass through bit-identical.
    mutating func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int,
                          release: Float) {
        guard frames > 0, channels > 0 else { return }
        var envelope = self.envelope
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

/// Lookahead limiter for realtime output. It delays a very small block so a
/// peak is known before that sample is emitted, then moves one linked gain
/// toward the required level across that window. The delay storage is owned
/// by the engine and allocated before the audio callback starts.
final class BoostLookaheadLimiter {
    static let lookaheadFrames = 256

    private let channelCapacity: Int
    private var delay: ContiguousArray<Float>
    private var position = 0
    private var filledFrames = 0
    private var activeChannels = 0
    private var gain: Float = 1
    private var targetGain: Float = 1
    private var attackFrames = 0
    private var attackStep: Float = 0
    private var holdFrames = 0

    init(channels: Int) {
        channelCapacity = max(channels, 1)
        delay = ContiguousArray(
            repeating: 0,
            count: Self.lookaheadFrames * channelCapacity)
    }

    @discardableResult
    func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int,
                 release: Float) -> Bool {
        guard frames > 0, channels > 0, channels <= channelCapacity else { return false }
        if channels != activeChannels {
            delay.withUnsafeMutableBufferPointer { buffer in
                buffer.initialize(repeating: 0)
            }
            position = 0
            filledFrames = 0
            gain = 1
            targetGain = 1
            attackFrames = 0
            attackStep = 0
            holdFrames = 0
            activeChannels = channels
        }
        let ceiling = BoostLimiter.ceiling
        var inputBase = 0
        for _ in 0..<frames {
            var peak: Float = 0
            for channel in 0..<channels {
                let magnitude = abs(samples[inputBase + channel])
                if magnitude > peak { peak = magnitude }
            }
            let requiredGain = peak > ceiling ? ceiling / peak : 1
            let isOverCeiling = requiredGain < 1
            if requiredGain < targetGain {
                targetGain = requiredGain
                let nextStep = (targetGain - gain) / Float(Self.lookaheadFrames)
                attackStep = attackFrames > 0 ? min(attackStep, nextStep) : nextStep
                // Restarting the deadline cannot violate an earlier one: the
                // existing, faster ramp is retained whenever that is needed.
                attackFrames = Self.lookaheadFrames
            }
            if isOverCeiling { holdFrames = Self.lookaheadFrames }

            if attackFrames > 0 {
                gain += attackStep
                attackFrames -= 1
                if gain <= targetGain {
                    gain = targetGain
                    attackFrames = 0
                }
            } else if isOverCeiling {
                // Keep the full hold window; this frame is emitted only after
                // that window has elapsed.
            } else if holdFrames > 0 {
                holdFrames -= 1
            } else {
                gain = 1 + (gain - 1) * release
                targetGain = gain
            }

            let delayedBase = position * channelCapacity
            for channel in 0..<channels {
                let delayed = filledFrames >= Self.lookaheadFrames
                    ? delay[delayedBase + channel]
                    : 0
                delay[delayedBase + channel] = samples[inputBase + channel]
                samples[inputBase + channel] = delayed * gain
            }
            position += 1
            if position == Self.lookaheadFrames { position = 0 }
            if filledFrames < Self.lookaheadFrames { filledFrames += 1 }
            inputBase += channels
        }
        return true
    }
}

/// The same lookahead envelope across every buffer in an AudioBufferList.
/// Non-interleaved stereo and wider devices must receive one linked gain;
/// limiting each buffer independently moves the stereo image. Storage is
/// allocated with the engine, never in the realtime callback.
final class BoostLookaheadBufferListLimiter {
    private let channelCapacity: Int
    private var delay: ContiguousArray<Float>
    private var position = 0
    private var filledFrames = 0
    private var activeChannels = 0
    private var gain: Float = 1
    private var targetGain: Float = 1
    private var attackFrames = 0
    private var attackStep: Float = 0
    private var holdFrames = 0

    init(channelCapacity: Int) {
        self.channelCapacity = max(1, channelCapacity)
        delay = ContiguousArray(repeating: 0,
                                count: BoostLookaheadLimiter.lookaheadFrames
                                    * self.channelCapacity)
    }

    @discardableResult
    func process(_ buffers: UnsafeMutableAudioBufferListPointer,
                 frames: Int,
                 release: Float) -> Bool {
        let channels = buffers.reduce(0) { partial, buffer in
            partial + (buffer.mData == nil ? 0 : Int(buffer.mNumberChannels))
        }
        guard frames > 0, channels > 0, channels <= channelCapacity else { return false }
        if channels != activeChannels {
            delay.withUnsafeMutableBufferPointer {
                $0.baseAddress?.update(repeating: 0, count: $0.count)
            }
            position = 0
            filledFrames = 0
            gain = 1
            targetGain = 1
            attackFrames = 0
            attackStep = 0
            holdFrames = 0
            activeChannels = channels
        }

        let ceiling = BoostLimiter.ceiling
        for frame in 0..<frames {
            var peak: Float = 0
            for buffer in buffers {
                let count = Int(buffer.mNumberChannels)
                guard count > 0,
                      let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = frame * count
                for channel in 0..<count {
                    peak = max(peak, abs(samples[base + channel]))
                }
            }

            let requiredGain = peak > ceiling ? ceiling / peak : 1
            let isOverCeiling = requiredGain < 1
            if requiredGain < targetGain {
                targetGain = requiredGain
                let nextStep = (targetGain - gain)
                    / Float(BoostLookaheadLimiter.lookaheadFrames)
                attackStep = attackFrames > 0 ? min(attackStep, nextStep) : nextStep
                attackFrames = BoostLookaheadLimiter.lookaheadFrames
            }
            if isOverCeiling { holdFrames = BoostLookaheadLimiter.lookaheadFrames }

            if attackFrames > 0 {
                gain += attackStep
                attackFrames -= 1
                if gain <= targetGain {
                    gain = targetGain
                    attackFrames = 0
                }
            } else if !isOverCeiling, holdFrames > 0 {
                holdFrames -= 1
            } else if !isOverCeiling {
                gain = 1 + (gain - 1) * release
                targetGain = gain
            }

            let delayedBase = position * channelCapacity
            var channelIndex = 0
            for buffer in buffers {
                let count = Int(buffer.mNumberChannels)
                guard count > 0,
                      let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = frame * count
                for channel in 0..<count {
                    let delayed = filledFrames >= BoostLookaheadLimiter.lookaheadFrames
                        ? delay[delayedBase + channelIndex] : 0
                    delay[delayedBase + channelIndex] = samples[base + channel]
                    samples[base + channel] = delayed * gain
                    channelIndex += 1
                }
            }
            position += 1
            if position == BoostLookaheadLimiter.lookaheadFrames { position = 0 }
            if filledFrames < BoostLookaheadLimiter.lookaheadFrames { filledFrames += 1 }
        }
        return true
    }
}

/// Zero-lookahead fallback for an unexpected output shape. It still links all
/// buffers, so the whole callback has one latency and one gain.
struct BoostBufferListLimiter {
    private var envelope: Float = 0

    mutating func process(_ buffers: UnsafeMutableAudioBufferListPointer,
                          frames: Int,
                          release: Float) {
        guard frames > 0 else { return }
        for frame in 0..<frames {
            var peak: Float = 0
            for buffer in buffers {
                let channels = Int(buffer.mNumberChannels)
                guard channels > 0,
                      let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = frame * channels
                for channel in 0..<channels { peak = max(peak, abs(samples[base + channel])) }
            }
            envelope = peak > envelope ? peak : peak + (envelope - peak) * release
            guard envelope > BoostLimiter.ceiling else { continue }
            let gain = BoostLimiter.ceiling / envelope
            for buffer in buffers {
                let channels = Int(buffer.mNumberChannels)
                guard channels > 0,
                      let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = frame * channels
                for channel in 0..<channels { samples[base + channel] *= gain }
            }
        }
    }
}
