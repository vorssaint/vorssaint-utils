// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

// MARK: - Overlay

/// One display's drawing surface: a click-through panel above everything,
/// including menus and the Dynamic Island, so the pointer stays visible
/// wherever the system pointer would be. Screen sharing captures it like any
/// window, which is the point.
final class PresentationPointerOverlay {
    let displayID: CGDirectDisplayID
    private(set) var frame: CGRect
    private let panel: PointerPanel
    private let canvas = NSView()
    /// Follows the pointer and nothing else, so moves never animate.
    private let pointerLayer = CALayer()
    /// The lean while moving sideways, turning about the tip.
    private let tiltLayer = CALayer()
    /// The tap itself, scaling about the tip.
    private let pressLayer = CALayer()
    private let imageLayer = CALayer()
    private var artwork: PresentationPointerArtwork?
    private var pressedScale: CGFloat?
    /// Whether the system pointer is on screen anyway, where macOS insists
    /// on drawing it; the picture then steps aside so only one shows.
    private var suppressed = false
    private var placed = false

    /// Above shielding windows and the island's own level, under nothing but
    /// the system pointer.
    static let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)

    init(frame: CGRect, displayID: CGDirectDisplayID) {
        self.displayID = displayID
        self.frame = frame
        panel = PointerPanel(contentRect: frame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = Self.level
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        canvas.frame = CGRect(origin: .zero, size: frame.size)
        // A layer of its own rather than one AppKit backs and redraws: the
        // tree below is all there is to draw, and it exists before the
        // deferred window does.
        canvas.layer = CALayer()
        canvas.wantsLayer = true
        panel.contentView = canvas

        // Zero-sized layers at the tip: their transforms turn and scale about
        // the point the pointer clicks with.
        for layer in [pointerLayer, tiltLayer, pressLayer] {
            layer.bounds = .zero
            layer.anchorPoint = .zero
        }
        pointerLayer.isHidden = true
        tiltLayer.addSublayer(pressLayer)
        pressLayer.addSublayer(imageLayer)
        pointerLayer.addSublayer(tiltLayer)
        canvas.layer?.addSublayer(pointerLayer)
        withoutAnimation {
            for layer in [pointerLayer, tiltLayer, pressLayer, imageLayer] {
                layer.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(),
                                 "hidden": NSNull()]
            }
        }
    }

    var windowNumber: Int { panel.windowNumber }

    /// Whether there is a picture to draw, which the system pointer is only
    /// hidden for.
    var hasArtwork: Bool { artwork != nil }

    func show() {
        panel.orderFrontRegardless()
        // Exactly over its display, or every point drawn is off by the gap.
        if panel.frame != frame { panel.setFrame(frame, display: false) }
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    func update(frame newFrame: CGRect) {
        guard newFrame != frame else { return }
        frame = newFrame
        panel.setFrame(newFrame, display: false)
        canvas.frame = CGRect(origin: .zero, size: newFrame.size)
    }

    func apply(_ artwork: PresentationPointerArtwork) {
        if artwork.image !== self.artwork?.image { burstImages = [:] }
        self.artwork = artwork
        withoutAnimation {
            imageLayer.contents = artwork.image
            imageLayer.contentsScale = CGFloat(artwork.image.width) / max(artwork.size.width, 1)
            // The layer space runs upward, the image's hot spot downward.
            imageLayer.frame = CGRect(x: -artwork.hotSpot.x,
                                      y: -(artwork.size.height - artwork.hotSpot.y),
                                      width: artwork.size.width,
                                      height: artwork.size.height)
        }
    }


    /// `point` is in screen coordinates.
    func movePointer(to point: CGPoint) {
        placed = true
        withoutAnimation {
            pointerLayer.position = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
            pointerLayer.isHidden = suppressed
        }
    }

    /// Steps the picture aside while the system pointer shows anyway, and
    /// brings it back once that one is hidden again.
    func setSuppressed(_ suppressed: Bool) {
        guard suppressed != self.suppressed else { return }
        self.suppressed = suppressed
        withoutAnimation { pointerLayer.isHidden = suppressed || !placed }
    }

    /// Where the drawn tip is, in screen coordinates: the point a click
    /// under the pointer lands on, which has to be the mouse location itself.
    var drawnTip: CGPoint? {
        guard !pointerLayer.isHidden, artwork != nil, let root = canvas.layer else { return nil }
        let bounds = imageLayer.bounds
        let tip = CGPoint(x: bounds.minX + (artwork?.hotSpot.x ?? 0),
                          y: bounds.maxY - (artwork?.hotSpot.y ?? 0))
        let inCanvas = imageLayer.convert(tip, to: root)
        return CGPoint(x: inCanvas.x + frame.minX, y: inCanvas.y + frame.minY)
    }

    /// The pointer arriving: a quick fade where it already stands, so it
    /// never seems to jump from somewhere else.
    /// How long the pointer takes to fade in when it is turned on.
    static let arrivalDuration: TimeInterval = 0.12

    /// Fades the pointer in as it arrives. `elapsed` is how far an arrival
    /// on another display had got, so a pointer crossing over mid-fade
    /// carries on from there rather than starting again or popping in.
    func fadeIn(elapsed: TimeInterval = 0, reduceMotion: Bool) {
        let remaining = Self.arrivalDuration - max(0, elapsed)
        guard !reduceMotion, remaining > 0 else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = Float(max(0, elapsed) / Self.arrivalDuration)
        fade.toValue = 1
        fade.duration = remaining
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pointerLayer.add(fade, forKey: "arrive")
    }

    /// The opacity the running arrival fade starts from, or nil when none
    /// runs.
    var arrivalFadeStart: Float? {
        (pointerLayer.animation(forKey: "arrive") as? CABasicAnimation)?.fromValue as? Float
    }

    func hidePointer() {
        placed = false
        withoutAnimation { pointerLayer.isHidden = true }
        pressedScale = nil
        pressLayer.removeAllAnimations()
        pressLayer.transform = CATransform3DIdentity
        // Upright again for whenever the pointer comes back to this display.
        tiltLayer.removeAllAnimations()
        tiltLayer.transform = CATransform3DIdentity
    }

    func setTilt(_ radians: CGFloat, animated: Bool) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.12)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        tiltLayer.transform = CATransform3DMakeRotation(radians, 0, 0, 1)
        CATransaction.commit()
    }

    /// The press of a tap: the pointer sinks toward its tip and holds there
    /// until the button comes up.
    func press(_ expression: PresentationPointerTapExpression, reduceMotion: Bool) {
        guard !reduceMotion else { return }
        let scale = expression.pressScale
        let from = currentPressScale()
        pressedScale = scale
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = from
        animation.toValue = scale
        animation.duration = 0.07
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        withoutAnimation { pressLayer.transform = CATransform3DMakeScale(scale, scale, 1) }
        pressLayer.add(animation, forKey: "tap")
    }

    /// The release of a tap: the pointer springs back past its size and settles.
    func release(reduceMotion: Bool) {
        guard pressedScale != nil else { return }
        pressedScale = nil
        let from = currentPressScale()
        withoutAnimation { pressLayer.transform = CATransform3DIdentity }
        guard !reduceMotion else {
            pressLayer.removeAnimation(forKey: "tap")
            return
        }
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = from
        spring.toValue = 1
        spring.mass = 0.8
        spring.stiffness = 420
        spring.damping = 11
        spring.duration = spring.settlingDuration
        pressLayer.add(spring, forKey: "tap")
    }

    /// A starburst of rays around a click, in the pointer's colors, that
    /// grows and fades on its own. `point` is in screen coordinates. The rays
    /// are drawn once per look and kept, so a click costs one layer with a
    /// ready picture rather than shapes to fill and stroke.
    func burst(at point: CGPoint, _ expression: PresentationPointerTapExpression, reduceMotion: Bool) {
        guard let artwork, let root = canvas.layer, let image = burstImage(expression, artwork: artwork)
        else { return }
        // The outer layer grows and fades; the rays inside it take a
        // different turn each time, so a series never looks stamped.
        let layer = CALayer()
        let rays = CALayer()
        withoutAnimation {
            rays.contents = image.image
            rays.contentsScale = image.scale
            rays.bounds = CGRect(origin: .zero, size: image.size)
            rays.position = .zero
            rays.transform = CATransform3DMakeRotation(CGFloat.random(in: 0..<(2 * .pi)), 0, 0, 1)
            layer.bounds = .zero
            layer.addSublayer(rays)
            layer.position = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
            // Under the pointer, so the shape that tapped stays in front.
            root.insertSublayer(layer, below: pointerLayer)
        }

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let animations = CAAnimationGroup()
        if reduceMotion {
            animations.animations = [fade]
        } else {
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.55
            grow.toValue = 1
            animations.animations = [grow, fade]
        }
        animations.duration = expression.burstDuration
        animations.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        withoutAnimation { layer.opacity = 0 }
        layer.add(animations, forKey: "burst")
        CATransaction.commit()
    }

    private struct BurstImage {
        let image: CGImage
        let size: CGSize
        let scale: CGFloat
    }

    /// Rays drawn once per ray count, length and thickness for the current
    /// look; applying a new look starts the cache over.
    private var burstImages: [String: BurstImage] = [:]

    private func burstImage(_ expression: PresentationPointerTapExpression,
                            artwork: PresentationPointerArtwork) -> BurstImage? {
        let radius = (expression.burstRadius * artwork.pointerSize).rounded()
        let width = max(1.5, (expression.rayWidth * artwork.pointerSize * 2).rounded() / 2)
        let key = "\(expression.rayCount)-\(radius)-\(width)"
        if let cached = burstImages[key] { return cached }

        let ink = width + max(1.5, width * 0.6)
        let side = ceil((radius + ink) * 2)
        let scale = max(1, CGFloat(artwork.image.width) / max(artwork.size.width, 1))
        let pixels = Int(side * scale)
        guard pixels > 0,
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: side / 2, y: side / 2)
        let path = CGMutablePath()
        for index in 0..<expression.rayCount {
            let angle = CGFloat(index) / CGFloat(expression.rayCount) * 2 * .pi
            path.move(to: CGPoint(x: cos(angle) * radius * 0.55, y: sin(angle) * radius * 0.55))
            path.addLine(to: CGPoint(x: cos(angle) * radius, y: sin(angle) * radius))
        }
        context.setLineCap(.round)
        for (stroke, lineWidth) in [(artwork.outlineColor, ink), (artwork.color, width)] {
            context.addPath(path)
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(lineWidth)
            context.strokePath()
        }
        guard let image = context.makeImage() else { return nil }
        let made = BurstImage(image: image, size: CGSize(width: side, height: side), scale: scale)
        burstImages[key] = made
        return made
    }

    /// A frame clock for this display, so the pointer moves once per refresh
    /// of the screen it is on, however fast the mouse reports.
    func makeDisplayLink(target: Any, selector: Selector) -> CADisplayLink {
        canvas.displayLink(target: target, selector: selector)
    }

    private func currentPressScale() -> CGFloat {
        let layer = pressLayer.presentation() ?? pressLayer
        return (layer.value(forKeyPath: "transform.scale") as? CGFloat) ?? 1
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

/// The overlays' panel. AppKit may move a window it is ordering in so that it
/// fits below the menu bar; these cover the whole display on purpose, so
/// their frames are kept exactly as given.
final class PointerPanel: OverlayPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

extension PresentationPointerOverlay {
    convenience init(screen: NSScreen) {
        self.init(frame: screen.frame, displayID: screen.displayID)
    }
}

// MARK: - Click shield

/// While clicks are blocked, an invisible panel over each display takes them
/// in place of the apps underneath. It sits just above the Dock, below the
/// menu bar, Vorssaint's own menu and every system surface, so those stay
/// clickable and there is always a way back. It never becomes key, so the
/// keyboard stays with the app being presented.
final class PresentationPointerClickShield {
    let displayID: CGDirectDisplayID
    private let panel: ShieldPanel

    static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)

    init(screen: NSScreen) {
        displayID = screen.displayID
        panel = ShieldPanel(contentRect: screen.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        // Fully clear windows let clicks fall through; a trace of alpha keeps
        // them here without drawing anything a viewer could see.
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.002)
        panel.hasShadow = false
        panel.level = Self.level
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = ShieldView(frame: CGRect(origin: .zero, size: screen.frame.size))
        // Screen sharing should see the presentation, not a faint film.
        panel.sharingType = .none
    }

    var windowNumber: Int { panel.windowNumber }

    func show() {
        panel.orderFrontRegardless()
    }

    func update(frame: CGRect) {
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: false)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    private final class ShieldPanel: OverlayPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    /// Takes the first click without activating anything and does nothing
    /// with it: the presentation pointer's own monitor already tapped.
    private final class ShieldView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {}
        override func rightMouseDown(with event: NSEvent) {}
        override func otherMouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) {}
        override func rightMouseUp(with event: NSEvent) {}
        override func otherMouseUp(with event: NSEvent) {}
        override func scrollWheel(with event: NSEvent) {}
        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}
