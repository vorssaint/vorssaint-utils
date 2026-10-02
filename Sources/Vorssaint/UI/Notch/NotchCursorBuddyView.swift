// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore
import SwiftUI

/// Drawn mascot. Motion is a layer animation that stops when the window is
/// hidden, occluded, or Reduce Motion is on. There is no timer.
final class NotchCursorBuddyLayerView: NSView {
    private let body = CAShapeLayer()
    private let leftEye = CAShapeLayer()
    private let rightEye = CAShapeLayer()
    private let leftPupil = CAShapeLayer()
    private let rightPupil = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let dots = (0..<3).map { _ in CAShapeLayer() }
    private var pose = CursorBuddyPose.idle
    private var animatedPose: CursorBuddyPose?
    private var animates = false
    private var gaze = CGPoint.zero
    private var visibilityObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for layer in [body, leftEye, rightEye, leftPupil, rightPupil, ring] + dots {
            self.layer?.addSublayer(layer)
        }
        ring.fillColor = nil
        ring.lineWidth = 1.5
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(pose: CursorBuddyPose, tint: NSColor, animates: Bool, gaze: CGPoint) {
        self.pose = pose
        self.animates = animates
        self.gaze = gaze
        applyColors(tint)
        layoutShapes()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                self?.layoutShapes()
            }
        }
        layoutShapes()
    }

    override func layout() {
        super.layout()
        layoutShapes()
    }

    override func viewDidHide() { super.viewDidHide(); layoutShapes() }
    override func viewDidUnhide() { super.viewDidUnhide(); layoutShapes() }

    private var moving: Bool {
        animates && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
    }

    private func applyColors(_ tint: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.fillColor = tint.withAlphaComponent(0.9).cgColor
        leftEye.fillColor = NSColor.white.cgColor
        rightEye.fillColor = NSColor.white.cgColor
        leftPupil.fillColor = NSColor.black.cgColor
        rightPupil.fillColor = NSColor.black.cgColor
        ring.strokeColor = tint.cgColor
        for dot in dots { dot.fillColor = tint.cgColor }
        CATransaction.commit()
    }

    private func layoutShapes() {
        let side = min(bounds.width, bounds.height)
        guard side > 0 else { return }
        let origin = CGPoint(x: bounds.midX - side / 2, y: bounds.midY - side / 2)
        let frame = CGRect(origin: origin, size: CGSize(width: side, height: side))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        body.frame = frame
        body.path = CGPath(ellipseIn: CGRect(x: side * 0.12, y: side * 0.08, width: side * 0.76, height: side * 0.76), transform: nil)
        placeEye(leftEye, pupil: leftPupil, x: 0.28, side: side, origin: origin)
        placeEye(rightEye, pupil: rightPupil, x: 0.56, side: side, origin: origin)
        ring.frame = frame
        ring.path = CGPath(ellipseIn: CGRect(x: side * 0.04, y: side * 0.04, width: side * 0.92, height: side * 0.92), transform: nil)
        ring.opacity = 1
        ring.isHidden = pose != .running && pose != .done && pose != .waiting
        let showDots = pose == .thinking
        for (index, dot) in dots.enumerated() {
            let dotSide = side * 0.1
            dot.isHidden = !showDots
            dot.frame = CGRect(x: origin.x + side * (0.3 + CGFloat(index) * 0.18),
                               y: origin.y + side * 0.82, width: dotSide, height: dotSide)
            dot.path = CGPath(ellipseIn: CGRect(origin: .zero, size: CGSize(width: dotSide, height: dotSide)), transform: nil)
        }
        applyMotion()
    }

    private func placeEye(_ eye: CAShapeLayer, pupil: CAShapeLayer, x: CGFloat, side: CGFloat, origin: CGPoint) {
        let eyeSize = CGSize(width: side * 0.16, height: pose == .quiet ? side * 0.05 : side * (pose == .waiting ? 0.2 : 0.16))
        let eyeOrigin = CGPoint(x: origin.x + side * x, y: origin.y + side * (pose == .thinking ? 0.48 : 0.4))
        eye.frame = CGRect(origin: eyeOrigin, size: eyeSize)
        eye.path = CGPath(ellipseIn: CGRect(origin: .zero, size: eyeSize), transform: nil)
        let pupilSide = side * 0.06
        let look = moving || pose == .idle ? gaze : .zero
        let lift: CGFloat = pose == .thinking ? side * 0.05 : 0
        let pupilOrigin = CGPoint(x: eyeOrigin.x + eyeSize.width * 0.3 + look.x * side * 0.03,
                                  y: eyeOrigin.y + eyeSize.height * 0.3 - look.y * side * 0.03 + lift)
        pupil.frame = CGRect(origin: pupilOrigin, size: CGSize(width: pupilSide, height: pupilSide))
        pupil.path = CGPath(ellipseIn: CGRect(origin: .zero, size: CGSize(width: pupilSide, height: pupilSide)), transform: nil)
    }

    private func applyMotion() {
        let key = "cursor.buddy"
        let blinkKey = "cursor.blink"
        let layers = [body, leftEye, rightEye, leftPupil, rightPupil, ring] + dots
        if !moving || animatedPose != pose {
            layers.forEach {
                $0.removeAnimation(forKey: key)
                $0.removeAnimation(forKey: blinkKey)
            }
            animatedPose = moving ? pose : nil
        }
        guard moving else { return }
        switch pose {
        case .idle:
            breathe(body, key: key, amount: 1.04, once: false)
            blink(leftEye, key: blinkKey)
            blink(rightEye, key: blinkKey)
        case .wave:
            breathe(body, key: key, amount: 1.08, once: true)
        case .thinking:
            body.removeAnimation(forKey: key)
            for (index, dot) in dots.enumerated() {
                orbit(dot, key: key, delay: Double(index) * 0.15)
            }
        case .reading:
            scan(leftPupil, key: key)
            scan(rightPupil, key: key)
        case .editing:
            bob(body, key: key)
        case .running:
            spin(ring, key: key)
        case .waiting:
            pulse(ring, key: key)
        case .done:
            hop(body, key: key)
            burst(ring, key: key)
        case .failed:
            shake(body, key: key)
        case .quiet:
            layers.forEach { $0.removeAnimation(forKey: key) }
        }
    }

    private func breathe(_ layer: CALayer, key: String, amount: CGFloat, once: Bool) {
        guard layer.animation(forKey: key) == nil else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = amount
        scale.duration = once ? 0.45 : 1.6
        scale.autoreverses = true
        scale.repeatCount = once ? 1 : .infinity
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(scale, forKey: key)
    }

    private func bob(_ layer: CALayer, key: String) {
        guard layer.animation(forKey: key) == nil else { return }
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = 0
        move.toValue = 2
        move.duration = 0.18
        move.autoreverses = true
        move.repeatCount = .infinity
        layer.add(move, forKey: key)
    }

    private func hop(_ layer: CALayer, key: String) {
        guard layer.animation(forKey: key) == nil else { return }
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = 0
        move.toValue = 6
        move.duration = 0.28
        move.autoreverses = true
        move.repeatCount = 1
        layer.add(move, forKey: key)
    }

    private func shake(_ layer: CALayer, key: String) {
        guard layer.animation(forKey: key) == nil else { return }
        let move = CABasicAnimation(keyPath: "transform.translation.x")
        move.fromValue = -3
        move.toValue = 3
        move.duration = 0.08
        move.autoreverses = true
        move.repeatCount = 4
        layer.add(move, forKey: key)
    }

    private func spin(_ layer: CALayer, key: String) {
        guard layer.animation(forKey: key) == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 1.1
        spin.repeatCount = .infinity
        layer.add(spin, forKey: key)
    }

    private func blink(_ layer: CALayer, key: String) {
        guard layer.animation(forKey: key) == nil else { return }
        let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
        blink.values = [1, 1, 0.12, 1, 1]
        blink.keyTimes = [0, 0.72, 0.78, 0.84, 1]
        blink.duration = 3.2
        blink.repeatCount = .infinity
        layer.add(blink, forKey: key)
    }

    private func pulse(_ layer: CALayer, key: String) {
        guard layer.animation(forKey: key) == nil else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1.08
        scale.duration = 0.7
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.45
        fade.toValue = 1
        fade.duration = 0.7
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.4
        group.autoreverses = true
        group.repeatCount = .infinity
        layer.add(group, forKey: key)
    }

    private func burst(_ layer: CALayer, key: String) {
        guard layer.animation(forKey: key) == nil else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.85
        scale.toValue = 1.35
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.45
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: key)
    }

    private func scan(_ layer: CALayer, key: String) {
        guard layer.animation(forKey: key) == nil else { return }
        let move = CABasicAnimation(keyPath: "transform.translation.x")
        move.fromValue = -2
        move.toValue = 2
        move.duration = 0.7
        move.autoreverses = true
        move.repeatCount = .infinity
        layer.add(move, forKey: key)
    }

    private func orbit(_ layer: CALayer, key: String, delay: Double) {
        guard layer.animation(forKey: key) == nil else { return }
        let across = CABasicAnimation(keyPath: "transform.translation.x")
        across.fromValue = -2.5
        across.toValue = 2.5
        across.duration = 0.55
        across.autoreverses = true
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = 0
        rise.toValue = 3
        rise.duration = 0.28
        rise.autoreverses = true
        let group = CAAnimationGroup()
        group.animations = [across, rise]
        group.duration = 1.1
        group.repeatCount = .infinity
        group.beginTime = CACurrentMediaTime() + delay
        layer.add(group, forKey: key)
    }
}

