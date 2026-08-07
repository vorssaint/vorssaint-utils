// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// The small pill that says a recording is running, and stops it when clicked.
///
/// It floats instead of living in the menu bar on purpose: a menu bar that is
/// full drops the items that do not fit, and the one control that ends a
/// recording can never be the one that disappears. It is one of this app's own
/// windows, so the capture filter excludes it and it never shows up inside the
/// video.
final class RecorderIndicator {

    private var panel: NSPanel?
    private var pill: PillView?
    private let onStop: () -> Void

    /// The window the capture has to leave out. Everything else this app puts
    /// on screen, the panel, the settings, the command bar, belongs in the
    /// recording: showing the app itself is a thing people record.
    var excludedWindowNumber: Int? { panel?.windowNumber }

    init(onStop: @escaping () -> Void) {
        self.onStop = onStop
    }

    /// Shows the pill centered under the menu bar of the screen being
    /// recorded, so it sits where the eye already expects status.
    func show(on screen: NSScreen?, tooltip: String) {
        guard panel == nil else { return }
        let host = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let host else { return }

        let pill = PillView(frame: CGRect(origin: .zero, size: PillView.size))
        pill.toolTip = tooltip
        pill.onClick = { [weak self] in self?.onStop() }

        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: PillView.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.contentView = pill
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        let frame = host.visibleFrame
        panel.setFrameOrigin(CGPoint(x: (frame.midX - PillView.size.width / 2).rounded(),
                                     y: (frame.maxY - PillView.size.height - 10).rounded()))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        self.pill = pill
    }

    func update(elapsed: String) {
        pill?.setTime(elapsed)
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        pill = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: - The pill

    private final class PillView: NSView {
        static let size = CGSize(width: 108, height: 30)

        var onClick: (() -> Void)?

        private let dot = CALayer()
        private let label = NSTextField(labelWithString: "0:00")
        private var isHovering = false {
            didSet { needsDisplay = true }
        }
        private var isPressed = false {
            didSet { needsDisplay = true }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true

            dot.backgroundColor = NSColor.systemRed.cgColor
            dot.cornerRadius = 4
            dot.frame = CGRect(x: 13, y: (Self.size.height - 8) / 2, width: 8, height: 8)
            // A pulse is the one thing that reads as "live" at a glance, and
            // Core Animation runs it on its own without waking the app.
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.28
            pulse.duration = 0.85
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.add(pulse, forKey: "pulse")
            layer?.addSublayer(dot)

            label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            label.textColor = .white
            label.alignment = .center
            label.frame = CGRect(x: 26, y: 5, width: Self.size.width - 26 - 12, height: 18)
            addSubview(label)

            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                           owner: self))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func setTime(_ text: String) {
            guard label.stringValue != text else { return }
            label.stringValue = text
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            let body = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = CGPath(roundedRect: body,
                              cornerWidth: body.height / 2,
                              cornerHeight: body.height / 2,
                              transform: nil)
            let fill: CGFloat = isPressed ? 0.34 : (isHovering ? 0.24 : 0.16)
            context.addPath(path)
            context.setFillColor(CGColor(gray: fill, alpha: 0.92))
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(CGColor(gray: 1, alpha: isHovering ? 0.28 : 0.16))
            context.setLineWidth(1)
            context.strokePath()
        }

        // The pointer has to say the whole pill is the stop button before the
        // click, or nobody tries it.
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func mouseEntered(with event: NSEvent) { isHovering = true }
        override func mouseExited(with event: NSEvent) { isHovering = false }
        override func mouseDown(with event: NSEvent) { isPressed = true }

        override func mouseUp(with event: NSEvent) {
            isPressed = false
            guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            onClick?()
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
