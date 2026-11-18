// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation

/// Vorssaint's own floating panel, placed exactly over a pinned window. It
/// floats above normal windows, follows the user onto every Space of its
/// display and over full-screen apps, and never takes focus: a click on it
/// asks for the real window instead.
final class AlwaysOnTopOverlay: NSPanel {
    private let mirrorView: AlwaysOnTopMirrorView

    var onClick: (() -> Void)? {
        get { mirrorView.onClick }
        set { mirrorView.onClick = newValue }
    }
    var onPointerEntered: (() -> Void)? {
        get { mirrorView.onEnter }
        set { mirrorView.onEnter = newValue }
    }
    var onPointerExited: (() -> Void)? {
        get { mirrorView.onExit }
        set { mirrorView.onExit = newValue }
    }

    init(displayLayer: AVSampleBufferDisplayLayer) {
        mirrorView = AlwaysOnTopMirrorView(displayLayer: displayLayer)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        contentView = mirrorView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The line around the mirror, in points; zero draws none. A nil
    /// colour follows the system accent colour.
    func setBorder(width: CGFloat, color: NSColor?) {
        mirrorView.borderWidth = width
        mirrorView.borderColor = color
    }

    /// A short line over the mirror, or nil to clear it.
    func setMessage(_ message: String?) {
        mirrorView.message = message
    }

    /// Counts show and hide requests, so a fade that finishes after the
    /// overlay was shown again leaves it on screen.
    private var visibilityRequest = 0

    func show() {
        visibilityRequest += 1
        alphaValue = 1
        orderFrontRegardless()
    }

    func hide(fade: Bool) {
        visibilityRequest += 1
        guard isVisible else { return }
        guard fade else {
            orderOut(nil)
            return
        }
        let request = visibilityRequest
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.visibilityRequest == request else { return }
            self.orderOut(nil)
            self.alphaValue = 1
        })
    }
}

private final class AlwaysOnTopMirrorView: NSView {
    private let displayLayer: AVSampleBufferDisplayLayer
    private let border = CALayer()
    private let label = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    var borderWidth: CGFloat = AlwaysOnTopBorder.medium.width {
        didSet {
            border.borderWidth = borderWidth
            border.isHidden = borderWidth == 0
        }
    }

    var borderColor: NSColor? {
        didSet { updateBorderColor() }
    }

    var message: String? {
        didSet {
            label.stringValue = message ?? ""
            label.isHidden = message == nil
            needsLayout = true
        }
    }

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(displayLayer)
        // The border marks the pin while the mirror stands in for the window.
        updateBorderColor()
        border.borderWidth = borderWidth
        border.cornerRadius = 10
        layer?.addSublayer(border)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        label.layer?.cornerRadius = 6
        label.isHidden = true
        addSubview(label)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        border.frame = bounds
        CATransaction.commit()
        let maxWidth = max(40, bounds.width - 32)
        let size = label.sizeThatFits(CGSize(width: maxWidth - 16, height: .greatestFiniteMagnitude))
        let width = min(maxWidth, size.width + 16)
        label.frame = CGRect(x: (bounds.width - width) / 2, y: 16, width: width, height: size.height + 8)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderColor()
    }

    private func updateBorderColor() {
        border.borderColor = (borderColor ?? .controlAccentColor).withAlphaComponent(0.85).cgColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
