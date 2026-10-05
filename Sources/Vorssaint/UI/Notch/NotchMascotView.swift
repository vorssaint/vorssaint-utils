// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore
import SwiftUI

extension Notification.Name {
    /// A file is being dragged toward the island while it shows where to drop it.
    static let notchMascotDragMoved = Notification.Name("NotchMascotDragMoved")
    /// The pointer moved over the open island, or left it.
    static let notchMascotPointerMoved = Notification.Name("NotchMascotPointerMoved")
    static let notchMascotPointerLeft = Notification.Name("NotchMascotPointerLeft")
    /// An activity takes the place of the companion resting in the closed island.
    static let notchMascotRestYields = Notification.Name("NotchMascotRestYields")
}

/// A one-off motion the companion plays over its face.
enum NotchMascotCue: Equatable {
    /// Results turned up: a hop with smiling eyes.
    case celebrate
    /// The eyes dart about, searching.
    case glance
    /// Something was typed: the eyes go to it for a moment, in shares of
    /// its size, then come back. Nil looks ahead again at once.
    case look(CGPoint?)
}

/// The companion, drawn with shape layers. Every motion is a Core Animation
/// animation: the app says where it goes once and the render server draws
/// the way there, with no timer or redraw in the app. Even the blinks chain
/// through Core Animation, each one starting from the end of the last.
/// `root` is its square, and its parent must lay out from the top, as a
/// flipped view does.
final class NotchMascotRig: NSObject {
    let root = CALayer()
    private(set) var look = NotchMascotLook.standard
    private(set) var size: CGFloat = 0
    private(set) var mood = NotchMascotMood.idle
    /// Whether it blinks now and then and, after a long rest, grows sleepy.
    private(set) var idles = false
    var reduceMotion = false

    private let hopper = CALayer()
    private let squasher = CALayer()
    private let tilter = CALayer()
    /// Where the eyes are drawn to beyond the face it keeps: the text being
    /// typed, or the pointer over the island.
    private let attention = CALayer()
    private let ears = CAShapeLayer()
    private let antenna = CAShapeLayer()
    private let bulb = CAShapeLayer()
    private let fill = CAGradientLayer()
    private let fillMask = CAShapeLayer()
    private let visor = CAShapeLayer()
    private let shine = CAShapeLayer()
    private let face = CALayer()
    private let leftEye = CAShapeLayer()
    private let rightEye = CAShapeLayer()
    private var blinks = 0
    /// It grew sleepy on its own after a long rest, rather than being shown
    /// so, and anything that happens wakes it.
    private var dozed = false
    /// When its eyes last went after something: a pointer, a drag or typing.
    private var attended: CFTimeInterval = -.infinity
    /// When the visit it plays is over, on the media clock.
    private var visitEnds: CFTimeInterval = 0
    private var blinkRelay: NotchMascotAnimationRelay?
    /// Blinks wait until a visit has gone by.
    private var blinksResume: CFTimeInterval = 0
    private var configured = false

    override init() {
        super.init()
        root.addSublayer(hopper)
        hopper.addSublayer(squasher)
        squasher.addSublayer(tilter)
        for layer in [ears, antenna, bulb, fill, visor, shine] { tilter.addSublayer(layer) }
        tilter.addSublayer(attention)
        attention.addSublayer(face)
        face.addSublayer(leftEye)
        face.addSublayer(rightEye)
        fill.mask = fillMask
        for layer in [root, hopper, squasher, tilter, attention, face, ears, antenna, bulb, fill, fillMask, visor, shine,
                      leftEye, rightEye] {
            layer.actions = Self.noActions
        }
        shine.fillColor = NotchMascotColor.shine.cgColor
        visor.fillColor = NotchMascotColor.visor.cgColor
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "path": NSNull(),
        "opacity": NSNull(), "hidden": NSNull(), "contents": NSNull(), "colors": NSNull(),
        "fillColor": NSNull(), "frame": NSNull(), "sublayers": NSNull(), "shadowColor": NSNull(),
        "shadowOpacity": NSNull(),
    ]

    // MARK: Look

    /// Draws the companion at `size` points with `look`. Nothing moves, and a
    /// new look at the same size cross-fades in, as a choice in Settings does.
    func configure(look: NotchMascotLook, size: CGFloat, contentsScale scale: CGFloat) {
        guard !configured || look != self.look || size != self.size || scale != root.contentsScale else { return }
        let restyled = configured && look != self.look && size == self.size && !reduceMotion
        configured = true
        self.look = look
        self.size = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if restyled {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.24
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            tilter.add(fade, forKey: "look")
        }
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        root.bounds = box
        for layer in [hopper, squasher, tilter, attention, face, ears, antenna, bulb, fill, fillMask, visor, shine] {
            layer.frame = box
            layer.contentsScale = scale
        }
        root.contentsScale = scale
        let robot = look.style == .robot
        let palette = look.palette
        fill.colors = [palette.light.cgColor, palette.shade.cgColor]
        fill.startPoint = CGPoint(x: 0.5, y: 0)
        fill.endPoint = CGPoint(x: 0.5, y: 1)
        if robot {
            let parts = NotchMascotGeometry.robot(size: size)
            fillMask.path = parts.head
            ears.path = parts.ears
            antenna.path = parts.antenna
            bulb.path = parts.bulb
            visor.path = parts.visor
            ears.fillColor = palette.shade.cgColor
            antenna.fillColor = palette.shade.cgColor
            bulb.fillColor = (mood == .sleepy ? palette.shade : palette.light).cgColor
            bulb.shadowColor = palette.light.cgColor
            bulb.shadowRadius = max(0.8, size * 0.09)
            bulb.shadowOffset = .zero
            for eye in [leftEye, rightEye] {
                eye.fillColor = palette.light.cgColor
                eye.shadowColor = palette.light.cgColor
                eye.shadowOpacity = 0.9
                eye.shadowRadius = max(0.6, size * 0.04)
                eye.shadowOffset = .zero
            }
        } else {
            fillMask.path = NotchMascotGeometry.body(look.shape, size: size)
            for eye in [leftEye, rightEye] {
                eye.fillColor = NotchMascotColor.ink.cgColor
                eye.shadowOpacity = 0
            }
        }
        for layer in [ears, antenna, bulb, visor] { layer.isHidden = !robot }
        shine.path = NotchMascotGeometry.shine(look.face, size: size)
        shine.isHidden = robot
        let face = look.face
        let side = size * 0.4
        leftEye.frame = CGRect(x: face.leftEye.x * size - side / 2, y: face.leftEye.y * size - side / 2, width: side, height: side)
        rightEye.frame = CGRect(x: face.rightEye.x * size - side / 2, y: face.rightEye.y * size - side / 2, width: side, height: side)
        leftEye.contentsScale = scale
        rightEye.contentsScale = scale
        apply(mood.expression, animated: false)
    }

