// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import Metal
import QuartzCore

/// Renders a runtime-compiled Metal screen-edge shockwave across a
/// click-through transparent borderless overlay window.
final class NotchEdgeWaveController: NSObject {
    private var window: NSWindow?
    private var metalView: NotchEdgeWaveMetalView?
    private var displayLink: CADisplayLink?
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?

    private var startDate: Date = .distantPast
    private var duration: TimeInterval = 2.8
    private var inward = false
    private var lightSurface = false
    private var floatingIsland = false
    private var notchSize = CGSize(width: 185, height: 32)
    private var originFraction = CGPoint(x: 0.5, y: 0.02)
    private var waveColor = SIMD4<Float>(0.4, 0.85, 1.0, 1.0)

    func trigger(palette: NotchHaloPalette, on screen: NSScreen, geometry: NotchGeometry,
                 closedSize: CGSize, inward: Bool = false, lightSurface: Bool = false) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        guard ensureMetal() else { return }

        let targetFrame = screen.frame
        let win = ensureWindow(frame: targetFrame)
        win.setFrame(targetFrame, display: false)
        if let metalView {
            metalView.frame = CGRect(origin: .zero, size: targetFrame.size)
            metalView.configureDrawable(size: targetFrame.size, scale: screen.backingScaleFactor)
        }

        self.inward = inward
        self.duration = inward ? 2.0 : 2.8
        self.lightSurface = lightSurface
        self.floatingIsland = geometry.floats
        self.notchSize = closedSize

        let centerScreenX = geometry.screen.midX + geometry.surfaceShift
        let topOffsetPts: CGFloat = geometry.floats ? (geometry.floatingDrop + closedSize.height * 0.5) : (closedSize.height * 0.55)
        let normX = (centerScreenX - targetFrame.minX) / max(1, targetFrame.width)
        let normY = topOffsetPts / max(1, targetFrame.height)
        self.originFraction = CGPoint(x: min(0.95, max(0.05, normX)), y: min(0.5, max(0.005, normY)))
        let primary = palette.adapted(lightSurface: lightSurface, style: .neon).primary
        self.waveColor = SIMD4<Float>(Float(primary.r), Float(primary.g), Float(primary.b), 1.0)
        self.startDate = Date()

        win.orderFrontRegardless()
        startDisplayLink(for: win)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        window?.orderOut(nil)
    }

    private func ensureMetal() -> Bool {
        if pipeline != nil, device != nil, commandQueue != nil { return true }
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue(),
              let built = Self.buildPipeline(device: dev) else {
            return false
        }
        self.device = dev
        self.commandQueue = queue
        self.pipeline = built
        return true
    }

    private static func buildPipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        guard let library = try? device.makeLibrary(source: NotchEdgeWaveShaderSource.metalSource, options: nil),
              let vertex = library.makeFunction(name: "edgeWaveVertex"),
              let fragment = library.makeFunction(name: "edgeWaveFragment") else {
            return nil
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .one
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: desc)
    }

    private func ensureWindow(frame: CGRect) -> NSWindow {
        if let window { return window }
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.level = .statusBar
        win.ignoresMouseEvents = true
        win.hasShadow = false
        win.isOpaque = false
        win.backgroundColor = .clear
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = NotchEdgeWaveMetalView(frame: CGRect(origin: .zero, size: frame.size))
        view.metalLayer?.device = device
        win.contentView = view
        self.window = win
        self.metalView = view
        return win
    }

    private func startDisplayLink(for window: NSWindow) {
        displayLink?.invalidate()
        let link = window.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func handleDisplayLink(_ sender: CADisplayLink) {
        let elapsed = Date().timeIntervalSince(startDate)
        if elapsed >= duration {
            stop()
            return
        }
        drawFrame(elapsed: elapsed)
    }

    private func drawFrame(elapsed: TimeInterval) {
        guard let layer = metalView?.metalLayer,
              let queue = commandQueue,
              let pipeline,
              let drawable = layer.nextDrawable() else { return }

        let size = layer.drawableSize
        let scale = Float(layer.contentsScale)
        guard size.width > 0, size.height > 0 else { return }

        let progress = Float(min(1.0, max(0.0, elapsed / duration)))
        let fade = progress > 0.78 ? max(0.0, 1.0 - (progress - 0.78) / 0.22) : 1.0
        var uniforms = NotchEdgeWaveUniforms(
            color: waveColor,
            res: SIMD2<Float>(Float(size.width), Float(size.height)),
            origin: SIMD2<Float>(Float(originFraction.x) * Float(size.width),
                                Float(originFraction.y) * Float(size.height)),
            notch: SIMD2<Float>(Float(notchSize.width) * scale, Float(notchSize.height) * scale),
            t: Float(elapsed),
            clock: Float(Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)),
            mode: inward ? 1.0 : 0.0,
            progress: progress,
            fade: fade,
            floatingIsland: floatingIsland ? 1.0 : 0.0,
            contourCorner: 12.0 * scale,
            lightSurface: lightSurface ? 1.0 : 0.0
        )

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store

        guard let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<NotchEdgeWaveUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

private final class NotchEdgeWaveMetalView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        layer.framebufferOnly = true
        return layer
    }

    var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    func configureDrawable(size: CGSize, scale: CGFloat) {
        guard let metalLayer else { return }
        metalLayer.contentsScale = max(1.0, scale)
        metalLayer.drawableSize = CGSize(
            width: max(1, (size.width * max(1.0, scale)).rounded()),
            height: max(1, (size.height * max(1.0, scale)).rounded())
        )
    }
}
