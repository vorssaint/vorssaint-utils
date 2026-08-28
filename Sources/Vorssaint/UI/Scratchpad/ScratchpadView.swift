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

    @State private var hoveredPadID: UUID?

    private var text: ScratchpadFeatureStrings { FeatureStrings.scratchpad(l10n.language) }
    private var isEmpty: Bool { service.text.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            editor
            footer
        }
        .frame(minWidth: 280, minHeight: 220)
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
        .overlay(ScratchpadResizeOverlay())
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
            // A borderless Menu takes every point its row can spare on macOS
            // 15, which left the tab strip beside it stuck at its old width
            // while the window grew and cut tab names for no reason (issue
            // #569). Pinned to its label, the strip gets the rest of the row.
            .fixedSize()
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
        let isHovered = hoveredPadID == pad.id
        let showClose = service.canClosePad && (isHovered || selected)
        return Button {
            service.selectPad(pad.id)
        } label: {
            HStack(spacing: 4) {
                Text(pad.name)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if showClose {
                    Button {
                        requestClose(pad)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(text.closePad)
                    .accessibilityLabel(text.closePad)
                }
            }
                .padding(.leading, 8)
                .padding(.trailing, showClose ? 4 : 8)
                .frame(minWidth: 46, maxWidth: 130)
                .frame(height: 24)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredPadID = pad.id
            } else if hoveredPadID == pad.id {
                hoveredPadID = nil
            }
        }
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
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        .padding(.trailing, 12)
        .frame(height: 34)
    }

    /// The editor's text inset, shared with the placeholder overlay below
    /// so the two cannot be moved independently.
    private static let editorInset = NSSize(width: 7, height: 2)

    private var editor: some View {
        ZStack {
            PlainTextEditor(text: $service.text,
                            textColor: .labelColor,
                            textContainerInset: Self.editorInset,
                            onCreate: { ScratchpadService.shared.registerTextView($0) })
                .opacity(service.isPreviewing ? 0 : 1)
                .allowsHitTesting(!service.isPreviewing)
                .accessibilityHidden(service.isPreviewing)
                .overlay(alignment: .topLeading) {
                    if isEmpty, !service.isPreviewing {
                        // NSTextView has no placeholder of its own; this sits at
                        // the exact spot of the first line and never takes clicks.
                        Text(text.placeholder)
                            .font(.system(size: PlainTextEditor.fontSize))
                            .foregroundStyle(.tertiary)
                            .padding(.leading,
                                     Self.editorInset.width + PlainTextEditor.lineFragmentPadding)
                            .padding(.top, Self.editorInset.height)
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
