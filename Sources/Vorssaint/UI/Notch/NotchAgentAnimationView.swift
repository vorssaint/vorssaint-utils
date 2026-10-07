// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// Small decorative layers, stepped at a limited rate while they show.
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
    private(set) var motionStart: CFTimeInterval = 0
    private lazy var clock = NotchDecorativeClock { [weak self] time in self?.step(at: time) }

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

    var isMoving: Bool { clock.isRunning }

    private func updateLayers() {
        let moving = animates && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        // Snapshot, time and geometry updates keep the motion's phase.
        if moving, !clock.isRunning { motionStart = CACurrentMediaTime() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artwork.isHidden = isPulse
        dot.isHidden = !isPulse
        ring.isHidden = !isPulse || !moving
        // Bounds and position rather than frames: the moving layer is scaled.
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        for layer in [artwork, dot, ring] {
            layer.bounds = box
            layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        for shape in [dot, ring] where shape.path?.boundingBox != box {
            shape.path = CGPath(ellipseIn: box, transform: nil)
        }
        show(at: moving ? CACurrentMediaTime() : nil)
        CATransaction.commit()
        if moving { clock.start(in: self) } else { clock.stop() }
    }

    /// The glyph grows and brightens and settles back, and the pulse's ring
    /// spreads from the dot as it fades, in the rhythm of the animations they
    /// replace. With no time, both rest.
    private func show(at time: CFTimeInterval?) {
        var glyph = (scale: 1.0, opacity: 1.0)
        var spreading = (scale: 1.0, opacity: 0.0)
        if let time, isPulse {
            let spread = NotchDecorativeClock.pulse(time - motionStart, period: 1.6)
            spreading = (1 + 0.9 * spread, 0.6 * (1 - spread))
        } else if let time {
            let breath = NotchDecorativeClock.swing((time - motionStart) / 1.2)
            glyph = (0.84 + 0.16 * breath, 0.7 + 0.3 * breath)
        }
        artwork.transform = CATransform3DMakeScale(glyph.scale, glyph.scale, 1)
        artwork.opacity = Float(glyph.opacity)
        ring.transform = CATransform3DMakeScale(spreading.scale, spreading.scale, 1)
        ring.opacity = Float(spreading.opacity)
    }

    func step(at time: CFTimeInterval) {
        guard clock.isRunning else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        show(at: time)
        CATransaction.commit()
    }
}
