// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import QuartzCore

/// Draws a ripple under every click and, optionally, dims the screen around
/// the pointer. Both are drawn on the real screen in click-through windows,
/// so any screen recorder, this app's included, captures them.
///
/// Clicks and pointer moves come from AppKit's own monitors, which need no
/// permission. Pointer moves are only followed while the spotlight shows,
/// and the overlay windows leave the screen whenever nothing is drawn.
final class ClickHighlightService: ObservableObject {
    static let shared = ClickHighlightService()

    @Published private(set) var isRunning = false

    private static let rippleDuration: CFTimeInterval = 0.5

    private var config = ClickHighlightConfig()
    private var overlays: [CGDirectDisplayID: ClickHighlightOverlay] = [:]
    private var clickMonitors: [Any] = []
    private var moveMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var recordingObserver: AnyCancellable?
    private var isRecording = false
    private var spotlightShowing = false

    private init() {}

    // MARK: Lifecycle

    func syncWithPreferences() {
        config = ClickHighlightConfig.load()
        // Without the recorder there is no recording to wait for.
        if !AppFeature.screenRecorder.isAvailable {
            config.rippleOnlyWhileRecording = false
            config.spotlightOnlyWhileRecording = false
        }
        let wanted = AppFeature.clickHighlight.isAvailable
            && (config.rippleEnabled || config.spotlightEnabled)
        guard wanted else {
            stop()
            return
        }
        observeRecording()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.rebuildOverlays()
            }
        }
        rebuildOverlays()
        applyState()
        if !isRunning { isRunning = true }
    }

    func suspend() {
        stop()
    }

    private func stop() {
        removeMonitors(&clickMonitors)
        removeMonitors(&moveMonitors)
        recordingObserver = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        overlays.values.forEach { $0.close() }
        overlays.removeAll()
        spotlightShowing = false
        if isRunning { isRunning = false }
    }

    /// The "only while recording" options follow this app's recorder.
    private func observeRecording() {
        guard recordingObserver == nil else { return }
        let needsRecorder = config.rippleOnlyWhileRecording || config.spotlightOnlyWhileRecording
        guard needsRecorder, AppFeature.screenRecorder.isAvailable else {
            isRecording = false
            return
        }
        recordingObserver = ScreenRecorderService.shared.$isRecording
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                self?.isRecording = recording
                self?.applyState()
            }
    }

    /// Installs only the monitors the current state needs.
    private func applyState() {
        let ripple = config.showsRipple(isRecording: isRecording)
        let spotlight = config.showsSpotlight(isRecording: isRecording)

        if ripple || spotlight {
            if clickMonitors.isEmpty {
                let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
                if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                    self?.handleClick()
                }) { clickMonitors.append(global) }
                if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                    self?.handleClick()
                    return event
                }) { clickMonitors.append(local) }
            }
        } else {
            removeMonitors(&clickMonitors)
        }

        if spotlight {
            if moveMonitors.isEmpty {
                let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                                   .otherMouseDragged]
                if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                    self?.moveSpotlight()
                }) { moveMonitors.append(global) }
                if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                    self?.moveSpotlight()
                    return event
                }) { moveMonitors.append(local) }
            }
            spotlightShowing = true
            overlays.values.forEach {
                $0.showSpotlight(darkness: config.spotlightDarkness, radius: config.spotlightRadius)
            }
            moveSpotlight()
        } else {
            removeMonitors(&moveMonitors)
            if spotlightShowing {
                spotlightShowing = false
                overlays.values.forEach { $0.hideSpotlight() }
            }
        }
    }

    private func removeMonitors(_ monitors: inout [Any]) {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func rebuildOverlays() {
        let screens = NSScreen.screens
        let ids = Set(screens.map(\.displayID).filter { $0 != 0 })
        for (id, overlay) in overlays where !ids.contains(id) {
            overlay.close()
            overlays.removeValue(forKey: id)
        }
        for screen in screens {
            let id = screen.displayID
            guard id != 0 else { continue }
            if let overlay = overlays[id] {
                overlay.setFrame(screen.frame)
            } else {
                overlays[id] = ClickHighlightOverlay(frame: screen.frame)
            }
        }
        if spotlightShowing {
            overlays.values.forEach {
                $0.showSpotlight(darkness: config.spotlightDarkness, radius: config.spotlightRadius)
            }
            moveSpotlight()
        }
    }

    // MARK: Drawing

    private func handleClick() {
        guard config.showsRipple(isRecording: isRecording) else { return }
        let point = NSEvent.mouseLocation
        guard let overlay = overlay(containing: point) else { return }
        overlay.ripple(at: point, style: config.style, size: CGFloat(config.size),
                       color: ClickHighlightSupport.color(hex: config.colorHex),
                       duration: Self.rippleDuration)
    }

    private func moveSpotlight() {
        guard spotlightShowing else { return }
        let point = NSEvent.mouseLocation
        overlays.values.forEach { $0.moveSpotlight(to: point) }
    }

    private func overlay(containing point: NSPoint) -> ClickHighlightOverlay? {
        overlays.values.first { NSMouseInRect(point, $0.frame, false) }
            ?? overlays.values.first
    }

    /// Shows a sample ripple in the middle of the main screen, for Settings.
    func preview() {
        let config = ClickHighlightConfig.load()
        guard let screen = NSScreen.main, screen.displayID != 0 else { return }
        let id = screen.displayID
        let overlay = overlays[id] ?? ClickHighlightOverlay(frame: screen.frame)
        overlays[id] = overlay
        let point = NSPoint(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y)
        overlay.ripple(at: point, style: config.style, size: CGFloat(config.size),
                       color: ClickHighlightSupport.color(hex: config.colorHex),
                       duration: Self.rippleDuration)
        if !isRunning {
            // Not running: let the borrowed overlay go once the sample ends.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.rippleDuration + 0.2) { [weak self] in
                guard let self, !self.isRunning else { return }
                self.overlays[id]?.close()
                self.overlays.removeValue(forKey: id)
            }
        }
    }
}

