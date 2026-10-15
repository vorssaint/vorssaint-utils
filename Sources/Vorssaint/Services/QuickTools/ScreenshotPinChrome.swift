// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Only these small panels receive input when the image is click-through.
final class ScreenshotPinChrome {
    private weak var pin: ScreenshotPinWindow?
    private let closePanel = PinControlPanel(size: CGSize(width: 30, height: 30))
    private let modePanel = PinControlPanel(size: CGSize(width: 64, height: 30))
    private let dragPanel = PinControlPanel(size: CGSize(width: 100, height: 26))
    private let feedbackPanel = PinControlPanel(size: CGSize(width: 76, height: 28))
    private let feedback = ScreenshotPinFeedbackView(frame: CGRect(x: 0, y: 0, width: 76, height: 28))
    private let lockButton = PinControlButton()
    private let cursorButton = PinControlButton()
    private var attached = false

    init(pin: ScreenshotPinWindow) {
        self.pin = pin
        let close = PinControlButton()
        configure(close, symbol: "xmark", label: L10n.shared.s.menuClose, action: #selector(closePin))
        closePanel.contentView?.addSubview(circle(close, x: 0))
        configure(lockButton, symbol: "lock.open", label: "", action: #selector(toggleLock))
        configure(cursorButton, symbol: "cursorarrow", label: "", action: #selector(toggleClickThrough))
        modePanel.contentView?.addSubview(circle(lockButton, x: 0))
        modePanel.contentView?.addSubview(circle(cursorButton, x: 34))
        feedbackPanel.contentView = feedback
        dragPanel.contentView = ScreenshotPinDragView(pin: pin)
        feedbackPanel.ignoresMouseEvents = true
        refreshButtons()
    }

    private var panels: [NSPanel] { [closePanel, modePanel, dragPanel, feedbackPanel] }

    func attach() {
        guard !attached, let pin else { return }
        attached = true
        layout()
        for panel in panels { pin.addChildWindow(panel, ordered: .above) }
        setControlsVisible(pin.isHovered)
    }

    func layout() {
        guard let pin else { return }
        closePanel.setFrameOrigin(CGPoint(x: pin.frame.minX + 8, y: pin.frame.maxY - 38))
        modePanel.setFrameOrigin(CGPoint(x: pin.frame.maxX - 72, y: pin.frame.maxY - 38))
        dragPanel.setFrameOrigin(CGPoint(x: pin.frame.midX - 50, y: pin.frame.minY + 8))
        feedbackPanel.setFrameOrigin(CGPoint(x: pin.frame.midX - 38, y: pin.frame.midY - 14))
    }

    func setControlsVisible(_ visible: Bool) {
        for panel in [closePanel, modePanel, dragPanel] {
            panel.alphaValue = visible ? 1 : 0
            panel.ignoresMouseEvents = !visible
        }
    }

    func showFeedback(_ text: String) { feedback.show(text) }

    func refreshButtons() {
        guard let pin else { return }
        let strings = ScreenshotPinStrings.localized(L10n.shared.language)
        let lockLabel = pin.isPositionLocked ? strings.unlock : strings.lock
        lockButton.image = NSImage(systemSymbolName: pin.isPositionLocked ? "lock.fill" : "lock.open", accessibilityDescription: lockLabel)
        lockButton.setAccessibilityLabel(lockLabel)
        lockButton.toolTip = lockLabel
        lockButton.contentTintColor = pin.isPositionLocked ? .systemYellow : .white
        cursorButton.setAccessibilityLabel(strings.clickThrough)
        cursorButton.toolTip = strings.clickThrough
        cursorButton.contentTintColor = pin.ignoresMouseEvents ? .systemYellow : .white
        lockButton.state = pin.isPositionLocked ? .on : .off
        cursorButton.state = pin.ignoresMouseEvents ? .on : .off
    }

    func detach() {
        feedback.dismiss()
        for panel in panels {
            pin?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        attached = false
    }

    private func configure(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.contentTintColor = .white
        button.setAccessibilityLabel(label)
        button.toolTip = label
        button.target = self
        button.action = action
    }

    private func circle(_ button: NSButton, x: CGFloat) -> NSView {
        let glass = NSVisualEffectView(frame: CGRect(x: x, y: 0, width: 30, height: 30))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 15
        glass.layer?.masksToBounds = true
        glass.addSubview(button)
        return glass
    }

    @objc private func closePin() { pin?.closePin() }
    @objc private func toggleLock() { if let pin { pin.setPositionLocked(!pin.isPositionLocked) } }
    @objc private func toggleClickThrough() { if let pin { pin.setClickThrough(!pin.ignoresMouseEvents) } }
}

private final class PinControlButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class PinControlPanel: OverlayPanel {
    init(size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { false }
}
