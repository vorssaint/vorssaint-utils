// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Sound families, in the order Settings lists them. Raw values are
/// persisted, so cases can be added but never renamed.
enum InputSoundFamily: String, CaseIterable, Identifiable {
    case desk, studio, toybox, tingle, fidget, analog, arena, spooky

    var id: String { rawValue }

    /// The scroll style that belongs with this family, for "match".
    var matchingScrollStyle: InputScrollStyle {
        switch self {
        case .desk: return .ratchet
        case .studio: return .soft
        case .toybox: return .bubble
        case .tingle: return .glass
        case .fidget: return .tick
        case .analog: return .wheel
        case .arena: return .pixel
        case .spooky: return .wood
        }
    }
}

/// One sound in the library: what a press and a release sound like, and
/// optionally what the Return key adds on top.
struct InputSoundPack: Identifiable, Equatable {
    /// Stable, persisted identity.
    let id: String
    let family: InputSoundFamily
    /// English name; sound names are kept the same in every language, the
    /// way instrument and switch names are.
    let name: String
    let press: InputSoundRecipe
    let release: InputSoundRecipe
    var returnAccent: [InputSoundRecipe.Mode] = []
}

/// Kinds of key the keyboard sounds tell apart. Which key was pressed is
/// never kept; only its kind decides the sound.
enum InputKeyKind: Equatable {
    case regular, space, returnKey, delete, modifier
}

/// The scroll tick styles. Raw values are persisted.
enum InputScrollStyle: String, CaseIterable, Identifiable {
    case tick, soft, wood, ratchet, bubble, glass, pixel, wheel

    var id: String { rawValue }

    var name: String {
        switch self {
        case .tick: return "Tick"
        case .soft: return "Soft"
        case .wood: return "Wood"
        case .ratchet: return "Ratchet"
        case .bubble: return "Bubble"
        case .glass: return "Glass"
        case .pixel: return "Pixel"
        case .wheel: return "Wheel"
        }
    }

    var recipe: InputSoundRecipe {
        typealias R = InputSoundRecipe
        switch self {
        case .tick:
            return R(duration: 0.012, modes: [.init(frequency: 3_100, decay: 0.0018, amplitude: 1)],
                     noise: .init(amplitude: 0.4, decay: 0.001, highpass: 3_000), gain: 0.35)
        case .soft:
            return R(duration: 0.02, modes: [.init(frequency: 1_500, decay: 0.004, amplitude: 1)], gain: 0.25)
        case .wood:
            return R(duration: 0.025, modes: [.init(frequency: 1_100, decay: 0.005, amplitude: 1),
                                              .init(frequency: 2_550, decay: 0.003, amplitude: 0.5)],
                     gain: 0.35)
        case .ratchet:
            return R(duration: 0.015, modes: [.init(frequency: 2_200, decay: 0.002, amplitude: 0.7)],
                     noise: .init(amplitude: 1, decay: 0.0015, highpass: 4_000), gain: 0.32)
        case .bubble:
            return R(duration: 0.03, tone: .init(waveform: .sine, startFrequency: 900, endFrequency: 1_400,
                                                 glide: 0.008, amplitude: 1, decay: 0.008),
                     gain: 0.3)
        case .glass:
            return R(duration: 0.05, modes: [.init(frequency: 4_200, decay: 0.009, amplitude: 1),
                                             .init(frequency: 6_900, decay: 0.005, amplitude: 0.3)],
                     gain: 0.22)
        case .pixel:
            return R(duration: 0.02, tone: .init(waveform: .square, startFrequency: 1_760, endFrequency: 1_760,
                                                 glide: 1, amplitude: 1, decay: 0.006),
                     gain: 0.2)
        case .wheel:
            return R(duration: 0.018, modes: [.init(frequency: 1_800, decay: 0.003, amplitude: 1)],
                     noise: .init(amplitude: 0.5, decay: 0.002, lowpass: 5_000, highpass: 1_200), gain: 0.32)
        }
    }
}

enum InputSoundLibrary {
    typealias R = InputSoundRecipe
    typealias M = InputSoundRecipe.Mode
    typealias N = InputSoundRecipe.Noise
    typealias T = InputSoundRecipe.Tone

