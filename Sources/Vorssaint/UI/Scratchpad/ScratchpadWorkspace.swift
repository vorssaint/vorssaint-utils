// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

extension Notification.Name {
    static let scratchpadFocusSearch = Notification.Name("VorssaintScratchpadFocusSearch")
    static let scratchpadFind = Notification.Name("VorssaintScratchpadFind")
}

struct ScratchpadWorkspace: View {
    let island: Bool
    @ObservedObject private var service = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.scratchpadTextSize) private var storedTextSize = ScratchpadSupport.defaultTextSize
    @State private var editor = EditorHandle()
    @State private var activeMarks = Set<ScratchpadMark>()
    @State private var copied = false
    @State private var pendingFind: NSTextFinder.Action?
    @State private var titleFocused = false
    @FocusState private var searchFocused: Bool
    private var text: ScratchpadFeatureStrings { FeatureStrings.scratchpad(l10n.language) }
    private var labels: ScratchpadLibraryStrings { .init(language: l10n.language) }

    private final class EditorHandle {
        weak var view: NSTextView?
        init(view: NSTextView? = nil) { self.view = view }
    }
    private enum Dialog {
        case newFolder, renameFolder(UUID), deleteFolder(UUID), purge(UUID?)
    }

    var body: some View {
        VStack(spacing: island ? 5 : 0) {
            navigation
            if service.saveFailed {
                Label(text.saveFailed, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if service.showsSidebar {
                        browser(width: geometry.size.width)
                            .frame(width: geometry.size.width >= 560 ? 195 : geometry.size.width)
                    }
                    if !service.showsSidebar || geometry.size.width >= 560 {
                        writingSurface
                    }
                }
            }
            footer
        }
        .foregroundStyle(island ? Color.white : Color.primary)
        .onChange(of: service.selectedPadID) { _, _ in
            titleFocused = false
            DispatchQueue.main.async { focusEditor() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scratchpadFocusSearch)) { _ in
            guard hostWindow?.isKeyWindow == true else { return }
            service.showsSidebar = true
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .scratchpadFind)) { notification in
            guard hostWindow?.isKeyWindow == true,
                  let action = notification.userInfo?["action"] as? NSTextFinder.Action else { return }
            if let view = editor.view { service.performFind(action, in: view) }
            else { pendingFind = action; searchFocused = false; service.showsSidebar = false }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { copied = false }
        }
    }

    private var navigation: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Button { service.showsSidebar.toggle() } label: { Image(systemName: "sidebar.left").frame(width: 24, height: 24).contentShape(Rectangle()) }
                    .help(labels[.sidebar]).accessibilityLabel(labels[.sidebar])
                Menu {
                    collectionChoices
                    Divider()
                    ForEach(service.folders) { folder in
                        Button(folder.name) { service.collection = .folder(folder.id); service.showsSidebar = true }
                    }
                    Divider()
                    Button(labels[.newFolder]) { present(.newFolder) }
                } label: {
                    Label(collectionName, systemImage: collectionSymbol).lineLimit(1).frame(maxWidth: 140, alignment: .leading)
                }
                .menuStyle(.borderlessButton).fixedSize()
                Spacer(minLength: 0)
                Button { service.createPadInCollection() } label: { Image(systemName: "plus").frame(width: 24, height: 24).contentShape(Rectangle()) }
                    .help(text.newPad).accessibilityLabel(text.newPad).disabled(!service.canCreatePad)
                actionsMenu
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 12).frame(height: 30)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 4) {
                        ForEach(service.pads) { pad in tab(pad).id(pad.id) }
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .onChange(of: service.selectedPadID) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .frame(height: 34)
            if !island { Divider().opacity(0.4) }
        }
    }

    @ViewBuilder private var collectionChoices: some View {
        Button(labels[.inbox]) { service.collection = .inbox; service.showsSidebar = true }
        Button(labels[.all]) { service.collection = .all; service.showsSidebar = true }
        Button(labels[.pinned]) { service.collection = .pinned; service.showsSidebar = true }
        Button(labels[.trash]) { service.collection = .trash; service.showsSidebar = true }
    }

    private var collectionName: String {
        switch service.collection {
        case .inbox: return labels[.inbox]
        case .all: return labels[.all]
        case .pinned: return labels[.pinned]
        case .trash: return labels[.trash]
        case .folder(let id): return service.folders.first { $0.id == id }?.name ?? labels[.inbox]
        }
    }

    private var collectionSymbol: String {
        switch service.collection {
        case .inbox: return "tray"
        case .all: return "note.text"
        case .pinned: return "pin"
        case .trash: return "trash"
        case .folder: return "folder"
        }
    }

    private func tab(_ pad: ScratchpadPad) -> some View {
        HStack(spacing: 5) {
            Button { service.selectPad(pad.id) } label: {
                HStack(spacing: 4) {
                    if pad.isPinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
                    Text(pad.name).lineLimit(1).frame(maxWidth: 140)
                }
            }
            .buttonStyle(.plain)
            Button { _ = service.closePad(pad.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9)).frame(width: 18, height: 22)
            }
            .buttonStyle(.plain).help(text.closePad).accessibilityLabel(text.closePad)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.leading, 8).padding(.trailing, 3).frame(height: 25)
        .background(service.selectedPadID == pad.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 6))
        .accessibilityAddTraits(service.selectedPadID == pad.id ? .isSelected : [])
        .draggable(pad.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let id = UUID(uuidString: value), service.pads.contains(where: { $0.id == id }) else { return false }
            service.reorderTab(id, before: pad.id)
            return true
        }
        .contextMenu { noteActions(pad) }
    }

    private var writingSurface: some View {
        VStack(spacing: 0) {
            if let pad = service.selectedPad {
                ScratchpadTitleField(name: pad.name, label: text.renamePad,
                    onCommit: { service.renamePad(pad.id, to: $0) },
                    onFocus: { titleFocused = $0 }, onSubmit: { focusEditor() })
                    .id(pad.id)
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.horizontal, 15).padding(.top, 12).padding(.bottom, 3)
                ZStack(alignment: .topLeading) {
                    ScratchpadEditor(text: service.binding(for: pad.id),
                        fontSize: CGFloat(ScratchpadSupport.sanitizedTextSize(storedTextSize)),
                        textColor: island ? .white : .labelColor, sourceMode: service.isSourceMode,
                        position: service.editingPositions[pad.id],
                        onPosition: { service.editingPositions[pad.id] = $0 },
                        onCreate: { view in
                            if !island { service.registerTextView(view) }
                            DispatchQueue.main.async {
                                guard service.selectedPadID == pad.id, view.window != nil else { return }
                                editor = EditorHandle(view: view)
                                if let action = pendingFind {
                                    pendingFind = nil
                                    service.performFind(action, in: view)
                                } else { focusEditor() }
                            }
                        },
                        onFormattingChange: { marks in
                            if service.selectedPadID == pad.id { activeMarks = marks }
                        })
                    .id(pad.id)
                    if pad.text.isEmpty {
                        Text(text.placeholder).font(.system(size: CGFloat(ScratchpadSupport.sanitizedTextSize(storedTextSize))))
                            .foregroundStyle(.secondary).padding(.leading, 15).padding(.top, 10)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            }
            if service.marksExpanded { ScratchpadFormatBar(style: island ? .island : .pad, editor: editor.view, activeMarks: activeMarks).padding(.horizontal, 10).frame(height: 30) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func browser(width: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack {
                TextField(labels[.search], text: $service.search).textFieldStyle(.roundedBorder).focused($searchFocused)
                if width < 560 {
                    Button { service.showsSidebar = false } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain).accessibilityLabel(text.editText)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(service.folders) { folder in
                        Button { service.collection = .folder(folder.id) } label: {
                            Label(folder.name, systemImage: "folder").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain).padding(6)
                        .contextMenu {
                            Button(labels[.renameFolder]) { present(.renameFolder(folder.id)) }
                            Button(labels[.deleteFolder], role: .destructive) { present(.deleteFolder(folder.id)) }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first, let id = UUID(uuidString: raw), service.allPads.contains(where: { $0.id == id }) else { return false }
                            service.movePad(id, to: folder.id)
                            return true
                        }
                    }
                    Divider().padding(.vertical, 5)
                    ForEach(service.visibleNotes) { pad in
                        Button {
                            if pad.deletedAt != nil { service.restorePad(pad.id) }
                            else { service.selectPad(pad.id) }
                            if width < 560 { searchFocused = false; service.showsSidebar = false }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    if pad.isPinned { Image(systemName: "pin.fill") }
                                    Text(pad.name).fontWeight(.medium).lineLimit(1)
                                }
                                Text(pad.text.replacingOccurrences(of: "\n", with: " ").prefix(100))
                                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            .background(pad.id == service.selectedPadID ? Color.accentColor.opacity(0.14) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain).contextMenu { noteActions(pad) }.draggable(pad.id.uuidString)
                    }
                }
            }
            if service.collection == .trash {
                Button(labels[.emptyTrash], role: .destructive) { present(.purge(nil)) }
                    .disabled(service.visibleNotes.isEmpty)
            }
        }
        .font(.system(size: 12)).padding(10)
        .background(Color.primary.opacity(0.035))
    }

    @ViewBuilder private func noteActions(_ pad: ScratchpadPad) -> some View {
        if pad.deletedAt != nil {
            Button(labels[.restore]) { service.restorePad(pad.id) }
            Button(labels[.deleteForever], role: .destructive) { present(.purge(pad.id)) }
        } else {
            Button(labels[.duplicate]) { service.duplicatePad(pad.id) }
            Button(pad.isPinned ? labels[.unpin] : labels[.pin]) { service.toggleNotePin(pad.id) }
            Toggle(labels[.temporary], isOn: Binding(get: { pad.isTemporary }, set: { _ in service.toggleTemporary(pad.id) }))
            Menu(labels[.move]) {
                Button(labels[.inbox]) { service.movePad(pad.id, to: nil) }
                ForEach(service.folders) { folder in Button(folder.name) { service.movePad(pad.id, to: folder.id) } }
            }
            Divider()
            Button(labels[.delete], role: .destructive) { service.deletePad(pad.id) }
        }
    }

    private var actionsMenu: some View {
        Menu {
            if let pad = service.selectedPad { noteActions(pad); Divider() }
            Menu(labels[.checklistTools]) {
                Button(labels[.uncheckAll]) { service.applyChecklist(.uncheckAll, through: editor.view) }
                Button(labels[.removeCompleted]) { service.applyChecklist(.removeCompleted, through: editor.view) }
            }
            .disabled(editor.view == nil || !ScratchpadMarkdown(service.text).tasks.contains(where: \.checked))
            Divider()
            Button(labels[.importNotes]) { service.importNotes(from: hostWindow) }
            Button(text.exportAction) { service.exportText(suggestedName: ScratchpadSupport.exportFileName(title: service.selectedPadName, date: Date()).replacingOccurrences(of: ".txt", with: ".md"), from: hostWindow) }
            Button(labels[.exportFolder]) { service.exportFolder(from: hostWindow) }
            Divider()
            Button(labels[.backup]) { service.backupNotes(from: hostWindow) }
            Button(labels[.restoreBackup]) { service.restoreBackup(from: hostWindow) }
            if island { Divider(); Button(text.openButton) { NotchService.shared.perform { service.show(allowsIsland: false) } } }
        } label: { Image(systemName: "ellipsis").frame(width: 22, height: 24) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(text.padActions).accessibilityLabel(text.padActions)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { service.toggleMarks() } label: { Image(systemName: "textformat") }
                .help(text.formatMarks).accessibilityLabel(text.formatMarks)
            Button { service.toggleSource() } label: { Image(systemName: service.isSourceMode ? "text.alignleft" : "chevron.left.forwardslash.chevron.right") }
                .help(service.isSourceMode ? labels[.liveEditing] : labels[.source])
                .accessibilityLabel(service.isSourceMode ? labels[.liveEditing] : labels[.source])
            Button { service.copyAll(); copied = true } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                .help(copied ? text.copied : text.copyAll).accessibilityLabel(text.copyAll).disabled(service.text.isEmpty)
            Spacer()
            Text(service.isSourceMode ? labels[.source] : labels[.liveEditing]).font(.system(size: 10)).foregroundStyle(.secondary)
            Button { service.clear(through: editor.view) } label: { Image(systemName: "eraser") }
                .help(text.clearAction).accessibilityLabel(text.clearAction).disabled(service.text.isEmpty)
        }
        .buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 12).frame(height: 32)
    }

    private var hostWindow: NSWindow? { editor.view?.window ?? (island ? NotchService.shared.presentationWindow : service.presentationWindow) }
    private func focusEditor() {
        guard !titleFocused, !searchFocused, let view = editor.view, let window = view.window, window.isKeyWindow else { return }
        window.makeFirstResponder(view)
    }
    private func present(_ value: Dialog) {
        switch value {
        case .newFolder:
            service.ask(title: labels[.newFolder], initialName: "", from: hostWindow) { name in
                if let name { service.addFolder(named: name) }
            }
        case .renameFolder(let id):
            let name = service.folders.first { $0.id == id }?.name ?? ""
            service.ask(title: labels[.renameFolder], initialName: name, from: hostWindow) { name in
                if let name { service.renameFolder(id, to: name) }
            }
        case .deleteFolder(let id):
            service.ask(title: labels[.deleteFolder], message: labels[.folderMessage], destructive: true, from: hostWindow) { _ in service.deleteFolder(id) }
        case .purge(let id):
            service.ask(title: labels[.deleteForever], message: labels[.permanentMessage], destructive: true, from: hostWindow) { _ in service.purgeTrash(id) }
        }
    }
}

