// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A short sound described by its parts instead of a recording, so the whole
/// library weighs nothing on disk and every sound can be tuned per key kind.
///
/// A sound is a sum of three optional layers, each with its own decay:
/// resonant modes (the body of a switch, a bar or a bell), a filtered noise
/// burst (the contact itself), and a pitched tone (the playful sounds).
struct InputSoundRecipe: Equatable {
    struct Mode: Equatable {
        /// Frequency in Hz.
        var frequency: Double
        /// Time for the mode to fall to about a third, in seconds.
        var decay: Double
        var amplitude: Double
        /// Extra pitch at the very start, as a ratio of `frequency`, that
        /// settles within `bendTime`. Gives knocks and drops their snap.
        var bend: Double = 0
        var bendTime: Double = 0.008
        /// Seconds after the start; lets a recipe stack a second hit.
        var delay: Double = 0
    }

    struct Noise: Equatable {
        var amplitude: Double
        var decay: Double
        /// One-pole filter corners in Hz. Zero leaves that side open.
        var lowpass: Double = 0
        var highpass: Double = 0
        var delay: Double = 0
    }

    enum Waveform: Equatable {
        case sine, triangle, square, saw
    }

    struct Tone: Equatable {
        var waveform: Waveform
        var startFrequency: Double
        var endFrequency: Double
        /// Time constant of the glide from start to end, in seconds.
        var glide: Double
        var amplitude: Double
        var decay: Double
        /// A second note jumped to at `stepTime`, as arcade coins do.
        var stepFrequency: Double = 0
        var stepTime: Double = 0
        var vibratoRate: Double = 0
        /// Vibrato depth as a ratio of the current frequency.
        var vibratoDepth: Double = 0
    }

    var duration: Double
    var attack: Double = 0.0008
    var modes: [Mode] = []
    var noise: Noise?
    var tone: Tone?
    /// A single repeat of the whole sound, for rattles.
    var echoDelay: Double = 0
    var echoGain: Double = 0
    /// Peak level the render is normalized to, 0...1.
    var gain: Double = 0.7

    /// The same sound shifted in pitch, length and level. Keeps every layer
    /// in proportion so a space bar still sounds like its letter keys.
    func adjusted(pitch: Double = 1, decay: Double = 1, gain gainScale: Double = 1) -> InputSoundRecipe {
        var copy = self
        copy.duration *= decay
        copy.modes = modes.map {
            var mode = $0
            mode.frequency *= pitch
            mode.decay *= decay
            return mode
        }
        if var noise {
            noise.decay *= decay
            noise.lowpass *= pitch
            noise.highpass *= pitch
            copy.noise = noise
        }
        if var tone {
            tone.startFrequency *= pitch
            tone.endFrequency *= pitch
            tone.stepFrequency *= pitch
            tone.decay *= decay
            copy.tone = tone
        }
        copy.gain = min(1, gain * gainScale)
        return copy
    }

    /// This sound with more modes ringing on top, the bell on a typewriter's
    /// return or a chime over a key.
    func adding(_ extra: [Mode], extending: Double = 0) -> InputSoundRecipe {
        var copy = self
        copy.modes += extra
        copy.duration = max(duration, extending)
        return copy
    }
}

/// Deterministic random numbers, so a sound renders the same on every launch
/// and in tests. SplitMix64.
struct InputSoundRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in -1...1.
    mutating func signed() -> Double {
        Double(next() >> 11) / Double(1 << 53) * 2 - 1
    }
}

enum InputSoundSynth {
    static let sampleRate: Double = 48_000
    /// Longest render allowed, whatever a recipe asks for.
    static let maximumDuration: Double = 1.5

