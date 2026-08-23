// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// The small pill that shows recording time and keeps pause and stop reachable.
///
/// It floats instead of living in the menu bar on purpose: a menu bar that is
/// full drops the items that do not fit, and the one control that ends a
/// recording can never be the one that disappears. It is one of this app's own
/// windows, so the capture filter excludes it and it never shows up inside the
/// video.
final class RecorderIndicator {

    private var panel: NSPanel?
    private var pill: PillView?
    private var regionGuide: NSPanel?
    private let onPause: () -> Void
    private let onStop: () -> Void

    /// The window the capture has to leave out. Everything else this app puts
    /// on screen, the panel, the settings, the command bar, belongs in the
    /// recording: showing the app itself is a thing people record.
    var excludedWindowNumbers: [Int] {
        [panel?.windowNumber, regionGuide?.windowNumber].compactMap { number in
            guard let number, number > 0 else { return nil }
            return number
        }
    }

    init(onPause: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onPause = onPause
        self.onStop = onStop
    }

    /// Keeps the chosen area visible without trapping clicks. The panel is
    /// app-owned capture chrome, so the recorder leaves it out of the video.
    func showRegionGuide(for region: RecorderSupport.Region) {
        guard regionGuide == nil, region.windowID == nil,
              let screen = NSScreen.screens.first(where: { $0.displayID == region.displayID })
        else { return }

        let selection = CGRect(x: region.anchorRect.minX - screen.frame.minX,
                               y: region.anchorRect.minY - screen.frame.minY,
                               width: region.anchorRect.width,
                               height: region.anchorRect.height)
            .intersection(CGRect(origin: .zero, size: screen.frame.size))
        guard selection.width >= 1, selection.height >= 1 else { return }

        let guide = RegionGuideView(frame: CGRect(origin: .zero, size: screen.frame.size),
                                    selection: selection)
        let panel = NSPanel(contentRect: screen.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.contentView = guide
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.orderFrontRegardless()
        regionGuide = panel
    }

    /// Shows the pill centered under the menu bar of the screen being
    /// recorded, so it sits where the eye already expects status.
    func show(on screen: NSScreen?,
              tooltip: String,
              pauseTooltip: String,
              resumeTooltip: String,
              stopTooltip: String) {
        guard panel == nil else { return }
        let host = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let host else { return }

        let pill = PillView(frame: CGRect(origin: .zero, size: PillView.size))
        pill.toolTip = tooltip
        pill.pauseTooltip = pauseTooltip
        pill.resumeTooltip = resumeTooltip
        pill.stopTooltip = stopTooltip
        pill.onPause = { [weak self] in self?.onPause() }
        pill.onStop = { [weak self] in self?.onStop() }

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

    func update(paused: Bool) {
        pill?.setPaused(paused)
    }

    func hide() {
        regionGuide?.orderOut(nil)
        regionGuide = nil
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

    private final class RegionGuideView: NSView {
        private let selection: CGRect

        init(frame frameRect: NSRect, selection: CGRect) {
            self.selection = selection
            super.init(frame: frameRect)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.beginPath()
            context.addRect(bounds)
            context.addRect(selection)
            context.setFillColor(CGColor(gray: 0, alpha: 0.3))
            context.fillPath(using: .evenOdd)

            context.addRect(selection.insetBy(dx: 1, dy: 1))
            context.setStrokeColor(CGColor(srgbRed: 0.18, green: 0.55, blue: 1, alpha: 0.95))
            context.setLineWidth(2)
            context.strokePath()
        }
    }

    // MARK: - The pill

    private final class PillView: NSView {
        static let size = CGSize(width: 150, height: 32)

        var onPause: (() -> Void)?
        var onStop: (() -> Void)?
        var pauseTooltip = ""
        var resumeTooltip = ""
        var stopTooltip = ""

        private let dot = CALayer()
        private let label = NSTextField(labelWithString: "0:00")
        private let pauseButton = IndicatorButton()
        private let stopButton = IndicatorButton()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true

            dot.backgroundColor = NSColor.systemRed.cgColor
            dot.cornerRadius = 4
            dot.frame = CGRect(x: 12, y: (Self.size.height - 8) / 2, width: 8, height: 8)
            addPulse()
            layer?.addSublayer(dot)

            label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            label.textColor = .white
            label.alignment = .center
            label.frame = CGRect(x: 25, y: 6, width: 50, height: 18)
            addSubview(label)

            configure(pauseButton,
                      symbol: "pause.fill",
                      frame: CGRect(x: 82, y: 3, width: 30, height: 26),
                      action: #selector(pausePressed))
            configure(stopButton,
                      symbol: "stop.fill",
                      frame: CGRect(x: 116, y: 3, width: 30, height: 26),
                      action: #selector(stopPressed))
            stopButton.contentTintColor = .systemRed
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func setTime(_ text: String) {
            guard label.stringValue != text else { return }
            label.stringValue = text
        }

        func setPaused(_ paused: Bool) {
            let symbol = paused ? "play.fill" : "pause.fill"
            pauseButton.image = symbolImage(symbol)
            pauseButton.toolTip = paused ? resumeTooltip : pauseTooltip
            pauseButton.setAccessibilityLabel(paused ? resumeTooltip : pauseTooltip)
            if paused {
                dot.removeAnimation(forKey: "pulse")
                dot.opacity = 0.4
            } else {
                dot.opacity = 1
                addPulse()
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            let body = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = CGPath(roundedRect: body,
                              cornerWidth: body.height / 2,
                              cornerHeight: body.height / 2,
                              transform: nil)
            context.addPath(path)
            context.setFillColor(CGColor(gray: 0.12, alpha: 0.94))
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
            context.setLineWidth(1)
            context.strokePath()

            context.move(to: CGPoint(x: 78.5, y: 8))
            context.addLine(to: CGPoint(x: 78.5, y: bounds.height - 8))
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
            context.strokePath()
        }

        private func configure(_ button: NSButton,
                               symbol: String,
                               frame: CGRect,
                               action: Selector) {
            button.frame = frame
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.image = symbolImage(symbol)
            button.contentTintColor = .white
            button.focusRingType = .none
            button.target = self
            button.action = action
            addSubview(button)
        }

        private func symbolImage(_ name: String) -> NSImage? {
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        }

        private func addPulse() {
            guard dot.animation(forKey: "pulse") == nil else { return }
            // Core Animation keeps the live state visible without waking the app.
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.28
            pulse.duration = 0.85
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.add(pulse, forKey: "pulse")
        }

        @objc private func pausePressed() { onPause?() }
        @objc private func stopPressed() { onStop?() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            pauseButton.toolTip = pauseTooltip
            pauseButton.setAccessibilityLabel(pauseTooltip)
            stopButton.toolTip = stopTooltip
            stopButton.setAccessibilityLabel(stopTooltip)
        }
    }

    private final class IndicatorButton: NSButton {
        private var hovering = false { didSet { needsDisplay = true } }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach { removeTrackingArea($0) }
            addTrackingArea(NSTrackingArea(rect: bounds,
                                           options: [.activeAlways, .mouseEnteredAndExited,
                                                     .inVisibleRect],
                                           owner: self))
        }

        override func draw(_ dirtyRect: NSRect) {
            if hovering || isHighlighted {
                NSColor.white.withAlphaComponent(isHighlighted ? 0.18 : 0.10).setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                             xRadius: 8, yRadius: 8).fill()
            }
            super.draw(dirtyRect)
        }

        override func mouseEntered(with event: NSEvent) { hovering = true }
        override func mouseExited(with event: NSEvent) { hovering = false }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