    static let defaultPackID = "desk.crisp"

    static func pack(id: String?) -> InputSoundPack? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    static func packs(in family: InputSoundFamily) -> [InputSoundPack] {
        all.filter { $0.family == family }
    }

    /// What `kind` sounds like for `pack`. Keys share the pack's press and
    /// release; space is deeper and longer, Return heavier, Delete brighter.
    static func keyRecipe(_ pack: InputSoundPack, kind: InputKeyKind, isRelease: Bool) -> InputSoundRecipe {
        let base = isRelease ? pack.release : pack.press
        switch kind {
        case .regular: return base
        case .space: return base.adjusted(pitch: 0.78, decay: 1.35, gain: 1.05)
        case .returnKey:
            let heavier = base.adjusted(pitch: 0.86, decay: 1.2, gain: 1.05)
            guard !isRelease, !pack.returnAccent.isEmpty else { return heavier }
            return heavier.adding(pack.returnAccent, extending: 0.6)
        case .delete: return base.adjusted(pitch: 1.1, decay: 0.9)
        case .modifier: return base.adjusted(pitch: 0.92, decay: 0.85, gain: 0.8)
        }
    }

    // MARK: - Extras

    /// A brighter second hit for the second press of a double click.
    static func doubleClick(_ pack: InputSoundPack) -> InputSoundRecipe {
        pack.press.adjusted(pitch: 1.15, gain: 0.95)
    }

    /// A soft rising swell once a press has been held.
    static let longPress = R(duration: 0.16,
                             tone: T(waveform: .sine, startFrequency: 520, endFrequency: 880,
                                     glide: 0.05, amplitude: 1, decay: 0.07),
                             gain: 0.28)

    /// The swish of something picked up when a drag begins.
    static let dragStart = R(duration: 0.12, attack: 0.02,
                             noise: N(amplitude: 1, decay: 0.05, lowpass: 2_400, highpass: 500),
                             gain: 0.22)

    /// A soft landing when a drag ends.
    static let drop = R(duration: 0.09,
                        modes: [M(frequency: 150, decay: 0.022, amplitude: 1, bend: 0.4),
                                M(frequency: 620, decay: 0.01, amplitude: 0.3)],
                        noise: N(amplitude: 0.3, decay: 0.008, lowpass: 1_200),
                        gain: 0.4)

    /// A major pentatonic run, so each combo step is one note higher.
    static func comboChime(step: Int) -> InputSoundRecipe {
        let semitones = [0, 2, 4, 7, 9]
        let clamped = max(0, min(step, 14))
        let octave = clamped / semitones.count
        let note = semitones[clamped % semitones.count] + 12 * octave
        let frequency = 1_046.5 * pow(2, Double(note) / 12)
        return R(duration: 0.45,
                 modes: [M(frequency: frequency, decay: 0.16, amplitude: 1),
                         M(frequency: frequency * 2.01, decay: 0.07, amplitude: 0.3),
                         M(frequency: frequency * 3.02, decay: 0.03, amplitude: 0.12)],
                 gain: 0.3)
    }

    // MARK: - The library

    static let all: [InputSoundPack] = desk + studio + toybox + tingle + fidget + analog + arena + spooky

