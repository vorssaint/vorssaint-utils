// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The maths behind the two effects that make a recording read as produced:
/// a pointer that glides instead of jittering, and a picture that leans in
/// when something is clicked.
///
/// All of it is pure and offline, which is the whole advantage: the recording
/// is already finished, so the smoothing can look at the future as well as the
/// past. A filter that only sees the past buys smoothness with lag, and lag is
/// exactly what makes a smoothed pointer feel wrong.
enum RecorderMotion {

    // MARK: - Track

    struct Sample: Equatable {
        /// Seconds from the start of the recording.
        var time: Double
        /// Position inside the recorded area, 0...1, top-left origin. Storing
        /// it normalized means a later crop or a different export size cannot
        /// invalidate the track.
        var point: CGPoint
        /// Which pointer image was on screen, as an index into the track's
        /// shape table. The pointer changes over text, over a link and at a
        /// window edge, and a recording that ignores that looks wrong in a way
        /// people notice immediately without being able to name.
        var shapeIndex: Int
        /// Whether the system was showing a pointer at all. Hiding it happens
        /// constantly, while typing and during full-screen video, and it does
        /// not change which shape is current, so it has to be recorded on its
        /// own or the export paints a pointer over moments that had none.
        var isPointerVisible: Bool

        init(time: Double,
             point: CGPoint,
             shapeIndex: Int = 0,
             isPointerVisible: Bool = true) {
            self.time = time
            self.point = point
            self.shapeIndex = shapeIndex
            self.isPointerVisible = isPointerVisible
        }
    }

    struct Click: Equatable {
        var time: Double
        var isDown: Bool
    }

    // MARK: - Uniform grid

    /// The samples arrive whenever the sampler ran; the filter needs an even
    /// spacing. Linear interpolation in time is enough because the input is
    /// already dense compared to the output rate.
    static func resampled(_ samples: [Sample], frameRate: Int, duration: Double) -> [CGPoint] {
        let count = max(1, Int((duration * Double(max(1, frameRate))).rounded()))
        guard let first = samples.first else {
            return Array(repeating: .zero, count: count)
        }
        guard samples.count > 1 else {
            return Array(repeating: first.point, count: count)
        }
        var result: [CGPoint] = []
        result.reserveCapacity(count)
        var cursor = 0
        let step = 1.0 / Double(max(1, frameRate))
        for index in 0..<count {
            let time = Double(index) * step
            while cursor + 1 < samples.count, samples[cursor + 1].time <= time {
                cursor += 1
            }
            if cursor + 1 >= samples.count {
                result.append(samples[samples.count - 1].point)
                continue
            }
            let a = samples[cursor]
            let b = samples[cursor + 1]
            let span = b.time - a.time
            let t = span > 0 ? min(1, max(0, (time - a.time) / span)) : 0
            result.append(CGPoint(x: a.point.x + (b.point.x - a.point.x) * t,
                                  y: a.point.y + (b.point.y - a.point.y) * t))
        }
        return result
    }

    /// Whether a pointer was on screen at each output frame. Nearest in time,
    /// like the shape.
    static func resampledVisibility(_ samples: [Sample],
                                    frameRate: Int,
                                    duration: Double) -> [Bool] {
        let count = max(1, Int((duration * Double(max(1, frameRate))).rounded()))
        guard !samples.isEmpty else { return Array(repeating: true, count: count) }
        var result: [Bool] = []
        result.reserveCapacity(count)
        var cursor = 0
        let step = 1.0 / Double(max(1, frameRate))
        for index in 0..<count {
            let time = Double(index) * step
            while cursor + 1 < samples.count, samples[cursor + 1].time <= time {
                cursor += 1
            }
            result.append(samples[cursor].isPointerVisible)
        }
        return result
    }

    /// Which pointer image is on screen at each output frame. Nearest in time,
    /// never interpolated: a shape either is or is not the one being shown.
    static func resampledShapes(_ samples: [Sample], frameRate: Int, duration: Double) -> [Int] {
        let count = max(1, Int((duration * Double(max(1, frameRate))).rounded()))
        guard !samples.isEmpty else { return Array(repeating: 0, count: count) }
        var result: [Int] = []
        result.reserveCapacity(count)
        var cursor = 0
        let step = 1.0 / Double(max(1, frameRate))
        for index in 0..<count {
            let time = Double(index) * step
            while cursor + 1 < samples.count, samples[cursor + 1].time <= time {
                cursor += 1
            }
            result.append(samples[cursor].shapeIndex)
        }
        return result
    }

