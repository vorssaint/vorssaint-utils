// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The history as a vertical list of cards, with everything the panel's list
/// and the quick panel offer on each: paste or copy, pin, move, delete, and
/// the recent ones cleared in one go from the search row.
struct NotchClipboardView: View {
    let service: NotchService
    let size: CGSize
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var enabled = false
    @State private var query = ""
    @State private var copiedID: UUID?
    @State private var pinnedOnly = false
    @FocusState private var searching: Bool
    @Environment(\.notchSettingsPreview) private var preview
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(l10n.language) }

    private var entries: [ClipboardHistoryEntry] {
        history.filteredEntries(matching: query).filter { !pinnedOnly || $0.isPinned }
    }

    /// Moving swaps neighbours in the list, which a search would misreport.
    private var canReorder: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: NotchLayout.rowSpacing) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(text.search, text: $query).textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searching)
                    .accessibilityLabel(text.search)
                NotchIconButton(symbol: "pin", title: text.pinned, selected: pinnedOnly) {
                    pinnedOnly.toggle()
                }
                NotchIconButton(symbol: "trash", title: text.clearRecent) {
                    history.clearRecent()
                    copiedID = nil
                }
                .disabled(history.recentEntries.isEmpty)
                NotchIconButton(symbol: "arrow.up.forward.app", title: text.title) {
                    service.perform { history.showHistoryWindow(preferNotch: false) }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: NotchLayout.clipboardSearchHeight)
            .modifier(NotchControlSurface(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(searching ? 0.34 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.15), value: searching)
            // Typing filters the history as soon as the page opens, as in Explore.
            .onAppear { if !preview { searching = true } }
            if !enabled, history.entries.isEmpty {
                // The panel offers the switch beside its caption; the page
                // says why it is empty and turns the history on from here.
                VStack(spacing: 10) {
                    NotchEmptyView(symbol: "doc.on.clipboard", message: text.disabled)
                    Button(text.enable) {
                        enabled = true
                        history.syncWithPreferences()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .frame(maxHeight: .infinity)
            } else if entries.isEmpty {
                NotchEmptyView(symbol: pinnedOnly ? "pin" : "doc.on.clipboard",
                               message: query.isEmpty && !pinnedOnly ? text.empty : text.noResults)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(entries) { entry in
                            card(entry).frame(height: NotchLayout.clipboardCardHeight)
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: copiedID) {
            // The tick confirms one copy; leaving it on the row forever would
            // read as a permanent state instead of an answer.
            guard copiedID != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            copiedID = nil
        }
    }

    /// The entry fills the card; its actions sit in the bottom row.
    private func card(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { activate(entry) } label: {
                preview(entry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(NotchButtonStyle(lifts: false))
            .help(permissions.accessibility ? text.clickRowShortcut : text.copy)
            HStack(spacing: 4) {
                Image(systemName: entry.kind == .image ? "photo" : entry.kind == .files ? "doc" : "text.alignleft")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text(entry.copiedAt, style: .time)
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                Spacer(minLength: 0)
                if entry.kind == .image, AppFeature.screenshot.isAvailable {
                    NotchIconButton(symbol: "pencil", title: text.edit) { history.editImage(entry) }
                }
                NotchIconButton(symbol: copiedID == entry.id ? "checkmark" : "doc.on.doc",
                                title: copiedID == entry.id ? text.copied : text.copy) { copy(entry) }
                NotchIconButton(symbol: entry.isPinned ? "pin.fill" : "pin",
                                title: entry.isPinned ? text.unpin : text.pin) {
                    history.togglePin(entry)
                }
                NotchIconButton(symbol: "trash", title: text.delete) { remove(entry) }
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
        .modifier(NotchControlSurface(cornerRadius: 14, selected: entry.isPinned))
        .clipped()
        .contextMenu { actions(entry) }
        .accessibilityAction(named: Text(text.moveUp)) { move(entry, .up) }
        .accessibilityAction(named: Text(text.moveDown)) { move(entry, .down) }
    }

    /// The quick panel's row menu: paste when the app may type, copy, pin,
    /// move within the list and delete.
    @ViewBuilder private func actions(_ entry: ClipboardHistoryEntry) -> some View {
        if permissions.accessibility {
            Button(l10n.s.menuPaste) { paste(entry) }
        }
        Button(text.copy) { copy(entry) }
        Divider()
        Button(entry.isPinned ? text.unpin : text.pin) { history.togglePin(entry) }
        Button(text.moveUp) { move(entry, .up) }
            .disabled(!canReorder || !history.canMove(entry, .up))
        Button(text.moveDown) { move(entry, .down) }
            .disabled(!canReorder || !history.canMove(entry, .down))
        Divider()
        Button(text.delete, role: .destructive) { remove(entry) }
    }

    private func activate(_ entry: ClipboardHistoryEntry) {
        if permissions.accessibility { paste(entry) } else { copy(entry) }
    }

    private func paste(_ entry: ClipboardHistoryEntry) {
        service.collapse()
        history.copyQuickEntry(entry)
    }

    private func copy(_ entry: ClipboardHistoryEntry) {
        history.copy(entry) { copied in
            if copied {
                copiedID = entry.id
            } else {
                NSSound.beep()
            }
        }
    }

    private func move(_ entry: ClipboardHistoryEntry, _ direction: ClipboardHistoryMoveDirection) {
        guard canReorder, history.canMove(entry, direction) else { return }
        history.move(entry, direction)
    }

    private func remove(_ entry: ClipboardHistoryEntry) {
        if copiedID == entry.id { copiedID = nil }
        history.remove(entry)
    }

    @ViewBuilder private func preview(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .image:
            if let name = entry.imageFile, let image = ClipboardImageStore.thumbnail(named: name) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .help("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
            } else {
                Text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .files:
            // One image file shows itself; anything else reads as its name
            // or its count, the way the panel lists files.
            if entry.filePaths.count == 1, let path = entry.filePaths.first,
               ClipboardImageStore.isImageFile(atPath: path),
               let image = ClipboardImageStore.fileThumbnail(atPath: path) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .help(path)
            } else {
                Label(entry.filePaths.count == 1
                      ? (entry.fileNames.first ?? entry.preview)
                      : String(format: text.fileCountFormat, entry.filePaths.count),
                      systemImage: "folder")
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .help(entry.filePaths.joined(separator: "\n"))
            }
        case .text:
            Text(entry.preview)
                .font(.system(size: 12))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