    // MARK: Faces

    func setMood(_ mood: NotchMascotMood, animated: Bool) {
        guard mood != self.mood else { return }
        let previous = self.mood
        self.mood = mood
        dozed = false
        if mood != .sleepy { blinks = 0 }
        apply(mood.expression, animated: animated && !reduceMotion)
        lightBulb(mood != .sleepy, animated: animated && !reduceMotion)
        guard animated, !reduceMotion, size > 0 else { syncBlinking(); return }
        switch mood {
        case .surprised: pop()
        case .confused: wobble()
        case .love: heartbeat()
        case .idle where previous == .sleepy: pop()
        default: break
        }
        syncBlinking()
    }

    private func eyePath(_ eye: NotchMascotEye, right: Bool) -> CGPath {
        let face = look.face
        let side = size * 0.4
        return NotchMascotGeometry.eye(eye, size: CGSize(width: face.eyeSize.width * size, height: face.eyeSize.height * size),
                                       center: CGPoint(x: side / 2, y: side / 2), right: right)
    }

    private func gazeTransform(_ gaze: CGPoint) -> CATransform3D {
        CATransform3DMakeTranslation(gaze.x * size, gaze.y * size, 0)
    }

    private func apply(_ expression: NotchMascotExpression, animated: Bool) {
        guard size > 0 else { return }
        let left = eyePath(expression.left, right: false)
        let right = eyePath(expression.right, right: true)
        let gaze = gazeTransform(expression.gaze)
        let tilt = CATransform3DMakeRotation(expression.tilt, 0, 0, 1)
        if animated {
            for (layer, path) in [(leftEye, left), (rightEye, right)] {
                let morph = CABasicAnimation(keyPath: "path")
                morph.fromValue = layer.presentation()?.path ?? layer.path
                morph.toValue = path
                morph.duration = 0.22
                morph.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)
                layer.add(morph, forKey: "morph")
            }
            let glance = CASpringAnimation(keyPath: "transform")
            glance.fromValue = face.presentation()?.transform ?? face.transform
            glance.toValue = gaze
            glance.damping = 16
            glance.stiffness = 260
            glance.duration = glance.settlingDuration
            face.add(glance, forKey: "gaze")
            let lean = CASpringAnimation(keyPath: "transform")
            lean.fromValue = tilter.presentation()?.transform ?? tilter.transform
            lean.toValue = tilt
            lean.damping = 12
            lean.stiffness = 200
            lean.duration = lean.settlingDuration
            tilter.add(lean, forKey: "tilt")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leftEye.path = left
        rightEye.path = right
        face.transform = gaze
        tilter.transform = tilt
        CATransaction.commit()
    }

    /// Turns to `mood` at `time` on the media clock and keeps it there, for
    /// a face set ahead of a moment, such as a drop landing. The face it
    /// keeps on its own stays as it was.
    func turn(to mood: NotchMascotMood, at time: CFTimeInterval) {
        guard size > 0 else { return }
        let from = self.mood.expression, to = mood.expression
        for (layer, eyes, right) in [(leftEye, (from.left, to.left), false), (rightEye, (from.right, to.right), true)] {
            let morph = CABasicAnimation(keyPath: "path")
            morph.fromValue = eyePath(eyes.0, right: right)
            morph.toValue = eyePath(eyes.1, right: right)
            morph.beginTime = time
            morph.duration = reduceMotion ? 0.01 : 0.22
            morph.fillMode = .both
            morph.isRemovedOnCompletion = false
            layer.add(morph, forKey: "turn")
        }
        for (layer, from, to) in [(face, gazeTransform(from.gaze), gazeTransform(to.gaze)),
                                  (tilter, CATransform3DMakeRotation(from.tilt, 0, 0, 1),
                                   CATransform3DMakeRotation(to.tilt, 0, 0, 1))] {
            let move = CABasicAnimation(keyPath: "transform")
            move.fromValue = NSValue(caTransform3D: from)
            move.toValue = NSValue(caTransform3D: to)
            move.beginTime = time
            move.duration = reduceMotion ? 0.01 : 0.22
            move.fillMode = .both
            move.isRemovedOnCompletion = false
            layer.add(move, forKey: "turn")
        }
    }

    /// Back to its own face at rest, with every motion taken off.
    func reset(to mood: NotchMascotMood) {
        stopBlinking()
        for layer in [root, hopper, squasher, tilter, attention, face, leftEye, rightEye] { layer.removeAllAnimations() }
        attention.transform = CATransform3DIdentity
        self.mood = mood
        blinks = 0
        dozed = false
        apply(mood.expression, animated: false)
    }

    // MARK: Attention

    /// Whether a stroll is moving it, with eyes for the way ahead.
    var isVisiting: Bool { root.animation(forKey: "visit") != nil && CACurrentMediaTime() < visitEnds }

    /// Whether a visit under way has it standing at `stand` just now, where
    /// ending the visit leaves it without a jump.
    func stands(at stand: CGPoint) -> Bool {
        guard let position = root.presentation()?.position else { return false }
        return abs(position.x - stand.x) < 0.5 && abs(position.y - stand.y) < 0.5
    }

    /// Ends a visit under way where it stands, and it blinks again.
    func endVisit() {
        for layer in [root, squasher, face] { layer.removeAnimation(forKey: "visit") }
        root.removeAnimation(forKey: "visitFade")
        blinksResume = CACurrentMediaTime()
        stopBlinking()
        syncBlinking()
    }

    /// Lets go of the last frame a visit that ended out of sight held, once
    /// the island has nothing more for it.
    func clearFinishedVisit() {
        guard root.animation(forKey: "visit") != nil, CACurrentMediaTime() >= visitEnds else { return }
        for layer in [root, squasher, face] { layer.removeAnimation(forKey: "visit") }
        root.removeAnimation(forKey: "visitFade")
    }
    /// It grew sleepy on its own after a long rest.
    var isDozing: Bool { dozed }

