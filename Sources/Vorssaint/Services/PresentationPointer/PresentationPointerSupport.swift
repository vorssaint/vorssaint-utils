// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// How the presentation pointer looks. Raw values are persisted.
enum PresentationPointerStyle: String, CaseIterable, Identifiable {
    case hand, wand, pencil, banana, ring

    var id: String { rawValue }

    /// The pictures stand in for the system pointer, which is hidden while
    /// they show. The ring circles the system pointer instead, so that one
    /// stays on screen.
    var replacesSystemPointer: Bool { self != .ring }

    /// The bundled picture, in Resources/Images: Fluent Emoji 3D artwork
    /// (Microsoft, MIT licence, see the licence file beside it), turned where
    /// needed so it points up and to the left like a pointer.
    var pictureResource: String? {
        switch self {
        case .hand: return "presentation-pointer-hand"
        case .wand: return "presentation-pointer-wand"
        case .pencil: return "presentation-pointer-pencil"
        case .banana: return "presentation-pointer-banana"
        case .ring: return nil
        }
    }

    /// Where the picture clicks, in its own pixels from the top-left: the
    /// fingertip, the wand's end, the pencil's lead, the banana's tip.
    var pictureTip: CGPoint? {
        switch self {
        case .hand: return CGPoint(x: 96.5, y: 16.5)
        case .wand: return CGPoint(x: 81.5, y: 80.5)
        case .pencil: return CGPoint(x: 18.5, y: 16.5)
        case .banana: return CGPoint(x: 102.5, y: 31.5)
        case .ring: return nil
        }
    }
}

/// Whether clicks are blocked right now, for the input taps that act on a
/// press before any window sees it. Written on the main thread, read from
/// tap callbacks, so it answers under a lock.
enum PresentationPointerClickBlock {
    /// Posted on the main thread when blocking starts or ends.
    static let didChange = Notification.Name("PresentationPointerClickBlock.didChange")

    private static let lock = NSLock()
    private static var active = false

    static var isActive: Bool { lock.withLock { active } }

    static func set(_ value: Bool) {
        let changed = lock.withLock { () -> Bool in
            defer { active = value }
            return active != value
        }
        if changed { NotificationCenter.default.post(name: didChange, object: nil) }
    }
}

/// The two switches a person flips while presenting. Showing the pointer and
/// letting clicks through are separate choices, but blocking clicks without a
/// pointer on screen would swallow every click invisibly, so blocking always
/// brings the pointer along and hiding the pointer always lets clicks through.
struct PresentationPointerMode: Equatable {
    private(set) var isShowing = false
    private(set) var blocksClicks = false

    mutating func toggleShowing() {
        if isShowing {
            self = PresentationPointerMode()
        } else {
            isShowing = true
        }
    }

    mutating func toggleBlockingClicks() {
        if blocksClicks {
            blocksClicks = false
        } else {
            isShowing = true
            blocksClicks = true
        }
    }

    mutating func reset() {
        self = PresentationPointerMode()
    }
}

/// Counts presses that follow each other quickly. Each press inside the
/// window of the one before climbs a level, so jabbing at something escalates
/// the tap while a single click stays at the first level.
struct PresentationPointerTapSeries {
    static let continuationInterval: TimeInterval = 0.45
    static let maximumLevel = 5

    private(set) var level = 0
    private var lastPress: TimeInterval?

    /// The level of a press at `time`, a monotonic clock in seconds.
    mutating func registerPress(at time: TimeInterval) -> Int {
        if let lastPress, time >= lastPress, time - lastPress <= Self.continuationInterval {
            level = min(level + 1, Self.maximumLevel)
        } else {
            level = 1
        }
        lastPress = time
        return level
    }

    mutating func reset() {
        level = 0
        lastPress = nil
    }
}

/// How hard one tap lands. Energy is the person's setting, from subtle to
/// bold; the level comes from the tap series. Both only ever make a tap
/// stronger, so a faster series never looks calmer than a slow one.
struct PresentationPointerTapExpression: Equatable {
    /// Scale of the pointer at the bottom of the press.
    let pressScale: CGFloat
    /// Burst radius, as a multiple of the pointer size.
    let burstRadius: CGFloat
    /// Number of rays in the burst.
    let rayCount: Int
    /// Ray thickness, as a multiple of the pointer size.
    let rayWidth: CGFloat
    /// Seconds the burst takes to expand and fade.
    let burstDuration: TimeInterval
    /// Multiplier on the chosen sound volume.
    let soundGain: Float

    /// 0 for the calmest tap, 1 for the strongest.
    static func intensity(level: Int, energy: Double) -> Double {
        let energy = PresentationPointerSupport.clampedFraction(energy)
        let maximum = PresentationPointerTapSeries.maximumLevel
        let step = Double(min(max(level, 1), maximum) - 1) / Double(maximum - 1)
        return (0.2 + 0.8 * energy) * (0.5 + 0.5 * step)
    }

