// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Draws inferred closing brackets without putting them in the editable text or undo history.
struct CommandBarGhostBrackets: NSViewRepresentable {
    let query: String
    let suffix: String

    /// Uses the native editor's character geometry so the hint follows horizontal scrolling.
    func makeNSView(context: Context) -> GhostView {
        GhostView()
    }

    /// Repaints after SwiftUI has passed the latest query to the native field.
    func updateNSView(_ view: GhostView, context: Context) {
        view.query = query
        view.suffix = suffix
        view.needsDisplay = true
        DispatchQueue.main.async { [weak view] in view?.needsDisplay = true }
    }

    final class GhostView: NSView {
        var query = ""
        var suffix = ""
        private var observers: [NSObjectProtocol] = []

        /// Redraws when typing, caret movement, or field-editor scrolling changes text geometry.
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setAccessibilityElement(false)
            for name in [
                NSText.didChangeNotification, NSTextView.didChangeSelectionNotification,
                NSView.boundsDidChangeNotification,
            ] {
                observers.append(
                    NotificationCenter.default.addObserver(
                        forName: name, object: nil, queue: .main
                    ) { [weak self] notification in
                        guard let self, !suffix.isEmpty, let window,
                            let source = notification.object as? NSView, source.window === window
                        else { return }
                        needsDisplay = true
                    })
            }
        }

        /// This view is only constructed programmatically.
        required init?(coder: NSCoder) { nil }

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }

        /// Leaves selection, clicks and drag gestures entirely to the search field.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// Positions ghost text at the actual end of the field editor's laid-out input.
        override func draw(_ dirtyRect: NSRect) {
            guard !suffix.isEmpty, let window,
                let editor = window.firstResponder as? NSTextView,
                editor.string == query, !editor.hasMarkedText()
            else { return }
            // A trailing equals sign is accepted by the parser, but cannot have an
            // inline insertion hint without covering real text. The answer row
            // still shows the completed expression in that case.
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("=") else { return }
            let end = NSRange(location: (query as NSString).length, length: 0)
            let screenRect = editor.firstRect(forCharacterRange: end, actualRange: nil)
            let caret = convert(window.convertFromScreen(screenRect), from: nil)
            let text = NSAttributedString(
                string: suffix,
                attributes: [
                    .font: editor.font ?? NSFont.systemFont(ofSize: 16),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ])
            NSGraphicsContext.saveGraphicsState()
            bounds.clip()
            text.draw(
                at: NSPoint(
                    x: caret.maxX + 1,
                    y: caret.midY - text.size().height / 2))
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