    /// Turns its eyes toward `target`, in shares of its size, on top of the
    /// face it keeps. With `hold`, they stay that long and come back, so
    /// keys typed in a row keep them there. Without it, they stay. Each turn
    /// starts where the eyes are, never where the last one meant to go.
    func attend(to target: CGPoint, hold: TimeInterval? = nil) {
        guard size > 0, !reduceMotion else { return }
        attended = CACurrentMediaTime()
        let from = attention.presentation()?.transform ?? attention.transform
        let to = CATransform3DMakeTranslation(target.x * size, target.y * size, 0)
        let look = CAKeyframeAnimation(keyPath: "transform")
        let settle = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)
        if let hold {
            let move = 0.16, back = 0.34
            let total = move + max(0, hold) + back
            look.values = [from, to, to, CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
            look.keyTimes = [0, move / total, (total - back) / total, 1].map { NSNumber(value: $0) }
            look.timingFunctions = [settle, CAMediaTimingFunction(name: .linear),
                                    CAMediaTimingFunction(name: .easeInEaseOut)]
            look.duration = total
        } else {
            look.values = [from, to].map { NSValue(caTransform3D: $0) }
            look.timingFunction = settle
            look.duration = 0.2
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        attention.transform = hold == nil ? to : CATransform3DIdentity
        attention.add(look, forKey: "attention")
        CATransaction.commit()
    }

    /// Its eyes come back to the face it keeps, after `delay`.
    func lookAhead(after delay: TimeInterval = 0) {
        guard size > 0 else { return }
        let from = attention.presentation()?.transform ?? attention.transform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        attention.transform = CATransform3DIdentity
        if !reduceMotion, !CATransform3DIsIdentity(from) {
            let back = CAKeyframeAnimation(keyPath: "transform")
            let total = max(0, delay) + 0.34
            back.values = [from, from, CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
            back.keyTimes = [0, NSNumber(value: max(0, delay) / total), 1]
            back.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeInEaseOut)]
            back.duration = total
            attention.add(back, forKey: "attention")
        } else {
            attention.removeAnimation(forKey: "attention")
        }
        CATransaction.commit()
    }

    // MARK: Cues

    func play(_ cue: NotchMascotCue) {
        guard size > 0, !reduceMotion else {
            if cue == .celebrate, reduceMotion { flashFace(.happy, duration: 1) }
            return
        }
        switch cue {
        case .celebrate:
            hop(height: size * 0.28)
            flashFace(.happy, duration: 1)
        case .glance:
            let dart = CAKeyframeAnimation(keyPath: "transform.translation.x")
            dart.values = [0, size * 0.07, -size * 0.06, 0]
            dart.keyTimes = [0, 0.3, 0.7, 1]
            dart.duration = 0.42
            dart.isAdditive = true
            dart.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            face.add(dart, forKey: "glance")
        case .look(let target):
            if let target { attend(to: target, hold: 0.9) } else { lookAhead() }
        }
    }

