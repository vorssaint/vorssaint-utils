// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// Small decorative layers, with no timers or frame callbacks in the app.
/// Settings retains its view hierarchy when closed, so disappearance alone
/// cannot stop motion: observe the actual window's visibility as well.
final class NotchAgentAnimationView: NSView {
    private let artwork = CALayer()
    private var image: NSImage?
    private var tint: NSColor?
    private let dot = CAShapeLayer()
    private let ring = CAShapeLayer()
    private var isPulse = false
    private var size: CGFloat = 0
    private var animates = false
    private var visibilityObserver: NSObjectProtocol?
    private static let animationKey = "notch.agent"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(artwork)
        layer?.addSublayer(dot)
        layer?.addSublayer(ring)
        ring.fillColor = nil
        ring.lineWidth = 1
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configureGlyph(image: NSImage?, size: CGFloat, tint: NSColor?, animates: Bool) {
        let changed = self.image !== image || self.size != size || self.tint != tint || isPulse
        isPulse = false
        self.image = image
        self.tint = tint
        self.size = size
        self.animates = animates
        if changed { renderArtwork() }
        updateLayers()
    }

    func configurePulse(size: CGFloat, tint: NSColor, animates: Bool) {
        isPulse = true
        self.size = size
        self.animates = animates
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.fillColor = tint.cgColor
        ring.strokeColor = tint.cgColor
        CATransaction.commit()
        updateLayers()
    }

    func stop() {
        animates = false
        updateLayers()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                self?.updateLayers()
            }
        }
        renderArtwork()
        updateLayers()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderArtwork()
    }

    /// Rasterize only when the mark, tint, size or display scale changes.
    /// The compositor reuses this small image for every animation frame.
    private func renderArtwork() {
        guard !isPulse, let image, size > 0 else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixels = max(1, Int(ceil(size * scale)))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let factor = CGFloat(pixels) / max(1, max(image.size.width, image.size.height))
        let width = image.size.width * factor
        let height = image.size.height * factor
        let rect = CGRect(x: (CGFloat(pixels) - width) / 2, y: (CGFloat(pixels) - height) / 2,
                          width: width, height: height)
        image.draw(in: rect)
        if let tint {
            tint.setFill()
            rect.fill(using: .sourceAtop)
        }
        NSGraphicsContext.restoreGraphicsState()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artwork.contents = bitmap.cgImage
        artwork.contentsScale = scale
        CATransaction.commit()
    }

    override func viewDidHide() { super.viewDidHide(); updateLayers() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateLayers() }
    override func layout() { super.layout(); updateLayers() }

    private func updateLayers() {
        let moving = animates && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        artwork.isHidden = isPulse
        dot.isHidden = !isPulse
        ring.isHidden = !isPulse || !moving
        let frame = CGRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
        artwork.frame = frame
        for shape in [dot, ring] where shape.frame != frame {
            shape.frame = frame
            shape.path = CGPath(ellipseIn: CGRect(origin: .zero, size: frame.size), transform: nil)
        }
        artwork.opacity = 1
        ring.opacity = 0
        let target = isPulse ? ring : artwork
        let inactive = isPulse ? artwork : ring
        inactive.removeAnimation(forKey: Self.animationKey)
        guard moving else {
            target.removeAnimation(forKey: Self.animationKey)
            return
        }
        // Snapshot/time/geometry updates keep the existing animation phase.
        guard target.animation(forKey: Self.animationKey) == nil else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = isPulse ? 1 : 0.84
        scale.toValue = isPulse ? 1.9 : 1
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = isPulse ? 0.6 : 0.7
        opacity.toValue = isPulse ? 0 : 1
        let animation = CAAnimationGroup()
        animation.duration = isPulse ? 1.6 : 1.2
        scale.duration = animation.duration
        opacity.duration = animation.duration
        animation.animations = [scale, opacity]
        animation.autoreverses = !isPulse
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: isPulse ? .easeOut : .easeInEaseOut)
        animation.beginTime = target.convertTime(CACurrentMediaTime(), from: nil)
        target.add(animation, forKey: Self.animationKey)
    }
}