    // MARK: - Zero-phase smoothing

    /// How far a smoothing preset lets the pointer lag behind the truth, as a
    /// cutoff in hertz. Lower is calmer.
    enum Smoothing: String, CaseIterable {
        case off, light, smooth, cinematic

        var cutoff: Double {
            switch self {
            case .off: return 0
            case .light: return 4.0
            case .smooth: return 2.0
            case .cinematic: return 1.2
            }
        }
    }

    static func sanitizedSmoothing(_ raw: String?) -> Smoothing {
        Smoothing(rawValue: raw ?? "") ?? .smooth
    }

    /// Running the same one-pole forward and then backward gives zero phase,
    /// but it also squares the magnitude response, so each pass has to be set
    /// wider than the cutoff we actually want. The factor is exact:
    /// 1 / sqrt(sqrt(2) - 1).
    static let filtfiltWidening = 1.553773974

    static func onePoleAlpha(cutoff: Double, dt: Double) -> Double {
        guard cutoff > 0, dt > 0 else { return 1 }
        return 1 - exp(-2 * .pi * cutoff * dt)
    }

    /// Forward then backward, with the ends padded by the first and last value
    /// so the backward pass does not drag the start of the clip toward the
    /// middle of it.
    static func filtfilt(_ values: [Double], alpha: Double) -> [Double] {
        guard values.count > 1, alpha > 0, alpha < 1 else { return values }
        let padding = min(values.count, max(1, Int((3 / alpha).rounded())))
        var padded = Array(repeating: values[0], count: padding)
            + values
            + Array(repeating: values[values.count - 1], count: padding)

        var carry = padded[0]
        for index in padded.indices {
            carry += alpha * (padded[index] - carry)
            padded[index] = carry
        }
        carry = padded[padded.count - 1]
        for index in padded.indices.reversed() {
            carry += alpha * (padded[index] - carry)
            padded[index] = carry
        }
        return Array(padded[padding..<(padding + values.count)])
    }

    static func smoothedPath(_ points: [CGPoint],
                             smoothing: Smoothing,
                             frameRate: Int) -> [CGPoint] {
        guard smoothing != .off, points.count > 1 else { return points }
        let dt = 1.0 / Double(max(1, frameRate))
        let alpha = onePoleAlpha(cutoff: smoothing.cutoff * filtfiltWidening, dt: dt)
        let xs = filtfilt(points.map { Double($0.x) }, alpha: alpha)
        let ys = filtfilt(points.map { Double($0.y) }, alpha: alpha)
        return zip(xs, ys).map { CGPoint(x: $0, y: $1) }
    }

    // MARK: - Click anchoring

    /// A plain low-pass rounds corners, so the smoothed pointer is NOT on the
    /// button at the instant it is pressed, which is the single most visible
    /// way this effect can look broken. Around every press the path is blended
    /// back to the truth, and for the whole press-to-release it IS the truth,
    /// or a dragged thing would come away from the pointer.
    static let clickAnchorWindow: Double = 0.12

    static func anchorWeight(at time: Double, clicks: [Click]) -> Double {
        var weight: Double = 0
        var pressedAt: Double?
        for click in clicks {
            if click.isDown {
                pressedAt = click.time
            } else if let down = pressedAt {
                if time >= down, time <= click.time { return 1 }
                pressedAt = nil
            }
            let distance = abs(time - click.time)
            guard distance <= clickAnchorWindow else { continue }
            weight = max(weight, smoothstep(1 - distance / clickAnchorWindow))
        }
        // A press with no matching release: the recording ended mid-drag.
        if let down = pressedAt, time >= down { return 1 }
        return weight
    }

    static func anchored(_ smoothed: [CGPoint],
                         raw: [CGPoint],
                         clicks: [Click],
                         frameRate: Int) -> [CGPoint] {
        guard !clicks.isEmpty, smoothed.count == raw.count else { return smoothed }
        let step = 1.0 / Double(max(1, frameRate))
        return smoothed.indices.map { index in
            let weight = anchorWeight(at: Double(index) * step, clicks: clicks)
            guard weight > 0 else { return smoothed[index] }
            return CGPoint(x: smoothed[index].x + (raw[index].x - smoothed[index].x) * weight,
                           y: smoothed[index].y + (raw[index].y - smoothed[index].y) * weight)
        }
    }