    private func hop(height: CGFloat) {
        let lift = CAKeyframeAnimation(keyPath: "transform.translation.y")
        lift.values = [0, -height, 0, -height * 0.3, 0]
        lift.keyTimes = [0, 0.32, 0.6, 0.78, 1]
        lift.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn),
                                CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        lift.duration = 0.62
        lift.isAdditive = true
        hopper.add(lift, forKey: "hop")
        let squash = CAKeyframeAnimation(keyPath: "transform")
        squash.values = [squashed(0), squashed(-0.12), squashed(0), squashed(0.14), squashed(0), squashed(0.06), squashed(0)]
            .map { NSValue(caTransform3D: $0) }
        squash.keyTimes = [0, 0.12, 0.3, 0.62, 0.72, 0.84, 1]
        squash.duration = 0.62
        squasher.add(squash, forKey: "squash")
    }

    /// The robot's antenna bulb goes dark while it sleeps and lights again as
    /// it wakes.
    private func lightBulb(_ lit: Bool, animated: Bool) {
        guard look.style == .robot else { return }
        let color = (lit ? look.palette.light : look.palette.shade).cgColor
        if animated {
            let fade = CABasicAnimation(keyPath: "fillColor")
            fade.fromValue = bulb.presentation()?.fillColor ?? bulb.fillColor
            fade.toValue = color
            fade.duration = lit ? 0.25 : 0.6
            bulb.add(fade, forKey: "light")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bulb.fillColor = color
        CATransaction.commit()
    }

    /// Lit already, the bulb shows dark a moment longer, then lights.
    private func relightBulb(after delay: TimeInterval) {
        guard look.style == .robot else { return }
        let dark = look.palette.shade.cgColor
        let light = CAKeyframeAnimation(keyPath: "fillColor")
        light.values = [dark, dark, look.palette.light.cgColor]
        light.keyTimes = [0, NSNumber(value: delay / (delay + 0.3)), 1]
        light.duration = delay + 0.3
        bulb.add(light, forKey: "light")
    }

    /// A reaction lights the robot's bulb up with a soft glow for as long as it plays.
    private func glowBulb(for duration: TimeInterval) {
        guard look.style == .robot else { return }
        let glow = CAKeyframeAnimation(keyPath: "shadowOpacity")
        glow.values = [0, 1, 1, 0]
        glow.keyTimes = [0, 0.12, 0.7, 1]
        glow.duration = duration
        bulb.add(glow, forKey: "glow")
    }

    /// Positive flattens it on the ground, negative stretches it up, and its
    /// bottom stays where it was.
    private func squashed(_ amount: CGFloat) -> CATransform3D {
        let scaleX = 1 + amount * 0.8, scaleY = 1 - amount
        let bottom = size * 0.42
        return CATransform3DConcat(CATransform3DMakeScale(scaleX, scaleY, 1),
                                   CATransform3DMakeTranslation(0, bottom * (1 - scaleY), 0))
    }

    private func pop() {
        let pop = CAKeyframeAnimation(keyPath: "transform")
        pop.values = [squashed(0), squashed(-0.14), squashed(0.06), squashed(0)].map { NSValue(caTransform3D: $0) }
        pop.keyTimes = [0, 0.35, 0.7, 1]
        pop.duration = 0.34
        squasher.add(pop, forKey: "pop")
    }

    private func wobble() {
        let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        shake.values = [0, 0.12, -0.1, 0.06, 0]
        shake.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        shake.duration = 0.5
        shake.isAdditive = true
        tilter.add(shake, forKey: "wobble")
    }

    private func heartbeat(beginTime: CFTimeInterval? = nil) {
        for eye in [leftEye, rightEye] {
            let beat = CAKeyframeAnimation(keyPath: "transform.scale")
            beat.values = [1, 1.3, 1, 1.22, 1]
            beat.keyTimes = [0, 0.2, 0.45, 0.65, 1]
            beat.duration = 0.7
            if let beginTime { beat.beginTime = beginTime }
            eye.add(beat, forKey: "heartbeat")
        }
    }

    /// A slow stretch up and back, as a yawn or waking up.
    private func stretch(beginTime: CFTimeInterval, duration: TimeInterval) {
        let stretch = CAKeyframeAnimation(keyPath: "transform")
        stretch.values = [squashed(0), squashed(-0.12), squashed(-0.12), squashed(0.05), squashed(0)]
            .map { NSValue(caTransform3D: $0) }
        stretch.keyTimes = [0, 0.35, 0.6, 0.82, 1]
        stretch.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .linear),
                                   CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .easeOut)]
        stretch.beginTime = beginTime
        stretch.duration = duration
        squasher.add(stretch, forKey: "stretch")
    }

    // MARK: Reactions

    /// A short reaction to something the island saw happen, over the face it
    /// keeps. `lift` is how high a hop may take it where it stands. With
    /// Reduce Motion it only changes face.
    func react(_ reaction: NotchMascotReaction, lift: CGFloat) {
        guard size > 0 else { return }
        // Whatever it is, it wakes up for it.
        if dozed, reaction != .wakeUp { setMood(.idle, animated: !reduceMotion) }
        blinks = 0
        let now = CACurrentMediaTime()
        glowBulb(for: reaction.length)
        guard !reduceMotion else {
            switch reaction {
            case .celebrate, .wakeUp: flashFace(.happy, duration: 1)
            case .love: flashFace(.love, duration: 1.2)
            case .surprised, .flash: flashFace(.surprised, duration: 0.8)
            case .confused: flashFace(.confused, duration: 1.1)
            case .yawn, .hush: flashFace(.sleepy, duration: 1.1)
            case .perk, .bounce: flashFace(.alert, duration: 1)
            case .ready: flashFace(.determined, duration: 1)
            case .groove: flashFace(.happy, duration: 1.4)
            }
            return
        }
        switch reaction {
        case .celebrate:
            hop(height: lift)
            flashFace(.happy, duration: 1)
        case .love:
            flashFace(.love, duration: 1.4)
            heartbeat(beginTime: now + 0.22)
        case .surprised:
            flashFace(.surprised, duration: 0.9)
            hop(height: lift * 0.7)
        case .flash:
            // Squeezed shut, then wide open, as a camera's flash goes off.
            let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
            blink.values = [1, 0.06, 0.06, 1.18, 1]
            blink.keyTimes = [0, 0.18, 0.42, 0.7, 1]
            blink.duration = 0.45
            for eye in [leftEye, rightEye] { eye.add(blink, forKey: "flashBlink") }
            pop()
            pauseBlinking(for: 0.5, from: nil)
        case .confused:
            flashFace(.confused, duration: 1.2)
            wobble()
        case .wakeUp:
            // Heavy eyes, a stretch, and a glad face. A robot's bulb lights
            // up again as it stretches.
            if dozed {
                setMood(.idle, animated: false)
                relightBulb(after: 0.35)
            }
            flashFace(.sleepy, duration: 0.7)
            stretch(beginTime: now + 0.35, duration: 0.6)
            flashFace(.happy, duration: 0.9, beginTime: now + 0.7, key: "flashAfter")
        case .yawn:
            flashFace(.sleepy, duration: 1.2)
            stretch(beginTime: now + 0.1, duration: 0.9)
        case .perk:
            flashFace(.alert, duration: 1)
            hop(height: lift * 0.55)
        case .bounce:
            // Time to go: two quick hops, the second lower, and a small
            // rebound, squashing as it lands and stretching to leave again.
            flashFace(.alert, duration: reaction.length)
            let height = max(1, lift * 0.6)
            let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bounce.values = [0, -height, 0, -height * 0.7, 0, -height * 0.15, 0]
            bounce.keyTimes = [0, 0.14, 0.32, 0.46, 0.63, 0.75, 0.88]
            bounce.timingFunctions = (0..<6).map { CAMediaTimingFunction(name: $0 % 2 == 0 ? .easeOut : .easeIn) }
            bounce.duration = 0.95
            bounce.isAdditive = true
            hopper.add(bounce, forKey: "hop")
            let squash = CAKeyframeAnimation(keyPath: "transform")
            squash.values = [squashed(0), squashed(-0.12), squashed(0), squashed(0.14), squashed(-0.1), squashed(0),
                             squashed(0.12), squashed(0), squashed(0.04), squashed(0)]
                .map { NSValue(caTransform3D: $0) }
            squash.keyTimes = [0, 0.04, 0.14, 0.32, 0.36, 0.46, 0.63, 0.7, 0.8, 0.88]
            squash.duration = 0.95
            squasher.add(squash, forKey: "squash")
        case .hush:
            // Eyes shut for a moment as it ducks, then back.
            let shut = CAKeyframeAnimation(keyPath: "transform.scale.y")
            shut.values = [1, 0.1, 0.1, 1]
            shut.keyTimes = [0, 0.22, 0.78, 1]
            shut.duration = 0.95
            for eye in [leftEye, rightEye] { eye.add(shut, forKey: "hush") }
            let duck = CAKeyframeAnimation(keyPath: "transform")
            duck.values = [squashed(0), squashed(0.1), squashed(0.1), squashed(-0.03), squashed(0)]
                .map { NSValue(caTransform3D: $0) }
            duck.keyTimes = [0, 0.25, 0.7, 0.88, 1]
            duck.duration = 0.95
            squasher.add(duck, forKey: "duck")
            pauseBlinking(for: 1, from: nil)
        case .ready:
            flashFace(.determined, duration: 1)
            // A nod: down a little, up past where it was, and settled.
            let nod = CAKeyframeAnimation(keyPath: "transform")
            nod.values = [squashed(0), squashed(0.1), squashed(-0.06), squashed(0)].map { NSValue(caTransform3D: $0) }
            nod.keyTimes = [0, 0.3, 0.65, 1]
            nod.duration = 0.5
            nod.beginTime = now + 0.12
            squasher.add(nod, forKey: "nod")
        case .groove:
            // It hears the music: smiling eyes, a bob on every beat and a
            // lean one way and the other, landing a little squashed.
            flashFace(.happy, duration: reaction.length)
            let beats = 4
            let height = max(1, lift * 0.45)
            var heights: [CGFloat] = [], leans: [CGFloat] = [], squashes: [CATransform3D] = []
            var times: [NSNumber] = []
            for step in 0...(beats * 2) {
                times.append(NSNumber(value: Double(step) / Double(beats * 2)))
                let up = step % 2 == 1
                heights.append(up ? -height : 0)
                leans.append(up ? (step % 4 == 1 ? 0.11 : -0.11) : 0)
                squashes.append(squashed(up ? -0.05 : step == 0 || step == beats * 2 ? 0 : 0.07))
            }
            let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
            bob.values = heights
            bob.keyTimes = times
            bob.timingFunctions = (0..<(beats * 2)).map {
                CAMediaTimingFunction(name: $0 % 2 == 0 ? .easeOut : .easeIn)
            }
            bob.duration = reaction.length
            bob.isAdditive = true
            hopper.add(bob, forKey: "hop")
            let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            sway.values = leans
            sway.keyTimes = times
            sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sway.duration = reaction.length
            sway.isAdditive = true
            tilter.add(sway, forKey: "wobble")
            let land = CAKeyframeAnimation(keyPath: "transform")
            land.values = squashes.map { NSValue(caTransform3D: $0) }
            land.keyTimes = times
            land.duration = reaction.length
            squasher.add(land, forKey: "squash")
        }
    }

    /// Shows another face for a moment and comes back to its own, without
    /// changing the face it keeps.
    private func flashFace(_ mood: NotchMascotMood, duration: TimeInterval, beginTime: CFTimeInterval? = nil,
                           key: String = "flash") {
        let expression = mood.expression
        let own = self.mood.expression
        for (layer, eye, base, right) in [(leftEye, expression.left, own.left, false), (rightEye, expression.right, own.right, true)] {
            let face = CAKeyframeAnimation(keyPath: "path")
            let back = eyePath(base, right: right), to = eyePath(eye, right: right)
            // One shown now leaves from the eyes on screen, heavy from a doze
            // or shut mid-blink, rather than from its own face for a frame.
            let from = beginTime == nil ? layer.presentation()?.path ?? back : back
            face.values = [from, to, to, back]
            face.keyTimes = [0, 0.15, 0.85, 1]
            face.duration = duration
            if let beginTime { face.beginTime = beginTime }
            if reduceMotion { face.calculationMode = .discrete }
            layer.add(face, forKey: key)
        }
        pauseBlinking(for: duration, from: beginTime)
    }

    // MARK: Visits

    /// Plays a stroll that began at `start` on the media clock, from where it
    /// should be now. `baseline` is the height of its center in its parent.
    /// With Reduce Motion it does not walk, and greets at `stand` instead.
    /// `holdsEnd` keeps it where the visit ends, out of sight, until what
    /// comes next takes over: the timer that ends a visit can fire a frame
    /// late, and it stood in its place for that frame.
    func playVisit(_ path: NotchMascotPath, greeting: NotchMascotMood, baseline: CGFloat, stand: CGPoint,
                   start: CFTimeInterval, holdsEnd: Bool = false) {
        guard size > 0, path.duration > 0, path.x.count == path.keyTimes.count else { return }
        let now = CACurrentMediaTime()
        // One that already ended out of sight still holds its last frame
        // for a strip drawn after it, until the island moves on.
        guard now < start + path.duration || (holdsEnd && !reduceMotion) else { return }
        visitEnds = start + path.duration
        if reduceMotion {
            // No stroll: it fades in where it would greet, says hello and fades out.
            let still = CAKeyframeAnimation(keyPath: "position")
            still.values = [NSValue(point: stand), NSValue(point: stand)]
            still.duration = path.duration
            still.beginTime = start
            root.add(still, forKey: "visit")
            if root.position != stand {
                // Staying on from where it stood, as to react over an
                // activity, it only fades out at the end.
                let inPlace = abs((path.x.first ?? .infinity) - stand.x) < 0.5
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [inPlace ? 1 : 0, 1, 1, 0]
                fade.keyTimes = [0, 0.12, 0.88, 1]
                fade.duration = path.duration
                fade.beginTime = start
                root.add(fade, forKey: "visitFade")
            }
            if path.greeting.upperBound > path.greeting.lowerBound {
                flashFace(greeting, duration: path.greeting.upperBound - path.greeting.lowerBound,
                          beginTime: start + path.greeting.lowerBound)
            }
            return
        }
        let walk = CAKeyframeAnimation(keyPath: "position")
        walk.values = zip(path.x, path.lift).map { NSValue(point: CGPoint(x: $0, y: baseline - $1)) }
        walk.keyTimes = path.keyTimes.map { NSNumber(value: $0) }
        walk.duration = path.duration
        walk.beginTime = start
        walk.calculationMode = .linear
        if holdsEnd {
            walk.fillMode = .forwards
            walk.isRemovedOnCompletion = false
        }
        root.add(walk, forKey: "visit")
        let squash = CAKeyframeAnimation(keyPath: "transform")
        squash.values = path.squash.map { NSValue(caTransform3D: squashed($0)) }
        squash.keyTimes = walk.keyTimes
        squash.duration = path.duration
        squash.beginTime = start
        squasher.add(squash, forKey: "visit")
        let look = CAKeyframeAnimation(keyPath: "transform.translation.x")
        look.values = path.gaze.map { $0 * size }
        look.keyTimes = walk.keyTimes
        look.duration = path.duration
        look.beginTime = start
        look.isAdditive = true
        face.add(look, forKey: "visit")
        // Its eyes are for the way ahead while it walks.
        lookAhead()
        if path.greeting.upperBound > path.greeting.lowerBound {
            flashFace(greeting, duration: path.greeting.upperBound - path.greeting.lowerBound,
                      beginTime: start + path.greeting.lowerBound)
        }
        // No blink while it walks, as the face it shows is the greeting's.
        pauseBlinking(for: start + path.duration - now, from: nil)
    }

    // MARK: Blinking

    /// Blinks wait while the layer is out of sight, and `visible` resumes them.
    func setIdles(_ idles: Bool, visible: Bool) {
        let wanted = idles && visible
        guard wanted != self.idles else { return }
        self.idles = wanted
        if !wanted {
            stopBlinking()
            if dozed, !idles { setMood(.idle, animated: false) }
        } else { syncBlinking() }
    }

    /// Wakes it from a long rest. A face shown sleepy on purpose stays.
    func wake(animated: Bool) {
        blinks = 0
        if dozed { setMood(.idle, animated: animated) }
    }

    private func syncBlinking() {
        guard idles, mood.expression.blinks, size > 0 else { stopBlinking(); return }
        guard leftEye.animation(forKey: "blink") == nil else { return }
        scheduleBlink()
    }

    private func stopBlinking() {
        blinkRelay?.target = nil
        blinkRelay = nil
        leftEye.removeAnimation(forKey: "blink")
        rightEye.removeAnimation(forKey: "blink")
        // A glance on its way goes with the blink it led to; one under way
        // finishes, so the eyes never jump.
        if let glance = attention.animation(forKey: "idleGlance"), glance.beginTime > CACurrentMediaTime() {
            attention.removeAnimation(forKey: "idleGlance")
        }
    }

    private func pauseBlinking(for duration: TimeInterval, from begin: CFTimeInterval?) {
        let end = (begin ?? CACurrentMediaTime()) + max(0, duration)
        blinksResume = max(blinksResume, end)
        guard idles else { return }
        stopBlinking()
        syncBlinking()
    }

    /// One blink, a few seconds from now. It starts the next one when it ends,
    /// so blinking costs a short animation every few seconds and nothing in between.
    private func scheduleBlink() {
        let now = CACurrentMediaTime()
        let interval = NotchMascotSupport.blinkInterval(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        let delay = max(0, blinksResume - now) + Double.random(in: interval)
        let twice = Double.random(in: 0...1) < 0.18
        let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
        blink.values = twice ? [1, 0.1, 1, 1, 0.1, 1] : [1, 0.1, 1]
        blink.keyTimes = twice ? [0, 0.2, 0.4, 0.58, 0.78, 1] : [0, 0.45, 1]
        blink.duration = twice ? 0.44 : 0.17
        blink.beginTime = now + delay
        // Reduce Motion: the eyes close and open without a motion between.
        if reduceMotion { blink.calculationMode = .discrete }
        // Now and then its eyes wander to one side, and the blink comes as
        // they find their way back, as eyes do. Not while they follow
        // something, which would pull them apart.
        if !twice, !reduceMotion, now - attended > 3, Double.random(in: 0...1) < NotchMascotSupport.glanceChance {
            let away = CATransform3DMakeTranslation((Bool.random() ? 1 : -1) * size * 0.12, 0, 0)
            let glance = CAKeyframeAnimation(keyPath: "transform")
            glance.values = [CATransform3DIdentity, away, away, CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
            glance.keyTimes = [0, 0.2, 0.8, 1]
            glance.timingFunctions = [CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1),
                                      CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeInEaseOut)]
            glance.duration = 1.3
            // On top of wherever the eyes look, so nothing else is undone.
            glance.isAdditive = true
            glance.beginTime = blink.beginTime - 1.1
            attention.add(glance, forKey: "idleGlance")
        }
        let relay = NotchMascotAnimationRelay(target: self)
        blinkRelay = relay
        blink.delegate = relay
        leftEye.add(blink, forKey: "blink")
        let pair = blink.copy() as? CAKeyframeAnimation ?? blink
        pair.delegate = nil
        rightEye.add(pair, forKey: "blink")
    }

    fileprivate func blinkDidStop(finished: Bool, relay: NotchMascotAnimationRelay) {
        guard finished, relay === blinkRelay, idles else { return }
        blinkRelay = nil
        blinks += 1
        // A long rest makes its eyes heavy, and it stops blinking then.
        if mood == .idle, blinks >= NotchMascotSupport.blinksBeforeSleep(hour: Calendar.current.component(.hour, from: Date())) {
            setMood(.sleepy, animated: true)
            dozed = true
            return
        }
        syncBlinking()
    }
}

