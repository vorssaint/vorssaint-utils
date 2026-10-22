// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import AppKit
import SwiftUI

struct HighlightingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 16, weight: .regular)
    var highlightRange: NSRange? = nil
    var cueColor: NSColor = NSColor.systemYellow
    var cueAlpha: CGFloat = 0.8
    @Binding var caretPosition: Int?
    @Binding var editorCaretPosition: Int
    var cueToInsert: Binding<String?>? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = PrompterScriptTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = font
        textView.delegate = context.coordinator
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        context.coordinator.textView = textView

        textView.string = text
        context.coordinator.applyHighlighting(textView)
        updateWritingDirection(textView, text: text)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if let cue = cueToInsert?.wrappedValue {
            let insertion = " [\(cue)] "
            textView.insertText(insertion, replacementRange: textView.selectedRange())
            self.text = textView.string
            context.coordinator.applyHighlighting(textView)
            DispatchQueue.main.async {
                self.cueToInsert?.wrappedValue = nil
            }
        }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.applyHighlighting(textView)
        }
        if context.coordinator.applyConfigurationIfNeeded(to: textView) {
            context.coordinator.applyHighlighting(textView)
        }
        updateWritingDirection(textView, text: text)

        if let range = highlightRange, range.location + range.length <= (textView.string as NSString).length {
            context.coordinator.applyBumpHighlight(textView, range: range)
        }

        if let pos = caretPosition, pos <= (textView.string as NSString).length {
            let caretRange = NSRange(location: pos, length: 0)
            textView.setSelectedRange(caretRange)
            textView.scrollRangeToVisible(caretRange)
            DispatchQueue.main.async {
                self.caretPosition = nil
            }
        }
    }

    private func updateWritingDirection(_ textView: NSTextView, text: String) {
        switch textBaseDirection(in: text) {
        case .rightToLeft:
            textView.baseWritingDirection = .rightToLeft
        case .leftToRight:
            textView.baseWritingDirection = .leftToRight
        case .natural:
            textView.baseWritingDirection = .natural
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightingTextEditor
        weak var textView: NSTextView?

        private static let annotationPattern = try? NSRegularExpression(
            pattern: "\\[[^\\]]+\\]",
            options: []
        )

        init(_ parent: HighlightingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.updateWritingDirection(textView, text: textView.string)
            applyHighlighting(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let pos = textView.selectedRange().location
            if parent.editorCaretPosition != pos {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.editorCaretPosition = pos
                }
            }
        }

        private var bumpTimer: Timer?
        private var lastFont: NSFont?
        private var lastCueColor: NSColor?
        private var lastCueAlpha: CGFloat?

        @discardableResult
        func applyConfigurationIfNeeded(to textView: NSTextView) -> Bool {
            textView.font = parent.font
            guard lastFont != parent.font || lastCueColor != parent.cueColor || lastCueAlpha != parent.cueAlpha else {
                return false
            }
            lastFont = parent.font
            lastCueColor = parent.cueColor
            lastCueAlpha = parent.cueAlpha
            return true
        }

        func applyBumpHighlight(_ textView: NSTextView, range: NSRange) {
            guard let textStorage = textView.textStorage else { return }
            guard range.length > 0, range.location + range.length <= textStorage.length else { return }

            let bumpColor = NSColor.controlAccentColor.withAlphaComponent(0.15)
            textStorage.beginEditing()
            textStorage.addAttribute(.backgroundColor, value: bumpColor, range: range)
            textStorage.endEditing()

            bumpTimer?.invalidate()
            bumpTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.applyHighlighting(textView)
            }
        }

        func applyHighlighting(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let text = textStorage.string
            let selectedRanges = textView.selectedRanges

            // Disable undo registration while applying styling so user's undo stack isn't polluted
            textView.undoManager?.disableUndoRegistration()
            textStorage.beginEditing()
            let defaultAttributes: [NSAttributedString.Key: Any] = [
                .font: parent.font,
                .foregroundColor: NSColor.labelColor
            ]
            textStorage.setAttributes(defaultAttributes, range: fullRange)

            if let pattern = Self.annotationPattern {
                let matches = pattern.matches(in: text, options: [], range: fullRange)
                for match in matches {
                    let cueCol = parent.cueColor.withAlphaComponent(parent.cueAlpha)
                    let annotationAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFontManager.shared.convert(parent.font, toHaveTrait: .italicFontMask),
                        .foregroundColor: cueCol,
                        .backgroundColor: cueCol.withAlphaComponent(parent.cueAlpha * 0.15)
                    ]
                    textStorage.addAttributes(annotationAttributes, range: match.range)
                }
            }

            textStorage.endEditing()
            textView.undoManager?.enableUndoRegistration()
            textView.selectedRanges = selectedRanges
        }
    }
}

/// A dedicated NSTextView subclass ensuring standard editing shortcuts (Undo, Redo, Cut, Copy, Paste, Select All)
/// execute reliably in auxiliary windows, sheets, and embedded panels.
final class PrompterScriptTextView: NSTextView {
    override var allowsUndo: Bool {
        get { true }
        set { super.allowsUndo = newValue }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z":
                if let um = undoManager, um.canUndo {
                    um.undo()
                    return true
                }
            case "x":
                cut(nil)
                return true
            case "c":
                copy(nil)
                return true
            case "v":
                paste(nil)
                return true
            case "a":
                selectAll(nil)
                return true
            default:
                break
            }
        } else if flags == [.command, .shift] {
            if event.charactersIgnoringModifiers?.lowercased() == "z" {
                if let um = undoManager, um.canRedo {
                    um.redo()
                    return true
                }
            }
        }

        return super.performKeyEquivalent(with: event)
    }
}
