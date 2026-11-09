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
}

/// The drop's whole motion, sampled densely enough for Core Animation to
/// play the frames as given: liquid stretching from the island's lower edge,
/// a bead pinching off and falling, a little squash as it lands, and the
/// spring that opens it into the bar. And the same in reverse.
struct CommandBarDropletMotion: Equatable {
    var frames: [CommandBarDropletFrame] = []
    var keyTimes: [Double] = []
    var duration: TimeInterval = 0
    /// When the falling shape lands, in seconds.
    var landing: TimeInterval = 0
    /// When the shape has all but arrived and the bar itself can take over,
    /// while the drop fades through its last half point of swing.
    var reveal: TimeInterval = 0

    /// The bar hangs this far below the island, where the drop lands.
    static let landingGap: CGFloat = 16
    static let beadSide: CGFloat = 26
    /// The neck roots this far inside the island, so it grows out of its edge.
    static let rootDepth: CGFloat = 6
    /// The field's corners, as the bar draws them.
    static let fieldRadius: CGFloat = 22
    /// Typed into as it falls, the bar fades in at once over this long, and
    /// what is left of the fall plays under it within the same time.
    static let hurriedReveal: TimeInterval = 0.12
    /// Closed as it falls, the drop rises back the way it came within this long.
    static let rewindLength: TimeInterval = 0.2
    private static let rate: Double = 120

    /// The frame on screen `elapsed` seconds into the motion.
    func frameIndex(at elapsed: TimeInterval) -> Int {
        guard duration > 0 else { return 0 }
        return keyTimes.lastIndex { $0 <= elapsed / duration } ?? 0
    }

    /// What is left from frame `index` on, within `limit` seconds and never
    /// slower than as written.
    func remainder(from index: Int, within limit: TimeInterval) -> CommandBarDropletMotion {
        guard !frames.isEmpty, frames.count == keyTimes.count else { return CommandBarDropletMotion() }
        let start = min(max(0, index), frames.count - 1)
        let from = keyTimes[start], span = 1 - from
        var rest = CommandBarDropletMotion()
        rest.frames = Array(frames[start...])
        rest.keyTimes = keyTimes[start...].map { span > 0 ? ($0 - from) / span : 0 }
        rest.duration = rest.frames.count > 1 ? min(limit, duration * span) : 0
        return rest
    }

    /// The way back from frame `index` to the first, within `limit` seconds
    /// and never slower than it came.
    func rewound(from index: Int, within limit: TimeInterval) -> CommandBarDropletMotion {
        guard !frames.isEmpty, frames.count == keyTimes.count else { return CommandBarDropletMotion() }
        let end = min(max(0, index), frames.count - 1)
        let span = keyTimes[end]
        var back = CommandBarDropletMotion()
        back.frames = Array(frames[...end].reversed())
        back.keyTimes = keyTimes[...end].reversed().map { span > 0 ? (span - $0) / span : 0 }
        back.duration = back.frames.count > 1 ? min(limit, duration * span) : 0
        return back
    }

