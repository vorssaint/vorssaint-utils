// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

// The companion is a small friend who lives in the Dynamic Island: a colored
// shape with two ink eyes and no mouth, or a little robot. It rests beside
// the camera when the closed island has nothing else to show, passes by now
// and then, and is the Command Bar's face when the bar comes out of the
// island. The code calls it the mascot, because "companion" already names
// the second activity sharing the closed island.

enum NotchMascotStyle: String, CaseIterable, Identifiable {
    case minimal, robot

    var id: String { rawValue }
}

enum NotchMascotShape: String, CaseIterable, Identifiable {
    case ball, egg, squircle, pill

    var id: String { rawValue }
}

/// sRGB components, so the model needs no AppKit.
struct NotchMascotColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    var alpha: CGFloat = 1

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    /// The eyes, a soft black that still reads on the black island's edge.
    static let ink = NotchMascotColor(red: 0.07, green: 0.07, blue: 0.08)
    /// The robot's face plate, where its lit eyes sit.
    static let visor = NotchMascotColor(red: 0.09, green: 0.09, blue: 0.11)
    static let shine = NotchMascotColor(red: 1, green: 1, blue: 1, alpha: 0.55)
}

/// The colors it comes in, in the order of the rainbow after white, so the
/// swatches in Settings read as one row.
enum NotchMascotPalette: String, CaseIterable, Identifiable {
    case pearl, lemon, peach, rose, lilac, sky, mint

    var id: String { rawValue }

    /// The body's lit top.
    var light: NotchMascotColor {
        switch self {
        case .pearl: return NotchMascotColor(red: 0.99, green: 0.98, blue: 0.96)
        case .lemon: return NotchMascotColor(red: 1.00, green: 0.96, blue: 0.64)
        case .peach: return NotchMascotColor(red: 1.00, green: 0.86, blue: 0.74)
        case .rose: return NotchMascotColor(red: 1.00, green: 0.80, blue: 0.87)
        case .lilac: return NotchMascotColor(red: 0.88, green: 0.83, blue: 1.00)
        case .sky: return NotchMascotColor(red: 0.77, green: 0.90, blue: 1.00)
        case .mint: return NotchMascotColor(red: 0.72, green: 0.97, blue: 0.86)
        }
    }

    /// The body's shaded bottom, and the robot's antenna and bolts.
    var shade: NotchMascotColor {
        switch self {
        case .pearl: return NotchMascotColor(red: 0.84, green: 0.85, blue: 0.90)
        case .lemon: return NotchMascotColor(red: 0.97, green: 0.83, blue: 0.30)
        case .peach: return NotchMascotColor(red: 0.98, green: 0.64, blue: 0.50)
        case .rose: return NotchMascotColor(red: 0.95, green: 0.54, blue: 0.68)
        case .lilac: return NotchMascotColor(red: 0.69, green: 0.59, blue: 0.96)
        case .sky: return NotchMascotColor(red: 0.43, green: 0.67, blue: 0.97)
        case .mint: return NotchMascotColor(red: 0.40, green: 0.83, blue: 0.66)
        }
    }
}

struct NotchMascotLook: Equatable {
    var style: NotchMascotStyle
    var shape: NotchMascotShape
    var palette: NotchMascotPalette

    static let standard = NotchMascotLook(style: .minimal, shape: .ball, palette: .pearl)
}

enum NotchMascotMood: String, CaseIterable, Identifiable {
    case idle, happy, wink, love, sleepy, determined, surprised, searching, thinking, confused
    /// Wide awake, while Keep Awake holds the Mac up.
    case alert

    var id: String { rawValue }
}

/// Which side of the camera the companion rests on.
enum NotchMascotSide: String, CaseIterable, Identifiable {
    case left, right

    var id: String { rawValue }
}

/// How often the companion strolls through the island.
enum NotchMascotVisitFrequency: String, CaseIterable, Identifiable {
    case rare, normal, frequent

    var id: String { rawValue }

    /// How long it waits between visits, in seconds.
    var delay: ClosedRange<TimeInterval> {
        switch self {
        case .rare: return 600...1200
        case .normal: return 240...540
        case .frequent: return 90...180
        }
    }
}

/// A short reaction to something the island saw happen.
enum NotchMascotReaction: String, CaseIterable {
    /// Something finished well: an agent's task, a download, a file dropped in.
    case celebrate
    /// Plugged in to charge, or petted.
    case love
    /// A timer ran out.
    case surprised
    /// A screenshot: a hard blink, as a camera's flash.
    case flash
    /// Something failed.
    case confused
    /// The Mac was unlocked: it wakes up glad to see you.
    case wakeUp
    /// Keep Awake let go: a yawn.
    case yawn
    /// Keep Awake took hold, or the microphone opened: wide eyes and a hop.
    case perk
    /// An event the island counted down to began: wide eyes and two quick
    /// hops, time to go.
    case bounce
    /// The microphone went quiet: eyes shut a moment as it ducks.
    case hush
    /// A timer started: a determined look and a little nod.
    case ready
    /// Music started: smiling eyes and a bob to the beat.
    case groove

    /// About how long it plays, so the companion stays out for all of it
    /// when it comes out over an activity to play it.
    var length: TimeInterval {
        switch self {
        case .celebrate: return 1.0
        case .love: return 1.4
        case .surprised: return 0.9
        case .flash: return 0.5
        case .confused: return 1.2
        case .wakeUp: return 1.6
        case .yawn: return 1.2
        case .perk: return 1.0
        case .bounce: return 1.0
        case .hush: return 1.0
        case .ready: return 1.0
        case .groove: return 1.6
        }
    }
}

/// What the Settings preview can act out: a visit, and the moments the
/// island reacts to, each with the reaction it brings.
enum NotchMascotMoment: String, CaseIterable, Identifiable {
    case visit, timerStarted, timeIsUp, music, agents, eventStarts, downloadFinished, downloadFailed, screenshot,
         micMuted, keepAwake, charging, lowBattery, unlocked

    var id: String { rawValue }

    /// Nil for a visit, which is a stroll rather than a reaction.
    var reaction: NotchMascotReaction? {
        switch self {
        case .visit: return nil
        case .timerStarted: return .ready
        case .timeIsUp: return .surprised
        case .music: return .groove
        case .agents: return .ready
        case .eventStarts: return .bounce
        case .downloadFinished: return .celebrate
        case .downloadFailed: return .confused
        case .screenshot: return .flash
        case .micMuted: return .hush
        case .keepAwake: return .perk
        case .charging: return .love
        case .lowBattery: return .yawn
        case .unlocked: return .wakeUp
        }
    }

    /// What it plays once the first reaction is over, for a moment told in
    /// two beats: an AI agent getting to work, then done.
    var followUp: NotchMascotReaction? {
        self == .agents ? .celebrate : nil
    }

    var symbol: String {
        switch self {
        case .visit: return "figure.walk"
        case .timerStarted: return "timer"
        case .timeIsUp: return "alarm"
        case .music: return "music.note"
        case .agents: return "sparkles"
        case .eventStarts: return "calendar"
        case .downloadFinished: return "arrow.down.circle"
        case .downloadFailed: return "exclamationmark.triangle"
        case .screenshot: return "camera.viewfinder"
        case .micMuted: return "mic.slash"
        case .keepAwake: return "cup.and.saucer"
        case .charging: return "bolt"
        case .lowBattery: return "battery.25percent"
        case .unlocked: return "lock.open"
        }
    }
}