    private static let desk: [InputSoundPack] = [
        InputSoundPack(
            id: "desk.crisp", family: .desk, name: "Crisp",
            press: R(duration: 0.03,
                     modes: [M(frequency: 3_300, decay: 0.004, amplitude: 1),
                             M(frequency: 5_900, decay: 0.002, amplitude: 0.4)],
                     noise: N(amplitude: 0.6, decay: 0.002, highpass: 2_000), gain: 0.55),
            release: R(duration: 0.025,
                       modes: [M(frequency: 3_900, decay: 0.003, amplitude: 1)],
                       noise: N(amplitude: 0.4, decay: 0.0015, highpass: 2_500), gain: 0.35)),
        InputSoundPack(
            id: "desk.thock", family: .desk, name: "Thock",
            press: R(duration: 0.08,
                     modes: [M(frequency: 190, decay: 0.022, amplitude: 1, bend: 0.3),
                             M(frequency: 430, decay: 0.014, amplitude: 0.6),
                             M(frequency: 1_250, decay: 0.004, amplitude: 0.25)],
                     noise: N(amplitude: 0.5, decay: 0.006, lowpass: 1_500), gain: 0.75),
            release: R(duration: 0.05,
                       modes: [M(frequency: 260, decay: 0.012, amplitude: 1),
                               M(frequency: 640, decay: 0.006, amplitude: 0.4)],
                       noise: N(amplitude: 0.3, decay: 0.004, lowpass: 1_800), gain: 0.4)),
        InputSoundPack(
            id: "desk.creamy", family: .desk, name: "Creamy",
            press: R(duration: 0.07,
                     modes: [M(frequency: 310, decay: 0.016, amplitude: 1),
                             M(frequency: 880, decay: 0.009, amplitude: 0.45)],
                     noise: N(amplitude: 0.45, decay: 0.008, lowpass: 2_400, highpass: 200), gain: 0.62),
            release: R(duration: 0.045,
                       modes: [M(frequency: 420, decay: 0.01, amplitude: 1)],
                       noise: N(amplitude: 0.3, decay: 0.005, lowpass: 2_600), gain: 0.35)),
        InputSoundPack(
            id: "desk.clack", family: .desk, name: "Clack",
            press: R(duration: 0.05,
                     modes: [M(frequency: 1_850, decay: 0.008, amplitude: 1),
                             M(frequency: 4_300, decay: 0.004, amplitude: 0.5),
                             M(frequency: 520, decay: 0.01, amplitude: 0.35)],
                     noise: N(amplitude: 0.7, decay: 0.003, highpass: 1_500), gain: 0.62),
            release: R(duration: 0.035,
                       modes: [M(frequency: 2_300, decay: 0.005, amplitude: 1)],
                       noise: N(amplitude: 0.5, decay: 0.002, highpass: 1_800), gain: 0.4)),
        InputSoundPack(
            id: "desk.tactile", family: .desk, name: "Tactile",
            press: R(duration: 0.06,
                     modes: [M(frequency: 720, decay: 0.01, amplitude: 1),
                             M(frequency: 2_600, decay: 0.004, amplitude: 0.5),
                             M(frequency: 2_900, decay: 0.003, amplitude: 0.45, delay: 0.006)],
                     noise: N(amplitude: 0.45, decay: 0.004, lowpass: 4_000, highpass: 600), gain: 0.58),
            release: R(duration: 0.04,
                       modes: [M(frequency: 980, decay: 0.006, amplitude: 1)],
                       noise: N(amplitude: 0.35, decay: 0.003, highpass: 900), gain: 0.36)),
    ]

    private static let studio: [InputSoundPack] = [
        InputSoundPack(
            id: "studio.soft", family: .studio, name: "Soft",
            press: R(duration: 0.04, attack: 0.002,
                     modes: [M(frequency: 1_200, decay: 0.008, amplitude: 1)], gain: 0.35),
            release: R(duration: 0.03, attack: 0.002,
                       modes: [M(frequency: 1_450, decay: 0.005, amplitude: 1)], gain: 0.2)),
        InputSoundPack(
            id: "studio.tap", family: .studio, name: "Tap",
            press: R(duration: 0.05,
                     modes: [M(frequency: 820, decay: 0.012, amplitude: 1),
                             M(frequency: 1_960, decay: 0.004, amplitude: 0.25)], gain: 0.45),
            release: R(duration: 0.03,
                       modes: [M(frequency: 1_040, decay: 0.006, amplitude: 1)], gain: 0.22)),
        InputSoundPack(
            id: "studio.felt", family: .studio, name: "Felt",
            press: R(duration: 0.045, attack: 0.0015,
                     noise: N(amplitude: 1, decay: 0.01, lowpass: 900, highpass: 120), gain: 0.42),
            release: R(duration: 0.03, attack: 0.0015,
                       noise: N(amplitude: 1, decay: 0.006, lowpass: 1_200, highpass: 200), gain: 0.22)),
        InputSoundPack(
            id: "studio.glass", family: .studio, name: "Glass",
            press: R(duration: 0.14,
                     modes: [M(frequency: 2_640, decay: 0.035, amplitude: 1),
                             M(frequency: 5_310, decay: 0.018, amplitude: 0.35)], gain: 0.3),
            release: R(duration: 0.08,
                       modes: [M(frequency: 3_170, decay: 0.02, amplitude: 1)], gain: 0.16)),
        InputSoundPack(
            id: "studio.pebble", family: .studio, name: "Pebble",
            press: R(duration: 0.06,
                     modes: [M(frequency: 1_120, decay: 0.014, amplitude: 1),
                             M(frequency: 2_740, decay: 0.006, amplitude: 0.5)],
                     noise: N(amplitude: 0.2, decay: 0.002, highpass: 2_000), gain: 0.45),
            release: R(duration: 0.04,
                       modes: [M(frequency: 1_480, decay: 0.008, amplitude: 1)], gain: 0.24)),
    ]

