// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A plain-text NSTextView bridge that also exposes the current selection.
/// SwiftUI's own TextEditor(text:selection:) would do this, but that
/// initializer and the TextSelection type both need macOS 15; this app
/// targets macOS 14, so callers that need cursor position use this
/// instead. Disables the OS's automatic text substitutions (quotes,
/// dashes, spelling correction) since a caller tracking cursor position
/// for programmatic token insertion cannot afford autocorrect silently
/// rewriting what the user typed.
struct SelectableTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: Range<String.Index>?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.string = text
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView,
              textView.string != text,
              !textView.hasMarkedText() else { return }
        textView.string = text
        textView.undoManager?.removeAllActions()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private let selectedRange: Binding<Range<String.Index>?>

        init(text: Binding<String>, selectedRange: Binding<Range<String.Index>?>) {
            self.text = text
            self.selectedRange = selectedRange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            selectedRange.wrappedValue = Range(textView.selectedRange(), in: text.wrappedValue)
        }
    }
}