    // MARK: - Shaking

    /// Shaking the mouse to find the pointer is a gesture, not noise: a
    /// low-pass turns it into a blurry wobble. Inside a shake the raw path is
    /// used untouched.
    static let shakeWindow: Double = 0.1
    static let shakeDistance: Double = 0.015
    static let shakeReversals = 3

    static func isShaking(_ points: [CGPoint], around index: Int, frameRate: Int) -> Bool {
        let span = max(2, Int((shakeWindow * Double(max(1, frameRate))).rounded()))
        let lower = max(0, index - span / 2)
        let upper = min(points.count - 1, index + span / 2)
        guard upper - lower >= 3 else { return false }

        var travel: Double = 0
        var reversals = 0
        var previousSign: Int = 0
        for i in (lower + 1)...upper {
            let dx = Double(points[i].x - points[i - 1].x)
            let dy = Double(points[i].y - points[i - 1].y)
            travel += (dx * dx + dy * dy).squareRoot()
            let sign = dx > 0 ? 1 : (dx < 0 ? -1 : 0)
            if sign != 0, previousSign != 0, sign != previousSign {
                reversals += 1
            }
            if sign != 0 { previousSign = sign }
        }
        return travel > shakeDistance * 4 && reversals >= shakeReversals
    }

    // MARK: - Easing

