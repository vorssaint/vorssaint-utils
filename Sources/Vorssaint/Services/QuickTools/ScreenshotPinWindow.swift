// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

/// Image presentation is independent from the small interactive chrome panels.
final class ScreenshotPinWindow: OverlayPanel, NSWindowDelegate {
    let image: CGImage
    let captureScale: CGFloat
    private let preferences: UserDefaults
    private(set) var chosenOpacity: CGFloat = 1
    private(set) var isPositionLocked = false
    private(set) var isHovered = false
    private(set) var isClosed = false
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onCloseAll: (() -> Void)?
    var onClickThroughChanged: (() -> Void)?
    private lazy var chrome = ScreenshotPinChrome(pin: self)
    private lazy var surface = ScreenshotPinContentView(image: image, pin: self)

    var displayedImageOpacity: CGFloat { CGFloat(surface.layer?.opacity ?? 1) }
    var zoomMultiplier: CGFloat { frame.width / (CGFloat(image.width) / captureScale) }
    var cornerRadius: CGFloat { surface.layer?.cornerRadius ?? 0 }

    init(image: CGImage, scale: CGFloat, preferences: UserDefaults = .standard) {
        self.image = image
        captureScale = scale.isFinite && scale > 0 ? scale : 1
        self.preferences = preferences
        let pointer = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
                      ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let native = CGSize(width: CGFloat(image.width) / captureScale,
                            height: CGFloat(image.height) / captureScale)
        let cap = min(screen.width, screen.height) * 0.55
        let fit = min(1, cap / max(native.width, native.height))
        let floor = max(140 / native.width, 90 / native.height)
        let factor = min(max(fit, floor), min(screen.width / native.width, screen.height / native.height))
        let size = CGSize(width: native.width * factor, height: native.height * factor)
        super.init(contentRect: CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                      width: size.width, height: size.height),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        contentAspectRatio = CGSize(width: image.width, height: image.height)
        minSize = CGSize(width: 140, height: 90)
        contentView = surface
        delegate = self
        refreshAppearance()
    }

    override var canBecomeKey: Bool { true }

    func showPin() {
        guard !isClosed else { return }
        orderFrontRegardless()
        chrome.attach()
        updateHover(at: NSEvent.mouseLocation)
    }

    func refreshAppearance() {
        let rounded = preferences.object(forKey: DefaultsKey.screenshotPinRoundedCorners) as? Bool ?? true
        surface.layer?.cornerRadius = rounded ? 10 : 0
        invalidateShadow()
    }

    func updateHover(at point: CGPoint) {
        guard !isClosed else { return }
        let hovered = frame.contains(point)
        guard hovered != isHovered else { return }
        isHovered = hovered
        updateImageOpacity()
        chrome.setControlsVisible(hovered)
    }

    func setOpacity(_ value: CGFloat) {
        guard !isClosed, value.isFinite else { return }
        let next = min(1, max(0.1, value))
        guard next != chosenOpacity else { return }
        chosenOpacity = next
        updateImageOpacity()
        chrome.showFeedback("\(Int((next * 100).rounded()))%")
    }

    func reportZoom() {
        guard !isClosed else { return }
        chrome.showFeedback(String(format: "%.1fx", locale: Locale.current, Double(zoomMultiplier)))
    }

    func setPositionLocked(_ enabled: Bool) {
        guard !isClosed else { return }
        isPositionLocked = enabled
        if enabled { styleMask.remove(.resizable) } else { styleMask.insert(.resizable) }
        chrome.refreshButtons()
    }

    func setClickThrough(_ enabled: Bool) {
        guard !isClosed else { return }
        ignoresMouseEvents = enabled
        updateImageOpacity()
        chrome.refreshButtons()
        onClickThroughChanged?()
    }

    private func updateImageOpacity() {
        surface.layer?.opacity = Float(ignoresMouseEvents && isHovered ? min(chosenOpacity, 0.25) : chosenOpacity)
    }

    func closePin() {
        guard !isClosed else { return }
        isClosed = true
        chrome.detach()
        orderOut(nil)
        onClose?()
    }

    func windowDidMove(_ notification: Notification) { chrome.layout() }
    func windowDidResize(_ notification: Notification) { chrome.layout() }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        isPositionLocked ? frame.size : frameSize
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let step: CGFloat = flags.contains(.shift) ? 12 : 1
        switch Int(event.keyCode) {
        case kVK_Escape: closePin()
        case kVK_ANSI_W where flags.contains(.command): closePin()
        case kVK_ANSI_C where flags.contains(.command): onCopy?()
        case kVK_LeftArrow where !isPositionLocked: setFrameOrigin(CGPoint(x: frame.minX - step, y: frame.minY))
        case kVK_RightArrow where !isPositionLocked: setFrameOrigin(CGPoint(x: frame.minX + step, y: frame.minY))
        case kVK_UpArrow where !isPositionLocked: setFrameOrigin(CGPoint(x: frame.minX, y: frame.minY + step))
        case kVK_DownArrow where !isPositionLocked: setFrameOrigin(CGPoint(x: frame.minX, y: frame.minY - step))
        default: break
        }
    }
}
