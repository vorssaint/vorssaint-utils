// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// An AppKit text view configured as a pure plain-text surface: no smart
/// quotes or dashes, no substitutions, no rich paste, with undo. SwiftUI's
/// editor cannot switch all of that off, and its TextEditor(text:selection:)
/// would cover the caret tracking below but needs macOS 15, a version past
/// this app's floor.
struct PlainTextEditor: NSViewRepresentable {
    /// Both shared with callers that overlay their own text on the editor,
    /// so a placeholder can be positioned from the same numbers as the
    /// first line rather than from literals that drift apart.
    /// `lineFragmentPadding` sits inside the inset and is set on the text
    /// container below rather than assumed, so this stays the source of
    /// the number instead of a copy of AppKit's default.
    static let defaultFontSize: CGFloat = 13
    static let lineFragmentPadding: CGFloat = 5

    /// The point size this editor draws at. Callers that overlay their own
    /// text pass the same number rather than the default, or the placeholder
    /// stops sitting on the first line as soon as the size is changed.
    var fontSize: CGFloat = PlainTextEditor.defaultFontSize

    /// Whether the keyboard is in a find bar's search field rather than in
    /// the text it searches, so Esc can put the search away before the pad.
    static func findBarHasKeyboard(in window: NSWindow?) -> Bool {
        guard let field = window?.firstResponder as? NSTextView, field.isFieldEditor,
              let control = field.delegate as? NSView else { return false }
        return sequence(first: control, next: \.superview).contains { view in
            guard let bar = (view as? NSScrollView)?.findBarView else { return false }
            return control.isDescendant(of: bar)
        }
    }

    @Binding var text: String
    /// Character offsets rather than String.Index: an index computed
    /// against one version of the text is undefined behavior to read back
    /// against another, and this binding outlives the edit that produced
    /// it. Offsets can simply be clamped by whoever reads them.
    var selectedRange: Binding<Range<Int>?>?
    /// Appearance is applied when the view is made, not on update, so
    /// these are configuration rather than state: a caller that derives
    /// one from something that changes will not see it re-applied.
    var textColor: NSColor?
    var textContainerInset: NSSize?
    /// Turns on AppKit's own find bar: the real Command-F, with its counter,
    /// its highlighting and Command-G, none of which is worth rewriting.
    var usesFindBar = false
    /// Handed the text view once, for callers that need to reach it later.
    var onCreate: ((NSTextView) -> Void)?

    init(text: Binding<String>,
         fontSize: CGFloat = PlainTextEditor.defaultFontSize,
         selectedRange: Binding<Range<Int>?>? = nil,
         textColor: NSColor? = nil,
         textContainerInset: NSSize? = nil,
         usesFindBar: Bool = false,
         onCreate: ((NSTextView) -> Void)? = nil) {
        self._text = text
        self.fontSize = fontSize
        self.selectedRange = selectedRange
        self.textColor = textColor
        self.textContainerInset = textContainerInset
        self.usesFindBar = usesFindBar
        self.onCreate = onCreate
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textContainer?.lineFragmentPadding = Self.lineFragmentPadding
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        if usesFindBar {
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
        }
        if let textColor {
            textView.textColor = textColor
        }
        if let textContainerInset {
            textView.textContainerInset = textContainerInset
        }
        textView.string = text
        // Delegate last: assigning .string posts a selection notification
        // synchronously, and makeNSView runs inside SwiftUI's update pass,
        // where writing state is undefined behavior.
        textView.delegate = context.coordinator
        onCreate?(textView)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Size is a preference and can change under a view that is already up,
        // so it is applied before the text guard below rather than after it.
        if textView.font?.pointSize != fontSize {
            textView.font = .systemFont(ofSize: fontSize)
        }
        guard textView.string != text, !textView.hasMarkedText() else { return }
        // Setting .string posts a selection notification, and answering it
        // here would write state from inside a view update.
        context.coordinator.isApplyingExternalText = true
        textView.string = text
        context.coordinator.isApplyingExternalText = false
        // Programmatic replaces (load, retention, restore) invalidate undo
        // entries recorded against the old storage; replaying one would
        // resurrect cleared text or throw a range exception.
        textView.undoManager?.removeAllActions()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: selectedRange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private let selectedRange: Binding<Range<Int>?>?
        var isApplyingExternalText = false

        init(text: Binding<String>, selectedRange: Binding<Range<Int>?>?) {
            self.text = text
            self.selectedRange = selectedRange
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText, let textView = notification.object as? NSTextView else { return }
            let current = textView.string
            if text.wrappedValue != current { text.wrappedValue = current }
            publishSelection(of: textView, in: current)
        }

        /// Publishes the caret only. Never writes the text binding: a caret
        /// move would then republish whatever the view currently holds,
        /// which for a caller that reloads its text out-of-band means
        /// writing stale content back over the fresh content.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalText,
                  selectedRange != nil,
                  let textView = notification.object as? NSTextView else { return }
            publishSelection(of: textView, in: textView.string)
        }

        private func publishSelection(of textView: NSTextView, in current: String) {
            guard let selectedRange else { return }
            // A selection that will not convert leaves the last known caret
            // alone, since nil here would read as "caret at the end".
            guard let converted = Range(textView.selectedRange(), in: current) else { return }
            selectedRange.wrappedValue =
                current.distance(from: current.startIndex, to: converted.lowerBound)
                    ..< current.distance(from: current.startIndex, to: converted.upperBound)
        }
    }
}
