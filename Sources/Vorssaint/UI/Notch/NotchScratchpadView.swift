// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The scratchpad's document inside the island: the editor or its formatted
/// reading fills the page, and the island's top row holds the pads. Beside
/// the camera the chosen pad's name opens a menu of the pads and what a pad
/// can do; a full row keeps the tabs, and the chosen tab opens that menu.
/// Everything the floating pad does, at the island's size: tabs close from
/// their own cross, Command-T and Command-W work, a new or chosen pad puts
/// the caret in its text, and a cleared pad comes back with one undo.
struct NotchScratchpadView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var pad = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchBand) private var band
    @State private var loadFailed = false
    @State private var copied = false
    @State private var hoveredPadID: UUID?
    @State private var editor = EditorHandle()
    @AppStorage(DefaultsKey.scratchpadTextSize) private var storedTextSize = ScratchpadSupport.defaultTextSize
    private var text: ScratchpadFeatureStrings { FeatureStrings.scratchpad(l10n.language) }
    private var textSize: CGFloat { CGFloat(ScratchpadSupport.sanitizedTextSize(storedTextSize)) }
    private static let editorInset = NSSize(width: 6, height: 6)

    /// Holds the editor's text view so a tab change can aim the caret at it
    /// and a clear or a checkbox click can go through its undo. Weak, since
    /// the view belongs to the editor.
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
                    // The marks open under the row, above the text they format.
                    if pad.marksExpanded {
                        markRow
                    }
                    if pad.saveFailed {
                        Label(text.saveFailed, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ZStack(alignment: .topLeading) {
                        PlainTextEditor(text: $pad.text, fontSize: textSize,
                                        textColor: .white,
                                        textContainerInset: Self.editorInset,
                                        usesFindBar: true,
                                        completesTaskBoxes: true,
                                        continuesLists: true,
                                        onCommandReturn: { pad.togglePreview() },
                                        isActive: !pad.isPreviewing) { view in
                            view.insertionPointColor = .white
                            editor.view = view
                            DispatchQueue.main.async { focusEditor() }
                        }
                        .opacity(pad.isPreviewing ? 0 : 1)
                        .allowsHitTesting(!pad.isPreviewing)
                        .accessibilityHidden(pad.isPreviewing)
                        if pad.isPreviewing {
                            MarkdownPreview(blocks: ScratchpadSupport.markdownPreview(pad.text),
                                            baseSize: textSize,
                                            taskStates: (done: text.taskDone, notDone: text.taskNotDone),
                                            onToggleTask: { pad.toggleTask(box: $0, through: editor.view) })
                        } else if pad.text.isEmpty {
                            Text(text.placeholder)
                                .font(.system(size: textSize))
                                .foregroundStyle(.white.opacity(0.35))
                                .padding(.leading, Self.editorInset.width + PlainTextEditor.lineFragmentPadding)
                                .padding(.top, Self.editorInset.height)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .notchBand(leading: {
            if !loadFailed { padControls }
        }, trailing: {
            if !loadFailed { noteActions }
        })
        .onAppear { loadFailed = !pad.loadForEmbedding() }
        .onDisappear { pad.commitEdits() }
        .onChange(of: pad.selectedPadID) { _, _ in
            DispatchQueue.main.async { focusEditor() }
        }
        .onChange(of: pad.isPreviewing) { _, previewing in
            guard let view = editor.view else { return }
            if previewing {
                pad.hideFindBar(in: view)
                if view.window?.firstResponder === view || PlainTextEditor.findBarHasKeyboard(in: view.window) {
                    view.window?.makeFirstResponder(nil)
                }
            } else {
                DispatchQueue.main.async {
                    // Preview closed the bar and took the keyboard, so a bar
                    // up now was opened by Command-F and a focused text was
                    // given the keyboard by Command-G, both on their way out
                    // of preview. Either keeps its focus and the match.
                    guard view.enclosingScrollView?.isFindBarVisible != true,
                          view.window?.firstResponder !== view else { return }
                    focusEditor()
                }
            }
        }
        .onChange(of: service.scratchpadCloseSerial) { _, _ in
            guard let selectedPad else { return }
            requestClose(selectedPad)
        }
        .onChange(of: service.scratchpadFindSerial) { _, _ in
            pad.performFind(service.scratchpadFindAction, in: editor.view)
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    private var tabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(pad.pads) { entry in tab(entry).id(entry.id) }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: 28)
            .onAppear {
                guard let selected = pad.selectedPadID else { return }
                proxy.scrollTo(selected, anchor: .center)
            }
            .onChange(of: pad.selectedPadID) { _, selected in
                guard let selected else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(selected, anchor: .center) }
            }
        }
    }

    private var markRow: some View {
        ScratchpadFormatBar(style: .island, editor: editor.view)
            .frame(height: 28)
    }

    /// Beside the camera the row has room for one pad: the chosen one's name
    /// opens the list of pads and what a pad can do. A full row keeps the
    /// tabs, with the way to a new pad after them.
    @ViewBuilder private var padControls: some View {
        if band.besideCamera {
            NotchMenuButton(title: text.padActions, items: padItems(listsPads: true), cornerRadius: 9) {
                NotchBandMenuLabel(title: pad.selectedPadName)
            }
            .help(text.padActions)
            .accessibilityValue(pad.selectedPadName)
        } else {
            HStack(spacing: 6) {
                tabStrip
                NotchIconButton(symbol: "plus", title: newPadTitle) {
                    pad.createPad(defaultName: text.pageTitle)
                }
                .disabled(!pad.canCreatePad)
            }
        }
    }

    private var noteActions: some View {
        HStack(spacing: 6) {
            NotchIconButton(symbol: "textformat",
                            title: text.formatMarks,
                            selected: pad.marksExpanded) {
                withAnimation(.easeOut(duration: 0.15)) { pad.toggleMarks() }
            }
            .disabled(pad.isPreviewing)
            NotchIconButton(symbol: pad.isPreviewing ? "pencil" : "eye",
                            title: pad.isPreviewing ? text.editText : text.previewFormatting,
                            selected: pad.isPreviewing, action: pad.togglePreview)
                .disabled(pad.text.isEmpty)
            NotchIconButton(symbol: copied ? "checkmark" : "doc.on.doc", title: copied ? text.copied : text.copyAll) {
                pad.copyAll()
                copied = true
            }
            .disabled(pad.text.isEmpty)
        }
    }

    private var newPadTitle: String {
        pad.canCreatePad ? text.newPad : String(format: text.padLimitFormat, ScratchpadDocument.maximumPadCount)
    }

    /// The pads, where the row shows only the chosen one, then what a pad
    /// can do, each with the confirmation or dialog it always had.
    private func padItems(listsPads: Bool) -> [NotchMenuItem] {
        let current = selectedPad
        var items: [NotchMenuItem] = []
        if listsPads, !pad.pads.isEmpty {
            items = pad.pads.map { entry in
                NotchMenuItem(title: entry.name, checked: entry.id == pad.selectedPadID) { pad.selectPad(entry.id) }
            }
            items.append(.separator)
        }
        items += [
            NotchMenuItem(title: newPadTitle, enabled: pad.canCreatePad) { pad.createPad(defaultName: text.pageTitle) },
            NotchMenuItem(title: text.renamePad, enabled: current != nil) {
                if let current { presentRename(current) }
            },
            NotchMenuItem(title: text.closePad, enabled: current != nil && pad.canClosePad) {
                if let current { requestClose(current) }
            },
            .separator,
            NotchMenuItem(title: text.exportAction, enabled: !pad.text.isEmpty) {
                guard let window = service.presentationWindow else { return }
                pad.exportText(suggestedName: ScratchpadSupport.exportFileName(title: pad.selectedPadName, date: Date()),
                               from: window)
            },
            NotchMenuItem(title: text.clearAction, enabled: !pad.text.isEmpty) { pad.clear(through: editor.view) },
            .separator,
            NotchMenuItem(title: text.openButton) { service.perform { pad.show(allowsIsland: false) } }
        ]
        return items
    }

    /// The chosen tab opens the pad's menu, as the pad's name does beside the
    /// camera. Another tab shows its cross under the pointer, as in the
    /// floating pad, while the strip keeps two pads or more.
    private func tab(_ entry: ScratchpadPad) -> some View {
        let selected = entry.id == pad.selectedPadID
        return Group {
            if selected {
                NotchMenuButton(title: text.padActions, items: padItems(listsPads: false), cornerRadius: 11) {
                    tabLabel(entry, selected: true)
                }
                .accessibilityValue(entry.name)
            } else {
                Button { pad.selectPad(entry.id) } label: { tabLabel(entry, selected: false) }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 11, lifts: false))
            }
        }
        .onHover { hovering in
            if hovering { hoveredPadID = entry.id } else if hoveredPadID == entry.id { hoveredPadID = nil }
        }
        .contextMenu {
            Button(text.renamePad) { presentRename(entry) }
            Button(text.closePad, role: .destructive) { requestClose(entry) }
                .disabled(!pad.canClosePad)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(selected ? text.padActions : entry.name)
    }

    private func tabLabel(_ entry: ScratchpadPad, selected: Bool) -> some View {
        let showsClose = !selected && pad.canClosePad && hoveredPadID == entry.id
        return HStack(spacing: 4) {
            Text(entry.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            if selected {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            } else if showsClose {
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
        .padding(.trailing, showsClose ? 5 : selected ? 8 : 10)
        .frame(height: 22)
        .background(.white.opacity(selected ? 0.14 : 0.05), in: Capsule())
        .contentShape(Capsule())
    }

    /// The caret lands at the end of the pad's text, as the floating pad
    /// puts it after a tab change.
    private func focusEditor() {
        guard !pad.isPreviewing, let view = editor.view, let window = view.window, window.isKeyWindow else { return }
        window.makeFirstResponder(view)
        let end = NSRange(location: (view.string as NSString).length, length: 0)
        view.setSelectedRange(end)
        view.scrollRangeToVisible(end)
    }

    private func presentRename(_ entry: ScratchpadPad) {
        DispatchQueue.main.async {
            let field = NSTextField(string: entry.name)
            field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
            let alert = NSAlert()
            alert.messageText = text.renamePad
            alert.accessoryView = field
            alert.addButton(withTitle: text.saveName)
            alert.addButton(withTitle: text.cancel)
            alert.window.initialFirstResponder = field
            guard NotchIslandAlert.run(alert, above: service.presentationWindow) == .alertFirstButtonReturn else { return }
            pad.renamePad(entry.id, to: field.stringValue)
        }
    }

    /// An empty pad goes without asking, like in the floating pad.
    private func requestClose(_ entry: ScratchpadPad) {
        guard pad.canClosePad else { return }
        guard ScratchpadSupport.requiresCloseConfirmation(entry) else { _ = pad.closePad(entry.id); return }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = text.closePad
            alert.informativeText = String(format: text.deletePadMessageFormat, entry.name)
            alert.addButton(withTitle: text.closePad).hasDestructiveAction = true
            alert.addButton(withTitle: text.cancel)
            guard NotchIslandAlert.run(alert, above: service.presentationWindow) == .alertFirstButtonReturn else { return }
            _ = pad.closePad(entry.id)
        }
    }
}
