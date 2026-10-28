// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Vorssaint's OpenBot card: a slim header and the mirrored OpenBot page.
/// The page itself is not a web view — it is the real OpenBot window's
/// content, streamed frame by frame and driven through the DevTools
/// protocol, so every part of the app behaves exactly as it does in its
/// own window.
struct OpenBotMirrorView: View {
    @ObservedObject private var service = OpenBotMirrorService.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            OpenBotSurfaceRepresentable()
        }
        .frame(minWidth: 480, minHeight: 380)
        .background {
            ZStack {
                HUDBackdrop(cornerRadius: 14)
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text("OpenBot")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .overlay(OpenBotDragHandle())
            if case .failed(let reason) = service.phase {
                Text(reason)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180, maxHeight: .infinity, alignment: .trailing)
            }
            Button {
                service.togglePin()
            } label: {
                Image(systemName: service.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(service.isPinned ? Color.accentColor : Color.secondary)
            Button {
                OpenBotMirrorService.shared.hide()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 12)
        .padding(.leading, 12)
        .frame(height: 34)
    }

    private var statusColor: Color {
        switch service.phase {
        case .streaming: .green
        case .launching, .connecting: .orange
        case .idle: .secondary
        case .failed: .red
        }
    }
}

/// The header's drag handle: the whole title row moves the window.
private struct OpenBotDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// The streamed page. Mouse, wheel and key events Vorssaint receives land in
/// the real OpenBot page through the DevTools protocol; the frames arrive on
/// the same channel and are drawn straight onto the layer.
final class OpenBotMirrorSurface: NSView {
    weak var service: OpenBotMirrorService?
    private var deviceWidth: Double = 0
    private var deviceHeight: Double = 0
    private var currentFrame: CGImage?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateTrackingArea()
    }

    override func layout() {
        super.layout()
        updateTrackingArea()
        service?.setViewport(width: Double(bounds.width), height: Double(bounds.height))
        if let image = currentFrame, deviceWidth > 0 {
            displayFrame(image, viewportWidth: deviceWidth, viewportHeight: deviceHeight)
        }
    }

    private var trackingAreaID: ObjectIdentifier?

    private func updateTrackingArea() {
        if let id = trackingAreaID, let area = trackingAreas.first(where: { ObjectIdentifier($0) == id }) {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingAreaID = ObjectIdentifier(area)
    }

    /// The newest frame from the mirrored page.
    func displayFrame(_ image: CGImage, viewportWidth: Double, viewportHeight: Double) {
        deviceWidth = viewportWidth
        deviceHeight = viewportHeight
        currentFrame = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        CATransaction.commit()
        needsDisplay = false
    }

    // MARK: - Coordinates

    /// DevTools input counts in CSS pixels from the page's top-left corner;
    /// AppKit hands out points from the view's bottom-left. The mirrored
    /// page is rendered at exactly this view's size, so the ratio is 1:1
    /// whenever the stream has caught up with the latest override.
    private var cssScale: Double {
        guard bounds.width > 0 else { return 1 }
        return deviceWidth > 0 ? deviceWidth / Double(bounds.width) : 1
    }

    private func cssPoint(from event: NSEvent) -> (x: Double, y: Double) {
        let location = convert(event.locationInWindow, from: nil)
        let scale = cssScale
        let x = Double(location.x) * scale
        let y = (Double(bounds.height) - Double(location.y)) * scale
        return (x, y)
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        let point = cssPoint(from: event)
        service?.sendMouseEvent("mouseMoved", x: point.x, y: point.y, button: "none")
    }

    override func mouseExited(with event: NSEvent) {
        let bounds = cssScale * Double(bounds.width)
        _ = bounds
        service?.sendMouseEvent("mouseMoved", x: -1, y: -1, button: "none")
    }

    private func press(_ event: NSEvent, down: Bool) {
        let point = cssPoint(from: event)
        let button = event.buttonNumber == 1 ? "right" : "left"
        service?.sendMouseEvent(down ? "mousePressed" : "mouseReleased",
                                x: point.x, y: point.y,
                                button: button,
                                clickCount: max(1, event.clickCount))
    }

    override func mouseDown(with event: NSEvent) { press(event, down: true) }
    override func mouseUp(with event: NSEvent) { press(event, down: false) }
    override func rightMouseDown(with event: NSEvent) { press(event, down: true) }
    override func rightMouseUp(with event: NSEvent) { press(event, down: false) }

    override func mouseDragged(with event: NSEvent) {
        let point = cssPoint(from: event)
        service?.sendMouseEvent("mouseMoved", x: point.x, y: point.y, button: "left")
    }

    override func scrollWheel(with event: NSEvent) {
        let point = cssPoint(from: event)
        // Line-based wheels report single lines; trackpads report points.
        let scale: CGFloat = abs(event.scrollingDeltaY) < 4 ? 40 : 1
        let deltaY = event.scrollingDeltaY * scale
        let deltaX = event.scrollingDeltaX * scale
        service?.sendMouseEvent("mouseWheel", x: point.x, y: point.y, button: "none",
                                deltaX: Double(deltaX), deltaY: Double(deltaY))
    }

    // MARK: - Keyboard

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘W closes Vorssaint's card; every other combination — copy, paste,
        // select all — belongs to the page and is dispatched to it.
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "w" {
            OpenBotMirrorService.shared.hide()
            return true
        }
        forwardKey(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        forwardKey(event)
    }

    private func forwardKey(_ event: NSEvent) {
        guard let service else { return }
        let modifiers = event.modifierFlags
        // Bare typing goes in as text; the page's own editor owns caret,
        // undo and input methods once the characters arrive.
        if modifiers.intersection([.command, .control, .option]).isEmpty,
           let characters = event.characters, !characters.isEmpty,
           let scalar = characters.unicodeScalars.first,
           scalar.value >= 32, scalar.value < 0xF700 {
            service.insertText(characters)
            return
        }
        let special: [(String, String, Int)] = [
            ("\r", "Enter", 13), ("\n", "Enter", 13), ("\t", "Tab", 9),
            (String(UnicodeScalar(0x1B)), "Escape", 27), (String(UnicodeScalar(0x7F)), "Backspace", 8),
        ]
        let characters = event.characters ?? ""
        if modifiers.intersection([.command, .control, .option]).isEmpty,
           let match = special.first(where: { $0.0 == characters }) {
            service.sendKeyEvent("rawKeyDown", key: match.1, code: match.1 == "Enter" ? "Enter" : match.1, keyCode: match.2)
            service.sendKeyEvent("keyUp", key: match.1, code: match.1 == "Enter" ? "Enter" : match.1, keyCode: match.2)
            return
        }
        // Modified keys: forward the bare key with its modifiers so copy,
        // paste and the app's own shortcuts run in the page.
        let key = event.charactersIgnoringModifiers ?? characters
        let upper = key.uppercased()
        let keyCode = Int(upper.first.map { scalarValue($0) } ?? 0)
        let code = keyCodeToCode(keyCode)
        service.sendKeyEvent("rawKeyDown", key: key, code: code, keyCode: keyCode)
        if !modifiers.contains(.command), !characters.isEmpty {
            service.insertText(characters)
        }
        service.sendKeyEvent("keyUp", key: key, code: code, keyCode: keyCode)
    }

    private func scalarValue(_ character: Character) -> Int {
        character.unicodeScalars.first.map { Int($0.value) } ?? 0
    }

    /// The USB code name Chromium expects for a letter or digit.
    private func keyCodeToCode(_ keyCode: Int) -> String {
        if keyCode >= 65, keyCode <= 90 {
            return "Key" + String(UnicodeScalar(UInt8(keyCode)))
        }
        if keyCode >= 48, keyCode <= 57 {
            return "Digit" + String(UnicodeScalar(UInt8(keyCode)))
        }
        return "Unidentified\(keyCode)"
    }
}

/// Bridges the SwiftUI card to the AppKit surface.
struct OpenBotSurfaceRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> OpenBotMirrorSurface {
        let view = OpenBotMirrorSurface(frame: .zero)
        view.service = OpenBotMirrorService.shared
        OpenBotMirrorService.shared.surface = view
        return view
    }

    func updateNSView(_ view: OpenBotMirrorSurface, context: Context) {
        if view.service == nil {
            view.service = OpenBotMirrorService.shared
            OpenBotMirrorService.shared.surface = view
        }
    }
}