/// Draft and native field identity belong to one note, including when a folder
/// browser removes and recreates the writing surface.
struct ScratchpadTitleField: View {
    let name: String
    let label: String
    let onCommit: (String) -> Void
    let onFocus: (Bool) -> Void
    let onSubmit: () -> Void
    @State private var draft: String
    @State private var edited = false
    @FocusState private var focused: Bool

    init(name: String, label: String, onCommit: @escaping (String) -> Void,
         onFocus: @escaping (Bool) -> Void, onSubmit: @escaping () -> Void) {
        self.name = name; self.label = label; self.onCommit = onCommit
        self.onFocus = onFocus; self.onSubmit = onSubmit
        _draft = State(initialValue: name)
    }

    var body: some View {
        TextField(label, text: Binding(get: { draft }, set: { value in
            guard value != draft else { return }
            draft = value; edited = true
        }))
            .textFieldStyle(.plain).lineLimit(1).focused($focused)
            .accessibilityLabel(label)
            .onSubmit { commit(); focused = false; onFocus(false); onSubmit() }
            .onChange(of: name) { _, value in if !focused { draft = value; edited = false } }
            .onChange(of: focused) { _, value in onFocus(value); if !value { commit() } }
            .onDisappear { commit(); onFocus(false) }
    }

    private func commit() {
        let proposed = ScratchpadSupport.sanitizedPadName(draft)
        guard edited, !proposed.isEmpty else { return }
        edited = false
        onCommit(proposed)
    }
}