/// One reaction, as the island publishes it for the companion to play.
struct NotchMascotReactionEvent: Equatable {
    let id: UUID
    let reaction: NotchMascotReaction
    /// When it was published, on the media clock.
    let start: CFTimeInterval
}

/// Keeps reactions short and rare. None comes within `spacing` of the last,
/// the same one does not come back within `repeatInterval`, and one the
/// companion cannot show waits for it at most `patience`.
struct NotchMascotReactionGate {
    static let spacing: TimeInterval = 2.5
    static let repeatInterval: TimeInterval = 30
    static let patience: TimeInterval = 8

    private(set) var last: (reaction: NotchMascotReaction, time: TimeInterval)?

    /// Whether `reaction` may play at `time`, remembering it when it may.
    mutating func admits(_ reaction: NotchMascotReaction, at time: TimeInterval) -> Bool {
        if let last {
            if time - last.time < Self.spacing { return false }
            if last.reaction == reaction, time - last.time < Self.repeatInterval { return false }
        }
        last = (reaction, time)
        return true
    }
}

/// How the Command Bar comes out of the island.
enum NotchCommandBarStyle: String, CaseIterable, Identifiable {
    /// A drop falls from the island's lower edge and opens into the bar.
    case droplet
    /// The bar opens inside the open island.
    case island

    var id: String { rawValue }
}

/// Where the Command Bar shows when it opens.
enum CommandBarPresentation: Equatable {
    /// Its own window, as it always has.
    case window
    /// A window below the island, reached by a falling drop.
    case droplet
    /// Inside the open island.
    case island
}

enum NotchMascotEye: Equatable {
    case open, closed, happy, heart, sleepy, wide, squint
    /// The lid slants down toward the other eye.
    case determined

    var blinks: Bool { self == .open || self == .wide || self == .squint }
}

struct NotchMascotExpression: Equatable {
    var left: NotchMascotEye
    var right: NotchMascotEye
    /// Where the eyes look, in shares of the companion's size. Y grows downward.
    var gaze: CGPoint = .zero
    /// The head's lean in radians, clockwise on screen.
    var tilt: CGFloat = 0

    /// Open eyes blink now and then. Closed, curved or heart eyes do not.
    var blinks: Bool { left.blinks && right.blinks }
}

extension NotchMascotMood {
    var expression: NotchMascotExpression {
        switch self {
        case .idle: return NotchMascotExpression(left: .open, right: .open)
        case .happy: return NotchMascotExpression(left: .happy, right: .happy, gaze: CGPoint(x: 0, y: -0.02))
        case .wink: return NotchMascotExpression(left: .open, right: .happy, tilt: -0.08)
        case .love: return NotchMascotExpression(left: .heart, right: .heart)
        case .sleepy: return NotchMascotExpression(left: .sleepy, right: .sleepy, gaze: CGPoint(x: 0, y: 0.03), tilt: 0.05)
        case .determined: return NotchMascotExpression(left: .determined, right: .determined)
        case .surprised: return NotchMascotExpression(left: .wide, right: .wide, gaze: CGPoint(x: 0, y: -0.02))
        case .searching: return NotchMascotExpression(left: .open, right: .open, gaze: CGPoint(x: 0.05, y: 0))
        case .thinking: return NotchMascotExpression(left: .squint, right: .open, gaze: CGPoint(x: 0.06, y: -0.06), tilt: -0.1)
        case .confused: return NotchMascotExpression(left: .open, right: .squint, gaze: CGPoint(x: -0.03, y: 0.01), tilt: 0.14)
        case .alert: return NotchMascotExpression(left: .wide, right: .wide)
        }
    }
}

/// Where the face sits on each body, in shares of the companion's size from
/// its top left corner.
struct NotchMascotFaceLayout: Equatable {
    let leftEye: CGPoint
    let rightEye: CGPoint
    /// An open eye's width and height.
    let eyeSize: CGSize
    /// The soft highlight on the body: its center, radii and lean.
    let shineCenter: CGPoint
    let shineRadii: CGSize
    let shineAngle: CGFloat
}

extension NotchMascotLook {
    var face: NotchMascotFaceLayout {
        if style == .robot {
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.36, y: 0.63), rightEye: CGPoint(x: 0.64, y: 0.63),
                                         eyeSize: CGSize(width: 0.085, height: 0.16),
                                         shineCenter: CGPoint(x: 0.27, y: 0.34), shineRadii: CGSize(width: 0.07, height: 0.04),
                                         shineAngle: -0.3)
        }
        switch shape {
        case .ball:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.36, y: 0.50), rightEye: CGPoint(x: 0.64, y: 0.50),
                                         eyeSize: CGSize(width: 0.10, height: 0.20),
                                         shineCenter: CGPoint(x: 0.31, y: 0.29), shineRadii: CGSize(width: 0.085, height: 0.055),
                                         shineAngle: -0.5)
        case .egg:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.375, y: 0.55), rightEye: CGPoint(x: 0.625, y: 0.55),
                                         eyeSize: CGSize(width: 0.095, height: 0.19),
                                         shineCenter: CGPoint(x: 0.33, y: 0.31), shineRadii: CGSize(width: 0.075, height: 0.05),
                                         shineAngle: -0.6)
        case .squircle:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.35, y: 0.53), rightEye: CGPoint(x: 0.65, y: 0.53),
                                         eyeSize: CGSize(width: 0.10, height: 0.20),
                                         shineCenter: CGPoint(x: 0.24, y: 0.28), shineRadii: CGSize(width: 0.08, height: 0.05),
                                         shineAngle: -0.55)
        case .pill:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.37, y: 0.57), rightEye: CGPoint(x: 0.63, y: 0.57),
                                         eyeSize: CGSize(width: 0.09, height: 0.19),
                                         shineCenter: CGPoint(x: 0.20, y: 0.42), shineRadii: CGSize(width: 0.07, height: 0.045),
                                         shineAngle: -0.45)
        }
    }
}

/// Outlines in a square of `size` points, from its top left corner.
enum NotchMascotGeometry {
    /// Every eye is drawn with this many curves, so any eye can turn into
    /// any other one point at a time.
    static let eyeCurveCount = 24

    static func body(_ shape: NotchMascotShape, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        switch shape {
        case .ball:
            path.addEllipse(in: CGRect(x: 0.08 * size, y: 0.12 * size, width: 0.84 * size, height: 0.84 * size))
        case .egg:
            path.move(to: point(0.5, 0.10))
            path.addCurve(to: point(0.86, 0.60), control1: point(0.71, 0.10), control2: point(0.86, 0.36))
            path.addCurve(to: point(0.5, 0.96), control1: point(0.86, 0.80), control2: point(0.70, 0.96))
            path.addCurve(to: point(0.14, 0.60), control1: point(0.30, 0.96), control2: point(0.14, 0.80))
            path.addCurve(to: point(0.5, 0.10), control1: point(0.14, 0.36), control2: point(0.29, 0.10))
            path.closeSubpath()
        case .squircle:
            // A superellipse: flatter sides than a rounded rectangle, no corner seam.
            let count = 72
            for index in 0..<count {
                let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
                let cosine = cos(angle), sine = sin(angle)
                let exponent: CGFloat = 2 / 3.4
                let x = 0.5 + 0.43 * (cosine < 0 ? -1 : 1) * pow(abs(cosine), exponent)
                let y = 0.55 + 0.40 * (sine < 0 ? -1 : 1) * pow(abs(sine), exponent)
                if index == 0 { path.move(to: point(x, y)) } else { path.addLine(to: point(x, y)) }
            }
            path.closeSubpath()
        case .pill:
            path.addRoundedRect(in: CGRect(x: 0.05 * size, y: 0.28 * size, width: 0.90 * size, height: 0.60 * size),
                                cornerWidth: 0.30 * size, cornerHeight: 0.30 * size)
        }
        return path
    }