    static func make(level: Int, energy: Double) -> PresentationPointerTapExpression {
        let intensity = intensity(level: level, energy: energy)
        let maximum = PresentationPointerTapSeries.maximumLevel
        let step = Double(min(max(level, 1), maximum) - 1) / Double(maximum - 1)
        return PresentationPointerTapExpression(
            pressScale: CGFloat(1 - 0.32 * intensity),
            burstRadius: CGFloat(0.45 + 0.8 * intensity),
            rayCount: 6 + Int((6 * intensity).rounded()),
            rayWidth: CGFloat(0.035 + 0.04 * intensity),
            burstDuration: 0.22 + 0.14 * intensity,
            soundGain: Float(0.6 + 0.4 * step)
        )
    }
}

enum PresentationPointerSupport {
    static let defaultStyle = PresentationPointerStyle.hand
    /// The source pictures are this many pixels square; the size setting is
    /// the height they are drawn at, in points.
    static let picturePixels: CGFloat = 256
    static let defaultColor = "#FFC400"
    static let sizeRange: ClosedRange<Double> = 32...128
    static let defaultSize: Double = 64
    static let defaultEnergy: Double = 0.5
    static let defaultSoundName = PresentationPointerTapSound.drum.storageValue
    static let defaultSoundVolume: Double = 0.6
    /// The sound preference value that stands for the file the person chose.
    static let customSoundName = "custom"

    /// The lean while moving sideways, at its strongest, in degrees.
    static let maximumTiltDegrees: Double = 12
    /// Horizontal speed, in points per second, that reaches the full lean.
    static let fullTiltSpeed: Double = 2400

    static func style(stored: String?) -> PresentationPointerStyle {
        stored.flatMap(PresentationPointerStyle.init(rawValue:)) ?? defaultStyle
    }

