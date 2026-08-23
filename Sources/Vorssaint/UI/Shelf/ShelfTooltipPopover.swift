// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// A hand-rolled stand-in for `NSView.toolTip`, used only for Shelf tiles.
///
/// The Shelf panel is a `.nonactivatingPanel` so dragging a file into it
/// never steals focus from whatever app the file came from. AppKit's own
/// tooltip manager, it turns out, only displays over a key window (or an
/// active app) - it never has a reason to become either before the user
/// clicks something, so native tooltips silently never appeared. This
/// panel orders itself front without ever calling `makeKey()` or
/// activating the app, so it shows on a plain hover with none of that
/// side effect.
final class ShelfTooltipPopover {
    static let shared = ShelfTooltipPopover()

    private static let showDelay: TimeInterval = 1.0
    private static let margin: CGFloat = 6
    private static let gap: CGFloat = 6
    private static let maxWidth: CGFloat = 280
    private static let font = NSFont.systemFont(ofSize: 11)

    private var panel: NSPanel?
    private var textView: TextView?
    private var pendingWork: DispatchWorkItem?

    private init() {}

    /// `owner` anchors both the eventual position and a liveness check: the
    /// delay means real time passes between scheduling and showing, during
    /// which the Shelf can close without ever delivering `mouseExited` to
    /// `owner` (observed happening when the mouse leaves the panel and the
    /// panel hides in the same stroke) - so this re-checks `owner.window`
    /// is still visible right before showing, rather than trusting that a
    /// cancellation would have arrived by then.
    func scheduleShow(text: String, for owner: NSView) {
        cancelPending()
        let work = DispatchWorkItem { [weak self, weak owner] in
            guard let owner, owner.window?.isVisible == true else { return }
            self?.show(text: text, near: owner)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
    }

    func hide() {
        cancelPending()
        panel?.orderOut(nil)
    }

    private func cancelPending() {
        pendingWork?.cancel()
        pendingWork = nil
    }

    private func show(text: String, near owner: NSView) {
        guard let ownerWindow = owner.window else { return }
        let panel = ensurePanel()
        guard let textView else { return }

        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font]
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: Self.maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes)
        let textSize = NSSize(width: min(ceil(bounding.width) + 4, Self.maxWidth), height: ceil(bounding.height) + 4)
        let size = NSSize(width: textSize.width + Self.margin * 2, height: textSize.height + Self.margin * 2)

        textView.text = text
        textView.frame = NSRect(x: Self.margin, y: Self.margin, width: textSize.width, height: textSize.height)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)

        // Anchored to the tile's own frame, not the live cursor position:
        // the cursor may have moved anywhere in the time since the hover
        // that scheduled this (including onto a different app entirely).
        let ownerScreenFrame = ownerWindow.convertToScreen(owner.convert(owner.bounds, to: nil))
        let screen = ownerWindow.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        var origin = NSPoint(x: ownerScreenFrame.minX, y: ownerScreenFrame.minY - Self.gap - size.height)
        if origin.y < screen.minY {
            // Not enough room below the tile - flip above it instead of
            // letting the clamp below just pin it in place, which would
            // otherwise overlap the bottom of the tile it's describing.
            origin.y = ownerScreenFrame.maxY + Self.gap
        }
        origin.x = min(max(screen.minX, origin.x), screen.maxX - size.width)
        origin.y = min(max(screen.minY, origin.y), screen.maxY - size.height)

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFront(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let effect = NSVisualEffectView()
        effect.material = .toolTip
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 5
        effect.layer?.masksToBounds = true

        let textView = TextView()
        effect.addSubview(textView)
        panel.contentView = effect
        self.panel = panel
        self.textView = textView
        return panel
    }

    /// Draws its text directly rather than going through NSTextField/NSCell:
    /// the cell-based label this replaced kept rendering a truncated first
    /// portion of its own verified-correct stringValue (confirmed via
    /// stringValue, attributedStringValue and cell.title all matching, a
    /// frame sized wider than the measured text needed, and an explicit
    /// forced display pass - none of it changed what actually painted).
    /// NSString.draw(in:withAttributes:) has none of that cell machinery to
    /// go wrong.
    private final class TextView: NSView {
        var text: String = "" {
            didSet { needsDisplay = true }
        }

        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: ShelfTooltipPopover.font,
                .foregroundColor: NSColor.labelColor,
            ]
            (text as NSString).draw(in: bounds, withAttributes: attributes)
        }
    }
}
