// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PanelClipboardView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var navigator = PanelKeyboardNavigator.shared
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var enabled = false
    @AppStorage(DefaultsKey.clipboardHistoryShortcutEnabled) private var shortcutEnabled = true
    @State private var query = ""
    @State private var copiedID: UUID?

    var onClose: () -> Void

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var filteredEntries: [ClipboardHistoryEntry] {
        history.filteredEntries(matching: query)
    }

    private var canReorderEntries: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            controls
            entriesList
        }
        .onAppear { PanelInteractionState.shared.viewKeepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(text.title, systemImage: "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.uninstallerCancel)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(text.enable, isOn: $enabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5, weight: .medium))
                .onChange(of: enabled) { _, _ in
                    ClipboardHistoryService.shared.syncWithPreferences()
                }
                .panelKeyboardRow(PanelRowID(.utilities, "clipboard-enable"),
                                  actions: PanelRowActions(activate: { enabled.toggle() }))
            Text(enabled ? text.caption : text.disabled)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if enabled, shortcutEnabled {
                Text("\(text.shortcut): \(shortcut.displayString)")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                TextField(text.search, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .disabled(history.entries.isEmpty)
                Button {
                    history.clearRecent()
                    copiedID = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(text.clearRecent)
                .disabled(history.recentEntries.isEmpty)
                .panelKeyboardRow(history.recentEntries.isEmpty ? nil : PanelRowID(.utilities, "clipboard-clearRecent"),
                                  actions: PanelRowActions(activate: {
                                      history.clearRecent()
                                      copiedID = nil
                                  }), cornerRadius: 6)
                Button {
                    history.showHistoryWindow()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(text.shortcut)
                .panelKeyboardRow(PanelRowID(.utilities, "clipboard-showWindow"),
                                  actions: PanelRowActions(activate: { history.showHistoryWindow() }), cornerRadius: 6)
            }
            .panelKeyboardRowGroup(history.recentEntries.isEmpty
                                   ? [PanelRowID(.utilities, "clipboard-showWindow")]
                                   : [PanelRowID(.utilities, "clipboard-clearRecent"),
                                      PanelRowID(.utilities, "clipboard-showWindow")])
        }
        .panelCard()
    }

    @ViewBuilder
    private var entriesList: some View {
        if history.entries.isEmpty {
            emptyState(text.empty)
        } else if filteredEntries.isEmpty {
            emptyState(text.noResults)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(filteredEntries) { entry in
                            entryRow(entry).id(entry.id)
                        }
                    }
                }
                .panelKeyboardRowList(filteredEntries.flatMap(keyboardRows))
                .onChange(of: navigator.focus) { _, focus in
                    guard let entryID = focusedEntryID(focus) else { return }
                    proxy.scrollTo(entryID, anchor: .center)
                }
            }
            .frame(maxHeight: 260)
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .panelCard()
    }

    /// One card's buttons, left to right. Only the ids the card actually
    /// registers: a missing neighbour would strand Left/Right inside the group.
    private func keyboardRows(for entry: ClipboardHistoryEntry) -> [PanelRowID] {
        var ids: [PanelRowID] = []
        if canReorderEntries, history.canMove(entry, .up) { ids.append(keyboardRow(entry, "up")) }
        if canReorderEntries, history.canMove(entry, .down) { ids.append(keyboardRow(entry, "down")) }
        ids.append(keyboardRow(entry, "pin"))
        ids.append(keyboardRow(entry, "copy"))
        ids.append(keyboardRow(entry, "delete"))
        return ids
    }

    private func keyboardRow(_ entry: ClipboardHistoryEntry, _ action: String) -> PanelRowID {
        PanelRowID(.utilities, "clipboard-\(entry.id)-\(action)")
    }

    private func focusedEntryID(_ focus: PanelFocusTarget?) -> UUID? {
        guard case .row(let row)? = focus,
              row.section == .utilities,
              let localID = row.local as? String else { return nil }
        return filteredEntries.first { localID.hasPrefix("clipboard-\($0.id)-") }?.id
    }

    private var shortcut: GlobalShortcut {
        GlobalShortcut.saved(for: DefaultsKey.clipboardHistoryShortcut,
                             fallback: .clipboardDefault)
    }

    @ViewBuilder
    private func entryPreview(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            // Deliberately not selectable: clicking a selectable Text swaps in
            // the selection renderer, which lays the whole preview out and
            // ignores the line limit, so a long entry paints over the rows
            // below it. The history window shows the full, selectable text.
            Text(entry.preview)
                .font(.system(size: 10.5))
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            HStack(alignment: .center, spacing: 7) {
                if let name = entry.imageFile,
                   let thumbnail = ClipboardImageStore.thumbnail(named: name) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 110, maxHeight: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        case .files:
            if entry.filePaths.count == 1,
               let path = entry.filePaths.first,
               ClipboardImageStore.isImageFile(atPath: path),
               let thumbnail = ClipboardImageStore.fileThumbnail(atPath: path) {
                HStack(alignment: .center, spacing: 7) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 110, maxHeight: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text(entry.fileNames.first ?? entry.preview)
                        .font(.system(size: 10.5))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .help(path)
            } else {
                HStack(alignment: .center, spacing: 7) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.filePaths.count == 1
                         ? (entry.fileNames.first ?? entry.preview)
                         : String(format: text.fileCountFormat, entry.filePaths.count))
                        .font(.system(size: 10.5))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .help(entry.filePaths.joined(separator: "\n"))
            }
        }
    }

    private func entryRow(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if entry.isPinned {
                Label(text.pinned, systemImage: "pin.fill")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            entryPreview(entry)
            HStack(spacing: 6) {
                let canMoveUp = canReorderEntries && history.canMove(entry, .up)
                let canMoveDown = canReorderEntries && history.canMove(entry, .down)
                Button {
                    history.move(entry, .up)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(text.moveUp)
                .disabled(!canMoveUp)
                .panelKeyboardRow(canMoveUp ? keyboardRow(entry, "up") : nil,
                                  actions: PanelRowActions(activate: { history.move(entry, .up) }), cornerRadius: 6)
                Button {
                    history.move(entry, .down)
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(text.moveDown)
                .disabled(!canMoveDown)
                .panelKeyboardRow(canMoveDown ? keyboardRow(entry, "down") : nil,
                                  actions: PanelRowActions(activate: { history.move(entry, .down) }), cornerRadius: 6)
                Button {
                    history.togglePin(entry)
                } label: {
                    Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(entry.isPinned ? text.unpin : text.pin)
                .panelKeyboardRow(keyboardRow(entry, "pin"),
                                  actions: PanelRowActions(activate: { history.togglePin(entry) }), cornerRadius: 6)
                Button {
                    // The tick means "it is on the clipboard", so it waits for
                    // the write instead of announcing one still queued behind
                    // a stalled pasteboard provider.
                    history.copy(entry) { copied in
                        if copied { copiedID = entry.id }
                    }
                } label: {
                    Label(copiedID == entry.id ? text.copied : text.copy,
                          systemImage: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .panelKeyboardRow(keyboardRow(entry, "copy"),
                                  actions: PanelRowActions(activate: {
                                      history.copy(entry) { copied in
                                          if copied { copiedID = entry.id }
                                      }
                                  }), cornerRadius: 6)
                Button {
                    history.remove(entry)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(text.delete)
                .panelKeyboardRow(keyboardRow(entry, "delete"),
                                  actions: PanelRowActions(activate: { history.remove(entry) }), cornerRadius: 6)
                Spacer()
                Text(entry.copiedAt, style: .time)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            .panelKeyboardRowGroup(keyboardRows(for: entry))
        }
        .panelCard()
    }
}