    /// The robot's head, ears, antenna and face plate.
    struct Robot {
        let head: CGPath
        let ears: CGPath
        let antenna: CGPath
        let bulb: CGPath
        let visor: CGPath
    }

    /// How far below the middle of its box the figure's own middle sits, as
    /// a share of the box. The box keeps room above a minimal body for the
    /// robot's antenna, so a body placed by its box would sit a little low
    /// wherever it is meant to be centred.
    static func figureOffset(_ look: NotchMascotLook) -> CGFloat {
        let bounds: CGRect
        if look.style == .robot {
            let parts = robot(size: 1)
            bounds = [parts.ears, parts.antenna, parts.bulb]
                .reduce(parts.head.boundingBoxOfPath) { $0.union($1.boundingBoxOfPath) }
        } else {
            bounds = body(look.shape, size: 1).boundingBoxOfPath
        }
        return bounds.midY - 0.5
    }

    static func robot(size: CGFloat) -> Robot {
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: x * size, y: y * size, width: width * size, height: height * size)
        }
        func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
            CGPath(roundedRect: rect, cornerWidth: radius * size, cornerHeight: radius * size, transform: nil)
        }
        let ears = CGMutablePath()
        ears.addPath(rounded(rect(0.05, 0.50, 0.08, 0.20), 0.035))
        ears.addPath(rounded(rect(0.87, 0.50, 0.08, 0.20), 0.035))
        return Robot(head: rounded(rect(0.12, 0.26, 0.76, 0.68), 0.20),
                     ears: ears,
                     antenna: rounded(rect(0.475, 0.12, 0.05, 0.16), 0.025),
                     bulb: CGPath(ellipseIn: rect(0.43, 0.04, 0.14, 0.14), transform: nil),
                     visor: rounded(rect(0.20, 0.44, 0.60, 0.38), 0.15))
    }

    /// The highlight, an ellipse leaning with the body's curve.
    static func shine(_ face: NotchMascotFaceLayout, size: CGFloat) -> CGPath {
        var transform = CGAffineTransform(translationX: face.shineCenter.x * size, y: face.shineCenter.y * size)
            .rotated(by: face.shineAngle)
        let radii = CGSize(width: face.shineRadii.width * size, height: face.shineRadii.height * size)
        return CGPath(ellipseIn: CGRect(x: -radii.width, y: -radii.height, width: radii.width * 2, height: radii.height * 2),
                      transform: &transform)
    }

    /// An eye's outline around `center`. `size` is an open eye's width and
    /// height, and the right eye mirrors the left one.
    static func eye(_ eye: NotchMascotEye, size: CGSize, center: CGPoint, right: Bool) -> CGPath {
        let points = eyePoints(eye, size: size, right: right).map {
            CGPoint(x: $0.x + center.x, y: $0.y + center.y)
        }
        return smoothClosedPath(points)
    }

    /// The eye's outline as `eyeCurveCount` points, from the top of its
    /// middle line, clockwise on screen.
    static func eyePoints(_ eye: NotchMascotEye, size: CGSize, right: Bool) -> [CGPoint] {
        let width = max(0.5, size.width), height = max(0.5, size.height)
        var outline: [CGPoint]
        switch eye {
        case .open:
            outline = stadium(width: width, height: height, center: .zero)
        case .closed:
            outline = stadium(width: width * 1.5, height: width * 0.45, center: CGPoint(x: 0, y: height * 0.12))
        case .squint:
            outline = stadium(width: width, height: height * 0.55, center: CGPoint(x: 0, y: height * 0.08))
        case .wide:
            outline = ellipse(radii: CGSize(width: width * 0.8, height: width * 0.8), center: CGPoint(x: 0, y: -height * 0.02))
        case .happy:
            outline = arch(span: width * 2.1, rise: height * 0.42, thickness: width * 0.55, top: -height * 0.18)
        case .heart:
            outline = heart(width: width * 2.0, height: width * 1.8, center: CGPoint(x: 0, y: -height * 0.02))
        case .sleepy:
            outline = lid(width: width * 1.25, top: height * 0.02, depth: height * 0.38)
        case .determined:
            // The left eye's lid falls toward the nose, on its right.
            outline = clipBelow(stadium(width: width, height: height, center: .zero),
                                from: CGPoint(x: -width / 2, y: -height * 0.30),
                                to: CGPoint(x: width / 2, y: height * 0.02))
        }
        if right { outline = outline.map { CGPoint(x: -$0.x, y: $0.y) } }
        return resample(outline, count: eyeCurveCount)
    }

    // MARK: Outlines

    private static let dense = 96

    /// A capsule standing on its round ends, or lying on them when wider.
    private static func stadium(width: CGFloat, height: CGFloat, center: CGPoint) -> [CGPoint] {
        let radius = min(width, height) / 2
        let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        return roundedRect(rect, radius: radius)
    }

    private static func roundedRect(_ rect: CGRect, radius: CGFloat) -> [CGPoint] {
        let corners: [(CGPoint, CGFloat)] = [
            (CGPoint(x: rect.maxX - radius, y: rect.minY + radius), -.pi / 2),
            (CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), 0),
            (CGPoint(x: rect.minX + radius, y: rect.maxY - radius), .pi / 2),
            (CGPoint(x: rect.minX + radius, y: rect.minY + radius), .pi),
        ]
        var points: [CGPoint] = []
        let steps = dense / 4
        for (center, start) in corners {
            for step in 0...steps {
                let angle = start + CGFloat(step) / CGFloat(steps) * .pi / 2
                points.append(CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
            }
        }
        return points
    }

    private static func ellipse(radii: CGSize, center: CGPoint) -> [CGPoint] {
        (0..<dense).map { index in
            let angle = -CGFloat.pi / 2 + CGFloat(index) / CGFloat(dense) * 2 * .pi
            return CGPoint(x: center.x + radii.width * cos(angle), y: center.y + radii.height * sin(angle))
        }
    }

    /// Eyes shut with a smile: a band bent upward, round at both ends.
    private static func arch(span: CGFloat, rise: CGFloat, thickness: CGFloat, top: CGFloat) -> [CGPoint] {
        let half = max(0.1, span / 2 - thickness / 2)
        let lift = max(0.1, rise)
        let radius = (half * half + lift * lift) / (2 * lift)
        let apex = top + thickness / 2
        let center = CGPoint(x: 0, y: apex + radius)
        let reach = asin(min(1, half / radius))
        func onArc(_ angle: CGFloat, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
        }
        let steps = dense / 3
        var points: [CGPoint] = []
        for step in 0...steps {
            points.append(onArc(-reach + CGFloat(step) / CGFloat(steps) * reach * 2, radius + thickness / 2))
        }
        // The right end's round cap, from the outer arc to the inner one.
        let rightEnd = onArc(reach, radius)
        for step in 1..<12 {
            let angle = reach + CGFloat(step) / 12 * .pi
            points.append(CGPoint(x: rightEnd.x + thickness / 2 * sin(angle), y: rightEnd.y - thickness / 2 * cos(angle)))
        }
        for step in 0...steps {
            points.append(onArc(reach - CGFloat(step) / CGFloat(steps) * reach * 2, radius - thickness / 2))
        }
        let leftEnd = onArc(-reach, radius)
        for step in 1..<12 {
            let angle = -reach + .pi + CGFloat(step) / 12 * .pi
            points.append(CGPoint(x: leftEnd.x + thickness / 2 * sin(angle), y: leftEnd.y - thickness / 2 * cos(angle)))
        }
        return points
    }

    private static func heart(width: CGFloat, height: CGFloat, center: CGPoint) -> [CGPoint] {
        // The classic heart curve, 32 wide and about 29 tall, with y up.
        let raw: [CGPoint] = (0..<dense).map { index in
            let t = CGFloat(index) / CGFloat(dense) * 2 * .pi
            let x = 16 * pow(sin(t), 3)
            let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            return CGPoint(x: x, y: y)
        }
        let minY = raw.map(\.y).min() ?? 0, maxY = raw.map(\.y).max() ?? 1
        let middle = (minY + maxY) / 2
        return raw.map {
            CGPoint(x: center.x + $0.x / 32 * width,
                    y: center.y - ($0.y - middle) / (maxY - minY) * height)
        }
    }

    /// A drowsy eye: the lid's flat edge on top, the eye's round bottom below.
    private static func lid(width: CGFloat, top: CGFloat, depth: CGFloat) -> [CGPoint] {
        let half = width / 2
        var points: [CGPoint] = []
        let flat = dense / 4
        for step in 0...flat {
            points.append(CGPoint(x: -half + CGFloat(step) / CGFloat(flat) * width, y: top))
        }
        let round = dense - flat
        for step in 1..<round {
            let angle = CGFloat(step) / CGFloat(round) * .pi
            points.append(CGPoint(x: half * cos(angle), y: top + depth * sin(angle)))
        }
        return points
    }

    /// The part of a convex outline below the line from `from` to `to`.
    private static func clipBelow(_ points: [CGPoint], from: CGPoint, to: CGPoint) -> [CGPoint] {
        func side(_ point: CGPoint) -> CGFloat {
            // Positive below the line, with y growing downward.
            (to.x - from.x) * (point.y - from.y) - (to.y - from.y) * (point.x - from.x)
        }
        var clipped: [CGPoint] = []
        for index in points.indices {
            let current = points[index], next = points[(index + 1) % points.count]
            let a = side(current), b = side(next)
            if a >= 0 { clipped.append(current) }
            if (a >= 0) != (b >= 0) {
                let share = a / (a - b)
                clipped.append(CGPoint(x: current.x + (next.x - current.x) * share,
                                       y: current.y + (next.y - current.y) * share))
            }
        }
        return clipped.count >= 3 ? clipped : points
    }

    // MARK: Resampling

    /// `count` points evenly spaced along the outline, starting where its top
    /// crosses the middle line and going clockwise on screen. Every eye then
    /// has its points in the same places, which is what lets one become another.
    static func resample(_ outline: [CGPoint], count: Int) -> [CGPoint] {
        guard outline.count >= 3, count >= 3 else { return outline }
        var points = outline
        // Clockwise on screen, with y growing downward, is a positive area.
        var area: CGFloat = 0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        if area < 0 { points.reverse() }
        // The start: the highest place where the outline crosses x = 0.
        var start: (index: Int, point: CGPoint)?
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            guard (a.x <= 0 && b.x > 0) || (a.x >= 0 && b.x < 0) || a.x == 0 else { continue }
            let share = b.x == a.x ? 0 : -a.x / (b.x - a.x)
            let crossing = CGPoint(x: 0, y: a.y + (b.y - a.y) * share)
            if start == nil || crossing.y < start!.point.y { start = (index, crossing) }
        }
        guard let start else { return Array(points.prefix(count)) }
        var walk = [start.point]
        for offset in 1...points.count {
            walk.append(points[(start.index + offset) % points.count])
        }
        walk.append(start.point)
        var lengths: [CGFloat] = [0]
        for index in 1..<walk.count {
            lengths.append(lengths[index - 1] + hypot(walk[index].x - walk[index - 1].x, walk[index].y - walk[index - 1].y))
        }
        let total = lengths.last ?? 0
        guard total > 0 else { return Array(repeating: start.point, count: count) }
        var result: [CGPoint] = []
        var segment = 1
        for step in 0..<count {
            let target = total * CGFloat(step) / CGFloat(count)
            while segment < lengths.count - 1, lengths[segment] < target { segment += 1 }
            let span = lengths[segment] - lengths[segment - 1]
            let share = span > 0 ? (target - lengths[segment - 1]) / span : 0
            let a = walk[segment - 1], b = walk[segment]
            result.append(CGPoint(x: a.x + (b.x - a.x) * share, y: a.y + (b.y - a.y) * share))
        }
        return result
    }

    /// A closed curve through every point, one cubic per point.
    static func smoothClosedPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let count = points.count
        guard count >= 3 else { return path }
        path.move(to: points[0])
        for index in 0..<count {
            let previous = points[(index - 1 + count) % count]
            let current = points[index]
            let next = points[(index + 1) % count]
            let after = points[(index + 2) % count]
            let first = CGPoint(x: current.x + (next.x - previous.x) / 6, y: current.y + (next.y - previous.y) / 6)
            let second = CGPoint(x: next.x - (after.x - current.x) / 6, y: next.y - (after.y - current.y) / 6)
            path.addCurve(to: next, control1: first, control2: second)
        }
        path.closeSubpath()
        return path
    }
}

