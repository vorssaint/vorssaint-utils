// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Shared capture outline. It stays visible over the selected display while
/// allowing input through to the app, and callers exclude it from capture.
final class CaptureRegionGuide {
    private var panel: NSPanel?

    var windowNumber: Int? { panel?.windowNumber }

    /// Callers show the guide before preparing their capture filter so its
    /// window can be excluded from the resulting image or video.
    func show(for region: RecorderSupport.Region) {
        guard panel == nil,
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
        let panel = OverlayPanel(contentRect: screen.frame,
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
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
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
}
