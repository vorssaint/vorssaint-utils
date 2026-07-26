// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PanelClipboardView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
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
        .onAppear { PanelInteractionState.shared.keepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
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
            }
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
            ScrollView {
                // Lazy: a large history would otherwise build every row, and
                // decode every image thumbnail, each time the panel opens.
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(filteredEntries) { entry in
                        entryRow(entry)
                    }
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

    private var shortcut: GlobalShortcut {
        GlobalShortcut.saved(for: DefaultsKey.clipboardHistoryShortcut,
                             fallback: .clipboardDefault)
    }

    @ViewBuilder
    private func entryPreview(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            Text(entry.preview)
                .font(.system(size: 10.5))
                .lineLimit(3)
                .truncationMode(.tail)
                .textSelection(.enabled)
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

    private func entryRow(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if entry.isPinned {
                Label(text.pinned, systemImage: "pin.fill")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            entryPreview(entry)
            HStack(spacing: 6) {
                Button {
                    history.move(entry, .up)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(text.moveUp)
                .disabled(!canReorderEntries || !history.canMove(entry, .up))
                Button {
                    history.move(entry, .down)
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(text.moveDown)
                .disabled(!canReorderEntries || !history.canMove(entry, .down))
                Button {
                    history.togglePin(entry)
                } label: {
                    Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(entry.isPinned ? text.unpin : text.pin)
                Button {
                    history.copy(entry)
                    copiedID = entry.id
                } label: {
                    Label(copiedID == entry.id ? text.copied : text.copy,
                          systemImage: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                Button {
                    history.remove(entry)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(text.delete)
                Spacer()
                Text(entry.copiedAt, style: .time)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .panelCard()
    }
}