/// One stroll of the companion through the closed island.
struct NotchMascotVisit: Equatable {
    enum Kind: Equatable {
        /// From its resting place, around the island and back.
        case lap
        /// In at one end and out at the other, over what the island shows.
        case pass
        /// Back from the Command Bar's drop: out from behind the camera to its place.
        case home
        /// Out from behind the camera over what the island shows, to play
        /// a reaction where it would rest, and back behind the camera.
        case cameo(NotchMascotReaction)
        /// The last seconds of a countdown, this long: out over the timer's
        /// mark to watch the reading run out, and back behind the camera.
        case countdown(TimeInterval)
        /// A countdown it watched was paused: back behind the camera.
        case retreat
        /// Switched off: a glad hop where it rests and away behind the
        /// camera, before the wings it rested in fold.
        case farewell
        /// Moved to the camera's other side: from where it rested, behind
        /// the camera, across, and out to its new place.
        case cross
        /// Switched on: out from behind the camera to its place as the wings
        /// open, or in at a capsule's near end.
        case arrive
        /// Still where it rested as an activity took its place: it plays a
        /// reaction right there and goes behind the camera, rather than
        /// leaving its place only to come back out for it.
        case linger(NotchMascotReaction)

        /// It ends out of sight, past the strip's end or behind the camera,
        /// so it can cross an activity's strip and leave nothing behind.
        var endsOutOfSight: Bool {
            switch self {
            case .pass, .cameo, .countdown, .retreat, .farewell, .linger: return true
            case .lap, .home, .cross, .arrive: return false
            }
        }

        /// It stands over the timer's mark only, and the reading stays in view.
        var watchesTimer: Bool {
            switch self {
            case .countdown, .retreat: return true
            default: return false
            }
        }

        /// Over an activity beside a camera it takes only the wing it stands
        /// in, and the other side reads on: the timer's mark while it watches
        /// a countdown, or its own wing as it reacts, with the music's bars
        /// playing on or an arriving activity reading at once. Only a stroll
        /// from end to end takes the whole strip.
        var takesOnlyItsWing: Bool {
            switch self {
            case .countdown, .retreat, .cameo, .linger: return true
            default: return false
            }
        }

        /// The reaction it comes out for, played as it lands or at once
        /// where it already stands.
        var reaction: NotchMascotReaction? {
            switch self {
            case .cameo(let reaction), .linger(let reaction): return reaction
            default: return nil
            }
        }
    }