    /// Mono samples for `recipe`. `variation` nudges pitch and level a few
    /// percent so repeated keys do not sound like a machine gun; zero gives
    /// the recipe exactly.
    static func render(_ recipe: InputSoundRecipe, variation: Int = 0) -> [Float] {
        let duration = min(max(recipe.duration, 0.002), maximumDuration)
        let echoTail = recipe.echoGain > 0 ? max(0, recipe.echoDelay) : 0
        let count = Int((duration + echoTail) * sampleRate)
        guard count > 0 else { return [] }

        var random = InputSoundRandom(seed: 0x5EED_0000 &+ UInt64(truncatingIfNeeded: variation) &* 7919)
        let pitchJitter = variation == 0 ? 1 : 1 + random.signed() * 0.025
        let levelJitter = variation == 0 ? 1 : 1 + random.signed() * 0.08

        let dry = renderDry(recipe, count: Int(duration * sampleRate), pitch: pitchJitter,
                            random: &random)
        var samples = [Double](repeating: 0, count: count)
        for index in dry.indices { samples[index] = dry[index] }
        if recipe.echoGain > 0 {
            let offset = Int(recipe.echoDelay * sampleRate)
            for index in dry.indices where index + offset < count {
                samples[index + offset] += dry[index] * recipe.echoGain
            }
        }

        // Gentle saturation keeps stacked layers from clipping harshly, then
        // the peak is set to the recipe's level.
        var peak = 0.0
        for index in samples.indices {
            samples[index] = tanh(samples[index] * 1.2)
            peak = max(peak, abs(samples[index]))
        }
        guard peak > 0 else { return [Float](repeating: 0, count: count) }
        let scale = min(1, max(0, recipe.gain)) * levelJitter / peak

        // A 3 ms fade at the end removes the click a cut tail would make.
        let fade = min(count, Int(0.003 * sampleRate))
        var output = [Float](repeating: 0, count: count)
        for index in samples.indices {
            var value = samples[index] * scale
            let remaining = count - index
            if remaining < fade { value *= Double(remaining) / Double(fade) }
            output[index] = Float(max(-1, min(1, value)))
        }
        return output
    }

    private static func renderDry(_ recipe: InputSoundRecipe, count: Int, pitch: Double,
                                  random: inout InputSoundRandom) -> [Double] {
        var samples = [Double](repeating: 0, count: count)
        let step = 1 / sampleRate
        let attack = max(recipe.attack, 0.0001)

        for mode in recipe.modes {
            var phase = 0.0
            let start = Int(max(0, mode.delay) * sampleRate)
            guard start < count else { continue }
            for index in start..<count {
                let t = Double(index - start) * step
                let bend = mode.bend == 0 ? 0 : mode.bend * exp(-t / max(mode.bendTime, 0.0001))
                let frequency = mode.frequency * pitch * (1 + bend)
                phase += 2 * .pi * frequency * step
                let envelope = min(1, t / attack) * exp(-t / max(mode.decay, 0.0001))
                samples[index] += mode.amplitude * envelope * sin(phase)
            }
        }

        if let noise = recipe.noise {
            let start = Int(max(0, noise.delay) * sampleRate)
            let lowAlpha = noise.lowpass > 0 ? onePoleAlpha(noise.lowpass * pitch) : 1
            let highAlpha = noise.highpass > 0 ? onePoleAlpha(noise.highpass * pitch) : 0
            var low = 0.0
            var highInput = 0.0
            var highOutput = 0.0
            if start < count {
                for index in start..<count {
                    let t = Double(index - start) * step
                    let white = random.signed()
                    low += lowAlpha * (white - low)
                    var value = low
                    if highAlpha > 0 {
                        // One-pole high-pass: what the low-pass at the corner
                        // would have removed.
                        highOutput = (1 - highAlpha) * (highOutput + value - highInput)
                        highInput = value
                        value = highOutput
                    }
                    let envelope = min(1, t / attack) * exp(-t / max(noise.decay, 0.0001))
                    samples[index] += noise.amplitude * envelope * value
                }
            }
        }

        if let tone = recipe.tone {
            var phase = 0.0
            let toneAttack = max(attack, 0.0015)
            for index in 0..<count {
                let t = Double(index) * step
                var frequency: Double
                if tone.stepFrequency > 0, t >= tone.stepTime {
                    frequency = tone.stepFrequency
                } else {
                    let glide = exp(-t / max(tone.glide, 0.0001))
                    frequency = tone.endFrequency + (tone.startFrequency - tone.endFrequency) * glide
                }
                if tone.vibratoRate > 0 {
                    frequency *= 1 + tone.vibratoDepth * sin(2 * .pi * tone.vibratoRate * t)
                }
                phase += frequency * pitch * step
                phase -= floor(phase)
                let envelope = min(1, t / toneAttack) * exp(-t / max(tone.decay, 0.0001))
                samples[index] += tone.amplitude * envelope * waveform(tone.waveform, phase: phase)
            }
        }
        return samples
    }

    /// Phase in 0..<1.
    private static func waveform(_ shape: InputSoundRecipe.Waveform, phase: Double) -> Double {
        switch shape {
        case .sine: return sin(2 * .pi * phase)
        case .triangle: return 1 - 4 * abs(phase - 0.5)
        // Softened edges: a raw square is shrill at these levels.
        case .square: return tanh(sin(2 * .pi * phase) * 4) * 0.6
        case .saw: return (2 * phase - 1) * 0.6
        }
    }

    private static func onePoleAlpha(_ cutoff: Double) -> Double {
        let clamped = min(max(cutoff, 10), sampleRate * 0.45)
        let rc = 1 / (2 * .pi * clamped)
        let dt = 1 / sampleRate
        return dt / (rc + dt)
    }
}
