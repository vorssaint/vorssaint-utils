// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardQuickPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @FocusState private var searchFocused: Bool
    @State private var hoveredEntryID: UUID?

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var filtered: [ClipboardHistoryEntry] {
        history.filteredQuickEntries
    }

    private var canReorderEntries: Bool {
        history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            search
            content
            footer
        }
        .padding(16)
        .frame(width: 520, height: 560, alignment: .topLeading)
        .background(.regularMaterial)
        .onAppear {
            hoveredEntryID = nil
            DispatchQueue.main.async { searchFocused = true }
        }
        .onDisappear {
            hoveredEntryID = nil
        }
        .onChange(of: history.quickWindowPresentationID) { _, _ in
            hoveredEntryID = nil
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(text.title)
                    .font(.system(size: 15, weight: .bold))
                Text(text.shortcutHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                shortcutGuide
            }
            Spacer()
            Button {
                history.hideHistoryWindow()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }

    private var search: some View {
        TextField(text.search, text: $history.quickQuery)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState(history.entries.isEmpty ? text.empty : text.noResults)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // Lazy: a large history would otherwise build every row,
                    // and decode every image thumbnail, each time the panel
                    // opens.
                    LazyVStack(alignment: .leading, spacing: 7) {
                        if history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            section(title: text.pinned, entries: history.pinnedEntries)
                            section(title: text.recent, entries: history.recentEntries,
                                    followsSection: !history.pinnedEntries.isEmpty)
                        } else {
                            section(title: text.newestFirst, entries: filtered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: history.quickSelectionIndex) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
                .onChange(of: history.quickSelectionIsVisible) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
                .onChange(of: history.quickQuery) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
            }
        }
    }

    /// Emits the header and the rows straight into the enclosing lazy stack:
    /// wrapped in their own container the whole section would become one lazy
    /// unit and build every row at once.
    @ViewBuilder
    private func section(title: String, entries: [ClipboardHistoryEntry],
                         followsSection: Bool = false) -> some View {
        if !entries.isEmpty {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
                .padding(.top, followsSection ? 3 : 0)
            ForEach(entries) { entry in
                entryRow(entry,
                         shortcutIndex: shortcutIndex(for: entry),
                         isSelected: history.quickSelectionIsVisible
                            && history.selectedQuickEntryID == entry.id,
                         isBatchSelected: history.isQuickBatchSelected(entry),
                         isHovered: hoveredEntryID == entry.id)
                    .id(entry.id)
            }
        }
    }

    private var shortcutGuide: some View {
        HStack(spacing: 6) {
            shortcutBadge(key: text.clickRowShortcut, action: l10n.s.menuPaste)
            shortcutBadge(key: text.commandClickShortcut, action: text.selectShortcutAction)
            shortcutBadge(key: "Enter", action: l10n.s.menuPaste)
            shortcutBadge(key: "⌘C", action: text.copy)
        }
    }

    private func shortcutBadge(key: String, action: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.78))
            Text(action)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func entryRow(_ entry: ClipboardHistoryEntry,
                          shortcutIndex: Int?,
                          isSelected: Bool,
                          isBatchSelected: Bool,
                          isHovered: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                history.toggleQuickBatchSelection(entry)
            } label: {
                leadingMarker(entry: entry,
                              shortcutIndex: shortcutIndex,
                              isBatchSelected: isBatchSelected,
                              isHovered: isHovered)
            }
            .buttonStyle(.plain)
            .help(isBatchSelected ? text.unselectMultiple : text.selectMultiple)

            VStack(alignment: .leading, spacing: 5) {
                entryContent(entry)
                HStack(spacing: 7) {
                    Text(entry.copiedAt, style: .time)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        history.move(entry, .up)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 18, height: 18)
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
                            .frame(width: 18, height: 18)
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
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(entry.isPinned ? text.unpin : text.pin)
                    Button {
                        history.remove(entry)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(text.delete)
                    Button {
                        history.copyOnlyQuickEntry(entry)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .help(text.copy)
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground(entry: entry,
                                    isSelected: isSelected,
                                    isBatchSelected: isBatchSelected,
                                    isHovered: isHovered))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isBatchSelected ? Color.accentColor.opacity(0.5)
                        : isSelected ? Color.accentColor.opacity(0.28)
                        : isHovered ? Color.accentColor.opacity(0.22) : Color.clear,
                        lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredEntryID = hovering ? entry.id : (hoveredEntryID == entry.id ? nil : hoveredEntryID)
            }
        }
        .onTapGesture {
            // Finder muscle memory: ⌘-click and ⇧-click build a selection.
            // A plain click pastes; on a selected row it pastes the whole
            // selection. Copying without pasting lives in ⌘C, the blue
            // button and the footer.
            let modifiers = NSEvent.modifierFlags.intersection([.command, .shift])
            if modifiers.contains(.command) {
                history.toggleQuickBatchSelection(entry)
            } else if modifiers.contains(.shift) {
                history.extendQuickBatchSelection(to: entry)
            } else if history.isQuickBatchSelected(entry) {
                history.copySelectedQuickEntry()
            } else {
                history.copyQuickEntry(entry)
            }
        }
        .help(entry.preview)
    }

    @ViewBuilder
    private func entryContent(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            Text(entry.preview)
                .font(.system(size: 11.5))
                .lineLimit(3)
                .truncationMode(.tail)
                .help(entry.preview)
        case .image:
            HStack(alignment: .center, spacing: 8) {
                if let name = entry.imageFile,
                   let thumbnail = ClipboardImageStore.thumbnail(named: name) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 150, maxHeight: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                Text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .help("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
        case .files:
            HStack(alignment: .center, spacing: 8) {
                fileIcon(entry)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileTitle(entry))
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if entry.filePaths.count > 1 {
                        Text(entry.preview)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
            }
            .help(entry.filePaths.joined(separator: "\n"))
        }
    }

    private func fileTitle(_ entry: ClipboardHistoryEntry) -> String {
        if entry.filePaths.count == 1 {
            return entry.fileNames.first ?? entry.preview
        }
        return String(format: text.fileCountFormat, entry.filePaths.count)
    }

    private func fileIcon(_ entry: ClipboardHistoryEntry) -> some View {
        let icon: NSImage?
        if let path = entry.filePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            icon = NSWorkspace.shared.icon(forFile: path)
        } else {
            icon = nil
        }
        return Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
        }
    }

    @ViewBuilder
    private func leadingMarker(entry: ClipboardHistoryEntry,
                               shortcutIndex: Int?,
                               isBatchSelected: Bool,
                               isHovered: Bool) -> some View {
        if isBatchSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        } else if isHovered {
            // An empty checkbox on hover, so the multi-select is visible
            // before anyone knows about ⌘-click.
            Image(systemName: "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.65))
                .frame(width: 32, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.07))
                )
        } else if let shortcutIndex {
            Text("⌘\(shortcutIndex + 1)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
        } else {
            Image(systemName: entry.isPinned ? "pin.fill" : kindSymbol(entry.kind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(entry.isPinned ? Color.accentColor : Color.secondary)
                .opacity(entry.isPinned ? 1 : 0.65)
                .frame(width: 32, height: 24)
        }
    }

    private func kindSymbol(_ kind: ClipboardHistoryEntryKind) -> String {
        switch kind {
        case .text: return "doc.text"
        case .image: return "photo"
        case .files: return "folder"
        }
    }

    private func rowBackground(entry: ClipboardHistoryEntry,
                               isSelected: Bool,
                               isBatchSelected: Bool,
                               isHovered: Bool) -> Color {
        if isBatchSelected { return Color.accentColor.opacity(isHovered ? 0.2 : 0.16) }
        if isSelected { return Color.accentColor.opacity(isHovered ? 0.16 : 0.12) }
        if isHovered { return Color.accentColor.opacity(0.1) }
        return Color.primary.opacity(entry.isPinned ? 0.075 : 0.045)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if history.quickBatchCount > 0 {
                // The selection's actions, spelled out: the visible twin of
                // Enter and ⌘C, so the flow needs no shortcut knowledge.
                Button(String(format: text.pasteSelectedFormat, history.quickBatchCount)) {
                    history.copySelectedQuickEntry()
                }
                .buttonStyle(.borderedProminent)
                Button(String(format: text.copySelectedFormat, history.quickBatchCount)) {
                    history.copySelectedQuickEntryOnly()
                }
                Button(text.clearSelection) {
                    history.clearQuickBatchSelection()
                }
            } else {
                Button(text.clearRecent) {
                    history.clearRecent()
                }
                .disabled(history.recentEntries.isEmpty)
                Button(text.clearAll) {
                    history.clearAll()
                }
                .disabled(history.recentEntries.isEmpty)
            }
            Spacer()
            Text("\(history.entries.count)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
    }

    private func shortcutIndex(for entry: ClipboardHistoryEntry) -> Int? {
        guard let index = filtered.firstIndex(where: { $0.id == entry.id }), index < 9 else { return nil }
        return index
    }

    private func scrollSelectedEntry(with proxy: ScrollViewProxy) {
        guard history.quickSelectionIsVisible, let id = history.selectedQuickEntryID else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}