    let id: UUID
    let kind: Kind
    let greeting: NotchMascotMood
    /// When it began, on the media clock, so a strip drawn again meanwhile
    /// picks it up where it is.
    let start: CFTimeInterval

    var duration: TimeInterval { NotchMascotMotion.duration(of: kind) }
}

/// Where the companion can walk in a closed strip, in points from the
/// strip's top left corner.
struct NotchMascotTrack: Equatable {
    var width: CGFloat
    var height: CGFloat
    /// The companion's square.
    var size: CGFloat
    /// Its center while resting.
    var rest: CGFloat
    /// The camera: walking there, it is behind it.
    var hidden: ClosedRange<CGFloat>?
    /// The height of its center.
    var baseline: CGFloat
    /// The top of the island over it: the screen's edge, or a capsule's.
    var ceiling: CGFloat = 0
    /// It rests right of the camera, and every stroll runs the other way.
    var mirrored = false
    /// How many times larger than the island it is drawn, so the few points
    /// it keeps from edges grow with it in the Settings preview.
    var scale: CGFloat = 1

    /// How high a hop of `share` of its size lifts it, kept clear of the
    /// island's top so it never brushes the screen's edge or a capsule's.
    func hop(_ share: CGFloat) -> CGFloat {
        min(size * share, max(scale, baseline - size / 2 - ceiling - (hidden == nil ? 1 : 2) * scale))
    }

    /// Where it stands just out of sight behind the camera, `margin` points
    /// past the camera's edge on its side.
    func behindCamera(_ hidden: ClosedRange<CGFloat>, margin: CGFloat) -> CGFloat {
        hidden.lowerBound + size / 2 + margin * scale
    }

    /// The same track `scale` times larger, for the Settings preview, which
    /// shows the island bigger than it is. The companion is drawn with shapes,
    /// so it stays sharp at any size.
    func scaled(by scale: CGFloat) -> NotchMascotTrack {
        NotchMascotTrack(width: width * scale, height: height * scale, size: size * scale, rest: rest * scale,
                         hidden: hidden.map { ($0.lowerBound * scale)...($0.upperBound * scale) },
                         baseline: baseline * scale, ceiling: ceiling * scale, mirrored: mirrored,
                         scale: self.scale * scale)
    }

    /// The same track with its resting place on the camera's left.
    var leftSide: NotchMascotTrack {
        guard mirrored else { return self }
        var left = self
        left.mirrored = false
        left.rest = width - rest
        return left
    }

    /// Where it says hello across the strip: past the camera, as far from it
    /// as it rests, or toward a capsule's far end.
    var farSpot: CGFloat {
        guard let hidden else { return min(width - size * 0.8, rest + width * 0.22) }
        return hidden.upperBound + (hidden.lowerBound - rest)
    }
}

/// The companion's walk, sampled densely enough for Core Animation to play
/// as given: where it is, how high a hop lifts it, how much a landing
/// squashes it and where it looks.
struct NotchMascotPath: Equatable {
    var keyTimes: [Double] = []
    var x: [CGFloat] = []
    var lift: [CGFloat] = []
    /// Positive squashes it flat, negative stretches it tall.
    var squash: [CGFloat] = []
    /// Where its eyes look across, in shares of its size.
    var gaze: [CGFloat] = []
    var duration: TimeInterval = 0
    /// When its greeting face shows, in seconds from the start.
    var greeting: ClosedRange<TimeInterval> = 0...0
}

enum NotchMascotMotion {
    static let lapDuration: TimeInterval = 3.6
    static let passDuration: TimeInterval = 3.4
    static let homeDuration: TimeInterval = 0.62
    /// A cameo lands where it would rest this long after it starts, and its
    /// reaction plays from there.
    static let cameoArrival: TimeInterval = 0.5
    /// It is back behind the camera as its exit ends, so the visit ends there.
    static let cameoExit: TimeInterval = 0.32
    static let farewellDuration: TimeInterval = 0.78
    static let crossDuration: TimeInterval = 1.24
    /// The closed island crossfades an activity arriving out of the companion
    /// at rest, and one leaving back into it, over this long.
    static let restCrossfade: TimeInterval = 0.2

    static func duration(of kind: NotchMascotVisit.Kind) -> TimeInterval {
        switch kind {
        case .lap: return lapDuration
        case .pass: return passDuration
        case .home, .arrive: return homeDuration
        case .cameo(let reaction): return cameoArrival + cameoHold(reaction) + cameoExit
        case .linger(let reaction): return cameoHold(reaction) + cameoExit
        case .countdown(let total): return total + countdownLinger + cameoExit
        case .retreat: return cameoExit
        case .farewell: return farewellDuration
        case .cross: return crossDuration
        }
    }

    /// How long before a countdown runs out the companion comes to watch it.
    static let countdownLead: TimeInterval = 5
    /// It stays past the end for a beat, under the notice that takes over.
    static let countdownLinger: TimeInterval = 0.1

    /// How long a cameo stays where it landed: its reaction and a beat after it.
    static func cameoHold(_ reaction: NotchMascotReaction) -> TimeInterval { reaction.length + 0.3 }

    /// When a reaction's visit gives back what it covered, from its start.
    /// Beside a camera it is behind the camera before it is halfway home, so
    /// the strip starts back as it sets off. In a capsule it walks out past
    /// the end, which it passes a little before its walk is over, so what it
    /// covered starts back a quarter of the way out and is mostly there as
    /// it goes. Later, the island stood empty for a few frames. Nil for a
    /// visit that comes out for no reaction.
    static func handBack(of kind: NotchMascotVisit.Kind, floats: Bool) -> TimeInterval? {
        guard let reaction = kind.reaction else { return nil }
        let arrival = kind == .linger(reaction) ? 0 : cameoArrival
        return arrival + cameoHold(reaction) + (floats ? cameoExit / 4 : 0)
    }

    /// A stroll of `kind`. Resting right of the camera, it walks the left
    /// side's stroll seen in a mirror.
    static func path(for kind: NotchMascotVisit.Kind, on track: NotchMascotTrack) -> NotchMascotPath {
        // A countdown is watched from the camera's left, over the timer's
        // mark, whichever side it rests on: the reading is on the right.
        switch kind {
        case .countdown(let total): return countdown(on: track.leftSide, total: total)
        case .retreat: return retreat(on: track.leftSide)
        default: break
        }
        guard track.mirrored else {
            switch kind {
            case .lap: return lap(on: track)
            case .pass: return pass(on: track)
            case .home: return home(on: track)
            case .cameo(let reaction): return cameo(on: track, hold: cameoHold(reaction))
            case .linger(let reaction): return linger(on: track, hold: cameoHold(reaction))
            case .farewell: return farewell(on: track)
            case .cross: return cross(on: track)
            case .arrive: return arrive(on: track)
            case .countdown, .retreat: return NotchMascotPath()
            }
        }
        var left = track
        left.mirrored = false
        left.rest = track.width - track.rest
        var path = self.path(for: kind, on: left)
        path.x = path.x.map { track.width - $0 }
        path.gaze = path.gaze.map { -$0 }
        return path
    }

    private enum Step {
        case stay(TimeInterval, bounces: Int = 0)
        case hop(to: CGFloat, TimeInterval, height: CGFloat)
        case walk(to: CGFloat, TimeInterval)
        case jump(to: CGFloat)
    }