    private static let toybox: [InputSoundPack] = [
        InputSoundPack(
            id: "toybox.boop", family: .toybox, name: "Boop",
            press: R(duration: 0.09,
                     tone: T(waveform: .sine, startFrequency: 640, endFrequency: 320, glide: 0.025,
                             amplitude: 1, decay: 0.04), gain: 0.5),
            release: R(duration: 0.06,
                       tone: T(waveform: .sine, startFrequency: 480, endFrequency: 560, glide: 0.02,
                               amplitude: 1, decay: 0.02), gain: 0.25)),
        InputSoundPack(
            id: "toybox.pixel", family: .toybox, name: "Pixel",
            press: R(duration: 0.05,
                     tone: T(waveform: .square, startFrequency: 880, endFrequency: 880, glide: 1,
                             amplitude: 1, decay: 0.02), gain: 0.3),
            release: R(duration: 0.04,
                       tone: T(waveform: .square, startFrequency: 1_320, endFrequency: 1_320, glide: 1,
                               amplitude: 1, decay: 0.012), gain: 0.18)),
        InputSoundPack(
            id: "toybox.bubble", family: .toybox, name: "Bubble",
            press: R(duration: 0.07,
                     tone: T(waveform: .sine, startFrequency: 380, endFrequency: 1_150, glide: 0.018,
                             amplitude: 1, decay: 0.025), gain: 0.45),
            release: R(duration: 0.05,
                       tone: T(waveform: .sine, startFrequency: 700, endFrequency: 1_400, glide: 0.012,
                               amplitude: 1, decay: 0.014), gain: 0.22)),
        InputSoundPack(
            id: "toybox.squeak", family: .toybox, name: "Squeak",
            press: R(duration: 0.08,
                     tone: T(waveform: .triangle, startFrequency: 1_450, endFrequency: 2_250, glide: 0.03,
                             amplitude: 1, decay: 0.03, vibratoRate: 30, vibratoDepth: 0.02), gain: 0.32),
            release: R(duration: 0.05,
                       tone: T(waveform: .triangle, startFrequency: 2_100, endFrequency: 1_700, glide: 0.02,
                               amplitude: 1, decay: 0.015), gain: 0.18)),
        InputSoundPack(
            id: "toybox.pop", family: .toybox, name: "Pop",
            press: R(duration: 0.06,
                     modes: [M(frequency: 300, decay: 0.012, amplitude: 1, bend: 1.2, bendTime: 0.004)],
                     noise: N(amplitude: 0.6, decay: 0.003, lowpass: 3_000), gain: 0.55),
            release: R(duration: 0.04,
                       modes: [M(frequency: 520, decay: 0.006, amplitude: 1, bend: 0.8, bendTime: 0.003)],
                       gain: 0.25)),
    ]

