// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The translucent thumbnail that follows the pointer while a preview card is
/// dragged out of the panel. Only this stand-in moves during the drag; the real
/// window stays put until the pointer lifts, so a drag that is abandoned costs
/// the dragged app nothing.
///
/// Its top-left corner sits under the pointer, which is also where the real
/// window's top-left lands on drop — what the user aims with is what they get.
///
/// Main thread only, like the rest of the panel it belongs to: every entry
/// point is a SwiftUI gesture callback or the session teardown that follows one.
final class DockPreviewDragGhost {
    static let shared = DockPreviewDragGhost()

    private var window: NSWindow?
    private var size: CGSize = .zero
    private var isSnapped = false

    private static let scale: CGFloat = 0.22
    private static let opacity: CGFloat = 0.55
    /// The snapped stand-in covers a whole screen region, so it has to be
    /// fainter than the small free-floating one to stay readable over content.
    private static let snappedOpacity: CGFloat = 0.7

    private init() {}

    func begin(image: CGImage, at pointer: CGPoint) {
        end()

        let size = CGSize(width: CGFloat(image.width) * Self.scale,
                          height: CGFloat(image.height) * Self.scale)
        guard size.width >= 1, size.height >= 1 else { return }
        self.size = size

        let ghost = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: false)
        ghost.backgroundColor = .clear
        ghost.isOpaque = false
        ghost.hasShadow = true
        ghost.level = .popUpMenu
        ghost.ignoresMouseEvents = true
        ghost.animationBehavior = .none
        ghost.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let view = NSImageView(frame: CGRect(origin: .zero, size: size))
        view.image = NSImage(cgImage: image, size: size)
        view.imageScaling = .scaleAxesIndependently
        view.alphaValue = Self.opacity
        ghost.contentView = view

        window = ghost
        move(to: pointer)
        ghost.orderFrontRegardless()
    }

    /// `pointer` is an AppKit screen point; the ghost hangs below and right of
    /// it so the corner the drop uses is the one under the cursor.
    func move(to pointer: CGPoint) {
        guard let window else { return }
        if isSnapped {
            isSnapped = false
            window.animator().alphaValue = 1
        }
        window.setFrame(CGRect(origin: CGPoint(x: pointer.x, y: pointer.y - size.height),
                               size: size),
                        display: true)
    }

    /// Fills the frame the window would land in. The stand-in *is* the preview:
    /// growing it to the target says where the window goes without a second
    /// overlay to keep in step with the first.
    func snap(to frame: CGRect) {
        guard let window else { return }
        if !isSnapped {
            isSnapped = true
            window.animator().alphaValue = Self.snappedOpacity
        }
        window.setFrame(frame, display: true)
    }

    func end() {
        window?.orderOut(nil)
        window = nil
        size = .zero
        isSnapped = false
    }
}
