// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Small, non-activating feedback panel. It is intentionally independent from
/// Settings so showing a confirmation never changes the target application.
final class QuitProtectionHUD {
    private static let minimumSize = CGSize(width: 300, height: 48)
    private static let textInset: CGFloat = 12
    private var size = QuitProtectionHUD.minimumSize
    private var panel: NSPanel?

    /// The confirmation lines are localized and formatted with the shortcut
    /// symbol, so their rendered width is only known at show time. The widest
    /// translations need more than the fixed 300pt panel left for text. The
    /// labels are asked rather than the strings measured, so whatever inset
    /// their cells add is inside the answer.
    private static func fittingSize(_ content: ContentView) -> CGSize {
        CGSize(width: max(minimumSize.width, (content.textWidth + textInset * 2).rounded(.up)),
               height: minimumSize.height)
    }

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
        // Fill the labels first: the width comes out of them, not out of a
        // separate measurement of the same strings.
        content.update(title: title, detail: detail)
        size = Self.fittingSize(content)
        panel?.setContentSize(size)
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

        /// Width the two labels need for what they currently hold, straight
        /// from the cells that draw them.
        var textWidth: CGFloat {
            max(title.fittingSize.width, detail.fittingSize.width)
        }

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
            let inset = QuitProtectionHUD.textInset
            title.frame = CGRect(x: inset, y: 23, width: bounds.width - inset * 2, height: 17)
            detail.frame = CGRect(x: inset, y: 7, width: bounds.width - inset * 2, height: 14)
        }

        func update(title: String, detail: String) {
            self.title.stringValue = title
            self.detail.stringValue = detail
            setAccessibilityLabel([title, detail].filter { !$0.isEmpty }.joined(separator: ". "))
            needsLayout = true
            // The pill is drawn from bounds, so a width change has to repaint.
            needsDisplay = true
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