    private static let tingle: [InputSoundPack] = [
        InputSoundPack(
            id: "tingle.kalimba", family: .tingle, name: "Kalimba",
            press: R(duration: 0.5,
                     modes: [M(frequency: 523.25, decay: 0.16, amplitude: 1),
                             M(frequency: 1_412, decay: 0.05, amplitude: 0.35),
                             M(frequency: 2_900, decay: 0.008, amplitude: 0.2)], gain: 0.42),
            release: R(duration: 0.3,
                       modes: [M(frequency: 659.25, decay: 0.08, amplitude: 1),
                               M(frequency: 1_780, decay: 0.025, amplitude: 0.25)], gain: 0.16)),
        InputSoundPack(
            id: "tingle.bell", family: .tingle, name: "Bell",
            press: R(duration: 0.7,
                     modes: [M(frequency: 880, decay: 0.24, amplitude: 1),
                             M(frequency: 2_210, decay: 0.12, amplitude: 0.5),
                             M(frequency: 3_530, decay: 0.06, amplitude: 0.3)], gain: 0.34),
            release: R(duration: 0.25,
                       modes: [M(frequency: 1_760, decay: 0.06, amplitude: 1)], gain: 0.1)),
        InputSoundPack(
            id: "tingle.marimba", family: .tingle, name: "Marimba",
            press: R(duration: 0.35,
                     modes: [M(frequency: 440, decay: 0.11, amplitude: 1),
                             M(frequency: 1_760, decay: 0.02, amplitude: 0.35)],
                     noise: N(amplitude: 0.15, decay: 0.002, lowpass: 2_000), gain: 0.5),
            release: R(duration: 0.15,
                       modes: [M(frequency: 554.37, decay: 0.04, amplitude: 1)], gain: 0.14)),
        InputSoundPack(
            id: "tingle.celesta", family: .tingle, name: "Celesta",
            press: R(duration: 0.55,
                     modes: [M(frequency: 1_046.5, decay: 0.18, amplitude: 1),
                             M(frequency: 2_093, decay: 0.07, amplitude: 0.4),
                             M(frequency: 4_186, decay: 0.02, amplitude: 0.15)], gain: 0.3),
            release: R(duration: 0.2,
                       modes: [M(frequency: 1_318.5, decay: 0.05, amplitude: 1)], gain: 0.1)),
        InputSoundPack(
            id: "tingle.droplet", family: .tingle, name: "Droplet",
            press: R(duration: 0.12,
                     tone: T(waveform: .sine, startFrequency: 1_850, endFrequency: 880, glide: 0.018,
                             amplitude: 1, decay: 0.04), gain: 0.38),
            release: R(duration: 0.08,
                       tone: T(waveform: .sine, startFrequency: 1_200, endFrequency: 1_600, glide: 0.015,
                               amplitude: 1, decay: 0.018), gain: 0.16)),
    ]

    private static let fidget: [InputSoundPack] = [
        InputSoundPack(
            id: "fidget.switch", family: .fidget, name: "Switch",
            press: R(duration: 0.03,
                     modes: [M(frequency: 2_400, decay: 0.003, amplitude: 1),
                             M(frequency: 2_650, decay: 0.002, amplitude: 0.7, delay: 0.004)],
                     noise: N(amplitude: 0.5, decay: 0.0015, highpass: 2_500), gain: 0.5),
            release: R(duration: 0.025,
                       modes: [M(frequency: 2_900, decay: 0.002, amplitude: 1)], gain: 0.3)),
        InputSoundPack(
            id: "fidget.snap", family: .fidget, name: "Snap",
            press: R(duration: 0.03,
                     modes: [M(frequency: 1_600, decay: 0.004, amplitude: 0.6)],
                     noise: N(amplitude: 1, decay: 0.003, highpass: 3_000), gain: 0.55),
            release: R(duration: 0.02,
                       noise: N(amplitude: 1, decay: 0.0015, highpass: 4_000), gain: 0.25)),
        InputSoundPack(
            id: "fidget.pen", family: .fidget, name: "Pen",
            press: R(duration: 0.05,
                     modes: [M(frequency: 3_050, decay: 0.006, amplitude: 1),
                             M(frequency: 6_100, decay: 0.003, amplitude: 0.4),
                             M(frequency: 900, decay: 0.008, amplitude: 0.35)], gain: 0.5),
            release: R(duration: 0.04,
                       modes: [M(frequency: 2_700, decay: 0.005, amplitude: 1),
                               M(frequency: 820, decay: 0.006, amplitude: 0.3)], gain: 0.38)),
        InputSoundPack(
            id: "fidget.latch", family: .fidget, name: "Latch",
            press: R(duration: 0.09,
                     modes: [M(frequency: 1_210, decay: 0.02, amplitude: 1),
                             M(frequency: 3_120, decay: 0.012, amplitude: 0.6),
                             M(frequency: 5_040, decay: 0.006, amplitude: 0.3)],
                     noise: N(amplitude: 0.4, decay: 0.002, highpass: 2_000), gain: 0.45),
            release: R(duration: 0.05,
                       modes: [M(frequency: 1_530, decay: 0.01, amplitude: 1)], gain: 0.25)),
    ]