    /// From its resting place behind the camera to the other side, a hello,
    /// out at the far end and back in at the near one to rest again.
    static func lap(on track: NotchMascotTrack) -> NotchMascotPath {
        let size = track.size
        let offstageRight = track.width + size
        let offstageLeft = -size
        var steps: [Step] = [.stay(0.18)]
        if let hidden = track.hidden {
            steps += [.hop(to: track.behindCamera(hidden, margin: 2), 0.34, height: track.hop(0.24)),
                      .walk(to: hidden.upperBound - size / 2 - 2 * track.scale, 0.50),
                      .hop(to: track.farSpot, 0.34, height: track.hop(0.24))]
        } else {
            steps += [.hop(to: track.farSpot, 0.60, height: track.hop(0.3)), .stay(0.58)]
        }
        steps += [.stay(0.94, bounces: 2),
                  .walk(to: offstageRight, 0.40),
                  .jump(to: offstageLeft),
                  .hop(to: track.rest, 0.52, height: track.hop(0.26))]
        var path = sample(steps, start: track.rest, track: track, duration: lapDuration)
        let greetStart: TimeInterval = track.hidden == nil ? 0.78 : 1.30
        path.greeting = greetStart...(greetStart + 1.0)
        return path
    }

    /// In at the near end, a hello on that side, behind the camera, out at the far end.
    static func pass(on track: NotchMascotTrack) -> NotchMascotPath {
        let size = track.size
        var steps: [Step] = [.stay(0.20), .hop(to: track.rest, 0.42, height: track.hop(0.26)), .stay(0.88, bounces: 2)]
        if let hidden = track.hidden {
            steps += [.hop(to: track.behindCamera(hidden, margin: 2), 0.34, height: track.hop(0.24)),
                      .walk(to: hidden.upperBound - size / 2 - 2 * track.scale, 0.50),
                      .hop(to: track.farSpot, 0.34, height: track.hop(0.24)),
                      .stay(0.22)]
        } else {
            steps += [.hop(to: track.farSpot, 0.60, height: track.hop(0.3)), .stay(0.80)]
        }
        steps += [.walk(to: track.width + size, 0.40)]
        var path = sample(steps, start: -size, track: track, duration: passDuration)
        path.greeting = 0.55...1.55
        return path
    }

    /// Back from the drop that rose into the island behind the camera: out
    /// from behind it with a little hop to its place, still wearing the face
    /// it left the bar with until it lands. A capsule has no camera, so it
    /// lands where it rests.
    static func home(on track: NotchMascotTrack) -> NotchMascotPath {
        guard let hidden = track.hidden else {
            var path = sample([.stay(0.08), .hop(to: track.rest, 0.36, height: track.hop(0.2))],
                              start: track.rest, track: track, duration: homeDuration)
            path.greeting = 0...0.4
            return path
        }
        var path = sample([.stay(0.06), .hop(to: track.rest, 0.42, height: track.hop(0.2))],
                          start: track.behindCamera(hidden, margin: 2), track: track, duration: homeDuration)
        path.greeting = 0...0.44
        return path
    }

    /// Out from behind the camera to where it would rest, `hold` there for
    /// its reaction, and back behind the camera. A capsule has no camera, so
    /// it comes in at the near end and leaves at the far one.
    static func cameo(on track: NotchMascotTrack, hold: TimeInterval) -> NotchMascotPath {
        let size = track.size
        let duration = cameoArrival + hold + cameoExit
        guard let hidden = track.hidden else {
            return sample([.stay(0.06), .hop(to: track.rest, cameoArrival - 0.06, height: track.hop(0.3)), .stay(hold),
                           .walk(to: track.width + size, cameoExit)],
                          start: -size, track: track, duration: duration)
        }
        // Just out of sight, so it shows the moment it moves and is gone as it lands.
        let behind = track.behindCamera(hidden, margin: 1)
        return sample([.stay(0.06), .hop(to: track.rest, cameoArrival - 0.06, height: track.hop(0.2)), .stay(hold),
                       .hop(to: behind, cameoExit, height: track.hop(0.16))],
                      start: behind, track: track, duration: duration)
    }

    /// Where it rests, `hold` for its reaction, and then behind the camera
    /// as a cameo leaves, or out at a capsule's far end.
    static func linger(on track: NotchMascotTrack, hold: TimeInterval) -> NotchMascotPath {
        let duration = hold + cameoExit
        guard let hidden = track.hidden else {
            return sample([.stay(hold), .walk(to: track.width + track.size, cameoExit)],
                          start: track.rest, track: track, duration: duration)
        }
        return sample([.stay(hold), .hop(to: track.behindCamera(hidden, margin: 1), cameoExit, height: track.hop(0.16))],
                      start: track.rest, track: track, duration: duration)
    }

    /// The last `total` seconds of a countdown: out from behind the camera
    /// over the timer's mark, eyes on the reading, a small hop with every
    /// second that goes, and back behind the camera just after it runs out.
    static func countdown(on track: NotchMascotTrack, total: TimeInterval) -> NotchMascotPath {
        let size = track.size
        let duration = total + countdownLinger + cameoExit
        guard let hidden = track.hidden else {
            return sample([.stay(duration)], start: -size, track: track, duration: duration)
        }
        let behind = track.behindCamera(hidden, margin: 1)
        var steps: [Step] = [.stay(0.06), .hop(to: track.rest, cameoArrival - 0.06, height: track.hop(0.2))]
        var time = cameoArrival
        // The reading changes on every whole second left; it hops just as it does.
        let ticks = stride(from: total.rounded(.up) - 1, through: 1, by: -1)
            .map { total - $0 }
            .filter { $0 - 0.15 > time + 0.1 }
        for tick in ticks {
            steps.append(.stay(tick - 0.15 - time))
            steps.append(.hop(to: track.rest, 0.3, height: track.hop(0.1)))
            time = tick + 0.15
        }
        steps.append(.stay(max(0, total + countdownLinger - time)))
        steps.append(.hop(to: behind, cameoExit, height: track.hop(0.16)))
        var path = sample(steps, start: behind, track: track, duration: duration)
        // Its eyes stay on the reading while it watches.
        path.gaze = zip(path.keyTimes, path.gaze).map { keyTime, gaze in
            let time = keyTime * duration
            return time >= cameoArrival && time <= total + countdownLinger ? 0.07 : gaze
        }
        return path
    }

    /// Switched on: as it comes back from the Command Bar's drop beside a
    /// camera. A capsule has no camera to come out from, and no drop rose
    /// into it, so it hops in at the near end instead of appearing in place.
    static func arrive(on track: NotchMascotTrack) -> NotchMascotPath {
        guard track.hidden == nil else { return home(on: track) }
        var path = sample([.stay(0.06), .hop(to: track.rest, 0.46, height: track.hop(0.3))],
                          start: -track.size, track: track, duration: homeDuration)
        path.greeting = 0...0.52
        return path
    }

    /// To this side of the camera from the other: from where it rested
    /// there, into the camera's far edge, across behind it, and out with a
    /// wink to its place on this side. A capsule has no sides, so it only
    /// hops where it rests.
    static func cross(on track: NotchMascotTrack) -> NotchMascotPath {
        guard let hidden = track.hidden else { return home(on: track) }
        let size = track.size
        var path = sample([.stay(0.06),
                           .hop(to: hidden.upperBound - size / 2 - 2 * track.scale, 0.34, height: track.hop(0.24)),
                           .walk(to: track.behindCamera(hidden, margin: 2), 0.38),
                           .hop(to: track.rest, 0.36, height: track.hop(0.24)), .stay(0.1)],
                          start: track.farSpot, track: track, duration: crossDuration)
        path.greeting = 0.72...crossDuration
        return path
    }

