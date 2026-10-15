// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// A file proxy, separate from the image's move gesture and click-through mode.
final class ScreenshotPinDragView: NSVisualEffectView, NSDraggingSource {
    private weak var pin: ScreenshotPinWindow?
    private var mouseDownEvent: NSEvent?
    private var keptAtStart = false

    init(pin: ScreenshotPinWindow) {
        self.pin = pin
        super.init(frame: CGRect(x: 0, y: 0, width: 100, height: 26))
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.masksToBounds = true
        let icon = NSImageView(frame: CGRect(x: 42, y: 5, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        icon.contentTintColor = .white
        addSubview(icon)
        for x: CGFloat in [17, 66] {
            let grip = NSView(frame: CGRect(x: x, y: 12, width: 17, height: 2))
            grip.wantsLayer = true
            grip.layer?.cornerRadius = 1
            grip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.65).cgColor
            addSubview(grip)
        }
        let title = ScreenshotPinStrings.localized(L10n.shared.language).drag
        toolTip = title
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { mouseDownEvent = event }

    override func mouseDragged(with event: NSEvent) {
        guard let initial = mouseDownEvent, let pin, !pin.isClosed else { return }
        let distance = hypot(event.locationInWindow.x - initial.locationInWindow.x,
                             event.locationInWindow.y - initial.locationInWindow.y)
        guard distance >= 4 else { return }
        mouseDownEvent = nil
        keptAtStart = initial.modifierFlags.contains(.option) || event.modifierFlags.contains(.option)
        let strings = FeatureStrings.screenshot(L10n.shared.language)
        let provider = ScreenshotPinFilePromise.make(image: pin.image, scale: pin.captureScale,
            fileName: ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date()))
        let item = NSDraggingItem(pasteboardWriter: provider)
        let preview = NSImage(cgImage: pin.image, size: CGSize(width: pin.frame.width, height: pin.frame.height))
        item.setDraggingFrame(CGRect(x: bounds.midX - 60, y: bounds.midY - 30, width: 120, height: 60), contents: preview)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        var modifiers = NSEvent.modifierFlags
        if keptAtStart { modifiers.insert(.option) }
        completeDrag(operation: operation, modifiers: modifiers)
    }

    func completeDrag(operation: NSDragOperation, modifiers: NSEvent.ModifierFlags) {
        mouseDownEvent = nil
        keptAtStart = false
        if operation.contains(.copy), !modifiers.contains(.option) { pin?.closePin() }
    }
}