    static func smoothstep(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    /// Second derivative zero at both ends too. This is the one that reads as
    /// expensive, so it drives the zoom amount.
    static func smootherstep(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * x * (10 - 15 * x + 6 * x * x)
    }

    // MARK: - Zoom segments

    struct ZoomSegment: Equatable {
        var start: Double
        var end: Double

        var duration: Double { max(0, end - start) }
    }

    /// Because the recording is already finished, the zoom can start BEFORE
    /// the click that causes it. That pre-roll is what makes the effect look
    /// deliberate instead of reactive, and it is impossible to do live.
    static let zoomLeadIn: Double = 0.3
    static let zoomHold: Double = 2.5
    static let zoomMinimumDuration: Double = 0.9
    /// The press that stops the recording must never cause a zoom.
    static let zoomIgnoreTail: Double = 1.0
    static let zoomEndMargin: Double = 0.8
    /// Typing after a click belongs to that click's zoom. The wider start
    /// window covers the natural pause between focusing a field and writing.
    static let typingZoomTail: Double = 1.4
    static let typingZoomContinuation: Double = 8.0

    static func zoomSegments(clicks: [Click],
                             typingTimes: [Double] = [],
                             duration: Double) -> [ZoomSegment] {
        guard duration > 0 else { return [] }
        let presses = clicks
            .filter { $0.isDown && $0.time < duration - zoomIgnoreTail }
            .map(\.time)
            .sorted()
        guard !presses.isEmpty else { return [] }

        var merged: [ZoomSegment] = []
        for press in presses {
            let segment = ZoomSegment(start: max(0.001, press - zoomLeadIn),
                                      end: press + zoomHold)
            if var last = merged.last, segment.start - last.end <= zoomHold {
                // A burst of clicks is one zoom that holds, not a flicker.
                last.end = max(last.end, segment.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }
        for time in typingTimes.filter({ $0.isFinite }).sorted() {
            guard let index = merged.lastIndex(where: {
                time >= $0.start && time <= $0.end + typingZoomContinuation
            }) else { continue }
            merged[index].end = max(merged[index].end, time + typingZoomTail)
        }
        let limit = max(0, duration - zoomEndMargin)
        return merged.compactMap { segment in
            var clamped = segment
            clamped.end = min(clamped.end, limit)
            guard clamped.duration >= zoomMinimumDuration else { return nil }
            return clamped
        }
    }

    /// How far into the zoom the picture is at a moment: 0 outside, 1 while it
    /// holds, eased in and out at the edges.
    static let zoomRampIn: Double = 0.42
    static let zoomRampOut: Double = 0.65

    static func zoomProgress(at time: Double, segments: [ZoomSegment]) -> Double {
        for segment in segments where time >= segment.start - 0.001 && time <= segment.end + zoomRampOut {
            if time <= segment.start + zoomRampIn {
                return smootherstep((time - segment.start) / zoomRampIn)
            }
            if time >= segment.end {
                return smootherstep(1 - (time - segment.end) / zoomRampOut)
            }
            return 1
        }
        return 0
    }

    // MARK: - Viewport

    /// The zoomed viewport is parameterized by where it sits in its OWN travel
    /// range rather than by an absolute origin, so it is inside the frame by
    /// construction: no clamping afterwards, and therefore no visible sticking
    /// when the pointer reaches an edge.
    static let edgeBand: Double = 0.25

    static func travelParameter(focus: Double) -> Double {
        let band = edgeBand
        return min(1, max(0, (focus - band) / (1 - 2 * band)))
    }

    /// Travel for a spot somebody aimed at by hand. Deliberately NOT the
    /// automatic formula: that one has an edge band so following the pointer
    /// stays calm, and it would quietly move a hand-picked target sitting near
    /// an edge, which arrives as "it did not zoom where I clicked".
    static func travelParameter(exactFocus focus: Double, zoom: Double) -> Double {
        let visible = 1 / max(1, zoom)
        let span = 1 - visible
        guard span > 0.0001 else { return 0.5 }
        return min(1, max(0, (focus - visible / 2) / span))
    }

    /// Top-left origin of the visible part of the frame, in 0...1.
    static func viewportOrigin(travel: CGPoint, zoom: Double) -> CGPoint {
        let span = max(0, 1 - 1 / max(1, zoom))
        return CGPoint(x: min(1, max(0, travel.x)) * span,
                       y: min(1, max(0, travel.y)) * span)
    }

    // MARK: - Focus clusters

    /// Aiming at the live pointer makes the picture drift constantly and reads
    /// as seasickness. Samples are grouped into boxes sized as a fraction of
    /// what is CURRENTLY visible, and the zoom aims at the centre of the group
    /// it is in. Wider than tall on purpose: sideways travel reads as normal,
    /// vertical travel is what turns the stomach.
    static let clusterWidthFraction: Double = 0.5
    static let clusterHeightFraction: Double = 0.7

    struct FocusCluster: Equatable {
        var time: Double
        var center: CGPoint
    }

    static func focusClusters(_ points: [CGPoint],
                              frameRate: Int,
                              zoom: Double) -> [FocusCluster] {
        guard !points.isEmpty else { return [] }
        let step = 1.0 / Double(max(1, frameRate))
        let maxWidth = clusterWidthFraction / max(1, zoom)
        let maxHeight = clusterHeightFraction / max(1, zoom)

        var clusters: [FocusCluster] = []
        var box = CGRect(origin: points[0], size: .zero)
        var startedAt: Double = 0

        for index in points.indices {
            let point = points[index]
            let grown = box.union(CGRect(origin: point, size: .zero))
            if grown.width <= maxWidth, grown.height <= maxHeight {
                box = grown
                continue
            }
            clusters.append(FocusCluster(time: startedAt,
                                         center: CGPoint(x: box.midX, y: box.midY)))
            box = CGRect(origin: point, size: .zero)
            startedAt = Double(index) * step
        }
        clusters.append(FocusCluster(time: startedAt,
                                     center: CGPoint(x: box.midX, y: box.midY)))
        return clusters
    }

    static func focus(at time: Double, clusters: [FocusCluster]) -> CGPoint {
        var current = clusters.first?.center ?? CGPoint(x: 0.5, y: 0.5)
        for cluster in clusters where cluster.time <= time {
            current = cluster.center
        }
        return current
    }

    // MARK: - Spring

    /// A critically damped spring, stepped at a fixed rate. The zoom retargets
    /// while it is moving, and a spring carries its velocity across a retarget,
    /// where a fixed-duration curve would have to restart and pop.
    struct Spring: Equatable {
        var value: Double
        var velocity: Double = 0

        static let stiffness: Double = 200
        static let mass: Double = 2.25
        static let damping: Double = 40

        mutating func step(toward target: Double, dt: Double) {
            guard dt > 0 else { return }
            let acceleration = (Self.stiffness * (target - value) - Self.damping * velocity)
                / Self.mass
            velocity += acceleration * dt
            value += velocity * dt
        }
    }

    /// Runs a spring over a whole timeline in fixed small steps, which keeps
    /// the result identical no matter what frame rate the export uses.
    static func springed(_ targets: [Double], frameRate: Int) -> [Double] {
        guard targets.count > 1 else { return targets }
        let frameStep = 1.0 / Double(max(1, frameRate))
        let substep = 1.0 / 240.0
        var spring = Spring(value: targets[0])
        var result: [Double] = []
        result.reserveCapacity(targets.count)
        for target in targets {
            var elapsed: Double = 0
            while elapsed < frameStep {
                spring.step(toward: target, dt: min(substep, frameStep - elapsed))
                elapsed += substep
            }
            result.append(spring.value)
        }
        return result
    }

    // MARK: - Standing still

    /// A pointer parked in a corner for the whole video is the thing that
    /// makes a recording look like a recording. It fades out after a while of
    /// not moving and comes back before it moves again, which is only possible
    /// because the whole path is known before any of it is drawn.
    static let idleDelay: Double = 2.5
    static let idleFadeOut: Double = 0.4
    static let idleFadeIn: Double = 0.25
    /// Below this much travel per frame the pointer counts as parked.
    static let idleTravel: Double = 0.0006

    static func pointerOpacity(_ points: [CGPoint], frameRate: Int) -> [Double] {
        guard points.count > 1 else { return Array(repeating: 1, count: max(1, points.count)) }
        let step = 1.0 / Double(max(1, frameRate))

        // How long the pointer has been still at each frame, and how long
        // until it moves again. Both, because the fade in has to finish
        // BEFORE the movement starts.
        var stillFor = [Double](repeating: 0, count: points.count)
        for index in 1..<points.count {
            let dx = Double(points[index].x - points[index - 1].x)
            let dy = Double(points[index].y - points[index - 1].y)
            let moved = (dx * dx + dy * dy).squareRoot() > idleTravel
            stillFor[index] = moved ? 0 : stillFor[index - 1] + step
        }
        var untilMoves = [Double](repeating: .greatestFiniteMagnitude, count: points.count)
        for index in stride(from: points.count - 2, through: 0, by: -1) {
            untilMoves[index] = stillFor[index + 1] == 0
                ? 0
                : untilMoves[index + 1] + step
        }

        return points.indices.map { index in
            let waking = untilMoves[index] <= idleFadeIn
                ? 1 - untilMoves[index] / idleFadeIn
                : 0
            let sleeping = stillFor[index] <= idleDelay
                ? 0
                : min(1, (stillFor[index] - idleDelay) / idleFadeOut)
            let hidden = max(0, sleeping - waking)
            return 1 - smoothstep(hidden)
        }
    }

    // MARK: - Click feedback

    /// The pointer presses in and comes back. It reads as a physical click and
    /// costs one multiply, and because the recording is finished the press can
    /// begin before the button actually goes down.
    static let pressPunchWindow: Double = 0.13
    static let pressPunchScale: Double = 0.8

    static func pressScale(at time: Double, clicks: [Click]) -> Double {
        let weight = anchorWeightForPunch(at: time, clicks: clicks)
        return 1 - (1 - pressPunchScale) * weight
    }

    private static func anchorWeightForPunch(at time: Double, clicks: [Click]) -> Double {
        var weight: Double = 0
        var pressedAt: Double?
        for click in clicks {
            if click.isDown {
                pressedAt = click.time
                if time >= click.time - pressPunchWindow, time <= click.time {
                    weight = max(weight, smoothstep((time - (click.time - pressPunchWindow))
                                                     / pressPunchWindow))
                }
            } else if let down = pressedAt {
                if time >= down, time <= click.time { weight = 1 }
                if time > click.time, time <= click.time + pressPunchWindow {
                    weight = max(weight, smoothstep(1 - (time - click.time) / pressPunchWindow))
                }
                pressedAt = nil
            }
        }
        if let down = pressedAt, time >= down { weight = 1 }
        return min(1, weight)
    }

    /// One thin ring, born where the click landed, growing and fading out.
    /// Returns how far along it is, or nil when there is nothing to draw.
    static let ringDuration: Double = 0.4
    static let ringRadius: Double = 22

    static func ringProgress(at time: Double, clicks: [Click]) -> Double? {
        var best: Double?
        for click in clicks where click.isDown {
            let elapsed = time - click.time
            guard elapsed >= 0, elapsed <= ringDuration else { continue }
            let progress = elapsed / ringDuration
            // A burst of clicks restarts the same ring instead of stacking.
            best = min(best ?? progress, progress)
        }
        return best
    }
}