    /// From the full width of the island's lower edge at `edge` into the bar.
    static func drop(edge: CGFloat, centerX: CGFloat, sourceSize: CGSize, field: CGRect) -> CommandBarDropletMotion {
        let side = beadSide
        let launchWidth = max(side, sourceSize.width)
        let launchHeight = max(1, sourceSize.height)
        let land = CGPoint(x: centerX, y: field.midY)
        let stretchEnd: TimeInterval = 0.1
        let detachEnd: TimeInterval = 0.26
        let startCenterY = edge + side * 0.45
        let fall = TimeInterval(min(0.16, max(0.1, Double(max(0, land.y - startCenterY)) / 500)))
        let fallEnd = detachEnd + fall
        let openStart = fallEnd + 0.04
        let preOpenWidth = min(field.width, max(launchWidth, field.width - 18))
        let squashed = CGSize(width: preOpenWidth, height: max(side * 1.12, field.height * 0.72))
        let widthSpring = NotchMotion.Spring(duration: 0.2, bounce: 0.08)
            .limited(travel: max(1, field.width - squashed.width), limit: 2)
        let heightSpring = NotchMotion.Spring(duration: 0.18, bounce: 0.08)
            .limited(travel: abs(field.height - squashed.height), limit: 1)
        let openLength = settling(widthSpring, from: squashed.width, to: field.width)
        let duration = openStart + max(openLength, settling(heightSpring, from: squashed.height, to: field.height))
        var motion = CommandBarDropletMotion()
        motion.duration = duration
        motion.landing = fallEnd
        motion.reveal = min(duration, openStart + max(settling(widthSpring, from: squashed.width, to: field.width, within: 2),
                                                      settling(heightSpring, from: squashed.height, to: field.height,
                                                               within: 1)))
        let count = max(2, Int((duration * rate).rounded(.up)))
        for step in 0...count {
            let time = duration * Double(step) / Double(count)
            var size = CGSize(width: side, height: side)
            var center = land
            var neckEnd = edge, neckRoot: CGFloat = 0, neckTip: CGFloat = 0
            if time < stretchEnd {
                // Begin at the island's fitted size so the tear has no jump
                // at either edge when it first appears.
                let share = ease(time / stretchEnd)
                size = CGSize(width: launchWidth, height: launchHeight + (side * 1.12 - launchHeight) * share)
                center = CGPoint(x: centerX, y: edge - launchHeight / 2
                                 + (launchHeight / 2 + side * 0.45) * share)
            } else if time < fallEnd {
                // Widen and round while it falls; the tear pulls back into
                // the island instead of pinching into a tiny bead first.
                let share = min(1, max(0, (time - stretchEnd) / (fallEnd - stretchEnd)))
                let eased = ease(share)
                size = CGSize(width: launchWidth + (squashed.width - launchWidth) * eased,
                              height: side * 1.12 + (squashed.height - side * 1.12) * eased)
                center = CGPoint(x: centerX, y: startCenterY + (land.y - startCenterY) * eased)
                let beadTop = center.y - size.height / 2
                if share <= 0.45 {
                    neckEnd = max(edge - 1, beadTop)
                } else {
                    let detachedTop = startCenterY + (land.y - startCenterY) * ease(0.45)
                        - (side * 1.12 + (squashed.height - side * 1.12) * ease(0.45)) / 2
                    let retreat = ease((share - 0.45) / 0.55)
                    neckEnd = detachedTop + (edge - 1 - detachedTop) * retreat
                }
                let attachment = CGFloat(1 - ease(share))
                neckRoot = launchWidth / 2 * attachment * attachment
                neckTip = min(neckRoot * 0.3, size.width * 0.15)
                if neckEnd - edge >= 1 { neckTip = max(neckTip, 0.21) }
            } else if time < openStart {
                size = squashed
                center = land
            } else {
                let open = time - openStart
                let width = squashed.width + (field.width - squashed.width) * CGFloat(widthSpring.progress(at: open))
                let heightShare = CGFloat(heightSpring.progress(at: open))
                size = CGSize(width: max(side * 0.5, width),
                              height: max(side * 0.5, squashed.height + (field.height - squashed.height) * heightShare))
                let spread = min(1, max(0, (size.width - squashed.width) / max(1, field.width - squashed.width)))
                center = CGPoint(x: centerX + (field.midX - centerX) * spread, y: land.y)
            }
            if time >= fallEnd { neckEnd = edge - 1 }
            let bead = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                              width: size.width, height: size.height)
            let openShare = time < openStart ? 0 : min(1, max(0, CGFloat(heightSpring.progress(at: time - openStart))))
            let radius = min(size.width, size.height) / 2 * (1 - openShare)
                + min(fieldRadius, min(size.width, size.height) / 2) * openShare
            motion.frames.append(CommandBarDropletFrame(bead: bead, radius: radius, neckEnd: max(edge - 1, neckEnd),
                                                        neckRoot: max(0, neckRoot), neckTip: max(0, neckTip)))
            motion.keyTimes.append(Double(step) / Double(count))
        }
        if let last = motion.frames.indices.last {
            motion.frames[last].bead = field
            motion.frames[last].radius = min(fieldRadius, field.height / 2)
        }
        return motion
    }

    /// The way back: the bar folds to its field and into a drop, which rises
    /// back into the island.
    static func retract(edge: CGFloat, centerX: CGFloat, sourceSize: CGSize, bar: CGRect,
                        field: CGRect) -> CommandBarDropletMotion {
        let side = beadSide
        let fold: TimeInterval = bar.height > field.height + 1 ? 0.1 : 0
        let shrinkSpring = NotchMotion.Spring(duration: 0.26, bounce: 0)
        let shrink = settling(shrinkSpring, from: field.width, to: side)
        let rise: TimeInterval = 0.16
        let absorb: TimeInterval = 0.06
        let riseStart = fold + shrink * 0.55
        let duration = riseStart + rise + absorb
        let rest = CGPoint(x: centerX, y: field.midY)
        let sourceHeight = max(1, sourceSize.height)
        var motion = CommandBarDropletMotion()
        motion.duration = duration
        let count = max(2, Int((duration * rate).rounded(.up)))
        for step in 0...count {
            let time = duration * Double(step) / Double(count)
            var rect = bar
            var radius = min(fieldRadius, field.height / 2)
            var neckEnd = edge, neckRoot: CGFloat = 0, neckTip: CGFloat = 0
            if time < fold {
                let share = ease(time / fold)
                rect.size.height = bar.height + (field.height - bar.height) * share
            } else {
                let open = time - fold
                let progress = CGFloat(shrinkSpring.progress(at: open))
                let width = field.width + (sourceSize.width - field.width) * progress
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
                        center.x = centerX
                        center.y = rest.y + (edge - sourceHeight / 2 - rest.y) * gone
                        size = CGSize(width: size.width + (sourceSize.width - size.width) * gone,
                                      height: size.height + (sourceHeight - size.height) * gone)
                        neckRoot = 14 * (1 - gone)
                        neckTip = size.width * 0.45 * (1 - gone)
                        neckEnd = edge - sourceHeight * gone
                    }
                }
                rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
                radius = min(size.width, size.height) / 2 * progress + min(fieldRadius, field.height / 2) * (1 - progress)
            }
            motion.frames.append(CommandBarDropletFrame(bead: rect, radius: radius, neckEnd: max(edge - 1, neckEnd),
                                                        neckRoot: max(0, neckRoot), neckTip: max(0, neckTip)))
            motion.keyTimes.append(Double(step) / Double(count))
        }
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