    static func sanitizedSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultSize }
        return min(max(value, sizeRange.lowerBound), sizeRange.upperBound)
    }

    /// WCAG relative luminance of an sRGB color, 0 for black and 1 for white.
    static func relativeLuminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        func linear(_ channel: CGFloat) -> CGFloat {
            let c = min(max(channel, 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    static func clampedFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// The lean for a horizontal speed: moving right leans the top to the
    /// right, a clockwise turn, which is a negative angle in screen space.
    static func tiltRadians(horizontalSpeed: Double) -> Double {
        guard horizontalSpeed.isFinite else { return 0 }
        let fraction = min(max(horizontalSpeed / fullTiltSpeed, -1), 1)
        return -fraction * maximumTiltDegrees * .pi / 180
    }

    /// The screen a point belongs to: the one containing it, or else the
    /// nearest one, because the pointer can rest exactly on the outer edge of
    /// the desktop, outside every half-open frame.
    static func screenIndex(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        if let index = frames.firstIndex(where: { $0.contains(point) }) {
            return index
        }
        return frames.indices.min { lhs, rhs in
            distanceSquared(from: point, to: frames[lhs]) < distanceSquared(from: point, to: frames[rhs])
        }
    }

    private static func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

/// What a stored sound name asks for. Anything it does not recognise, such as
/// a system sound this macOS no longer ships, is the default sound rather
/// than silence while the switch still reads on.
enum PresentationPointerSoundChoice: Equatable {
    case builtIn(PresentationPointerTapSound)
    case system(String)
    case custom

    static func resolve(stored: String?, systemNames: [String]) -> PresentationPointerSoundChoice {
        if let sound = PresentationPointerTapSound(storageValue: stored) { return .builtIn(sound) }
        if stored == PresentationPointerSupport.customSoundName { return .custom }
        if let stored, systemNames.contains(stored) { return .system(stored) }
        return .builtIn(.drum)
    }
}

/// The tap sounds the pointer brings with it, synthesized here rather than
/// shipped as recordings: each is a few short decaying tones and a burst of
/// noise, and each level of a tap series sounds a little higher and brighter
/// than the one before, the same way the tap itself lands harder.
enum PresentationPointerTapSound: String, CaseIterable, Identifiable {
    /// A stick click on a deep drum. Quick clicks climb like toms in a fill.
    case drum
    /// A fingertip and nail on a hard surface: a crisp click and a small
    /// rebound just after it.
    case tap
    /// Knuckles on wood.
    case knock
    /// A bubble popping.
    case pop
    /// A short, crisp tick.
    case tick

    var id: String { rawValue }

    static let sampleRate = 44_100
    /// Stored sound names carry this prefix, so none can be mistaken for a
    /// system alert sound of the same name.
    static let storagePrefix = "builtin."

    var storageValue: String { Self.storagePrefix + rawValue }

    init?(storageValue: String?) {
        guard let storageValue, storageValue.hasPrefix(Self.storagePrefix) else { return nil }
        self.init(rawValue: String(storageValue.dropFirst(Self.storagePrefix.count)))
    }

    var duration: Double {
        switch self {
        case .drum: return 0.22
        case .tap: return 0.11
        case .knock: return 0.12
        case .pop: return 0.08
        case .tick: return 0.06
        }
    }

    /// The sound of one tap at `level`, as samples between -1 and 1. The same
    /// level always gives the same samples.
    func samples(level: Int) -> [Float] {
        let maximum = PresentationPointerTapSeries.maximumLevel
        let step = Double(min(max(level, 1), maximum) - 1)
        let pitch = 1 + 0.06 * step
        let brightness = 1 + 0.15 * step
        let rate = Double(Self.sampleRate)
        let count = Int(duration * rate)
        // The same grain of noise at every level, so a level differs from the
        // next only in pitch and brightness.
        var noise = Noise(seed: 0x5EED_0000 + UInt64(Self.allCases.firstIndex(of: self) ?? 0))
        var lowpassed = 0.0
        var phase = 0.0
        var output = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / rate
            let white = noise.next()
            lowpassed += 0.25 * (white - lowpassed)
            var value: Double
            switch self {
            case .drum:
                // The stick: a sharp click on the attack, brighter the
                // harder the series hits.
                let stick = 0.8 * brightness * (white - lowpassed) * exp(-t / 0.0008)
                    + 0.45 * sin(2 * .pi * 2300 * t) * exp(-t / 0.003)
                // The drum: a deep tone that drops in pitch as it rings,
                // pitched up a step at each level of a series, like toms.
                let tom = 1 + 0.12 * step
                let frequency = (62 + 120 * exp(-t / 0.025)) * tom
                phase += 2 * .pi * frequency / rate
                value = stick + sin(phase) * exp(-t / 0.11)
                    + 0.3 * sin(2.6 * phase) * exp(-t / 0.035)
            case .tap:
                // The click: bright noise and two high rings that are gone
                // within a few milliseconds. Then the rebound, softer and
                // lower, as the finger settles, and a little warmth under both.
                let click = 0.9 * brightness * (white - lowpassed) * exp(-t / 0.0012)
                    + 0.7 * sin(2 * .pi * 3900 * pitch * t) * exp(-t / 0.004)
                    + 0.45 * sin(2 * .pi * 4700 * pitch * t) * exp(-t / 0.003)
                    + 0.35 * sin(2 * .pi * 2000 * pitch * t) * exp(-t / 0.005)
                let u = t - 0.019
                let rebound = u > 0
                    ? 0.45 * (0.6 * sin(2 * .pi * 3300 * pitch * u) + 0.4 * sin(2 * .pi * 4200 * pitch * u))
                        * exp(-u / 0.016) * (1 - exp(-u / 0.0008))
                    : 0
                value = click + rebound + 0.08 * sin(2 * .pi * 600 * pitch * t) * exp(-t / 0.02)
            case .knock:
                value = sin(2 * .pi * 310 * pitch * t) * exp(-t / 0.022)
                    + 0.6 * sin(2 * .pi * 820 * pitch * t) * exp(-t / 0.011)
                    + 0.25 * brightness * sin(2 * .pi * 1740 * pitch * t) * exp(-t / 0.005)
                    + 0.5 * white * exp(-t / 0.0015)
            case .pop:
                // A tone that rises quickly as it starts, like a bubble
                // giving way.
                let frequency = (420 + 240 * (1 - exp(-t / 0.01))) * pitch
                phase += 2 * .pi * frequency / rate
                value = sin(phase) * (1 - exp(-t / 0.0015)) * exp(-t / 0.011)
                    + 0.5 * brightness * white * exp(-t / 0.001)
            case .tick:
                value = sin(2 * .pi * 2900 * pitch * t) * exp(-t / 0.006)
                    + 0.4 * brightness * (white - lowpassed) * exp(-t / 0.0012)
            }
            output[index] = Float(value)
        }
        return Self.finished(output, rate: rate)
    }

    /// Short fades at both ends, so no tap clicks on its own edges, then
    /// brought to the same peak, so every sound and level is equally loud
    /// before the volume setting and none clips.
    private static func finished(_ samples: [Float], rate: Double) -> [Float] {
        var samples = samples
        let fadeIn = Int(0.001 * rate)
        let fadeOut = Int(0.003 * rate)
        for index in samples.indices {
            if index < fadeIn { samples[index] *= Float(index) / Float(fadeIn) }
            let fromEnd = samples.count - 1 - index
            if fromEnd < fadeOut { samples[index] *= Float(fromEnd) / Float(fadeOut) }
        }
        let peak = samples.reduce(0) { max($0, abs($1)) }
        let gain: Float = peak > 0 ? 0.85 / peak : 0
        return samples.map { $0 * gain }
    }

    /// Samples as a 16-bit mono WAV file, which NSSound plays from memory.
    static func wavData(_ samples: [Float], sampleRate: Int = sampleRate) -> Data {
        var data = Data()
        func append<Value: FixedWidthInteger>(_ value: Value) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let payload = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + payload)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(payload)
        for sample in samples {
            append(Int16((max(-1, min(1, sample)) * Float(Int16.max)).rounded()))
        }
        return data
    }

    /// A small xorshift generator: the same seed gives the same noise, so
    /// every tap at a level sounds exactly alike.
    private struct Noise {
        var state: UInt64

        init(seed: UInt64) {
            state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        }

        mutating func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }
    }
}
