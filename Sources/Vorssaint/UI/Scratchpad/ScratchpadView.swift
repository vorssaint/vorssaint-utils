// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct ScratchpadView: View {
    @ObservedObject private var service = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.scratchpadBackgroundOpacity) private var backgroundOpacity = 0.0
    private var text: ScratchpadFeatureStrings { FeatureStrings.scratchpad(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(text.pageTitle).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                ScratchpadDragHandle().frame(maxWidth: .infinity, minHeight: 30)
                Button(action: service.togglePin) {
                    Image(systemName: service.isPinned ? "pin.fill" : "pin").frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .help(service.isPinned ? text.closeOnClickOutside : text.keepOpen)
                .accessibilityLabel(service.isPinned ? text.closeOnClickOutside : text.keepOpen)
                Button(action: service.hide) { Image(systemName: "xmark.circle.fill").frame(width: 24, height: 24).contentShape(Rectangle()) }
                    .help(l10n.s.menuClose).accessibilityLabel(l10n.s.menuClose)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 32)
            ScratchpadWorkspace(island: false)
        }
        .frame(minWidth: 280, minHeight: 220)
        .background {
            ZStack {
                HUDBackdrop(cornerRadius: 14)
                Color(nsColor: .windowBackgroundColor)
                    .opacity(ScratchpadSupport.sanitizedBackgroundOpacity(backgroundOpacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(ScratchpadResizeOverlay())
        .onChange(of: service.keyboardCloseSelectedPadSerial) { _, _ in
            if let id = service.selectedPadID { _ = service.closePad(id) }
        }
    }
}

/// A transparent strip over the header that moves the whole panel when
/// dragged; everything below it stays free for text selection.
private struct ScratchpadDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView()
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {}

    final class DragHandleView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// An invisible border overlay that gives the borderless panel generous resize
/// hitboxes on all four edges and corners, keeps the resize cursors visible,
/// and enforces the minimum pad size during interactive dragging.
private struct ScratchpadResizeOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeBorderOverlayView {
        ResizeBorderOverlayView()
    }

    func updateNSView(_ nsView: ResizeBorderOverlayView, context: Context) {}

    final class ResizeBorderOverlayView: NSView {
        private let borderThickness: CGFloat = 6
        private let cornerSize: CGFloat = 12

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            guard bounds.width > cornerSize * 2, bounds.height > cornerSize * 2 else { return }

            let bottomLeft = NSRect(x: 0, y: 0, width: cornerSize, height: cornerSize)
            let bottomRight = NSRect(x: bounds.maxX - cornerSize, y: 0, width: cornerSize, height: cornerSize)
            let topLeft = NSRect(x: 0, y: bounds.maxY - cornerSize, width: cornerSize, height: cornerSize)
            let topRight = NSRect(x: bounds.maxX - cornerSize, y: bounds.maxY - cornerSize, width: cornerSize, height: cornerSize)

            let left = NSRect(x: 0, y: cornerSize, width: borderThickness, height: bounds.height - cornerSize * 2)
            let right = NSRect(x: bounds.maxX - borderThickness, y: cornerSize, width: borderThickness, height: bounds.height - cornerSize * 2)
            let bottom = NSRect(x: cornerSize, y: 0, width: bounds.width - cornerSize * 2, height: borderThickness)
            let top = NSRect(x: cornerSize, y: bounds.maxY - borderThickness, width: bounds.width - cornerSize * 2, height: borderThickness)

            addCursorRect(left, cursor: .resizeLeftRight)
            addCursorRect(right, cursor: .resizeLeftRight)
            addCursorRect(top, cursor: .resizeUpDown)
            addCursorRect(bottom, cursor: .resizeUpDown)

            addCursorRect(topLeft, cursor: .resizeLeftRight)
            addCursorRect(topRight, cursor: .resizeLeftRight)
            addCursorRect(bottomLeft, cursor: .resizeLeftRight)
            addCursorRect(bottomRight, cursor: .resizeLeftRight)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = superview != nil ? convert(point, from: superview) : convert(point, from: nil)
            guard bounds.contains(local) else { return nil }

            let isLeft = local.x <= borderThickness
            let isRight = local.x >= bounds.width - borderThickness
            let isBottom = local.y <= borderThickness
            let isTop = local.y >= bounds.height - borderThickness

            let isCornerLeft = local.x <= cornerSize
            let isCornerRight = local.x >= bounds.width - cornerSize
            let isCornerBottom = local.y <= cornerSize
            let isCornerTop = local.y >= bounds.height - cornerSize

            let isCorner = (isCornerLeft && (isCornerTop || isCornerBottom))
                || (isCornerRight && (isCornerTop || isCornerBottom))

            if isLeft || isRight || isBottom || isTop || isCorner {
                return self
            }
            return nil
        }

        private enum ResizeEdge {
            case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
        }

        private func resizeEdge(at point: NSPoint) -> ResizeEdge? {
            let isLeft = point.x <= borderThickness
            let isRight = point.x >= bounds.width - borderThickness
            let isBottom = point.y <= borderThickness
            let isTop = point.y >= bounds.height - borderThickness

            let isCornerLeft = point.x <= cornerSize
            let isCornerRight = point.x >= bounds.width - cornerSize
            let isCornerBottom = point.y <= cornerSize
            let isCornerTop = point.y >= bounds.height - cornerSize

            if isCornerLeft && isCornerTop { return .topLeft }
            if isCornerRight && isCornerTop { return .topRight }
            if isCornerLeft && isCornerBottom { return .bottomLeft }
            if isCornerRight && isCornerBottom { return .bottomRight }

            if isLeft { return .left }
            if isRight { return .right }
            if isTop { return .top }
            if isBottom { return .bottom }

            return nil
        }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard let window, let edge = resizeEdge(at: point) else {
                super.mouseDown(with: event)
                return
            }

            let initialFrame = window.frame
            let initialMouse = NSEvent.mouseLocation
            let minWidth: CGFloat = 280
            let minHeight: CGFloat = 220

            while true {
                guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
                if nextEvent.type == .leftMouseUp { break }

                let currentMouse = NSEvent.mouseLocation
                let deltaX = currentMouse.x - initialMouse.x
                let deltaY = currentMouse.y - initialMouse.y

                var newFrame = initialFrame

                switch edge {
                case .left:
                    let clampedDeltaX = min(deltaX, initialFrame.width - minWidth)
                    newFrame.origin.x = initialFrame.origin.x + clampedDeltaX
                    newFrame.size.width = initialFrame.width - clampedDeltaX

                case .right:
                    newFrame.size.width = max(minWidth, initialFrame.width + deltaX)

                case .top:
                    newFrame.size.height = max(minHeight, initialFrame.height + deltaY)

                case .bottom:
                    let clampedDeltaY = min(deltaY, initialFrame.height - minHeight)
                    newFrame.origin.y = initialFrame.origin.y + clampedDeltaY
                    newFrame.size.height = initialFrame.height - clampedDeltaY

                case .topLeft:
                    let clampedDeltaX = min(deltaX, initialFrame.width - minWidth)
                    newFrame.origin.x = initialFrame.origin.x + clampedDeltaX
                    newFrame.size.width = initialFrame.width - clampedDeltaX
                    newFrame.size.height = max(minHeight, initialFrame.height + deltaY)

                case .topRight:
                    newFrame.size.width = max(minWidth, initialFrame.width + deltaX)
                    newFrame.size.height = max(minHeight, initialFrame.height + deltaY)

                case .bottomLeft:
                    let clampedDeltaX = min(deltaX, initialFrame.width - minWidth)
                    let clampedDeltaY = min(deltaY, initialFrame.height - minHeight)
                    newFrame.origin.x = initialFrame.origin.x + clampedDeltaX
                    newFrame.size.width = initialFrame.width - clampedDeltaX
                    newFrame.origin.y = initialFrame.origin.y + clampedDeltaY
                    newFrame.size.height = initialFrame.height - clampedDeltaY

                case .bottomRight:
                    let clampedDeltaY = min(deltaY, initialFrame.height - minHeight)
                    newFrame.size.width = max(minWidth, initialFrame.width + deltaX)
                    newFrame.origin.y = initialFrame.origin.y + clampedDeltaY
                    newFrame.size.height = initialFrame.height - clampedDeltaY
                }

                window.setFrame(newFrame, display: true, animate: false)
            }
        }
    }
}