/// Core Animation keeps its delegate alive. This one keeps only a weak
/// reference, so a companion taken off screen is let go even with a blink pending.
private final class NotchMascotAnimationRelay: NSObject, CAAnimationDelegate {
    weak var target: NotchMascotRig?

    init(target: NotchMascotRig) { self.target = target }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        target?.blinkDidStop(finished: flag, relay: self)
    }
}

/// Holds the companion in a view. It draws only through its layers and never
/// takes a click: what it stands on decides what a click does.
final class NotchMascotHostView: NSView {
    let mascot = NotchMascotRig()
    private let stage = CALayer()
    private let visibilityMask = CAShapeLayer()
    private var visibilityObserver: NSObjectProtocol?
    private var idlesWhenVisible = false
    private var playedVisit: UUID?
    private var lastCueID = 0
    /// The face last asked for. Asked again, it changes nothing: a companion
    /// grown sleepy on its own stays so until something new happens.
    private var requestedMood: NotchMascotMood?
    /// Where it stands, its center, or nil for the middle of the view, and
    /// where it can be seen, nil everywhere. Kept for when the view is resized.
    private var placement: (center: CGPoint?, visible: [CGRect]?) = (nil, nil)
    /// A resting companion's eyes follow the pointer over the island, and
    /// the pointer wakes it from a long rest.
    var followsPointer = false {
        didSet {
            guard followsPointer != oldValue else { return }
            updateTrackingAreas()
            if !followsPointer { mascot.lookAhead() }
        }
    }
    private var pointerArea: NSTrackingArea?
    private var playedReaction: UUID?
    /// A fresh reaction for a strip not yet in its window.
    private var waitingReaction: (event: NotchMascotReactionEvent, lift: CGFloat)?
    /// The pointer resting on it for a moment is a pat on the head.
    private var pettingWork: DispatchWorkItem?
    private var lastPetting: CFTimeInterval = 0
    /// A cameo's reaction, waiting for it to land.
    private var cameoWork: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        root.isGeometryFlipped = true
        root.masksToBounds = false
        layer = root
        wantsLayer = true
        stage.actions = ["position": NSNull(), "bounds": NSNull(), "mask": NSNull()]
        root.addSublayer(stage)
        stage.addSublayer(mascot.root)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        if let dragObserver { NotificationCenter.default.removeObserver(dragObserver) }
        islandObservers.forEach(NotificationCenter.default.removeObserver)
        if let yieldObserver { NotificationCenter.default.removeObserver(yieldObserver) }
        cameoWork?.cancel()
    }

    /// In the island's drop hint, its eyes follow a file dragged anywhere on screen.
    var followsDrag = false {
        didSet {
            guard followsDrag != oldValue else { return }
            if let dragObserver { NotificationCenter.default.removeObserver(dragObserver) }
            dragObserver = followsDrag
                ? NotificationCenter.default.addObserver(forName: .notchMascotDragMoved, object: nil, queue: .main) {
                    [weak self] _ in self?.followDrag()
                }
                : nil
        }
    }
    private var dragObserver: NSObjectProtocol?

    private func followDrag() {
        guard let window else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        mascot.attend(to: NotchMascotSupport.pointerGaze(from: mascot.root.position, to: point, size: mascot.size))
    }

    /// Beside the camera in the open island, its eyes follow the pointer
    /// anywhere over the island, not only over the row it stands in, and the
    /// pointer coming back wakes it.
    var followsIsland = false {
        didSet {
            guard followsIsland != oldValue else { return }
            islandObservers.forEach(NotificationCenter.default.removeObserver)
            islandObservers = !followsIsland ? [] : [
                NotificationCenter.default.addObserver(forName: .notchMascotPointerMoved, object: nil, queue: .main) {
                    [weak self] _ in self?.followIslandPointer()
                },
                NotificationCenter.default.addObserver(forName: .notchMascotPointerLeft, object: nil, queue: .main) {
                    [weak self] _ in self?.mascot.lookAhead(after: 0.25)
                },
            ]
        }
    }
    private var islandObservers: [NSObjectProtocol] = []

    /// Resting in the closed island, it fades out in the first half of the
    /// crossfade an arriving activity brings, and the strip comes in over the
    /// second. SwiftUI fades a hosted view out over the whole crossfade
    /// whatever its transition says, which left it half seen over the text.
    var yieldsToActivities = false {
        didSet {
            guard yieldsToActivities != oldValue else { return }
            if let yieldObserver { NotificationCenter.default.removeObserver(yieldObserver) }
            yieldObserver = yieldsToActivities
                ? NotificationCenter.default.addObserver(forName: .notchMascotRestYields, object: nil, queue: .main) {
                    [weak self] _ in self?.yieldToActivity()
                }
                : nil
        }
    }
    private var yieldObserver: NSObjectProtocol?

    private func yieldToActivity() {
        guard window != nil, let root = layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = NotchMascotMotion.restCrossfade / 2
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        root.add(fade, forKey: "yield")
        // The view is gone once the crossfade is over. One still on screen
        // after it comes back.
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMascotMotion.restCrossfade * 2) { [weak self] in
            self?.layer?.removeAnimation(forKey: "yield")
        }
    }

    private func followIslandPointer() {
        guard followsPointer, !mascot.isVisiting, let window else { return }
        greetPointer()
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        mascot.attend(to: NotchMascotSupport.pointerGaze(from: mascot.root.position, to: point, size: mascot.size))
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                self?.syncIdling()
            }
        }
        syncIdling()
        if window != nil, let waiting = waitingReaction {
            waitingReaction = nil
            playReaction(waiting.event, lift: waiting.lift)
        }
    }

    override func viewDidHide() { super.viewDidHide(); syncIdling() }
    override func viewDidUnhide() { super.viewDidUnhide(); syncIdling() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        pointerArea = nil
        guard followsPointer else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard followsPointer else { return }
        greetPointer()
        follow(event)
    }

    /// The pointer coming back wakes it, with a stretch from a doze.
    private func greetPointer() {
        if mascot.isDozing, !mascot.isVisiting { mascot.react(.wakeUp, lift: 0) } else { mascot.wake(animated: true) }
    }

    override func mouseMoved(with event: NSEvent) {
        guard followsPointer else { return }
        follow(event)
        notePetting(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard followsPointer else { return }
        pettingWork?.cancel(); pettingWork = nil
        mascot.lookAhead(after: 0.25)
    }

    /// A second of the pointer resting on it brings out the hearts, at most
    /// once in a while. One work item waits per pat, nothing ticks.
    private func notePetting(at point: CGPoint) {
        let center = mascot.root.position
        let reach = mascot.size / 2 + 3
        guard abs(point.x - center.x) <= reach, abs(point.y - center.y) <= reach, !mascot.isVisiting else {
            pettingWork?.cancel(); pettingWork = nil
            return
        }
        guard pettingWork == nil,
              CACurrentMediaTime() - lastPetting > NotchMascotReactionGate.repeatInterval else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pettingWork = nil
            self.lastPetting = CACurrentMediaTime()
            self.mascot.react(.love, lift: 0)
            // A soft tick under a finger on the trackpad, as the hearts come.
            if NotchSupport.usesHapticFeedback() {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        }
        pettingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Plays a reaction the island published, once, and only while it is
    /// fresh: a strip drawn after its moment, as the island closes, keeps still.
    func react(_ event: NotchMascotReactionEvent?, lift: CGFloat) {
        guard let event, event.id != playedReaction else { return }
        playedReaction = event.id
        guard window != nil else { waitingReaction = (event, lift); return }
        playReaction(event, lift: lift)
    }

    private func playReaction(_ event: NotchMascotReactionEvent, lift: CGFloat) {
        guard CACurrentMediaTime() - event.start < 1.5, !mascot.isVisiting else { return }
        mascot.react(event.reaction, lift: lift)
    }

    /// Moves come only while the pointer moves over it: nothing runs while
    /// it rests, and each look is one short animation from where the eyes are.
    private func follow(_ event: NSEvent) {
        guard !mascot.isVisiting else { return }
        let point = convert(event.locationInWindow, from: nil)
        mascot.attend(to: NotchMascotSupport.pointerGaze(from: mascot.root.position, to: point, size: mascot.size))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        mascot.configure(look: mascot.look, size: mascot.size, contentsScale: backingScale)
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    private var isOnScreen: Bool {
        !isHiddenOrHasHiddenAncestor && window?.isVisible == true
            && window?.occlusionState.contains(.visible) == true
    }

    private func syncIdling() {
        mascot.setIdles(idlesWhenVisible, visible: isOnScreen)
    }

    func configure(look: NotchMascotLook, size: CGFloat, mood: NotchMascotMood, idles: Bool,
                   reduceMotion: Bool, animated: Bool) {
        mascot.reduceMotion = reduceMotion
        mascot.configure(look: look, size: size, contentsScale: backingScale)
        if mood != requestedMood {
            requestedMood = mood
            mascot.setMood(mood, animated: animated && window != nil)
        }
        idlesWhenVisible = idles
        syncIdling()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyPlacement()
    }

    /// Grows or shrinks it about the middle of this view, as from one size
    /// of it to another.
    func scale(from start: CGFloat, to end: CGFloat, duration: CFTimeInterval,
               timing: CAMediaTimingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.removeAnimation(forKey: "scale")
        stage.transform = CATransform3DMakeScale(end, end, 1)
        if duration > 0, start != end, !mascot.reduceMotion {
            let grow = CABasicAnimation(keyPath: "transform")
            grow.fromValue = NSValue(caTransform3D: CATransform3DMakeScale(start, start, 1))
            grow.toValue = NSValue(caTransform3D: CATransform3DMakeScale(end, end, 1))
            grow.duration = duration
            grow.timingFunction = timing
            stage.add(grow, forKey: "scale")
        }
        CATransaction.commit()
    }

    /// Where it stands, its center in this view or nil for the middle, and
    /// where it can be seen: nil everywhere, or only inside `visible`.
    func place(at center: CGPoint?, visible: [CGRect]?) {
        placement = (center, visible)
        applyPlacement()
    }

    private func applyPlacement() {
        let center = placement.center ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let visible = placement.visible
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Bounds and position rather than a frame, which a scaled stage has none of.
        stage.bounds = CGRect(origin: .zero, size: bounds.size)
        stage.position = CGPoint(x: bounds.midX, y: bounds.midY)
        if mascot.root.position != center { mascot.root.position = center }
        if let visible {
            let path = CGMutablePath()
            visible.forEach { path.addRect($0) }
            visibilityMask.path = path
            if stage.mask !== visibilityMask { stage.mask = visibilityMask }
        } else if stage.mask != nil {
            stage.mask = nil
        }
        CATransaction.commit()
    }

    func play(_ cue: NotchMascotCue, id: Int) {
        guard id != lastCueID else { return }
        lastCueID = id
        guard window != nil else { return }
        mascot.play(cue)
    }

    /// Plays `visit` once. A cameo's reaction plays as it lands, `lift`
    /// being how high a hop may take it there.
    func playVisit(_ visit: NotchMascotVisit?, path: @autoclosure () -> NotchMascotPath, baseline: CGFloat,
                   stand: CGPoint, lift: CGFloat) {
        guard let visit else {
            // Ended early while it stands in its place, as when what it
            // reacted over went away: it stays there rather than leave.
            if mascot.isVisiting, mascot.stands(at: stand) { mascot.endVisit() }
            else if !mascot.isVisiting { mascot.clearFinishedVisit() }
            return
        }
        guard visit.id != playedVisit else { return }
        playedVisit = visit.id
        cameoWork?.cancel(); cameoWork = nil
        mascot.wake(animated: false)
        mascot.playVisit(path(), greeting: visit.greeting, baseline: baseline, stand: stand, start: visit.start,
                         holdsEnd: visit.kind.endsOutOfSight)
        guard let reaction = visit.kind.reaction else { return }
        // A strip drawn again after it landed picks the visit up there, and
        // does not play the reaction late. Lingering, it is already there.
        let arrival = visit.kind == .linger(reaction) ? 0 : NotchMascotMotion.cameoArrival
        let wait = visit.start + arrival - CACurrentMediaTime()
        guard wait > -0.2 else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.cameoWork = nil
            self?.mascot.react(reaction, lift: lift)
        }
        cameoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, wait), execute: work)
    }
}

