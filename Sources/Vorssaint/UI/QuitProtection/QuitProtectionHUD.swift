// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Small, non-activating feedback panel. It is intentionally independent from
/// Settings so showing a confirmation never changes the target application.
final class QuitProtectionHUD {
    private let size = CGSize(width: 300, height: 48)
    private var panel: NSPanel?

    func show(title: String, detail: String) {
        if panel == nil {
            let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
            panel.contentView = ContentView(frame: CGRect(origin: .zero, size: size))
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .statusBar
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                        .stationary, .ignoresCycle]
            self.panel = panel
        }

        guard let content = panel?.contentView as? ContentView else { return }
        content.update(title: title, detail: detail)
        positionPanel()
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
        // Event taps can arrive between normal AppKit drawing passes. Draw now
        // so a short confirmation never waits for another app event to appear.
        panel?.display()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func positionPanel() {
        guard let panel,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
                ?? NSScreen.screens.first
        else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: (frame.midX - size.width / 2).rounded(),
                                     y: (frame.minY + 18).rounded()))
    }

    private final class ContentView: NSView {
        private let title = NSTextField(labelWithString: "")
        private let detail = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            title.font = .systemFont(ofSize: 13, weight: .semibold)
            title.textColor = .white
            title.alignment = .center
            detail.font = .systemFont(ofSize: 10.5)
            detail.textColor = .white.withAlphaComponent(0.68)
            detail.alignment = .center
            addSubview(title)
            addSubview(detail)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            title.frame = CGRect(x: 12, y: 23, width: bounds.width - 24, height: 17)
            detail.frame = CGRect(x: 12, y: 7, width: bounds.width - 24, height: 14)
        }

        func update(title: String, detail: String) {
            self.title.stringValue = title
            self.detail.stringValue = detail
            setAccessibilityLabel([title, detail].filter { !$0.isEmpty }.joined(separator: ". "))
            needsLayout = true
        }

        override func draw(_ dirtyRect: NSRect) {
            let body = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: body,
                                    xRadius: body.height / 2,
                                    yRadius: body.height / 2)
            NSColor(calibratedWhite: 0.09, alpha: 0.95).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.16).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}
