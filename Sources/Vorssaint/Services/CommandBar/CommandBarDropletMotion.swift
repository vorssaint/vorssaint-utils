// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// One moment of the drop that carries the Command Bar out of the Dynamic
/// Island, in points from the top left of the area it falls through.
struct CommandBarDropletFrame: Equatable {
    /// The drop itself, which ends as the bar's field.
    var bead: CGRect
    var radius: CGFloat
    /// The neck still joining it to the island, from the island's edge down
    /// to `neckEnd`: `neckRoot` wide at the edge, `neckTip` at its end.
    var neckEnd: CGFloat
    var neckRoot: CGFloat
    var neckTip: CGFloat
    /// The companion riding inside, and its size as a share of the bar's.
    var mascot: CGPoint
    var mascotScale: CGFloat
}

/// The drop's whole motion, sampled densely enough for Core Animation to
/// play the frames as given: liquid stretching from the island's lower edge,
/// a bead pinching off and falling, a little squash as it lands, and the
/// spring that opens it into the bar. And the same in reverse.
struct CommandBarDropletMotion: Equatable {
    var frames: [CommandBarDropletFrame] = []
    var keyTimes: [Double] = []
    var duration: TimeInterval = 0
    /// When the companion's face settles from surprise, in seconds.
    var landing: TimeInterval = 0
    /// When the shape has all but arrived and the bar itself can take over,
    /// while the drop fades through its last half point of swing.
    var reveal: TimeInterval = 0

    /// The bar hangs this far below the island, where the drop lands.
    static let landingGap: CGFloat = 16
    static let beadSide: CGFloat = 26
    /// The companion's size in the bar's field.
    static let mascotSize: CGFloat = 22
    /// Its size riding in the drop, as a share of that.
    static let ridingScale: CGFloat = 0.7
    /// The neck roots this far inside the island, so it grows out of its edge.
    static let rootDepth: CGFloat = 6
    /// The field's corners, as the bar draws them.
    static let fieldRadius: CGFloat = 22
    private static let rate: Double = 120

