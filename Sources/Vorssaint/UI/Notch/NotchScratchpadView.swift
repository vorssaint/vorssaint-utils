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
    @State private var hoveredPadID: UUID?
    @State private var editor = EditorHandle()
    @AppStorage(DefaultsKey.scratchpadTextSize) private var storedTextSize = ScratchpadSupport.defaultTextSize
    private var text: ScratchpadFeatureStrings { FeatureStrings.scratchpad(l10n.language) }
    private var textSize: CGFloat { CGFloat(ScratchpadSupport.sanitizedTextSize(storedTextSize)) }
    private static let editorInset = NSSize(width: 6, height: 6)

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
                        PlainTextEditor(text: $pad.text, fontSize: textSize,
                                        textColor: .white,
                                        textContainerInset: Self.editorInset,
                                        usesFindBar: true) { view in
                            view.insertionPointColor = .white
                            editor.view = view
                            DispatchQueue.main.async { focusEditor() }
                        }
                        .opacity(pad.isPreviewing ? 0 : 1)
                        .allowsHitTesting(!pad.isPreviewing)
                        .accessibilityHidden(pad.isPreviewing)
                        if pad.isPreviewing {
                            MarkdownPreview(blocks: ScratchpadSupport.markdownPreview(pad.text),
                                            baseSize: textSize)
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
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            // The island has one row to spend. The marks take the tab strip's
            // place while they are up rather than squeezing in beside it, and
            // the chip stays put so the same click puts the tabs back.
            if pad.marksExpanded {
                markRow
            } else {
                tabStrip
            }
            NotchIconButton(symbol: "textformat",
                            title: text.formatMarks,
                            selected: pad.marksExpanded) {
                withAnimation(.easeOut(duration: 0.15)) { pad.toggleMarks() }
            }
            .disabled(pad.isPreviewing)
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
                    if let window = service.presentationWindow {
                        pad.exportText(suggestedName: ScratchpadSupport.exportFileName(title: pad.selectedPadName, date: Date()),
                                       from: window)
                    }
                }
                .disabled(pad.text.isEmpty)
                Button(text.clearAction, role: .destructive) { pad.clear(through: editor.view) }
                    .disabled(pad.text.isEmpty)
                Divider()
                Button(text.openButton) { service.perform { pad.show(allowsIsland: false) } }
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
            guard runAboveIsland(alert) == .alertFirstButtonReturn else { return }
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
            guard runAboveIsland(alert) == .alertFirstButtonReturn else { return }
            _ = pad.closePad(entry.id)
        }
    }

    /// A SwiftUI alert hangs from the island as a sheet, which moves and
    /// reskins the borderless surface. The question opens on its own, above
    /// the island, which gets the keyboard back afterwards.
    private func runAboveIsland(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let island = service.presentationWindow
        var observers: [NSObjectProtocol] = []
        if let island {
            // The modal session puts the alert at the modal panel level, below
            // the island, and puts it back there when it activates the app or
            // makes the alert key. Raise it once running and after each of those.
            let level = NSWindow.Level(rawValue: island.level.rawValue + 1)
            let raise: (Notification) -> Void = { _ in alert.window.level = level }
            observers = [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main, using: raise)
            }
            DispatchQueue.main.async { alert.window.level = level }
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        observers.forEach(NotificationCenter.default.removeObserver)
        // A closed island declines key status, so this only returns to an open one.
        if let island, island.isVisible { island.makeKey() }
        return response
    }
}