/// One click-through window over a screen, holding the ripple and spotlight
/// layers.
private final class ClickHighlightOverlay {
    private let panel: NSPanel
    private let root = CALayer()
    private var spotlight: CAGradientLayer?
    private var activeRipples = 0

    var frame: NSRect { panel.frame }

    init(frame: NSRect) {
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.addSublayer(root)
        root.frame = view.bounds
        panel.contentView = view
    }

    func setFrame(_ frame: NSRect) {
        panel.setFrame(frame, display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = CGRect(origin: .zero, size: frame.size)
        CATransaction.commit()
    }

    func close() {
        panel.orderOut(nil)
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        spotlight = nil
    }

    private func updateVisibility() {
        if activeRipples > 0 || spotlight != nil {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func local(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
    }

    // MARK: Ripple

    func ripple(at point: NSPoint, style: ClickRippleStyle, size: CGFloat, color: ColorValue,
                duration: CFTimeInterval) {
        let center = local(point)
        let cgColor = CGColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        let layers: [(CALayer, CFTimeInterval)]
        switch style {
        case .ring:
            layers = [(ring(size: size, color: cgColor, lineWidth: 3), 0)]
        case .doubleRing:
            layers = [(ring(size: size, color: cgColor, lineWidth: 3), 0),
                      (ring(size: size * 0.7, color: cgColor, lineWidth: 2), 0.1)]
        case .glow:
            layers = [(glow(size: size * 1.1, color: cgColor), 0)]
        case .dot:
            layers = [(dot(size: size * 0.4, color: cgColor), 0)]
        }

        activeRipples += 1
        updateVisibility()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, delay) in layers {
            layer.position = center
            layer.opacity = 0
            root.addSublayer(layer)
            animate(layer, style: style, duration: duration, delay: delay)
        }
        CATransaction.commit()

        let total = duration + (layers.map(\.1).max() ?? 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.05) { [weak self] in
            layers.forEach { $0.0.removeFromSuperlayer() }
            guard let self else { return }
            self.activeRipples = max(0, self.activeRipples - 1)
            self.updateVisibility()
        }
    }

    private func animate(_ layer: CALayer, style: ClickRippleStyle, duration: CFTimeInterval,
                         delay: CFTimeInterval) {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = style == .dot ? 1.0 : 0.25
        scale.toValue = style == .dot ? 0.55 : 1.0
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0, 0.08, 0.45, 1]

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = duration
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "ripple")
    }

    /// A ring with a light rim, so it reads on dark and light screens alike.
    private func ring(size: CGFloat, color: CGColor, lineWidth: CGFloat) -> CALayer {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let rect = container.bounds.insetBy(dx: lineWidth, dy: lineWidth)
        let rim = CAShapeLayer()
        rim.path = CGPath(ellipseIn: rect, transform: nil)
        rim.fillColor = nil
        rim.strokeColor = CGColor(gray: 1, alpha: 0.55)
        rim.lineWidth = lineWidth + 2
        let stroke = CAShapeLayer()
        stroke.path = rim.path
        stroke.fillColor = nil
        stroke.strokeColor = color
        stroke.lineWidth = lineWidth
        container.addSublayer(rim)
        container.addSublayer(stroke)
        return container
    }

    private func glow(size: CGFloat, color: CGColor) -> CALayer {
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        layer.colors = [color.copy(alpha: 0.75) ?? color, color.copy(alpha: 0.35) ?? color,
                        color.copy(alpha: 0) ?? color]
        layer.locations = [0, 0.45, 1]
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
        return layer
    }

    private func dot(size: CGFloat, color: CGColor) -> CALayer {
        let layer = CAShapeLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        layer.path = CGPath(ellipseIn: layer.bounds, transform: nil)
        layer.fillColor = color.copy(alpha: 0.85)
        layer.strokeColor = CGColor(gray: 1, alpha: 0.6)
        layer.lineWidth = 1.5
        return layer
    }

    // MARK: Spotlight

    /// A dim over the whole screen with a soft clear circle, drawn as one
    /// radial gradient large enough to cover the screen from any point.
    func showSpotlight(darkness: Double, radius: Double) {
        let extent = 2 * hypot(panel.frame.width, panel.frame.height)
        let layer = spotlight ?? CAGradientLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.type = .radial
        layer.bounds = CGRect(x: 0, y: 0, width: extent * 2, height: extent * 2)
        let dim = CGColor(gray: 0, alpha: darkness)
        let clear = CGColor(gray: 0, alpha: 0)
        layer.colors = [clear, clear, dim, dim]
        layer.locations = ClickHighlightSupport.spotlightLocations(radius: radius, extent: extent)
            .map { NSNumber(value: $0) }
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
        if spotlight == nil {
            root.insertSublayer(layer, at: 0)
            spotlight = layer
        }
        CATransaction.commit()
        updateVisibility()
    }

    func hideSpotlight() {
        spotlight?.removeFromSuperlayer()
        spotlight = nil
        updateVisibility()
    }

    func moveSpotlight(to point: NSPoint) {
        guard let spotlight else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spotlight.position = local(point)
        CATransaction.commit()
    }
}
