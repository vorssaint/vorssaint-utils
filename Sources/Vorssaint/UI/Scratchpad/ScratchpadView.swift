// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The scratchpad card: a slim header that drags the panel, the plain-text
/// editor filling the middle, and a quiet footer with copy, export and clear.
struct ScratchpadView: View {
    @ObservedObject private var service = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var copied = false

    private var text: ScratchpadFeatureStrings { FeatureStrings.scratchpad(l10n.language) }
    private var isEmpty: Bool { service.text.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            editor
            footer
        }
        .background(HUDBackdrop(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
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
                ScratchpadService.shared.hide()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuClose)
            .accessibilityLabel(l10n.s.menuClose)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var editor: some View {
        PlainTextEditor(text: $service.text)
            .overlay(alignment: .topLeading) {
                if isEmpty {
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
    }

    private var footer: some View {
        HStack(spacing: 12) {
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
                    ScratchpadSupport.exportFileName(title: text.pageTitle, date: Date()))
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