    private static let analog: [InputSoundPack] = [
        InputSoundPack(
            id: "analog.typebar", family: .analog, name: "Typebar",
            press: R(duration: 0.09,
                     modes: [M(frequency: 120, decay: 0.02, amplitude: 0.8, bend: 0.5),
                             M(frequency: 700, decay: 0.012, amplitude: 0.7),
                             M(frequency: 2_450, decay: 0.006, amplitude: 1, delay: 0.012)],
                     noise: N(amplitude: 0.8, decay: 0.006, lowpass: 5_000, highpass: 400), gain: 0.68),
            release: R(duration: 0.05,
                       modes: [M(frequency: 1_900, decay: 0.006, amplitude: 1)],
                       noise: N(amplitude: 0.4, decay: 0.003, highpass: 1_000), gain: 0.3),
            returnAccent: [M(frequency: 2_093, decay: 0.25, amplitude: 0.9, delay: 0.05),
                           M(frequency: 5_250, decay: 0.08, amplitude: 0.3, delay: 0.05)]),
        InputSoundPack(
            id: "analog.relay", family: .analog, name: "Relay",
            press: R(duration: 0.06,
                     modes: [M(frequency: 1_100, decay: 0.012, amplitude: 1),
                             M(frequency: 2_920, decay: 0.006, amplitude: 0.6),
                             M(frequency: 1_180, decay: 0.008, amplitude: 0.5, delay: 0.009)],
                     noise: N(amplitude: 0.5, decay: 0.002, highpass: 1_500), gain: 0.5),
            release: R(duration: 0.04,
                       modes: [M(frequency: 1_420, decay: 0.006, amplitude: 1)], gain: 0.3)),
        InputSoundPack(
            id: "analog.shutter", family: .analog, name: "Shutter",
            press: R(duration: 0.08,
                     modes: [M(frequency: 640, decay: 0.008, amplitude: 0.5)],
                     noise: N(amplitude: 1, decay: 0.006, lowpass: 6_000, highpass: 800),
                     echoDelay: 0.035, echoGain: 0.6, gain: 0.5),
            release: R(duration: 0.03,
                       noise: N(amplitude: 1, decay: 0.004, lowpass: 5_000, highpass: 1_000), gain: 0.22)),
        InputSoundPack(
            id: "analog.toggle", family: .analog, name: "Toggle",
            press: R(duration: 0.08,
                     modes: [M(frequency: 160, decay: 0.018, amplitude: 1, bend: 0.4),
                             M(frequency: 2_200, decay: 0.007, amplitude: 0.7)],
                     noise: N(amplitude: 0.5, decay: 0.003, lowpass: 3_500), gain: 0.62),
            release: R(duration: 0.06,
                       modes: [M(frequency: 210, decay: 0.012, amplitude: 1),
                               M(frequency: 2_500, decay: 0.005, amplitude: 0.5)], gain: 0.4)),
        InputSoundPack(
            id: "analog.rotary", family: .analog, name: "Rotary",
            press: R(duration: 0.05,
                     modes: [M(frequency: 1_700, decay: 0.004, amplitude: 1),
                             M(frequency: 1_700, decay: 0.003, amplitude: 0.6, delay: 0.014),
                             M(frequency: 1_700, decay: 0.002, amplitude: 0.35, delay: 0.026)],
                     gain: 0.42),
            release: R(duration: 0.03,
                       modes: [M(frequency: 1_900, decay: 0.003, amplitude: 1)], gain: 0.22)),
    ]

