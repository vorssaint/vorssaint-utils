// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

final class AlwaysOnTopBorder {
    private var panel: NSPanel?
    private var stroke: AlwaysOnTopBorderView?
    private var windowID: CGWindowID?
    private var timer: Timer?
    private var minimized = false

    func show(windowID: CGWindowID, colorHex: String, thickness: CGFloat) {
        self.windowID = windowID
        minimized = false
        let rgb = MenuBarUsageBarSupport.rgb(for: colorHex, fallback: "#00ADEF")
        let color = NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        let line = max(1, thickness)

        if panel == nil {
            let panel = NSPanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let stroke = AlwaysOnTopBorderView(frame: .zero)
            panel.contentView = stroke
            self.panel = panel
            self.stroke = stroke
        }
        stroke?.color = color
        stroke?.thickness = line
        stroke?.needsDisplay = true
        startTimer()
        updateFrame()
        if !minimized {
            panel?.orderFrontRegardless()
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        stroke = nil
        windowID = nil
        minimized = false
    }

    func updateFrame() {
        guard !minimized, let windowID, let quartz = quartzBounds(windowID) else { return }
        let frame = appKitFrame(fromQuartz: quartz)
        panel?.setFrame(frame, display: true)
        stroke?.needsDisplay = true
    }

    func setMinimized(_ minimized: Bool) {
        self.minimized = minimized
        if minimized {
            panel?.orderOut(nil)
        } else {
            updateFrame()
            panel?.orderFrontRegardless()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func quartzBounds(_ windowID: CGWindowID) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let dict = info.first?[kCGWindowBounds as String] as? [String: CGFloat]
        else { return nil }
        let bounds = CGRect(x: dict["X"] ?? 0, y: dict["Y"] ?? 0,
                            width: dict["Width"] ?? 0, height: dict["Height"] ?? 0)
        return bounds.width > 1 && bounds.height > 1 ? bounds : nil
    }

    private func appKitFrame(fromQuartz rect: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: menuBarScreenTopY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    private var menuBarScreenTopY: CGFloat {
        let menuBarScreen = NSScreen.screens.first {
            abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5
        }
        return (menuBarScreen ?? NSScreen.main ?? NSScreen.screens.first)?.frame.maxY ?? 0
    }
}

private final class AlwaysOnTopBorderView: NSView {
    var color = NSColor.systemCyan
    var thickness: CGFloat = 4

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let inset = thickness / 2
        let path = NSBezierPath(rect: bounds.insetBy(dx: inset, dy: inset))
        path.lineWidth = thickness
        color.setStroke()
        path.stroke()
    }
}