/// The companion on its own, centred in its frame: the Command Bar's face
/// and the Settings preview.
struct NotchMascotView: NSViewRepresentable {
    var look: NotchMascotLook
    var mood: NotchMascotMood = .idle
    var size: CGFloat
    var idles = true
    /// A one-off motion, played whenever `cueID` changes.
    var cue: NotchMascotCue? = nil
    var cueID = 0
    /// Its eyes follow a file being dragged toward the island.
    var followsDrag = false
    /// A reaction it plays once, as it first shows: a notice's.
    var reaction: NotchMascotReaction? = nil

    func makeNSView(context: Context) -> NotchMascotHostView {
        let view = NotchMascotHostView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        view.followsDrag = followsDrag
        view.configure(look: look, size: size, mood: mood, idles: idles,
                       reduceMotion: context.environment.accessibilityReduceMotion, animated: false)
        if let reaction {
            // Small in a notice, it hops a little higher for its size to read.
            view.react(NotchMascotReactionEvent(id: UUID(), reaction: reaction, start: CACurrentMediaTime()),
                       lift: size * 0.32)
        }
        return view
    }

    func updateNSView(_ view: NotchMascotHostView, context: Context) {
        view.configure(look: look, size: size, mood: mood, idles: idles,
                       reduceMotion: context.environment.accessibilityReduceMotion, animated: true)
        view.place(at: nil, visible: nil)
        if let cue { view.play(cue, id: cueID) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchMascotHostView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? size, height: proposal.height ?? size)
    }
}

