// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct ScratchpadEditorPosition {
    var selection: NSRange
    var scroll: NSPoint
}

/// A native text view keeps Markdown as its storage. Presentation attributes
/// and hidden glyphs never enter the binding, pasteboard or undo history.
struct ScratchpadEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13
    var textColor: NSColor = .labelColor
    var sourceMode = false
    var position: ScratchpadEditorPosition?
    var onPosition: ((ScratchpadEditorPosition) -> Void)?
    var onCreate: ((NSTextView) -> Void)?
    var onFormattingChange: ((Set<ScratchpadMark>) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 5
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = TextView(frame: .zero, textContainer: container)
        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.usesFontPanel = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.textContainerInset = NSSize(width: 10, height: 10)
        view.string = text
        view.sourceMode = sourceMode
        view.delegate = context.coordinator
        view.layoutManager?.delegate = context.coordinator
        context.coordinator.view = view
        view.onLayout = { [weak coordinator = context.coordinator] in coordinator?.positionCheckboxes() }
        context.coordinator.refresh()
        if let position {
            let length = (text as NSString).length
            view.setSelectedRange(NSRange(location: min(position.selection.location, length),
                                         length: min(position.selection.length, max(0, length - position.selection.location))))
            DispatchQueue.main.async { scroll.contentView.scroll(to: position.scroll) }
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak coordinator = context.coordinator] _ in coordinator?.publishPosition() }
        onCreate?(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? TextView else { return }
        context.coordinator.parent = self
        view.sourceMode = sourceMode
        let changed = view.string != text
        if changed, !view.hasMarkedText() {
            context.coordinator.isUpdating = true
            let selection = view.selectedRange()
            view.string = text
            let length = (text as NSString).length
            view.setSelectedRange(NSRange(location: min(selection.location, length),
                                         length: min(selection.length, max(0, length - selection.location))))
            view.undoManager?.removeAllActions()
            context.coordinator.isUpdating = false
        }
        if !view.hasMarkedText() { context.coordinator.refresh() }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.publishPosition()
        if let observer = coordinator.scrollObserver { NotificationCenter.default.removeObserver(observer) }
        coordinator.view?.delegate = nil
        coordinator.view?.layoutManager?.delegate = nil
    }

    final class TextView: NSTextView {
        var sourceMode = false
        var onLayout: (() -> Void)?
        override func layout() { super.layout(); onLayout?() }

        override func keyDown(with event: NSEvent) {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if !hasMarkedText(), let coordinator = delegate as? Coordinator {
                if modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "l" {
                    coordinator.apply(ScratchpadSupport.edit(applying: .checklist, to: string, selection: selectedRange()))
                    return
                }
                if modifiers == .command, event.keyCode == 36,
                   let edit = ScratchpadMarkdown.toggleTask(in: string, at: selectedRange().location) {
                    coordinator.apply(edit)
                    return
                }
                if modifiers == .command, let key = event.charactersIgnoringModifiers?.lowercased(),
                   let mark = ["b": ScratchpadMark.bold, "i": .italic, "k": .link][key] {
                    coordinator.apply(ScratchpadSupport.edit(applying: mark, to: string, selection: selectedRange()))
                    return
                }
            }
            super.keyDown(with: event)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: ScratchpadEditor
        weak var view: TextView?
        var isUpdating = false
        var scrollObserver: NSObjectProtocol?
        private var analysis = ScratchpadMarkdown("")
        private var analyzedText: String?
        private var hidden: [NSRange] = []
        private var buttons: [NSButton] = []
        private var renderedAppearance: String?
        private var publishedMarks: Set<ScratchpadMark>?

        init(_ parent: ScratchpadEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let view else { return }
            parent.text = view.string
            if !view.hasMarkedText() { refresh() }
            publishPosition()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, view?.hasMarkedText() != true else { return }
            refresh()
            publishPosition()
        }

        func publishPosition() {
            guard !isUpdating, let view else { return }
            parent.onPosition?(.init(selection: view.selectedRange(),
                                     scroll: view.enclosingScrollView?.contentView.bounds.origin ?? .zero))
        }

        func refresh() {
            guard !isUpdating, let view, !view.hasMarkedText(), let storage = view.textStorage else { return }
            isUpdating = true
            defer { isUpdating = false }
            let textChanged = analyzedText != view.string
            if textChanged { analysis = ScratchpadMarkdown(view.string); analyzedText = view.string }
            let ns = view.string as NSString
            let appearance = "\(parent.sourceMode):\(parent.fontSize):\(parent.textColor.description)"
            if textChanged || renderedAppearance != appearance {
                renderedAppearance = appearance
                let undo = view.undoManager
                let undoEnabled = undo?.isUndoRegistrationEnabled == true
                if undoEnabled { undo?.disableUndoRegistration() }
                storage.beginEditing()
                let full = NSRange(location: 0, length: ns.length)
                let font = NSFont.systemFont(ofSize: parent.fontSize)
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacing = 7
                storage.setAttributes([.font: font, .foregroundColor: parent.textColor, .paragraphStyle: paragraph], range: full)
                view.appearance = parent.textColor == .white ? NSAppearance(named: .darkAqua) : nil
                view.insertionPointColor = parent.textColor
                view.typingAttributes = [.font: font, .foregroundColor: parent.textColor, .paragraphStyle: paragraph]
                if !parent.sourceMode {
                    for span in analysis.spans {
                        var styled = font
                        if let heading = span.heading {
                            styled = .systemFont(ofSize: parent.fontSize + CGFloat(max(2, 12 - heading * 2)), weight: .semibold)
                        }
                        if span.code || span.inline.contains(.code) {
                            styled = .monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
                            storage.addAttribute(.backgroundColor, value: parent.textColor.withAlphaComponent(0.05), range: span.range)
                        }
                        if span.inline.contains(.stronglyEmphasized) { styled = NSFontManager.shared.convert(styled, toHaveTrait: .boldFontMask) }
                        if span.inline.contains(.emphasized) { styled = NSFontManager.shared.convert(styled, toHaveTrait: .italicFontMask) }
                        storage.addAttribute(.font, value: styled, range: span.range)
                        if span.inline.contains(.strikethrough) { storage.addAttribute(.strikethroughStyle, value: 1, range: span.range) }
                        if span.quote { storage.addAttribute(.foregroundColor, value: parent.textColor.withAlphaComponent(0.65), range: span.range) }
                        if let link = span.link, ["http", "https", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                            storage.addAttribute(.link, value: link, range: span.range)
                        }
                    }
                    for task in analysis.tasks {
                        let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
                        style.firstLineHeadIndent = 22
                        style.headIndent = 22
                        storage.addAttribute(.paragraphStyle, value: style, range: task.line)
                        if task.checked {
                            storage.addAttributes([.strikethroughStyle: 1, .foregroundColor: parent.textColor.withAlphaComponent(0.55)], range: task.content)
                        }
                    }
                }
                storage.endEditing()
                if undoEnabled { undo?.enableUndoRegistration() }
            }
            let selection = view.selectedRange()
            let marks = analysis.activeMarks(at: selection)
            if publishedMarks != marks {
                publishedMarks = marks
                let callback = parent.onFormattingChange
                DispatchQueue.main.async { callback?(marks) }
            }
            let active = ns.lineRange(for: NSRange(location: min(selection.location, ns.length),
                                                 length: min(selection.length, max(0, ns.length - selection.location))))
            let taskMarkers = analysis.tasks.flatMap { [$0.prefix, $0.marker] }
            let newHidden = parent.sourceMode ? [] : analysis.markers.filter {
                taskMarkers.contains($0) || NSIntersectionRange($0, active).length == 0
            }
            if newHidden != hidden || textChanged {
                hidden = newHidden
                view.layoutManager?.invalidateGlyphs(forCharacterRange: NSRange(location: 0, length: ns.length), changeInLength: 0, actualCharacterRange: nil)
            }
            if textChanged || buttons.count != (parent.sourceMode ? 0 : analysis.tasks.count) {
                buttons.forEach { $0.removeFromSuperview() }
                buttons = []
                if !parent.sourceMode {
                    for (index, task) in analysis.tasks.enumerated() {
                        let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleCheckbox(_:)))
                        button.tag = index
                        button.state = task.checked ? .on : .off
                        button.setAccessibilityLabel(ns.substring(with: task.content))
                        view.addSubview(button)
                        buttons.append(button)
                    }
                }
            }
            positionCheckboxes()
        }

        func positionCheckboxes() {
            guard let view, let manager = view.layoutManager, view.textContainer != nil else { return }
            for (index, button) in buttons.enumerated() where index < analysis.tasks.count {
                let task = analysis.tasks[index]
                manager.ensureLayout(forCharacterRange: task.line)
                let empty = task.content.length == 0
                let character = empty ? task.prefix.location : task.content.location
                let glyph = manager.glyphIndexForCharacter(at: character)
                let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let location = manager.location(forGlyphAt: glyph)
                let origin = view.textContainerOrigin
                let ns = view.string as NSString
                let indent = ns.substring(with: NSRange(location: task.line.location, length: task.prefix.location - task.line.location))
                let font = NSFont.systemFont(ofSize: parent.fontSize)
                let gutter = empty ? 5 + (indent as NSString).size(withAttributes: [.font: font]).width : max(0, location.x - 22)
                button.frame = NSRect(x: origin.x + line.minX + gutter,
                                      y: origin.y + line.minY, width: 20, height: max(20, line.height))
                button.isHidden = parent.sourceMode
                button.state = task.checked ? .on : .off
            }
        }

        @objc private func toggleCheckbox(_ sender: NSButton) {
            guard let view, sender.tag < analysis.tasks.count,
                  let edit = ScratchpadMarkdown.toggleTask(in: view.string, at: analysis.tasks[sender.tag].content.location) else { return }
            let selection = view.selectedRange()
            apply(.init(range: edit.range, replacement: edit.replacement, selection: selection))
        }

        func apply(_ edit: ScratchpadMarkEdit) {
            guard let view, !view.hasMarkedText(), NSMaxRange(edit.range) <= (view.string as NSString).length else { return }
            view.window?.makeFirstResponder(view)
            // insertText performs its own shouldChangeText check. Calling it
            // here too records a deletion twice in the native Undo history.
            view.insertText(edit.replacement, replacementRange: edit.range)
            view.setSelectedRange(edit.selection)
            view.scrollRangeToVisible(edit.selection)
        }

        @discardableResult
        func applyChecklist(_ action: ScratchpadMarkdown.ChecklistAction) -> Bool {
            guard let view, !view.hasMarkedText(),
                  let edit = analysis.checklistEdit(action, in: view.string, selection: view.selectedRange()) else { return false }
            view.breakUndoCoalescing()
            apply(edit)
            view.breakUndoCoalescing()
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            let edit: ScratchpadMarkEdit?
            switch selector {
            case #selector(NSTextView.deleteBackward(_:)):
                let selection = textView.selectedRange()
                let prefixes = analysis.tasks.map {
                    NSRange(location: $0.prefix.location, length: NSMaxRange($0.marker) - $0.prefix.location)
                } + analysis.bullets.map(\.prefix)
                guard !parent.sourceMode, selection.length == 0,
                      let prefix = prefixes.first(where: { NSMaxRange($0) == selection.location }) else { return false }
                edit = .init(range: prefix, replacement: "", selection: NSRange(location: prefix.location, length: 0))
            case #selector(NSTextView.insertNewline(_:)):
                edit = ScratchpadMarkdown.continueList(in: textView.string, selection: textView.selectedRange())
            case #selector(NSTextView.insertTab(_:)), #selector(NSTextView.insertBacktab(_:)):
                edit = ScratchpadMarkdown.indentList(in: textView.string, selection: textView.selectedRange(),
                                                    outdent: selector == #selector(NSTextView.insertBacktab(_:)))
            default: return false
            }
            guard let edit else { return false }
            apply(edit)
            return true
        }

        func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                           properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                           font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
            guard !hidden.isEmpty || !parent.sourceMode && !analysis.bullets.isEmpty else { return 0 }
            var output = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
            var flags = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
            var bulletCharacter: UniChar = 0x2022
            var bulletGlyph = CGGlyph()
            CTFontGetGlyphsForCharacters(font, &bulletCharacter, &bulletGlyph, 1)
            for index in 0..<glyphRange.length {
                if hidden.contains(where: { NSLocationInRange(characterIndexes[index], $0) }) {
                    output[index] = 0
                    flags[index].insert(.null)
                } else if !parent.sourceMode, analysis.bullets.contains(where: { $0.prefix.location == characterIndexes[index] }) {
                    output[index] = bulletGlyph
                }
            }
            layoutManager.setGlyphs(output, properties: flags, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
            return glyphRange.length
        }
    }
}
