// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Metal
import QuartzCore

/// Pushes the built-in XDR display past its regular maximum brightness by
/// using the panel's HDR headroom for everything on screen.
///
/// Mechanism: a fullscreen, click-through overlay window holds a Metal layer
/// whose compositing filter is "multiply". The layer renders a solid gray
/// above 1.0 in extended linear sRGB, so the window server multiplies every
/// pixel beneath it into the extended range the panel reserves for HDR:
/// whites get brighter, blacks stay black, contrast is preserved. Showing
/// extended range content is also exactly what makes macOS engage the
/// panel's headroom, so the overlay bootstraps itself: it starts with a
/// small boost and ramps up as the reported headroom rises.
///
/// Everything is public API and macOS stays in charge of the panel: thermal
/// or power pressure can shrink the headroom at any time and the poll adapts.
/// The overlay dies with the app, so no display state can outlive a crash.
/// No windows, timers or observers exist while the feature is off.
final class ExtraBrightnessService: ObservableObject {
    static let shared = ExtraBrightnessService()

    /// A built-in display with EDR headroom exists (feature can work here).
    @Published private(set) var supported = false
    /// The boost is currently visible on the panel.
    @Published private(set) var boosting = false

    private var overlayWindow: NSWindow?
    private var overlayLayer: CAMetalLayer?
    /// A one-pixel corner window without the multiply filter. The multiply
    /// layer alone does not reliably make macOS engage the panel's headroom,
    /// but a plain extended range pixel does (verified on this hardware).
    private var triggerWindow: NSWindow?
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pollTimer: Timer?
    private var renderedFactor: Double = 0
    private var screenObserver: NSObjectProtocol?

    private init() {}

    func syncWithPreferences() {
        refreshSupported()
        let wanted = UserDefaults.standard.bool(forKey: DefaultsKey.extraBrightnessEnabled)
            && supported
        if wanted { start() } else { stop() }
    }

    /// Re-applies a level change immediately instead of waiting for the poll.
    func levelDidChange() {
        guard pollTimer != nil else { return }
        renderIfNeeded()
    }

    // MARK: - Detection

    private static func builtInXDRScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
                && ExtraBrightnessSupport.isXDRPanelName(screen.localizedName)
                && screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0
        }
    }

    private func refreshSupported() {
        let now = Self.builtInXDRScreen() != nil
        if supported != now { supported = now }
    }

    // MARK: - Lifecycle

    private func start() {
        guard pollTimer == nil else { return }
        guard let screen = Self.builtInXDRScreen() else { return }
        showOverlay(on: screen)
        installObserver()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.renderIfNeeded()
        }
        pollTimer?.tolerance = 0.1
        renderIfNeeded()
    }

    func stop() {
        guard pollTimer != nil || overlayWindow != nil else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        removeObserver()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayLayer = nil
        triggerWindow?.orderOut(nil)
        triggerWindow = nil
        commandQueue = nil
        metalDevice = nil
        renderedFactor = 0
        if boosting { boosting = false }
    }

    private func installObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.handleScreenChange()
        }
    }

    private func removeObserver() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    private func handleScreenChange() {
        refreshSupported()
        guard pollTimer != nil else { return }
        guard let screen = Self.builtInXDRScreen() else {
            // Built-in display gone (clamshell): release everything; the
            // preference stays on and a later screen change brings it back.
            stop()
            syncWithPreferences()
            return
        }
        showOverlay(on: screen)
        renderedFactor = 0
        renderIfNeeded()
    }

    // MARK: - Overlay

    private func showOverlay(on screen: NSScreen) {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayLayer = nil

        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        // Above regular windows and the menu bar so the whole picture is
        // boosted evenly; it ignores clicks, so it is never in the way.
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        // Screenshots and recordings must show the real content, not the
        // boosted composite (the overlay would wash captures out).
        window.sharingType = .none
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle,
                                     .fullScreenAuxiliary, .canJoinAllApplications]

        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return }
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.wantsExtendedDynamicRangeContent = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.isOpaque = false
        // The window server multiplies everything beneath by this layer's
        // pixels. A uniform color needs no resolution: two by two is plenty.
        layer.compositingFilter = "multiply"
        layer.drawableSize = CGSize(width: 2, height: 2)
        layer.frame = CGRect(origin: .zero, size: screen.frame.size)

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer = layer
        window.contentView = view
        window.orderFrontRegardless()

        overlayWindow = window
        overlayLayer = layer
        metalDevice = device
        commandQueue = queue
        showTrigger(on: screen, device: device, queue: queue)
    }

    /// The one-pixel plain extended range window that makes macOS engage the
    /// panel's headroom (the multiply layer alone does not).
    private func showTrigger(on screen: NSScreen, device: MTLDevice, queue: MTLCommandQueue) {
        triggerWindow?.orderOut(nil)
        triggerWindow = nil

        let frame = NSRect(x: screen.frame.maxX - 1, y: screen.frame.maxY - 1, width: 1, height: 1)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.sharingType = .none
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle,
                                     .fullScreenAuxiliary, .canJoinAllApplications]

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.wantsExtendedDynamicRangeContent = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.drawableSize = CGSize(width: 1, height: 1)
        layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.wantsLayer = true
        view.layer = layer
        window.contentView = view
        window.orderFrontRegardless()
        triggerWindow = window

        if let drawable = layer.nextDrawable(), let commands = queue.makeCommandBuffer() {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 3.0, green: 3.0, blue: 3.0, alpha: 1.0)
            if let encoder = commands.makeRenderCommandEncoder(descriptor: pass) {
                encoder.endEncoding()
                commands.present(drawable)
                commands.commit()
            }
        }
    }

    /// Renders the multiply color for the current level and headroom. While
    /// the headroom has not engaged yet it keeps re-presenting (a present on a
    /// freshly created window can be dropped); once boosted, steady state does
    /// no Metal work at all.
    private func renderIfNeeded() {
        guard let screen = Self.builtInXDRScreen(), overlayLayer != nil else { return }
        let level = Double(UserDefaults.standard.integer(forKey: DefaultsKey.extraBrightnessLevel)) / 100.0
        let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        let factor = ExtraBrightnessSupport.renderFactor(level: level, currentEDR: headroom)
        let engaged = headroom > ExtraBrightnessSupport.headroomThreshold
        guard !engaged || abs(factor - renderedFactor) > 0.005 else { return }
        render(factor: factor)
    }

    /// One clear-only render pass, no shaders: the drawable is a uniform gray
    /// at `factor`, which the compositing filter multiplies with the screen.
    private func render(factor: Double) {
        guard let layer = overlayLayer,
              let queue = commandQueue,
              let drawable = layer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: factor, green: factor,
                                                            blue: factor, alpha: 1.0)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
        renderedFactor = factor
        let visible = factor > 1.001
        if boosting != visible { boosting = visible }
    }
}