    private static let arena: [InputSoundPack] = [
        InputSoundPack(
            id: "arena.blip", family: .arena, name: "Blip",
            press: R(duration: 0.045,
                     tone: T(waveform: .square, startFrequency: 1_200, endFrequency: 1_200, glide: 1,
                             amplitude: 1, decay: 0.015), gain: 0.25),
            release: R(duration: 0.03,
                       tone: T(waveform: .square, startFrequency: 1_600, endFrequency: 1_600, glide: 1,
                               amplitude: 1, decay: 0.008), gain: 0.14)),
        InputSoundPack(
            id: "arena.laser", family: .arena, name: "Laser",
            press: R(duration: 0.1,
                     tone: T(waveform: .saw, startFrequency: 2_100, endFrequency: 380, glide: 0.025,
                             amplitude: 1, decay: 0.04), gain: 0.3),
            release: R(duration: 0.04,
                       tone: T(waveform: .saw, startFrequency: 900, endFrequency: 1_400, glide: 0.01,
                               amplitude: 1, decay: 0.012), gain: 0.12)),
        InputSoundPack(
            id: "arena.coin", family: .arena, name: "Coin",
            press: R(duration: 0.16,
                     tone: T(waveform: .square, startFrequency: 988, endFrequency: 988, glide: 1,
                             amplitude: 1, decay: 0.08, stepFrequency: 1_319, stepTime: 0.04),
                     gain: 0.24),
            release: R(duration: 0.03,
                       tone: T(waveform: .square, startFrequency: 1_976, endFrequency: 1_976, glide: 1,
                               amplitude: 1, decay: 0.008), gain: 0.1)),
        InputSoundPack(
            id: "arena.select", family: .arena, name: "Select",
            press: R(duration: 0.07,
                     tone: T(waveform: .triangle, startFrequency: 660, endFrequency: 880, glide: 0.012,
                             amplitude: 1, decay: 0.03), gain: 0.4),
            release: R(duration: 0.04,
                       tone: T(waveform: .triangle, startFrequency: 990, endFrequency: 990, glide: 1,
                               amplitude: 1, decay: 0.012), gain: 0.18)),
    ]

    private static let spooky: [InputSoundPack] = [
        InputSoundPack(
            id: "spooky.pumpkin", family: .spooky, name: "Pumpkin",
            press: R(duration: 0.12,
                     modes: [M(frequency: 140, decay: 0.04, amplitude: 1, bend: 0.3),
                             M(frequency: 285, decay: 0.025, amplitude: 0.6)],
                     noise: N(amplitude: 0.35, decay: 0.01, lowpass: 900), gain: 0.7),
            release: R(duration: 0.07,
                       modes: [M(frequency: 210, decay: 0.02, amplitude: 1)], gain: 0.35)),
        InputSoundPack(
            id: "spooky.cauldron", family: .spooky, name: "Cauldron",
            press: R(duration: 0.14,
                     tone: T(waveform: .sine, startFrequency: 320, endFrequency: 120, glide: 0.04,
                             amplitude: 1, decay: 0.05, vibratoRate: 22, vibratoDepth: 0.06), gain: 0.55),
            release: R(duration: 0.08,
                       tone: T(waveform: .sine, startFrequency: 180, endFrequency: 360, glide: 0.02,
                               amplitude: 1, decay: 0.025), gain: 0.28)),
        InputSoundPack(
            id: "spooky.bones", family: .spooky, name: "Bones",
            press: R(duration: 0.05,
                     modes: [M(frequency: 920, decay: 0.006, amplitude: 1),
                             M(frequency: 1_730, decay: 0.004, amplitude: 0.7),
                             M(frequency: 2_610, decay: 0.003, amplitude: 0.5)],
                     echoDelay: 0.028, echoGain: 0.55, gain: 0.5),
            release: R(duration: 0.03,
                       modes: [M(frequency: 1_250, decay: 0.004, amplitude: 1)],
                       echoDelay: 0.02, echoGain: 0.4, gain: 0.26)),
        InputSoundPack(
            id: "spooky.ghost", family: .spooky, name: "Ghost",
            press: R(duration: 0.4, attack: 0.03,
                     tone: T(waveform: .sine, startFrequency: 520, endFrequency: 430, glide: 0.2,
                             amplitude: 1, decay: 0.14, vibratoRate: 6, vibratoDepth: 0.03), gain: 0.3),
            release: R(duration: 0.18, attack: 0.02,
                       tone: T(waveform: .sine, startFrequency: 430, endFrequency: 470, glide: 0.1,
                               amplitude: 1, decay: 0.05), gain: 0.12)),
    ]
}
