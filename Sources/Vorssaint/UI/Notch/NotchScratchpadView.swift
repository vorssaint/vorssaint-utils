// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The scratchpad's document inside the island: its tabs in a row, the
/// editor or its formatted reading filling the rest, and the pad's actions
/// behind one menu. Everything the floating pad does, at the island's size:
/// tabs close from their own cross, Command-T and Command-W work, a new or
/// chosen pad puts the caret in its text, and a cleared pad comes back with
/// one undo.
struct NotchScratchpadView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var pad = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var loadFailed = false
    @State private var copied = false
    @State private var dialog: Dialog?
    @State private var renameDraft = ""
    @State private var hoveredPadID: UUID?
    @State private var editor = EditorHandle()
    private var text: ScratchpadFeatureStrings { FeatureStrings.scratchpad(l10n.language) }
    private static let editorInset = NSSize(width: 6, height: 6)

    private enum Dialog {
        case rename(ScratchpadPad)
        case close(ScratchpadPad)
    }

    /// Holds the editor's text view so a tab change can aim the caret at it
    /// and a clear can go through its undo. Weak, since the view belongs to
    /// the editor.
    private final class EditorHandle {
        weak var view: NSTextView?
    }

    private var selectedPad: ScratchpadPad? { pad.pads.first { $0.id == pad.selectedPadID } }

    var body: some View {
        Group {
            if loadFailed {
                NotchEmptyView(symbol: "exclamationmark.triangle", message: text.loadFailed)
            } else {
                VStack(spacing: 6) {
                    toolbar
                    ZStack(alignment: .topLeading) {
                        if pad.isPreviewing {
                            MarkdownPreview(blocks: ScratchpadSupport.markdownPreview(pad.text))
                        } else {
                            PlainTextEditor(text: $pad.text, textColor: .white, textContainerInset: Self.editorInset) { view in
                                view.insertionPointColor = .white
                                editor.view = view
                                DispatchQueue.main.async { focusEditor() }
                            }
                            if pad.text.isEmpty {
                                Text(text.placeholder)
                                    .font(.system(size: PlainTextEditor.fontSize))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .padding(.leading, Self.editorInset.width + PlainTextEditor.lineFragmentPadding)
                                    .padding(.top, Self.editorInset.height)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFailed = !pad.loadForEmbedding() }
        .onDisappear { pad.commitEdits() }
        .onChange(of: pad.selectedPadID) { _, _ in
            DispatchQueue.main.async { focusEditor() }
        }
        .onChange(of: service.scratchpadCloseSerial) { _, _ in
            guard let selectedPad else { return }
            requestClose(selectedPad)
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            copied = false
        }
        .alert(dialogTitle, isPresented: Binding(get: { dialog != nil }, set: { if !$0 { dialog = nil } })) {
            switch dialog {
            case .rename(let entry):
                TextField(entry.name, text: $renameDraft)
                Button(text.cancel, role: .cancel) { dialog = nil }
                Button(text.saveName) {
                    pad.renamePad(entry.id, to: renameDraft)
                    dialog = nil
                }
            case .close(let entry):
                Button(text.cancel, role: .cancel) { dialog = nil }
                Button(text.closePad, role: .destructive) {
                    _ = pad.closePad(entry.id)
                    dialog = nil
                }
            case nil:
                EmptyView()
            }
        } message: {
            if case .close(let entry) = dialog {
                Text(String(format: text.deletePadMessageFormat, entry.name))
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(pad.pads) { entry in tab(entry).id(entry.id) }
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    guard let selected = pad.selectedPadID else { return }
                    proxy.scrollTo(selected, anchor: .center)
                }
                .onChange(of: pad.selectedPadID) { _, selected in
                    guard let selected else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(selected, anchor: .center) }
                }
            }
            NotchIconButton(symbol: "plus",
                            title: pad.canCreatePad
                                ? text.newPad
                                : String(format: text.padLimitFormat, ScratchpadDocument.maximumPadCount)) {
                pad.createPad(defaultName: text.pageTitle)
            }
            .disabled(!pad.canCreatePad)
            NotchIconButton(symbol: pad.isPreviewing ? "pencil" : "eye",
                            title: pad.isPreviewing ? text.editText : text.previewFormatting,
                            selected: pad.isPreviewing, action: pad.togglePreview)
                .disabled(pad.text.isEmpty)
            NotchIconButton(symbol: copied ? "checkmark" : "doc.on.doc", title: copied ? text.copied : text.copyAll) {
                pad.copyAll()
                copied = true
            }
            .disabled(pad.text.isEmpty)
            Menu {
                if let selectedPad {
                    Button(text.renamePad) { presentRename(selectedPad) }
                    Button(text.closePad, role: .destructive) { requestClose(selectedPad) }
                        .disabled(!pad.canClosePad)
                    Divider()
                }
                Button(text.exportAction) {
                    pad.exportText(suggestedName: ScratchpadSupport.exportFileName(title: pad.selectedPadName, date: Date()))
                }
                .disabled(pad.text.isEmpty)
                Button(text.clearAction, role: .destructive) { pad.clear(through: editor.view) }
                    .disabled(pad.text.isEmpty)
                Divider()
                Button(text.openButton) { service.perform { pad.show() } }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(text.padActions)
            .accessibilityLabel(text.padActions)
        }
        .frame(height: 24)
    }

    /// The cross shows on the selected tab and under the pointer, as in the
    /// floating pad; it needs the tab strip to keep two pads or more.
    private func tab(_ entry: ScratchpadPad) -> some View {
        let selected = entry.id == pad.selectedPadID
        let showsClose = pad.canClosePad && (selected || hoveredPadID == entry.id)
        return Button { pad.selectPad(entry.id) } label: {
            HStack(spacing: 4) {
                Text(entry.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if showsClose {
                    Button { requestClose(entry) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(text.closePad)
                    .accessibilityLabel(text.closePad)
                }
            }
            .foregroundStyle(selected ? .white : .white.opacity(0.6))
            .padding(.leading, 10)
            .padding(.trailing, showsClose ? 5 : 10)
            .frame(height: 22)
            .background(.white.opacity(selected ? 0.14 : 0.05), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 11, lifts: false))
        .onHover { hovering in
            if hovering { hoveredPadID = entry.id } else if hoveredPadID == entry.id { hoveredPadID = nil }
        }
        .contextMenu {
            Button(text.renamePad) { presentRename(entry) }
            Button(text.closePad, role: .destructive) { requestClose(entry) }
                .disabled(!pad.canClosePad)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(entry.name)
    }

    private var dialogTitle: String {
        switch dialog {
        case .rename: return text.renamePad
        case .close: return text.closePad
        case nil: return ""
        }
    }

    /// The caret lands at the end of the pad's text, as the floating pad
    /// puts it after a tab change.
    private func focusEditor() {
        guard let view = editor.view, let window = view.window else { return }
        window.makeFirstResponder(view)
        let end = NSRange(location: (view.string as NSString).length, length: 0)
        view.setSelectedRange(end)
        view.scrollRangeToVisible(end)
    }

    private func presentRename(_ entry: ScratchpadPad) {
        renameDraft = entry.name
        dialog = .rename(entry)
    }

    /// An empty pad goes without asking, like in the floating pad.
    private func requestClose(_ entry: ScratchpadPad) {
        guard pad.canClosePad else { return }
        if ScratchpadSupport.requiresCloseConfirmation(entry) { dialog = .close(entry) }
        else { _ = pad.closePad(entry.id) }
    }
}
