// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchKaraokeMotion {
    static let tail = 0.45
    static let fontSize = 22.0
    static let backgroundFontSize = 16.0
    static let gapHandoffLead = 0.3
    static let gapCollapseDuration = 0.5
    static let gapHandoffDuration = 0.8
    static let gapEntranceDuration = 0.4

    static func gapSlotHeight(at time: Double, begin: Double = 0, end: Double, discrete: Bool) -> Double {
        if discrete { return time < end ? 42 : 0 }
        let entrance = begin > 0 ? smooth((time - begin) / gapEntranceDuration) : 1
        return 42 * entrance * (1 - smooth((time - end) / gapCollapseDuration))
    }

    static func gapOpacity(at time: Double, begin: Double, end: Double, discrete: Bool) -> Double {
        guard time >= begin, time < end else { return 0 }
        if discrete { return 1 }
        return smooth((time - begin) / gapEntranceDuration)
            * (1 - smooth((time - (end - gapHandoffLead)) / gapHandoffLead))
    }
    struct Pose { let lift: Double; let scale: Double; let glow: Double; let emphasis: Double }
    struct GapPose { let scale: Double; let opacities: [Double] }

    /// The dots stay in a fixed row. One shared heartbeat scales the group;
    /// entrance grows from small; the final pulse swells then settles before vocals.
    static func gap(at time: Double, begin: Double, end: Double, discrete: Bool) -> GapPose {
        guard time.isFinite, begin.isFinite, end.isFinite, end > begin else {
            return GapPose(scale: 1, opacities: [0.3, 0.3, 0.3])
        }
        let elapsed = max(0, time - begin)
        let segment = (end - begin) / 3
        let opacities = (0..<3).map { index -> Double in
            let progress = min(1, max(0, (elapsed - segment * Double(index)) / segment))
            if discrete { return elapsed >= segment * Double(index) ? 1 : 0.3 }
            return 0.3 + 0.7 * curve(progress, x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
        }
        guard !discrete else { return GapPose(scale: 1, opacities: opacities) }
        let scale: Double
        if end - time < 1.5, time >= begin {
            let start = max(begin, end - 1.5)
            let phase = (start - begin).truncatingRemainder(dividingBy: 5) / 5
            let half = phase < 0.5 ? phase * 2 : (phase - 0.5) * 2
            let eased = curve(half, x1: 0.42, y1: 0, x2: 1, y2: 1)
            let from = phase < 0.5 ? 1 + 0.2 * eased : 1.2 - 0.2 * eased
            let peak = end - 0.6
            if time <= peak {
                scale = from + (1.4 - from) * smooth((time - start) / max(0.001, peak - start))
            } else {
                scale = 1.4 - 0.4 * smooth((time - peak) / max(0.001, end - peak))
            }
        } else {
            let phase = elapsed.truncatingRemainder(dividingBy: 5) / 5
            let half = phase < 0.5 ? phase * 2 : (phase - 0.5) * 2
            let eased = curve(half, x1: 0.42, y1: 0, x2: 1, y2: 1)
            scale = phase < 0.5 ? 1 + 0.2 * eased : 1.2 - 0.2 * eased
        }
        let entrance = 0.15 + 0.85 * smooth(elapsed / gapEntranceDuration)
        return GapPose(scale: scale * entrance, opacities: opacities)
    }

    private static func curve(_ x: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func coordinate(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
        }
        var low = 0.0, high = 1.0
        for _ in 0..<14 {
            let middle = (low + high) / 2
            if coordinate(middle, x1, x2) < x { low = middle } else { high = middle }
        }
        return coordinate((low + high) / 2, y1, y2)
    }

    static func smooth(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }

    static func activity(at time: Double, begin: Double, end: Double?) -> Double {
        guard time.isFinite else { return 0 }
        let enter = smooth((time - begin) / 0.12)
        let leave = end.map { 1 - smooth((time - $0) / tail) } ?? 1
        return min(enter, leave)
    }

    static func needsClock(at time: Double, begin: Double, end: Double?) -> Bool {
        time >= begin && (end.map { time < $0 + tail } ?? true)
    }

    static func word(at time: Double, begin: Double, end: Double, background: Bool, discrete: Bool) -> Pose {
        guard !discrete, time.isFinite, end > begin else { return Pose(lift: 0, scale: 1, glow: 0, emphasis: 0) }
        let envelope = min(smooth((time - begin) / 0.17), 1 - smooth((time - end) / 0.3))
        let progress = min(1, max(0, (time - begin) / (end - begin)))
        let sustained = !background && end - begin >= 1.2 && time > begin && time < end
            ? pow(max(0, sin(progress * .pi)), 0.8) : 0
        return Pose(lift: -(background ? 0.9 : 1.8) * envelope - 0.7 * sustained,
                    scale: 1 + 0.065 * sustained, glow: 2.5 * envelope + 5.5 * sustained, emphasis: sustained)
    }

    static func letterLift(index: Int, count: Int, progress: Double, emphasis: Double) -> Double {
        guard count > 1 else { return 0 }
        let phase = progress * .pi * 2 - Double(index) / Double(count - 1) * 1.6
        return -0.8 * sin(phase) * emphasis
    }
}