    /// Switched off: a glad little hop where it rests, then away behind the
    /// camera, out of sight before the wings fold. A capsule has no camera,
    /// so it walks out past the far end.
    static func farewell(on track: NotchMascotTrack) -> NotchMascotPath {
        let size = track.size
        guard let hidden = track.hidden else {
            var path = sample([.stay(0.06), .hop(to: track.rest, 0.3, height: track.hop(0.22)), .stay(0.02),
                               .walk(to: track.width + size, 0.4)],
                              start: track.rest, track: track, duration: farewellDuration)
            path.greeting = 0...0.44
            return path
        }
        var path = sample([.stay(0.06), .hop(to: track.rest, 0.3, height: track.hop(0.22)), .stay(0.08),
                           .hop(to: track.behindCamera(hidden, margin: 1), cameoExit, height: track.hop(0.16))],
                          start: track.rest, track: track, duration: farewellDuration)
        path.greeting = 0...0.48
        return path
    }

    /// Back behind the camera from where it watched a countdown.
    static func retreat(on track: NotchMascotTrack) -> NotchMascotPath {
        guard let hidden = track.hidden else {
            return sample([.stay(cameoExit)], start: -track.size, track: track, duration: cameoExit)
        }
        return sample([.hop(to: track.behindCamera(hidden, margin: 1), cameoExit, height: track.hop(0.16))],
                      start: track.rest, track: track, duration: cameoExit)
    }

    private static func sample(_ steps: [Step], start: CGFloat, track: NotchMascotTrack,
                               duration: TimeInterval) -> NotchMascotPath {
        let rate: Double = 60
        var path = NotchMascotPath()
        var time: TimeInterval = 0
        var position = start
        // A landing's squash eases out over the start of the next step.
        var landing: (squash: CGFloat, time: TimeInterval) = (0, 0)
        func add(_ x: CGFloat, lift: CGFloat, squash: CGFloat, gaze: CGFloat) {
            let recovery = landing.squash * CGFloat(max(0, 1 - (time - landing.time) / 0.14))
            path.keyTimes.append(min(1, time / duration))
            path.x.append(x)
            path.lift.append(lift)
            path.squash.append(squash != 0 ? squash : recovery)
            path.gaze.append(gaze)
        }
        add(position, lift: 0, squash: 0, gaze: 0)
        for step in steps {
            switch step {
            case .jump(let target):
                // Off stage at both ends, and in no time: two frames at the
                // same moment, so no frame ever draws it on the way across.
                position = target
                add(position, lift: 0, squash: 0, gaze: 0.05)
            case .stay(let length, let bounces):
                let frames = max(1, Int((length * rate).rounded()))
                for frame in 1...frames {
                    let share = CGFloat(frame) / CGFloat(frames)
                    time += length / Double(frames)
                    let wave = bounces > 0 ? abs(sin(share * .pi * CGFloat(bounces))) : 0
                    add(position, lift: wave * track.hop(0.16), squash: 0, gaze: 0)
                }
            case .hop(let target, let length, let height):
                let from = position
                let frames = max(2, Int((length * rate).rounded()))
                let direction: CGFloat = target >= from ? 1 : -1
                for frame in 1...frames {
                    let share = CGFloat(frame) / CGFloat(frames)
                    time += length / Double(frames)
                    // Eased along the ground, a parabola above it.
                    let eased = share * share * (3 - 2 * share)
                    let squash: CGFloat = share < 0.2 ? -0.12 * (1 - share / 0.2) : share > 0.88 ? 0.14 * (share - 0.88) / 0.12 : 0
                    add(from + (target - from) * eased, lift: height * 4 * share * (1 - share),
                        squash: squash, gaze: 0.05 * direction)
                }
                position = target
                landing = (0.14, time)
            case .walk(let target, let length):
                let from = position
                let frames = max(2, Int((length * rate).rounded()))
                let direction: CGFloat = target >= from ? 1 : -1
                for frame in 1...frames {
                    let share = CGFloat(frame) / CGFloat(frames)
                    time += length / Double(frames)
                    // Little steps: a small bob on each.
                    let bob = abs(sin(share * .pi * 3)) * track.hop(0.06)
                    add(from + (target - from) * share, lift: bob, squash: 0, gaze: 0.05 * direction)
                }
                position = target
            }
        }
        // The last step lands, and it stays for whatever time is left.
        if time < duration {
            time = duration
            add(position, lift: 0, squash: 0, gaze: 0)
        } else if let last = path.keyTimes.indices.last {
            path.keyTimes[last] = 1
        }
        path.duration = duration
        return path
    }
}

enum NotchMascotSupport {
    /// Turned on in Settings, the companion says hello almost at once.
    static let welcomeDelay: TimeInterval = 1.5
    /// Music starting brings it out to bob along at most this often, so
    /// pressing play again and again does not keep calling it out.
    static let grooveInterval: TimeInterval = 600
    /// It waits this long after the music starts, until the song's strip has
    /// settled, before it comes out over it.
    static let grooveDelay: TimeInterval = 1.2
    /// An AI agent getting to work where it rests has it hand the island over
    /// with a ready face at most this often, since agents start many turns.
    static let agentStartInterval: TimeInterval = 600

    /// Hiding when idle, it goes into the island this long after it last did
    /// anything, before it would doze off where it rests, even late at night.
    static let hideDelay: TimeInterval = 30
    /// Busy just then, or under the pointer, it tries again this much later.
    static let hideRetry: TimeInterval = 3
    /// How it goes into the island to hide: a yawn where it rests, then in
    /// behind the camera, or out at a capsule's far end.
    static let hideAway = NotchMascotVisit.Kind.linger(.yawn)

    /// How it takes a countdown running out: startled by a plain timer's
    /// ring, glad at the end of a focus session, and ready to go again when
    /// a break is over.
    static func timerReaction(finishing phase: NotchTimerPhase) -> NotchMascotReaction {
        switch phase {
        case .focus: return .celebrate
        case .shortBreak, .longBreak: return .ready
        case .timer, .stopwatch: return .surprised
        }
    }

    /// How it takes the Mac's power changing: glad when the charger goes in,
    /// cheering once the battery is full, and tired when it runs low.
    static func powerReaction(pluggedIn: Bool, charged: Bool, low: Bool) -> NotchMascotReaction? {
        pluggedIn ? .love : charged ? .celebrate : low ? .yawn : nil
    }

    /// Whether the event the island counted down to, as `before`, began as
    /// the countdown became `after` at `now`: it perks up then. Only just
    /// begun, so a Mac that slept through the start, or an event moved or
    /// removed before it, is no news.
    static func eventBegan(from before: NotchCalendarCountdown?, to after: NotchCalendarCountdown?,
                           at now: Date) -> Bool {
        guard let before, !before.ongoing else { return false }
        let since = now.timeIntervalSince(before.event.start)
        // Its refresh may come a second early.
        guard since >= -2, since < 60 else { return false }
        guard let after else { return true }
        return after.event.id != before.event.id || after.ongoing
    }
    static let greetings: [NotchMascotMood] = [.happy, .wink, .love]

    /// A blink comes this long after the previous one, twice as long in Low
    /// Power Mode, where it blinks less.
    static func blinkInterval(lowPower: Bool) -> ClosedRange<TimeInterval> {
        lowPower ? 5.2...12.8 : 2.6...6.4
    }

    /// The share of blinks at rest its eyes wander to one side before:
    /// about once in twenty seconds, enough to look about without fidgeting.
    static let glanceChance = 0.25

