// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The preview pane's text, as an AppKit text view. SwiftUI's selectable
/// `Text` lays the whole string out before it can draw, and a 20 KB entry
/// costs a visible pause every time the selection lands on it; TextKit lays
/// out what is on screen and the rest as it scrolls. Read only, selectable,
/// so ⌘C on a fragment keeps working.
struct ClipboardTextPreview: NSViewRepresentable {
    let text: String
    var font: NSFont = .systemFont(ofSize: 12)

    /// The font last applied. The text view's own `font` reads the first
    /// character, which a fallback font replaces for emoji or CJK text.
    final class Coordinator {
        var font: NSFont?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = font
        context.coordinator.font = font
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.textContainer?.lineFragmentPadding = 4
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.scroll(.zero)
        }
        // Setting the font restyles the whole text, so only a new font does
        // it, after any new text so all of that text takes it too.
        if context.coordinator.font != font {
            textView.font = font
            context.coordinator.font = font
        }
    }
}