    /// From the island's lower edge at `edge`, centred on `centerX`, into
    /// the bar's `field`, with the companion's place at `icon`.
    static func drop(edge: CGFloat, centerX: CGFloat, field: CGRect, icon: CGPoint) -> CommandBarDropletMotion {
        let side = beadSide
        let land = CGPoint(x: centerX, y: field.midY)
        let stretchEnd: TimeInterval = 0.12
        let pinchEnd: TimeInterval = 0.20
        let pinched = edge + side * 0.95
        let fall = TimeInterval(min(0.14, max(0.06, Double(max(0, land.y - pinched)) / 380)))
        let fallEnd = pinchEnd + fall
        let neckBack: TimeInterval = 0.12
        let openStart = fallEnd + 0.04
        let squashed = CGSize(width: side * 1.3, height: side * 0.72)
        let widthSpring = NotchMotion.Spring(duration: 0.3, bounce: 0.18)
            .limited(travel: max(1, field.width - squashed.width), limit: 6)
        let heightSpring = NotchMotion.Spring(duration: 0.24, bounce: 0.2)
            .limited(travel: abs(field.height - squashed.height), limit: 3)
        let openLength = settling(widthSpring, from: squashed.width, to: field.width)
        let duration = openStart + max(openLength, settling(heightSpring, from: squashed.height, to: field.height))
        var motion = CommandBarDropletMotion()
        motion.duration = duration
        motion.landing = fallEnd
        motion.reveal = min(duration, openStart + max(settling(widthSpring, from: squashed.width, to: field.width, within: 2),
                                                      settling(heightSpring, from: squashed.height, to: field.height,
                                                               within: 1)))
        var pinchY = edge
        let count = max(2, Int((duration * rate).rounded(.up)))
        for step in 0...count {
            let time = duration * Double(step) / Double(count)
            var size = CGSize(width: side, height: side)
            var center = land
            var neckEnd = edge, neckRoot: CGFloat = 0, neckTip: CGFloat = 0
            var mascot = land
            var scale = ridingScale
            if time < stretchEnd {
                // Liquid bulging out of the edge and stretching down.
                let share = ease(time / stretchEnd)
                size = CGSize(width: side * (0.8 + 0.12 * share), height: side * (0.7 + 0.42 * share))
                center = CGPoint(x: centerX, y: edge - side * 0.25 + (side * 0.7) * share)
                // As wide as the bead where they meet, so the two read as one liquid.
                neckRoot = 22 - 6 * share
                neckTip = size.width * (0.5 - 0.08 * share)
                neckEnd = center.y
                pinchY = neckEnd
            } else if time < pinchEnd {
                // The neck thins to nothing while the bead pulls away.
                let share = (time - stretchEnd) / (pinchEnd - stretchEnd)
                size = CGSize(width: side * (0.92 + 0.08 * share), height: side * (1.12 - 0.06 * share))
                center = CGPoint(x: centerX, y: edge + side * 0.45 + side * 0.5 * CGFloat(share * share))
                neckRoot = 16 - 6 * share
                neckTip = size.width * 0.42 * CGFloat(1 - share)
                neckEnd = center.y - size.height * 0.3 * CGFloat(share)
                pinchY = neckEnd
            } else {
                // What is left of the neck springs back into the island,
                // its torn end rounding off as liquid does, never a point.
                let back = min(1, (time - pinchEnd) / neckBack)
                neckEnd = pinchY + (edge - 1 - pinchY) * ease(back)
                neckRoot = 10 * CGFloat(1 - back)
                neckTip = min(3, neckRoot * 0.3) * CGFloat(min(1, back / 0.25))
                if time < fallEnd {
                    // Falling, faster and faster, a little long.
                    let share = (time - pinchEnd) / max(0.001, fall)
                    center = CGPoint(x: centerX, y: pinched + (land.y - pinched) * CGFloat(share * share))
                    size = CGSize(width: side * 0.96, height: side * 1.06)
                } else if time < openStart {
                    // Landing flattens it, as it starts to spread.
                    let share = (time - fallEnd) / (openStart - fallEnd)
                    size = CGSize(width: side + (squashed.width - side) * ease(share),
                                  height: side + (squashed.height - side) * ease(share))
                } else {
                    // Landed: it springs open into the field.
                    let open = time - openStart
                    let width = squashed.width + (field.width - squashed.width) * CGFloat(widthSpring.progress(at: open))
                    let heightShare = CGFloat(heightSpring.progress(at: open))
                    size = CGSize(width: max(side * 0.5, width),
                                  height: max(side * 0.5, squashed.height + (field.height - squashed.height) * heightShare))
                    let spread = min(1, max(0, (size.width - squashed.width) / max(1, field.width - squashed.width)))
                    center = CGPoint(x: centerX + (field.midX - centerX) * spread, y: land.y)
                    mascot = CGPoint(x: center.x + (icon.x - center.x) * spread, y: center.y + (icon.y - center.y) * spread)
                    scale = ridingScale + (1 - ridingScale) * min(1, spread * 1.4)
                }
            }
            if time < openStart { mascot = center }
            let bead = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                              width: size.width, height: size.height)
            let openShare = time < openStart ? 0 : min(1, CGFloat(heightSpring.progress(at: time - openStart)))
            let radius = min(size.width, size.height) / 2 * (1 - openShare)
                + min(fieldRadius, min(size.width, size.height) / 2) * openShare
            motion.frames.append(CommandBarDropletFrame(bead: bead, radius: radius, neckEnd: max(edge - 1, neckEnd),
                                                        neckRoot: max(0, neckRoot), neckTip: max(0, neckTip),
                                                        mascot: mascot, mascotScale: scale))
            motion.keyTimes.append(Double(step) / Double(count))
        }
        if let last = motion.frames.indices.last {
            motion.frames[last].bead = field
            motion.frames[last].radius = min(fieldRadius, field.height / 2)
            motion.frames[last].mascot = icon
            motion.frames[last].mascotScale = 1
        }
        return motion
    }

    /// The way back: the bar folds to its field and into a drop, which rises
    /// back into the island.
    static func retract(edge: CGFloat, centerX: CGFloat, bar: CGRect, field: CGRect,
                        icon: CGPoint) -> CommandBarDropletMotion {
        let side = beadSide
        let fold: TimeInterval = bar.height > field.height + 1 ? 0.1 : 0
        let shrinkSpring = NotchMotion.Spring(duration: 0.26, bounce: 0)
        let shrink = settling(shrinkSpring, from: field.width, to: side)
        let rise: TimeInterval = 0.16
        let absorb: TimeInterval = 0.06
        let riseStart = fold + shrink * 0.55
        let duration = riseStart + rise + absorb
        let rest = CGPoint(x: centerX, y: field.midY)
        var motion = CommandBarDropletMotion()
        motion.duration = duration
        let count = max(2, Int((duration * rate).rounded(.up)))
        for step in 0...count {
            let time = duration * Double(step) / Double(count)
            var rect = bar
            var radius = min(fieldRadius, field.height / 2)
            var neckEnd = edge, neckRoot: CGFloat = 0, neckTip: CGFloat = 0
            var mascot = icon
            var scale: CGFloat = 1
            if time < fold {
                let share = ease(time / fold)
                rect.size.height = bar.height + (field.height - bar.height) * share
            } else {
                let open = time - fold
                let progress = CGFloat(shrinkSpring.progress(at: open))
                let width = field.width + (side - field.width) * progress
                let height = field.height + (side - field.height) * progress
                var center = CGPoint(x: field.midX + (rest.x - field.midX) * progress, y: rest.y)
                var size = CGSize(width: width, height: height)
                if time >= riseStart {
                    // Pulled up, faster and faster, stretching as it goes,
                    // while it finishes narrowing.
                    let share = min(1, (time - riseStart) / rise)
                    let target = edge + side * 0.2
                    center.y = rest.y + (target - rest.y) * CGFloat(share * share)
                    size = CGSize(width: width * (1 - 0.15 * share), height: height * (1 + 0.2 * share))
                    // The island bulges toward the drop as it nears and joins
                    // it once the two all but touch, so no thread ever
                    // stretches across the gap between them.
                    let gap = center.y - size.height / 2 - edge
                    let near = ease(Double(1 - gap / (side * 1.6)))
                    let reach = side * 0.3 * near
                    let bridge = min(1, max(0, (reach + 2 - gap) / 4))
                    let bulge = 9 * near
                    neckRoot = bulge + (14 - bulge) * bridge
                    neckTip = bulge * 0.45 + (size.width * 0.45 - bulge * 0.45) * bridge
                    neckEnd = edge + reach + (center.y - size.height * 0.2 - edge - reach) * bridge
                    if time >= riseStart + rise {
                        let gone = min(1, (time - riseStart - rise) / absorb)
                        center.y = target - (side * 0.8) * gone
                        size = CGSize(width: size.width * (1 - 0.4 * gone), height: size.height * (1 - 0.4 * gone))
                        neckRoot = 14 * (1 - gone)
                        neckTip = size.width * 0.45 * (1 - gone)
                        neckEnd = center.y - size.height * 0.2
                    }
                }
                rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
                radius = min(size.width, size.height) / 2 * progress + min(fieldRadius, field.height / 2) * (1 - progress)
                mascot = CGPoint(x: icon.x + (center.x - icon.x) * progress, y: icon.y + (center.y - icon.y) * progress)
                scale = 1 - (1 - ridingScale) * progress
            }
            motion.frames.append(CommandBarDropletFrame(bead: rect, radius: radius, neckEnd: max(edge - 1, neckEnd),
                                                        neckRoot: max(0, neckRoot), neckTip: max(0, neckTip),
                                                        mascot: mascot, mascotScale: scale))
            motion.keyTimes.append(Double(step) / Double(count))
        }
        if let last = motion.frames.indices.last { motion.frames[last].mascotScale = ridingScale }
        return motion
    }

    /// The neck's outline, with the same curves at every moment so one frame
    /// can turn into the next: from the island's edge, inside it by
    /// `rootDepth`, down to its end, round there, and back up.
    static func neckPath(_ frame: CommandBarDropletFrame, edge: CGFloat, centerX: CGFloat) -> CGPath {
        let top = edge - rootDepth
        let bottom = max(top, frame.neckEnd)
        let length = bottom - top
        let root = frame.neckRoot, tip = frame.neckTip
        let path = CGMutablePath()
        path.move(to: CGPoint(x: centerX - root - rootDepth, y: top))
        // Flaring from the edge, narrowing toward the drop.
        path.addCurve(to: CGPoint(x: centerX - tip, y: bottom),
                      control1: CGPoint(x: centerX - root * 0.55 - tip * 0.45, y: top + rootDepth + length * 0.12),
                      control2: CGPoint(x: centerX - tip, y: bottom - length * 0.45))
        path.addCurve(to: CGPoint(x: centerX + tip, y: bottom),
                      control1: CGPoint(x: centerX - tip, y: bottom + tip * 0.6),
                      control2: CGPoint(x: centerX + tip, y: bottom + tip * 0.6))
        path.addCurve(to: CGPoint(x: centerX + root + rootDepth, y: top),
                      control1: CGPoint(x: centerX + tip, y: bottom - length * 0.45),
                      control2: CGPoint(x: centerX + root * 0.55 + tip * 0.45, y: top + rootDepth + length * 0.12))
        path.closeSubpath()
        return path
    }

    private static func ease(_ share: Double) -> CGFloat {
        let clamped = min(1, max(0, share))
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }

    /// When a spring from `from` to `to` stays within `within` points of it.
    private static func settling(_ spring: NotchMotion.Spring, from: CGFloat, to: CGFloat,
                                 within: Double = 0.5) -> TimeInterval {
        let travel = abs(to - from)
        guard Double(travel) > within else { return 0 }
        let step = 1.0 / 240
        var settled = step
        var time = step
        while time < 2 {
            if abs(1 - spring.progress(at: time)) * Double(travel) > within { settled = time + step }
            time += step
        }
        return settled
    }
}
