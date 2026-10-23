// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore
import SwiftUI

/// What moves on the moon wallpaper over the lock screen. It sits over the
/// still frame in a clear window under the widgets and draws nothing of the
/// sky itself: the moon again in tonight's phase, sparkles on the frame's
/// brightest stars, and now and then a shooting star through open sky.
/// Everything that moves keeps clear of the widgets, the moon and the
/// system's clock and login controls, which the window would otherwise
/// cover. Core Animation runs the sparkles and the shooting stars itself,
/// so the main thread does nothing between them. With Reduce Motion on only
/// the moon shows.
struct NotchLockWallpaperLayer: NSViewRepresentable {
    let scene: NotchLockWallpaperScene

    func makeNSView(context: Context) -> NotchLockWallpaperView {
        NotchLockWallpaperView(scene: scene,
                               reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func updateNSView(_ nsView: NotchLockWallpaperView, context: Context) {}
}

final class NotchLockWallpaperView: NSView {
    private let scene: NotchLockWallpaperScene
    private let reduceMotion: Bool
    private var meteorTimer: Timer?
    private var started = false

    /// Tonight's moon is drawn once a phase step, about every three and a
    /// half hours, and kept between locks.
    private static var moonCache: (step: Int, size: CGSize, image: CGImage, frame: CGRect)?
    private static let phaseSteps = 200.0

    init(scene: NotchLockWallpaperScene, reduceMotion: Bool) {
        self.scene = scene
        self.reduceMotion = reduceMotion
        super.init(frame: CGRect(x: 0, y: 0, width: scene.width, height: scene.height))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { meteorTimer?.invalidate() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            meteorTimer?.invalidate()
            meteorTimer = nil
            return
        }
        guard !started, let root = layer else { return }
        started = true
        showMoon(in: root)
        guard !reduceMotion else { return }
        addSparkles(to: root)
        scheduleMeteor(after: .random(in: 2.5...6))
    }

    /// A rect in points from the top left, in the layer's own space.
    private func place(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: scene.height - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Tonight's moon

    private func showMoon(in root: CALayer) {
        let moon = CALayer()
        moon.contentsScale = scene.scale
        moon.opacity = 0
        root.addSublayer(moon)
        let step = Int((NotchLockWallpaperScene.phase(at: Date()) * Self.phaseSteps).rounded())
        let size = CGSize(width: scene.width, height: scene.height)
        let reveal = { [weak self] (image: CGImage, frame: CGRect) in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            moon.frame = self.place(frame)
            moon.contents = image
            CATransaction.commit()
            // The frame's own moon is already there, so tonight's eases in
            // over it rather than appearing.
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 1.2
            moon.opacity = 1
            moon.add(fade, forKey: "reveal")
        }
        if let cached = Self.moonCache, cached.step == step, cached.size == size {
            reveal(cached.image, cached.frame)
            return
        }
        let scene = scene
        DispatchQueue.global(qos: .userInitiated).async {
            let phase = Double(step) / Self.phaseSteps
            guard let drawn = scene.renderMoon(sun: NotchLockWallpaperScene.sun(phase: phase),
                                               earthshine: NotchLockWallpaperScene.earthshine(phase: phase))
            else { return }
            DispatchQueue.main.async {
                Self.moonCache = (step, size, drawn.image, drawn.frame)
                reveal(drawn.image, drawn.frame)
            }
        }
    }

    // MARK: Sparkles

    private static let sparkleCount = 90

    private func addSparkles(to root: CALayer) {
        let stars = scene.sparklingStars().sorted { $0.brightness > $1.brightness }.prefix(Self.sparkleCount)
        let now = CACurrentMediaTime()
        for star in stars {
            let warm = star.tone.x > star.tone.z
            let sprite = CALayer()
            sprite.contents = Self.sparkle(warm: warm)
            sprite.contentsScale = scene.scale
            let side = 7 + 12 * min(1, star.brightness)
            sprite.frame = place(CGRect(x: star.x - side / 2, y: star.y - side / 2, width: side, height: side))
            sprite.opacity = 0
            // A star flares and settles a few times a cycle, each at its own
            // pace, so the field never pulses together.
            let peak = Float(0.45 + 0.5 * min(1, star.brightness))
            let flicker = CAKeyframeAnimation(keyPath: "opacity")
            flicker.values = [0, 0, peak, peak * 0.25, peak * 0.8, 0, 0]
            flicker.keyTimes = [0, 0.35, 0.45, 0.52, 0.6, 0.72, 1]
            flicker.duration = .random(in: 4...11)
            flicker.beginTime = now + .random(in: 0...flicker.duration)
            flicker.repeatCount = .infinity
            flicker.isRemovedOnCompletion = false
            sprite.add(flicker, forKey: "twinkle")
            root.addSublayer(sprite)
        }
    }

    private static var sparkles: [Bool: CGImage] = [:]

    /// A soft point with faint rays, white with a hint of the star's colour.
    private static func sparkle(warm: Bool) -> CGImage? {
        if let image = sparkles[warm] { return image }
        let size = 48
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let tint = warm ? CGColor(srgbRed: 1, green: 0.93, blue: 0.82, alpha: 1)
                        : CGColor(srgbRed: 0.85, green: 0.9, blue: 1, alpha: 1)
        let centre = CGPoint(x: Double(size) / 2, y: Double(size) / 2)
        if let glow = CGGradient(colorsSpace: space, colors: [
            tint, tint.copy(alpha: 0.35)!, tint.copy(alpha: 0)!] as CFArray, locations: [0, 0.18, 1]) {
            context.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre,
                                       endRadius: Double(size) / 4, options: [])
        }
        context.setStrokeColor(tint.copy(alpha: 0.5)!)
        context.setLineWidth(0.8)
        context.setLineCap(.round)
        for (dx, dy) in [(1.0, 0.0), (0.0, 1.0)] {
            let reach = Double(size) / 2 - 2
            context.move(to: CGPoint(x: centre.x - dx * reach, y: centre.y - dy * reach))
            context.addLine(to: CGPoint(x: centre.x + dx * reach, y: centre.y + dy * reach))
        }
        context.strokePath()
        let image = context.makeImage()
        sparkles[warm] = image
        return image
    }

    // MARK: Shooting stars

    private func scheduleMeteor(after delay: TimeInterval) {
        meteorTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.window != nil else { return }
            self.launchMeteor()
            self.scheduleMeteor(after: .random(in: 14...55))
        }
        RunLoop.main.add(timer, forMode: .common)
        meteorTimer = timer
    }

    /// A path through open sky: every point of it, tail included, clear of
    /// the widgets, the moon and the system's controls.
    private func meteorPath() -> (start: CGPoint, end: CGPoint, tail: Double)? {
        // Open sky is narrow on a small display, so starts are drawn only
        // from it and a path that does not fit is simply tried again.
        for _ in 0..<300 {
            let start = CGPoint(x: .random(in: 0...scene.width), y: .random(in: 0...scene.height))
            guard scene.isOpenSky(start.x, start.y, clearance: 12) else { continue }
            // Falling, steeply or shallowly, to the left or the right.
            let angle = Double.random(in: 0.3...1.4) * (Bool.random() ? 1 : -1)
            let direction = CGPoint(x: sin(angle), y: cos(angle))
            let travel = Double.random(in: 110...280), tail = Double.random(in: 50...110)
            var clear = true
            var along = -tail
            while along <= travel {
                let x = start.x + direction.x * along, y = start.y + direction.y * along
                if !scene.isOpenSky(x, y, clearance: 12) { clear = false; break }
                along += 6
            }
            if clear {
                return (start, CGPoint(x: start.x + direction.x * travel, y: start.y + direction.y * travel), tail)
            }
        }
        return nil
    }

    private func launchMeteor() {
        guard let root = layer, let path = meteorPath() else { return }
        let from = place(CGRect(origin: path.start, size: .zero)).origin
        let to = place(CGRect(origin: path.end, size: .zero)).origin
        let streak = CAGradientLayer()
        streak.contentsScale = scene.scale
        streak.colors = [NSColor(white: 1, alpha: 0).cgColor, NSColor(srgbRed: 0.85, green: 0.9, blue: 1, alpha: 0.95).cgColor]
        streak.startPoint = CGPoint(x: 0, y: 0.5)
        streak.endPoint = CGPoint(x: 1, y: 0.5)
        streak.bounds = CGRect(x: 0, y: 0, width: path.tail, height: 1.6)
        streak.cornerRadius = 0.8
        // Its head leads, the tail trailing back along the way it came.
        streak.anchorPoint = CGPoint(x: 1, y: 0.5)
        streak.position = to
        streak.setAffineTransform(CGAffineTransform(rotationAngle: atan2(to.y - from.y, to.x - from.x)))
        streak.opacity = 0
        let distance = hypot(to.x - from.x, to.y - from.y)
        let duration = Double(distance) / .random(in: 380...620)

        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: from)
        move.toValue = NSValue(point: to)
        move.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0.9, 0]
        fade.keyTimes = [0, 0.15, 0.7, 1]
        let group = CAAnimationGroup()
        group.animations = [move, fade]
        group.duration = duration
        CATransaction.begin()
        CATransaction.setCompletionBlock { streak.removeFromSuperlayer() }
        root.addSublayer(streak)
        streak.add(group, forKey: "fall")
        CATransaction.commit()
    }
}
