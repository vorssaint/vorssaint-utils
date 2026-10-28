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
    @AppStorage(DefaultsKey.scratchpadTextSize) private var storedTextSize = ScratchpadSupport.defaultTextSize
    @State private var copied = false
    @State private var dialog: ScratchpadDialog?
    @State private var renameDraft = ""

    @State private var hoveredPadID: UUID?

    private var text: ScratchpadFeatureStrings { FeatureStrings.scratchpad(l10n.language) }
    private var isEmpty: Bool { service.text.isEmpty }
    private var textSize: CGFloat { CGFloat(ScratchpadSupport.sanitizedTextSize(storedTextSize)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            if service.saveFailed {
                Label(text.saveFailed, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
            editor
            if service.marksExpanded, !service.isPreviewing { formatBar }
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
        .onChange(of: service.keyboardCloseSelectedPadSerial) { _, _ in
            guard let selectedPad else { return }
            requestClose(selectedPad)
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
                            fontSize: textSize,
                            textColor: .labelColor,
                            textContainerInset: Self.editorInset,
                            usesFindBar: true,
                            completesTaskBoxes: true,
                            continuesLists: true,
                            onCommandReturn: { service.togglePreview() },
                            isActive: !service.isPreviewing,
                            onCreate: { ScratchpadService.shared.registerTextView($0) })
                .opacity(service.isPreviewing ? 0 : 1)
                .allowsHitTesting(!service.isPreviewing)
                .accessibilityHidden(service.isPreviewing)
                .overlay(alignment: .topLeading) {
                    if isEmpty, !service.isPreviewing {
                        // NSTextView has no placeholder of its own; this sits at
                        // the exact spot of the first line and never takes clicks.
                        Text(text.placeholder)
                            .font(.system(size: textSize))
                            .foregroundStyle(.tertiary)
                            .padding(.leading,
                                     Self.editorInset.width + PlainTextEditor.lineFragmentPadding)
                            .padding(.top, Self.editorInset.height)
                            .allowsHitTesting(false)
                    }
                }

            if service.isPreviewing {
                MarkdownPreview(blocks: ScratchpadSupport.markdownPreview(service.text),
                                baseSize: textSize,
                                taskStates: (done: text.taskDone, notDone: text.taskNotDone),
                                onToggleTask: { service.toggleTask(box: $0) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var formatBar: some View {
        ScratchpadFormatBar(style: .pad)
            .padding(.horizontal, 12)
            .frame(height: 30)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            // Outside the disabled group below: an empty pad is exactly where
            // someone reaches for a heading, and the chip is how they find one.
            footerButton("textformat", text.formatMarks,
                         tint: service.marksExpanded ? .accentColor : nil) {
                withAnimation(.easeOut(duration: 0.15)) { service.toggleMarks() }
            }
            .disabled(service.isPreviewing)

            Group {
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
        }
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
/// Shared with the island's page, which shows the same formatted reading.
struct MarkdownPreview: NSViewRepresentable {
    let blocks: [ScratchpadMarkdownBlock]
    var baseSize: CGFloat = PlainTextEditor.defaultFontSize
    /// How a task's checkbox tells VoiceOver it is done or not.
    let taskStates: (done: String, notDone: String)
    /// Called with the text offset of the box whose checkbox is clicked; the
    /// owner edits the text, and the preview follows from it.
    var onToggleTask: ((Int) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        // The same text view `scrollableTextView()` makes, as the subclass that
        // answers a click on a checkbox and points its cursor at it.
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let textView = TaskPreviewTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        textView.onToggleTask = onToggleTask
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 7, height: 2)
        textView.linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor]
        context.coordinator.show(blocks, base: baseSize, taskStates: taskStates, in: textView)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.onToggleTask = onToggleTask
        (textView as? TaskPreviewTextView)?.onToggleTask = onToggleTask
        context.coordinator.show(blocks, base: baseSize, taskStates: taskStates, in: textView)
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.onToggleTask = onToggleTask
        return coordinator
    }

    /// Where a list item's text starts, which is where the items nested under
    /// it start. `indented` marks an item placed by paragraph indents, a task
    /// or an item under one, rather than by the leading spaces bullets use.
    private struct ListLevel {
        let column: CGFloat
        let indented: Bool
    }

    private static func rendered(_ blocks: [ScratchpadMarkdownBlock],
                                 base: CGFloat,
                                 taskStates: (done: String, notDone: String)) -> NSAttributedString {
        let result = NSMutableAttributedString()
        // The latest item at each depth of the list being drawn.
        var levels: [ListLevel] = []
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                let sameContainer = block.containerID != nil
                    && block.containerID == blocks[index - 1].containerID
                result.append(NSAttributedString(string: sameContainer ? "\n" : "\n\n"))
                if !sameContainer { levels = [] }
            }
            result.append(rendered(block, base: base, taskStates: taskStates, levels: &levels))
        }
        return result
    }

    private static func rendered(_ block: ScratchpadMarkdownBlock,
                                 base: CGFloat,
                                 taskStates: (done: String, notDone: String),
                                 levels: inout [ListLevel]) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        var font = NSFont.systemFont(ofSize: base)
        var color = NSColor.labelColor
        var prefix = ""
        var marker = ""
        var listDepth = 0
        var checkbox: (checked: Bool, box: Int)?
        let boxSize = base + 3
        var text = block.text
        text.presentationIntent = nil

        switch block.kind {
        case .heading(let level):
            // Steps above the body rather than fixed points, so the
            // document keeps its shape at whatever size the pad is set to.
            let size: CGFloat = base + (level == 1 ? 5 : (level == 2 ? 3 : 1))
            font = .systemFont(ofSize: size, weight: .semibold)
        case .unorderedListItem(let depth):
            listDepth = depth
            marker = "• "
        case .taskListItem(let depth, let checked, let box):
            listDepth = depth
            checkbox = (checked, box)
            if checked { color = .secondaryLabelColor }
        case .orderedListItem(let ordinal, let depth):
            listDepth = depth
            marker = "\(ordinal). "
        case .quote(let depth):
            prefix = String(repeating: "  ", count: depth - 1) + "▏ "
            color = .secondaryLabelColor
        case .code:
            // A point under the body, as inline code is, since monospace
            // reads larger than the system face at the same size.
            font = .monospacedSystemFont(ofSize: base - 1, weight: .regular)
        case .thematicBreak:
            text = AttributedString(String(repeating: "─", count: 24))
            color = .secondaryLabelColor
        case .paragraph:
            break
        }

        // A list inside a quote keeps the quote's bar and colour ahead of
        // its own marker.
        let quote = block.quoteDepth > 0 ? String(repeating: "  ", count: block.quoteDepth - 1) + "▏ " : ""
        if block.quoteDepth > 0 { color = .secondaryLabelColor }
        var quoteGap: CGFloat = 0
        if listDepth > 0 {
            func width(_ string: String) -> CGFloat { (string as NSString).size(withAttributes: [.font: font]).width }
            // The items above this one. A list can open below depth 1, as
            // `- - [ ] a` does; the levels it skips hold no text, so each
            // takes two spaces, as bullets do, and the item still lands at
            // its own depth for its siblings to find.
            levels = Array(levels.prefix(listDepth - 1))
            while levels.count < listDepth - 1 {
                let above = levels.last ?? ListLevel(column: width(quote), indented: false)
                levels.append(ListLevel(column: above.column + width("  "), indented: above.indented))
            }
            let parent = levels.last
            if checkbox != nil || parent?.indented == true {
                // As in Notes, a task's circle, or an item under a task, sits
                // under its parent's text, and a task's wrapped lines hang
                // under its own text rather than under the circle. A quote's
                // bar can be wider than a parent's marker, and then the item
                // starts after the bar.
                let lead = max(parent?.column ?? 0, width(quote))
                let column = lead + (checkbox != nil ? boxSize + width(" ") : width(marker))
                if quote.isEmpty { paragraph.firstLineHeadIndent = lead } else { quoteGap = lead - width(quote) }
                paragraph.headIndent = checkbox != nil ? column : lead
                prefix = quote + marker
                levels.append(ListLevel(column: column, indented: true))
            } else {
                prefix = quote + String(repeating: "  ", count: listDepth - 1) + marker
                levels.append(ListLevel(column: width(prefix), indented: false))
            }
        }

        let result = NSMutableAttributedString()
        if !prefix.isEmpty {
            result.append(NSAttributedString(string: prefix, attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]))
            // The quote's bar stays at the line's start, so a nested item
            // in a quote reaches its column by widening the space after it.
            if quoteGap > 0 {
                result.addAttribute(.kern, value: quoteGap,
                                    range: NSRange(location: (quote as NSString).length - 1, length: 1))
            }
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
        if let checkbox {
            // The glyph is a link, so a click on it reaches the coordinator.
            let attachment = TaskBoxAttachment(checked: checkbox.checked, size: boxSize,
                                               description: checkbox.checked ? taskStates.done : taskStates.notDone)
            let box = NSMutableAttributedString(attachment: attachment)
            box.append(NSAttributedString(string: " "))
            box.addAttributes([
                .font: font,
                .paragraphStyle: paragraph,
                .link: URL(string: "\(ScratchpadSupport.taskScheme)://\(checkbox.box)") as Any
            ], range: NSRange(location: 0, length: box.length))
            result.append(box)
            if case .taskListItem(_, true, _) = block.kind {
                content.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
            }
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
                ? NSFont.monospacedSystemFont(ofSize: max(9, baseFont.pointSize - 1), weight: .regular)
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
        var onToggleTask: ((Int) -> Void)?
        /// What the reading was last drawn from. Every render makes new
        /// checkbox attachments, and two attachments never compare equal, so
        /// the drawn text cannot tell an unchanged reading from a new one;
        /// replacing it on every view update would drop its selection.
        private var shown: (blocks: [ScratchpadMarkdownBlock], base: CGFloat, done: String, notDone: String)?

        func show(_ blocks: [ScratchpadMarkdownBlock], base: CGFloat,
                  taskStates: (done: String, notDone: String), in textView: NSTextView) {
            if let shown, shown.blocks == blocks, shown.base == base,
               shown.done == taskStates.done, shown.notDone == taskStates.notDone { return }
            shown = (blocks, base, taskStates.done, taskStates.notDone)
            textView.textStorage?.setAttributedString(MarkdownPreview.rendered(blocks, base: base, taskStates: taskStates))
        }

        func textView(_ textView: NSTextView,
                      clickedOnLink link: Any,
                      at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            if url.scheme == ScratchpadSupport.taskScheme {
                if let box = url.host.flatMap(Int.init) { onToggleTask?(box) }
                return true
            }
            return NSWorkspace.shared.open(url)
        }
    }
}

/// A task's checkbox as Notes draws its checklist: an empty ring, filled
/// with the accent colour and a check once the task is done. The system
/// colours resolve as the box is drawn, so it follows the light or dark
/// appearance, and `description` names which of the two it is.
final class TaskBoxAttachment: NSTextAttachment {
    let checked: Bool

    init(checked: Bool, size: CGFloat, description: String) {
        self.checked = checked
        super.init(data: nil, ofType: nil)
        // A palette lays a colour's alpha over the ring's own, which leaves
        // tertiary label at a faint 7%; hierarchical draws it as Notes does.
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(checked
                ? NSImage.SymbolConfiguration(paletteColors: [.white, .controlAccentColor])
                : NSImage.SymbolConfiguration(hierarchicalColor: .tertiaryLabelColor))
        let symbol = NSImage(systemSymbolName: checked ? "checkmark.circle.fill" : "circle",
                             accessibilityDescription: description)?
            .withSymbolConfiguration(configuration)
        symbol?.isTemplate = false
        image = symbol
        bounds = CGRect(x: 0, y: -(size * 0.2), width: size, height: size)
    }

    required init?(coder: NSCoder) { nil }
}

/// The preview's text view: a click on a checkbox toggles its task, and the
/// pointer over one becomes a hand, as over any button of the island.
final class TaskPreviewTextView: NSTextView {
    var onToggleTask: ((Int) -> Void)?
    private var pointerArea: NSTrackingArea?
    /// Kept while their boxes stay, so the one VoiceOver is on lives on.
    private var boxElements: [Int: BoxElement] = [:]
    /// A link element of the text view asks the view for its children to
    /// answer its own attributes, so that inner call gets the plain list.
    private var listingChildren = false

    /// A task's checkbox as VoiceOver meets it: named by its task, valued by
    /// whether it is done, and pressed as a click on it is.
    private final class BoxElement: NSAccessibilityElement {
        weak var view: TaskPreviewTextView?
        var box = 0
        var character = 0

        init(view: TaskPreviewTextView) {
            self.view = view
            super.init()
            setAccessibilityRole(.checkBox)
            setAccessibilityParent(view)
            setAccessibilityElement(true)
        }

        override func accessibilityFrame() -> NSRect {
            view?.firstRect(forCharacterRange: NSRange(location: character, length: 1), actualRange: nil) ?? .zero
        }

        override func accessibilityPerformPress() -> Bool {
            guard let toggle = view?.onToggleTask else { return false }
            toggle(box)
            return true
        }
    }

    /// The text view offers a box only as a link named by the attachment's
    /// object replacement character, so the box's link leaves the children
    /// and the box stands there as a checkbox of its own.
    override func accessibilityChildren() -> [Any]? {
        let children = super.accessibilityChildren() ?? []
        guard !listingChildren, let storage = textStorage else { return children }
        listingChildren = true
        defer { listingChildren = false }
        let text = storage.string as NSString
        var boxes: [BoxElement] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? TaskBoxAttachment,
                  let url = storage.attribute(.link, at: range.location, effectiveRange: nil) as? URL,
                  url.scheme == ScratchpadSupport.taskScheme, let box = url.host.flatMap(Int.init) else { return }
            let element = boxElements[box] ?? BoxElement(view: self)
            let line = text.paragraphRange(for: range)
            let task = NSRange(location: range.upperBound, length: line.upperBound - range.upperBound)
            element.box = box
            element.character = range.location
            element.setAccessibilityLabel(text.substring(with: task).trimmingCharacters(in: .whitespacesAndNewlines))
            element.setAccessibilityValue(attachment.checked ? 1 : 0)
            element.setAccessibilityValueDescription(attachment.image?.accessibilityDescription)
            boxes.append(element)
        }
        boxElements = Dictionary(boxes.map { ($0.box, $0) }, uniquingKeysWith: { first, _ in first })
        return children.filter {
            ($0 as? NSAccessibilityElement)?.accessibilityURL()?.scheme != ScratchpadSupport.taskScheme
        } + boxes
    }

    /// The text offset of the box whose checkbox is under `point`.
    private func taskBox(at point: NSPoint) -> Int? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage,
              storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let inContainer = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyph = layout.glyphIndex(for: inContainer, in: container, fractionOfDistanceThroughGlyph: nil)
        guard glyph < layout.numberOfGlyphs,
              layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(inContainer)
        else { return nil }
        let character = layout.characterIndexForGlyph(at: glyph)
        guard let url = storage.attribute(.link, at: character, effectiveRange: nil) as? URL,
              url.scheme == ScratchpadSupport.taskScheme else { return nil }
        return url.host.flatMap(Int.init)
    }

    override func mouseDown(with event: NSEvent) {
        if let box = taskBox(at: convert(event.locationInWindow, from: nil)) {
            onToggleTask?(box)
        } else {
            super.mouseDown(with: event)
        }
    }

    /// NSTextView puts its text cursor back on every move over selectable
    /// text, past any cursor rect, so the pointer is set here instead, as the
    /// pointer moves and when it enters.
    private func pointer(for event: NSEvent) -> Bool {
        guard taskBox(at: convert(event.locationInWindow, from: nil)) != nil else { return false }
        NSCursor.pointingHand.set()
        return true
    }

    override func cursorUpdate(with event: NSEvent) {
        if !pointer(for: event) { super.cursorUpdate(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        if !pointer(for: event) { super.mouseMoved(with: event) }
    }

    /// AppKit asks again whenever the view's geometry changes, so the area
    /// added last time goes before the next one, or they pile up and each
    /// pointer move runs the hit test once per area.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }
}