struct NotchCursorBuddy: NSViewRepresentable {
    var pose: CursorBuddyPose
    var tint: Color
    var reduceMotion: Bool
    var gaze: CGPoint

    func makeNSView(context: Context) -> NotchCursorBuddyLayerView {
        NotchCursorBuddyLayerView()
    }

    func updateNSView(_ view: NotchCursorBuddyLayerView, context: Context) {
        view.configure(pose: pose, tint: NSColor(tint), animates: !reduceMotion, gaze: gaze)
    }
}

struct NotchTypewriterText: View {
    let text: String
    let token: String
    var dimmed: Bool
    var enabled: Bool
    var pageVisible: Bool
    var alreadyShown: Bool
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finished = false
    @State private var faded = false
    @State private var started = Date()

    var body: some View {
        Group {
            if !enabled || finished || alreadyShown {
                Text(prefix(min(text.count, CursorTypewriter.preview)))
                    .opacity(dimmed ? 0.55 : 1)
            } else if reduceMotion {
                Text(prefix(min(text.count, CursorTypewriter.preview)))
                    .opacity((faded ? 1 : 0) * (dimmed ? 0.55 : 1))
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.25)) { faded = true }
                    }
                    .onChange(of: faded) { _, value in
                        if value { finish() }
                    }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !pageVisible)) { context in
                    let elapsed = context.date.timeIntervalSince(started)
                    let count = CursorTypewriter.shownCount(elapsed: elapsed, length: text.count)
                    let limit = min(text.count, CursorTypewriter.preview)
                    let caret = count < limit && CursorTypewriter.showsCaret(elapsed: elapsed) ? "▍" : ""
                    Text(prefix(count) + caret)
                        .opacity(dimmed ? 0.55 : 1)
                        .onChange(of: count) { _, value in
                            if value >= limit { finish() }
                        }
                }
                .onTapGesture { finish() }
            }
        }
        .onAppear {
            if alreadyShown { finished = true }
        }
        .onChange(of: token) { _, _ in
            finished = alreadyShown
            faded = alreadyShown
            started = Date()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }

    private func prefix(_ count: Int) -> String {
        String(text.prefix(count))
    }
}

/// A moving edge on the closed island. It exists only while a turn is working.
struct NotchCursorWorkingGlow: View {
    var state: CursorLiveState
    var paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(DefaultsKey.notchCursorGlow) private var glow = false

    var body: some View {
        if glow, state.isWorking, !paused, !reduceMotion,
           !ProcessInfo.processInfo.isLowPowerModeEnabled {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
                Capsule()
                    .stroke(CursorStateTint.color(state, increaseContrast: contrast == .increased)
                        .opacity(0.35 + 0.4 * phase), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct NotchCursorShimmer: View {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if active, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: (phase * 1.4 - 0.2) * geo.size.width)
                }
                .allowsHitTesting(false)
            }
        }
    }
}