/// The companion in a closed strip: resting beside the camera, or strolling
/// through on a visit. It is hidden behind the camera as it passes.
struct NotchMascotTrackView: NSViewRepresentable {
    var look: NotchMascotLook
    var track: NotchMascotTrack
    /// Whether it stands at its resting place, or only comes for the visit.
    var rests: Bool
    var visit: NotchMascotVisit?
    /// The face it keeps at rest: wide awake while Keep Awake holds the Mac up.
    var mood: NotchMascotMood = .idle
    var reaction: NotchMascotReactionEvent?
    /// Switched off, the Settings preview shows it asleep: eyes shut, no
    /// blinking, and no eyes for the pointer.
    var awake = true
    /// Its eyes follow the pointer over the whole open island.
    var followsIsland = false
    /// It rests in the closed island and fades out early as an activity takes its place.
    var yieldsToActivities = false

    func makeNSView(context: Context) -> NotchMascotHostView {
        NotchMascotHostView(frame: CGRect(x: 0, y: 0, width: track.width, height: track.height))
    }

    func updateNSView(_ view: NotchMascotHostView, context: Context) {
        view.configure(look: look, size: track.size, mood: awake ? mood : .sleepy, idles: rests && awake,
                       reduceMotion: context.environment.accessibilityReduceMotion, animated: true)
        // Off stage at the far end once a visit is over, so nothing jumps
        // when its last frame hands back to where it stands.
        let x = rests ? track.rest : track.mirrored ? -track.size * 2 : track.width + track.size * 2
        var visible: [CGRect]?
        if let hidden = track.hidden {
            visible = [CGRect(x: -track.size * 3, y: -track.height, width: hidden.lowerBound + track.size * 3,
                              height: track.height * 3),
                       CGRect(x: hidden.upperBound, y: -track.height, width: track.width - hidden.upperBound + track.size * 3,
                              height: track.height * 3)]
        }
        view.place(at: CGPoint(x: x, y: track.baseline), visible: visible)
        view.followsPointer = rests && awake
        view.followsIsland = followsIsland && rests && awake
        view.yieldsToActivities = yieldsToActivities
        // A countdown is watched from the camera's left whatever the side.
        let stand = visit?.kind.watchesTimer == true ? track.leftSide.rest : track.rest
        view.playVisit(visit, path: NotchMascotMotion.path(for: visit?.kind ?? .pass, on: track),
                       baseline: track.baseline, stand: CGPoint(x: stand, y: track.baseline),
                       lift: track.hop(0.22))
        if rests { view.react(reaction, lift: track.hop(0.22)) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchMascotHostView, context: Context) -> CGSize? {
        CGSize(width: track.width, height: track.height)
    }
}

/// The companion over an activity's closed strip, which steps aside while
/// it visits or comes out to react. `track` is nil when the strip has no
/// room for it.
struct NotchMascotActivityVisit: ViewModifier {
    @ObservedObject var service: NotchService
    let track: NotchMascotTrack?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // A lap or a homecoming ends where it rests, which an activity's
        // strip has no place for, so only what ends out of sight comes over it.
        let visit = track == nil ? nil : service.mascotVisit.flatMap { $0.kind.endsOutOfSight ? $0 : nil }
        // Reacting or watching a countdown beside a camera, it covers only
        // the wing it stands in, as the black of the closed island, and the
        // other side stays in view. A capsule has no wings, so what it shows
        // steps aside instead.
        let hidden = track?.hidden
        let ownWing = visit?.kind.takesOnlyItsWing == true && hidden != nil
        let stepsAside = visit != nil && service.mascotStepsAside && !ownWing
        // A countdown is watched from the camera's left whatever the side.
        let rightWing = track?.mirrored == true && visit?.kind.watchesTimer == false
        content
            .opacity(stepsAside ? 0 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: stepsAside)
            .overlay(alignment: .topLeading) {
                // Handed back with the strip, halfway home, so what it covered
                // returns as it goes behind the camera.
                if ownWing, service.mascotStepsAside, let track, let hidden {
                    Color.black
                        .frame(width: rightWing ? track.width - hidden.upperBound : hidden.lowerBound,
                               height: track.height)
                        .offset(x: rightWing ? hidden.upperBound : 0)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: ownWing && service.mascotStepsAside)
            .overlay(alignment: .top) {
                if let track, let visit {
                    NotchMascotTrackView(look: NotchMascotSupport.look(), track: track, rests: false, visit: visit,
                                         mood: service.mascotRestingMood)
                        .frame(width: track.width, height: track.height)
                        .allowsHitTesting(false)
                }
            }
    }
}
