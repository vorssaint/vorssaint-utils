// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The scratchpad card: a slim header, named tabs, the plain-text editor and a
/// quiet footer with an on-demand formatted preview and file actions.
struct ScratchpadView: View {
    @ObservedObject private var service = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.scratchpadBackgroundOpacity) private var backgroundOpacity = 0.0
    @State private var copied = false
    @State private var dialog: ScratchpadDialog?
    @State private var renameDraft = ""

    private var text: ScratchpadFeatureStrings { FeatureStrings.scratchpad(l10n.language) }
    private var isEmpty: Bool { service.text.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            editor
            footer
        }
        .background {
            ZStack {
                HUDBackdrop(cornerRadius: 14)
                Color(nsColor: .windowBackgroundColor)
                    .opacity(ScratchpadSupport.sanitizedBackgroundOpacity(backgroundOpacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .alert(dialogTitle, isPresented: dialogIsPresented) {
            switch dialog {
            case .rename(let pad):
                TextField(pad.name, text: $renameDraft)
                Button(text.cancel, role: .cancel) { dismissDialog() }
                Button(text.saveName) {
                    service.renamePad(pad.id, to: renameDraft)
                    dismissDialog()
                }
            case .close(let pad):
                Button(text.cancel, role: .cancel) { dismissDialog() }
                Button(text.closePad, role: .destructive) {
                    _ = service.closePad(pad.id)
                    dismissDialog()
                }
            case nil:
                EmptyView()
            }
        } message: {
            if case .close(let pad) = dialog {
                Text(String(format: text.deletePadMessageFormat, pad.name))
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(service.pads) { pad in
                            tabButton(pad)
                                .id(pad.id)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    guard let selected = service.selectedPadID else { return }
                    proxy.scrollTo(selected, anchor: .center)
                }
                .onChange(of: service.selectedPadID) { _, selected in
                    guard let selected else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(selected, anchor: .center)
                    }
                }
            }

            Button {
                service.createPad(defaultName: text.pageTitle)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!service.canCreatePad)
            .help(service.canCreatePad
                ? text.newPad
                : String(format: text.padLimitFormat, ScratchpadDocument.maximumPadCount))
            .accessibilityLabel(text.newPad)

            Menu {
                if let selectedPad {
                    Button(text.renamePad) { presentRename(selectedPad) }
                    Button(text.closePad, role: .destructive) { requestClose(selectedPad) }
                        .disabled(!service.canClosePad)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(text.padActions)
            .accessibilityLabel(text.padActions)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }

    private func tabButton(_ pad: ScratchpadPad) -> some View {
        let selected = service.selectedPadID == pad.id
        return Button {
            service.selectPad(pad.id)
        } label: {
            Text(pad.name)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 46, maxWidth: 120)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(text.renamePad) { presentRename(pad) }
            Button(text.closePad, role: .destructive) { requestClose(pad) }
                .disabled(!service.canClosePad)
        }
        .accessibilityLabel(pad.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var selectedPad: ScratchpadPad? {
        service.pads.first(where: { $0.id == service.selectedPadID })
    }

    private var dialogTitle: String {
        switch dialog {
        case .rename: return text.renamePad
        case .close: return text.closePad
        case nil: return ""
        }
    }

    private var dialogIsPresented: Binding<Bool> {
        Binding(
            get: { dialog != nil },
            set: { if !$0 { dismissDialog() } }
        )
    }

    private func presentRename(_ pad: ScratchpadPad) {
        renameDraft = pad.name
        dialog = .rename(pad)
        service.setModalInteractionActive(true)
    }

    private func requestClose(_ pad: ScratchpadPad) {
        guard service.canClosePad else { return }
        if !ScratchpadSupport.requiresCloseConfirmation(pad) {
            _ = service.closePad(pad.id)
        } else {
            dialog = .close(pad)
            service.setModalInteractionActive(true)
        }
    }

    private func dismissDialog() {
        dialog = nil
        service.setModalInteractionActive(false)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(text.pageTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .overlay(ScratchpadDragHandle())
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
            .help(service.isPinned ? text.closeOnClickOutside : text.keepOpen)
            .accessibilityLabel(service.isPinned ? text.closeOnClickOutside : text.keepOpen)
            Button {
                ScratchpadService.shared.hide()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuClose)
            .accessibilityLabel(l10n.s.menuClose)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var editor: some View {
        ZStack {
            PlainTextEditor(text: $service.text)
                .opacity(service.isPreviewing ? 0 : 1)
                .allowsHitTesting(!service.isPreviewing)
                .accessibilityHidden(service.isPreviewing)
                .overlay(alignment: .topLeading) {
                    if isEmpty, !service.isPreviewing {
                        // NSTextView has no placeholder of its own; this sits at
                        // the exact spot of the first line and never takes clicks.
                        Text(text.placeholder)
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 12)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                }

            if service.isPreviewing {
                MarkdownPreview(blocks: ScratchpadSupport.markdownPreview(service.text))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            footerButton(service.isPreviewing ? "pencil" : "eye",
                         service.isPreviewing ? text.editText : text.previewFormatting,
                         tint: service.isPreviewing ? .accentColor : nil) {
                service.togglePreview()
            }
            footerButton(copied ? "checkmark" : "doc.on.doc",
                         copied ? text.copied : text.copyAll,
                         tint: copied ? .green : nil) {
                service.copyAll()
                withAnimation(.easeOut(duration: 0.15)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeOut(duration: 0.2)) { copied = false }
                }
            }
            footerButton("square.and.arrow.down", text.exportAction) {
                service.exportText(suggestedName:
                    ScratchpadSupport.exportFileName(title: service.selectedPadName, date: Date()))
            }
            Spacer()
            footerButton("trash", text.clearAction) {
                service.clear()
            }
        }
        .disabled(isEmpty)
        .opacity(isEmpty ? 0.5 : 1)
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private func footerButton(_ symbol: String,
                              _ label: String,
                              tint: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private enum ScratchpadDialog {
    case rename(ScratchpadPad)
    case close(ScratchpadPad)
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

/// A selectable native preview. NSTextView keeps Markdown links interactive in
/// the nonactivating scratchpad panel, where SwiftUI's Text link handling does
/// not receive clicks reliably.
private struct MarkdownPreview: NSViewRepresentable {
    let blocks: [ScratchpadMarkdownBlock]

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 7, height: 2)
        textView.linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor]
        textView.textStorage?.setAttributedString(Self.rendered(blocks))
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let content = Self.rendered(blocks)
        guard !textView.attributedString().isEqual(to: content) else { return }
        textView.textStorage?.setAttributedString(content)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private static func rendered(_ blocks: [ScratchpadMarkdownBlock]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                let sameContainer = block.containerID != nil
                    && block.containerID == blocks[index - 1].containerID
                result.append(NSAttributedString(string: sameContainer ? "\n" : "\n\n"))
            }
            result.append(rendered(block))
        }
        return result
    }

    private static func rendered(_ block: ScratchpadMarkdownBlock) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        var font = NSFont.systemFont(ofSize: 13)
        var color = NSColor.labelColor
        var prefix = ""
        var text = block.text
        text.presentationIntent = nil

        switch block.kind {
        case .heading(let level):
            let size: CGFloat = level == 1 ? 18 : (level == 2 ? 16 : 14)
            font = .systemFont(ofSize: size, weight: .semibold)
        case .unorderedListItem(let depth):
            prefix = String(repeating: "  ", count: depth - 1) + "• "
        case .orderedListItem(let ordinal, let depth):
            prefix = String(repeating: "  ", count: depth - 1) + "\(ordinal). "
        case .quote(let depth):
            prefix = String(repeating: "  ", count: depth - 1) + "▏ "
            color = .secondaryLabelColor
        case .code:
            font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        case .thematicBreak:
            text = AttributedString(String(repeating: "─", count: 24))
            color = .secondaryLabelColor
        case .paragraph:
            break
        }

        let result = NSMutableAttributedString()
        if !prefix.isEmpty {
            result.append(NSAttributedString(string: prefix, attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]))
        }

        let content = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let fullRange = NSRange(location: 0, length: content.length)
        content.removeAttribute(NSAttributedString.Key("NSPresentationIntent"), range: fullRange)
        content.addAttributes([
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ], range: fullRange)
        if block.kind == .code {
            content.addAttribute(.backgroundColor,
                                 value: NSColor.labelColor.withAlphaComponent(0.07),
                                 range: fullRange)
        }
        applyInlineFormatting(to: content, baseFont: font)
        result.append(content)
        return result
    }

    private static func applyInlineFormatting(to content: NSMutableAttributedString,
                                              baseFont: NSFont) {
        let fullRange = NSRange(location: 0, length: content.length)
        var intents: [(InlinePresentationIntent, NSRange)] = []
        content.enumerateAttribute(.inlinePresentationIntent, in: fullRange) { value, range, _ in
            guard let rawValue = (value as? NSNumber)?.uintValue else { return }
            intents.append((InlinePresentationIntent(rawValue: rawValue), range))
        }

        for (intent, range) in intents {
            var font = intent.contains(.code)
                ? NSFont.monospacedSystemFont(ofSize: max(12, baseFont.pointSize - 1), weight: .regular)
                : baseFont
            if intent.contains(.stronglyEmphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if intent.contains(.emphasized) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            content.addAttribute(.font, value: font, range: range)
            if intent.contains(.code) {
                content.addAttribute(.backgroundColor,
                                     value: NSColor.labelColor.withAlphaComponent(0.07),
                                     range: range)
            }
            if intent.contains(.strikethrough) {
                content.addAttribute(.strikethroughStyle,
                                     value: NSUnderlineStyle.single.rawValue,
                                     range: range)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView,
                      clickedOnLink link: Any,
                      at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            return NSWorkspace.shared.open(url)
        }
    }
}

/// An AppKit text view configured as a pure plain-text surface: no smart
/// quotes or dashes, no substitutions, no rich paste, with undo. SwiftUI's
/// editor cannot switch all of that off.
private struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
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
        textView.textContainerInset = NSSize(width: 7, height: 2)
        textView.string = text
        ScratchpadService.shared.registerTextView(textView)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView,
              textView.string != text,
              !textView.hasMarkedText() else { return }
        textView.string = text
        // Programmatic replaces (load, retention, restore) invalidate undo
        // entries recorded against the old storage; replaying one would
        // resurrect cleared text or throw a range exception.
        textView.undoManager?.removeAllActions()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