    /// After this many blinks at rest its eyes grow heavy: about three minutes
    /// by day, under a minute late at night.
    static func blinksBeforeSleep(hour: Int) -> Int {
        hour >= 22 || hour < 6 ? 12 : 36
    }

    /// Installed on the Features page, switched on, and in an island that is on.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.notchMascot.isAvailable(in: defaults) && NotchSupport.isEnabled(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchMascotEnabled)
    }

    static func visits(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchMascotVisits)
    }

    /// Whether it comes out to react to what the island sees, and watches a
    /// countdown run out.
    static func reacts(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchMascotReactions)
    }

    /// Whether it hides in the island once nothing has happened for a
    /// while, and comes out only to visit or to react.
    static func hidesWhenIdle(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchMascotHidesWhenIdle)
    }

    static func visitFrequency(in defaults: UserDefaults = .standard) -> NotchMascotVisitFrequency {
        NotchMascotVisitFrequency(rawValue: defaults.string(forKey: DefaultsKey.notchMascotVisitFrequency) ?? "") ?? .normal
    }

    static func side(in defaults: UserDefaults = .standard) -> NotchMascotSide {
        NotchMascotSide(rawValue: defaults.string(forKey: DefaultsKey.notchMascotSide) ?? "") ?? .left
    }

    static func look(in defaults: UserDefaults = .standard) -> NotchMascotLook {
        NotchMascotLook(
            style: NotchMascotStyle(rawValue: defaults.string(forKey: DefaultsKey.notchMascotStyle) ?? "") ?? .minimal,
            shape: NotchMascotShape(rawValue: defaults.string(forKey: DefaultsKey.notchMascotShape) ?? "") ?? .ball,
            palette: NotchMascotPalette(rawValue: defaults.string(forKey: DefaultsKey.notchMascotPalette) ?? "") ?? .pearl)
    }

    /// How the Command Bar comes out of the island, or nil when it opens in
    /// its own window as it always has.
    static func commandBarStyle(in defaults: UserDefaults = .standard) -> NotchCommandBarStyle? {
        guard isEnabled(in: defaults), AppFeature.commandBar.isAvailable(in: defaults),
              defaults.bool(forKey: DefaultsKey.notchCommandBar) else { return nil }
        return NotchCommandBarStyle(rawValue: defaults.string(forKey: DefaultsKey.notchCommandBarStyle) ?? "") ?? .droplet
    }

    /// What the bar's face shows for what is typed. Results get a hop of
    /// their own on arrival, and afterward the eyes simply stay open on them.
    static func commandBarMood(query: String, hasResults: Bool, searching: Bool) -> NotchMascotMood {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .idle }
        if searching { return .thinking }
        return hasResults ? .idle : .confused
    }

    /// Whether the face's change is worth a little celebration: results
    /// turning up after a wait, or after nothing matched. The first letters
    /// typed find something every time, so that is no news.
    static func celebrates(from old: NotchMascotMood, to new: NotchMascotMood, query: String,
                           hasResults: Bool) -> Bool {
        (old == .thinking || old == .confused) && new == .idle && hasResults
            && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Where its eyes go while something is typed: along the text beside
    /// it, a little further as the text grows. Nil when the field is empty.
    static func readingGaze(for query: String) -> CGPoint? {
        guard !query.isEmpty else { return nil }
        return CGPoint(x: 0.07 + 0.04 * min(1, CGFloat(query.count) / 28), y: 0.01)
    }

    /// Where its eyes go for a pointer at `pointer`, with its center at
    /// `center`: toward it, more the farther it is, within its face.
    static func pointerGaze(from center: CGPoint, to pointer: CGPoint, size: CGFloat) -> CGPoint {
        guard size > 0 else { return .zero }
        let dx = (pointer.x - center.x) / (size * 3), dy = (pointer.y - center.y) / (size * 2)
        return CGPoint(x: max(-1, min(1, dx)) * 0.08, y: max(-1, min(1, dy)) * 0.05)
    }

    /// Visits come every few minutes, never on a fixed beat.
    static func nextVisitDelay(_ frequency: NotchMascotVisitFrequency = visitFrequency(),
                               random: Double = Double.random(in: 0...1)) -> TimeInterval {
        let range = frequency.delay
        return range.lowerBound + (range.upperBound - range.lowerBound) * min(1, max(0, random))
    }

    static func greeting(random: Double = Double.random(in: 0..<1)) -> NotchMascotMood {
        greetings[min(greetings.count - 1, max(0, Int(random * Double(greetings.count))))]
    }

    /// The companion's square in a closed strip of `height`, with or without
    /// a capsule's margins around its body.
    static func size(stripHeight: CGFloat, floats: Bool) -> CGFloat {
        floats ? max(10, min(18, stripHeight - 6)) : max(12, min(20, stripHeight - 12))
    }

    /// Where it rests in a strip with a camera: inside a wing, a little way
    /// from the camera, so it sits beside it and never under it. A capsule
    /// has no camera, so it rests in the middle whatever the side.
    static func track(stripWidth: CGFloat, stripHeight: CGFloat, wing: CGFloat,
                      cameraWidth: CGFloat, floats: Bool, bodyHeight: CGFloat,
                      side: NotchMascotSide = .left) -> NotchMascotTrack {
        if floats {
            let size = self.size(stripHeight: bodyHeight, floats: true)
            return NotchMascotTrack(width: stripWidth, height: stripHeight, size: size, rest: stripWidth / 2,
                                    hidden: nil, baseline: stripHeight / 2,
                                    ceiling: max(0, (stripHeight - bodyHeight) / 2))
        }
        let size = self.size(stripHeight: stripHeight, floats: false)
        let gap = max(4, min(8, wing - size - 6))
        let rest = max(size / 2, wing - gap - size / 2)
        return NotchMascotTrack(width: stripWidth, height: stripHeight, size: size,
                                rest: side == .right ? stripWidth - rest : rest,
                                hidden: wing...(wing + cameraWidth), baseline: stripHeight / 2 + 0.5,
                                mirrored: side == .right)
    }

    /// Room a wing keeps beyond the companion for it to come out in, so it
    /// stays clear of the strip's rounded end.
    static let wingRoom: CGFloat = 10

    /// Its size in a notice it stands in, in place of the notice's symbol.
    static let noticeSize: CGFloat = 18

    /// What the open island's top row gives it beside the camera: the gap it
    /// keeps from the camera at rest, itself, and air before the title or the
    /// actions on that side.
    static func residentLane(stripHeight: CGFloat) -> CGFloat {
        8 + size(stripHeight: stripHeight, floats: false) + 6
    }

    /// Where it comes out over an activity's closed strip of `size`, drawn
    /// with `strip`: through a capsule, or in the wing on its side of the
    /// camera. Nil when that wing has no room for it, as when the menus
    /// leave none and the activity hangs below the camera instead.
    static func track(overActivity strip: NotchGeometry, size: CGSize,
                      side: NotchMascotSide = .left) -> NotchMascotTrack? {
        if strip.floats {
            return track(stripWidth: size.width, stripHeight: strip.stripHeight, wing: 0, cameraWidth: 0,
                         floats: true, bodyHeight: strip.stripBodyHeight)
        }
        guard !strip.compactActivityUsesFooter else { return nil }
        let wing = strip.compactActivityWingWidth
        guard wing >= self.size(stripHeight: strip.stripHeight, floats: false) + wingRoom else { return nil }
        return track(stripWidth: strip.compactActivitySize.width, stripHeight: strip.stripHeight, wing: wing,
                     cameraWidth: strip.compactActivityCameraGap, floats: false, bodyHeight: strip.stripBodyHeight,
                     side: side)
    }
}
