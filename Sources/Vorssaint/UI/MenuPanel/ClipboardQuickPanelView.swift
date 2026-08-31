// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardQuickPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @FocusState private var searchFocused: Bool
    @State private var hoveredEntryID: UUID?
    @State private var previewEntryID: UUID?
    @State private var previewIsEditing = false

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var filtered: [ClipboardHistoryEntry] {
        history.filteredQuickEntries
    }

    private var previewEntry: ClipboardHistoryEntry? {
        ClipboardHistorySelection.previewEntry(preferredID: previewEntryID,
                                               visibleEntries: filtered,
                                               selectedEntry: history.selectedQuickEntry)
    }

    private var canReorderEntries: Bool {
        history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var panelSize: CGSize {
        history.quickPreviewPresented
            ? ClipboardHistoryService.quickPanelPreviewSize
            : ClipboardHistoryService.quickPanelCompactSize
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    content
                    Divider()
                    footer
                }
                if history.quickPreviewPresented {
                    Divider()
                    ClipboardEntryPreviewSidebar(text: text,
                                                 entry: previewEntry,
                                                 isEditing: $previewIsEditing,
                                                 onClose: { history.setQuickPreviewPresented(false) })
                        .frame(width: 280)
                        .transition(.opacity)
                }
            }
            // Over the list and the pane both: the card takes every key, so
            // nothing beside it should look, or be, clickable meanwhile.
            .overlay {
                if history.quickActionsPresented {
                    ZStack {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .onTapGesture { history.setQuickActionsPresented(false) }
                        actionsCard
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
            }
            .animation(.easeOut(duration: 0.14), value: history.quickActionsPresented)
        }
        .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
        .background(.regularMaterial)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            hoveredEntryID = nil
            previewEntryID = history.selectedQuickEntryID
            DispatchQueue.main.async { searchFocused = true }
        }
        .onDisappear {
            hoveredEntryID = nil
            previewEntryID = nil
            previewIsEditing = false
        }
        .onChange(of: history.quickSelectionIndex) { _, _ in
            previewEntryID = history.selectedQuickEntryID
        }
        .onChange(of: history.quickQuery) { _, _ in
            previewEntryID = history.selectedQuickEntryID
        }
        .onChange(of: history.quickWindowPresentationID) { _, _ in
            hoveredEntryID = nil
            previewEntryID = history.selectedQuickEntryID
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField(text.search, text: $history.quickQuery)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            Button {
                history.toggleQuickPreview()
            } label: {
                Label(text.previewLabel,
                      systemImage: history.quickPreviewPresented ? "sidebar.right" : "eye")
                    .foregroundStyle(history.quickPreviewPresented ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(previewEntry == nil && !history.quickPreviewPresented)
            .help(text.previewLabel)
            .accessibilityLabel(text.previewLabel)
            Button {
                history.hideHistoryWindow()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuClose)
            .accessibilityLabel(l10n.s.menuClose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState(history.entries.isEmpty ? text.empty : text.noResults)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // A plain stack for an ordinary history: with every row
                    // already laid out, scrolling is the clip view moving and
                    // nothing else, which is what makes it smooth. Only a
                    // very large history goes lazy, where building every row
                    // (and decoding every thumbnail) on open would cost more
                    // than the placement work a lazy stack does per tick.
                    Group {
                        if filtered.count <= Self.eagerRowLimit {
                            VStack(alignment: .leading, spacing: 0) { sections }
                        } else {
                            LazyVStack(alignment: .leading, spacing: 0) { sections }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(ScrollBounceDisabler())
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

    /// Emits the header and rows straight into the enclosing lazy stack. If
    /// wrapped, the whole section becomes one lazy unit and builds every row.
    private static let eagerRowLimit = 300

    @ViewBuilder
    private var sections: some View {
        if history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            section(title: text.pinned, entries: history.pinnedEntries)
            section(title: text.recent, entries: history.recentEntries,
                    followsSection: !history.pinnedEntries.isEmpty)
        } else {
            section(title: text.newestFirst, entries: filtered)
        }
    }

    @ViewBuilder
    private func section(title: String, entries: [ClipboardHistoryEntry],
                         followsSection: Bool = false) -> some View {
        if !entries.isEmpty {
            if followsSection {
                Divider()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                QuickEntryRow(entry: entry,
                              shortcutIndex: shortcutIndex(for: entry),
                              isSelected: history.quickSelectionIsVisible
                                 && history.selectedQuickEntryID == entry.id,
                              isBatchSelected: history.isQuickBatchSelected(entry),
                              isHovered: hoveredEntryID == entry.id,
                              canReorderEntries: canReorderEntries,
                              previewIsEditing: previewIsEditing,
                              language: l10n.language,
                              hoveredEntryID: $hoveredEntryID,
                              previewEntryID: $previewEntryID)
                    .equatable()
                    .id(entry.id)
                if index < entries.count - 1 {
                    Divider()
                        .padding(.leading, 43)
                        .padding(.trailing, 8)
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


    private var footer: some View {
        HStack(spacing: 8) {
            if history.quickBatchCount > 0 {
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
                Button {
                    history.clearRecent()
                } label: {
                    Label(text.clearRecent, systemImage: "trash")
                }
                .disabled(history.recentEntries.isEmpty)
            }
            Spacer()
            if let selected = history.selectedQuickEntry {
                HStack(spacing: 4) {
                    if !ClipboardHistoryService.dragItems(for: selected).isEmpty {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 9))
                        Text(String(format: text.dragHintFormat, l10n.s.shelfName))
                            .font(.system(size: 9.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 260, alignment: .trailing)
                Button {
                    history.toggleQuickActions()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "command")
                            .font(.system(size: 9, weight: .semibold))
                        Text("K")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        Text(text.actionsTitle)
                    }
                }
                .buttonStyle(.bordered)
                .help(text.actionsTitle)
            }
            HStack(spacing: 5) {
                Image(systemName: "doc.on.clipboard")
                Text("\(history.entries.count)")
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Everything that can be done to the selected entry, as a card over the
    /// list: the entry it is about at the top, one row per action with the key
    /// that does the same thing on the right. ⌘K opens it, Esc closes it, and
    /// the service owns the selection so the key monitor and the mouse agree.
    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let entry = history.selectedQuickEntry {
                HStack(spacing: 10) {
                    ClipboardKindGlyph(kind: entry.displayKind, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.kind == .text ? entry.preview : ClipboardKindPresentation.label(entry, text: text))
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 5) {
                            Text(ClipboardKindPresentation.label(entry, text: text))
                            Text("·")
                            Text(entry.copiedAt, style: .time)
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(UserDefaults.standard.bool(forKey: DefaultsKey.clipboardArrowOpensActions) ? "← ⌘K" : "⌘K")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)
                Divider()
            }
            VStack(spacing: 2) {
                ForEach(Array(history.quickActionRows.enumerated()), id: \.element.id) { index, action in
                    actionRow(action, isSelected: index == history.quickActionIndex)
                }
            }
            .padding(8)
        }
        .frame(width: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
    }

    private func actionRow(_ action: ClipboardHistoryService.QuickAction, isSelected: Bool) -> some View {
        let tint: Color = action.isDestructive ? .red : .accentColor
        return Button {
            history.runQuickAction(action)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(action.isDestructive ? Color.red : Color.primary.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? tint.opacity(0.18) : Color.primary.opacity(0.06))
                    )
                Text(action.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(action.isDestructive ? Color.red : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if let hint = action.keyHint {
                    Text(hint)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                }
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.13) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func shortcutIndex(for entry: ClipboardHistoryEntry) -> Int? {
        guard let index = filtered.firstIndex(where: { $0.id == entry.id }), index < 9 else { return nil }
        return index
    }

    private func scrollSelectedEntry(with proxy: ScrollViewProxy) {
        guard history.quickSelectionIsVisible, let id = history.selectedQuickEntryID else { return }
        // No anchor and no animation: the list moves only when the selected
        // row is off screen, and then straight to it, so every arrow press
        // costs the same and the rows never redraw mid-slide.
        proxy.scrollTo(id)
    }
}

/// One row of the list, a view of its own with value inputs so SwiftUI can
/// skip the rows a change did not touch. Before this every hover, and every
/// row passing under a still pointer during a scroll, rebuilt the whole list,
/// which is what made a flick stall for a quarter second at a time.
private struct QuickEntryRow: View, Equatable {
    let entry: ClipboardHistoryEntry
    let shortcutIndex: Int?
    let isSelected: Bool
    let isBatchSelected: Bool
    let isHovered: Bool
    let canReorderEntries: Bool
    let previewIsEditing: Bool
    let language: AppLanguage
    @Binding var hoveredEntryID: UUID?
    @Binding var previewEntryID: UUID?
    /// The pane follows a row only once the pointer has rested on it: while
    /// rows stream under a still pointer during a scroll, every one of them
    /// would otherwise redraw the pane, and a long entry costs a frame or two
    /// each time.
    @State private var previewFollowTask: Task<Void, Never>?
    private static let previewFollowDelay: Duration = .milliseconds(120)

    private var history: ClipboardHistoryService { .shared }
    private var l10n: L10n { .shared }
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(language) }

    // The bindings are channels back to the list, not part of what the row
    // looks like, so they stay out of the comparison.
    static func == (lhs: QuickEntryRow, rhs: QuickEntryRow) -> Bool {
        lhs.entry == rhs.entry
            && lhs.shortcutIndex == rhs.shortcutIndex
            && lhs.isSelected == rhs.isSelected
            && lhs.isBatchSelected == rhs.isBatchSelected
            && lhs.isHovered == rhs.isHovered
            && lhs.canReorderEntries == rhs.canReorderEntries
            && lhs.previewIsEditing == rhs.previewIsEditing
            && lhs.language == rhs.language
    }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Button {
                history.toggleQuickBatchSelection(entry)
            } label: {
                leadingMarker(entry: entry,
                              isBatchSelected: isBatchSelected,
                              isHovered: isHovered)
            }
            .buttonStyle(.plain)
            .help(isBatchSelected ? text.unselectMultiple : text.selectMultiple)

            HStack(alignment: .center, spacing: 9) {
                ClipboardKindGlyph(kind: entry.displayKind)
                entryContent(entry)
            }
            .modifier(FileDraggable(entry: entry, activate: activate))
            Spacer(minLength: 8)
            // One width for both states, so the buttons that replace the
            // labels on hover never change the room the text has, and the
            // text never reflows under the pointer.
            entryTrailing(entry, shortcutIndex: shortcutIndex, isHovered: isHovered)
                .frame(width: Self.trailingWidth, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(rowBackground(isSelected: isSelected,
                                    isBatchSelected: isBatchSelected,
                                    isHovered: isHovered))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isBatchSelected ? Color.accentColor.opacity(0.38)
                              : isSelected ? Color.accentColor.opacity(0.24) : Color.clear,
                              lineWidth: 1)
        )
        .contentShape(Rectangle())
        .contextMenu { entryActions(entry) }
        .onHover { hovering in
            // A row arriving under a pointer that has not moved since the
            // arrow keys took over is not a hover.
            if hovering, NSEvent.mouseLocation == history.keyboardSelectionPointer { return }
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredEntryID = hovering ? entry.id : (hoveredEntryID == entry.id ? nil : hoveredEntryID)
            }
            previewFollowTask?.cancel()
            guard hovering, !previewIsEditing else { return }
            let id = entry.id
            previewFollowTask = Task { @MainActor in
                try? await Task.sleep(for: Self.previewFollowDelay)
                guard !Task.isCancelled else { return }
                previewEntryID = id
            }
        }
        .onTapGesture { activate(entry) }
    }

    /// Read at draw time rather than observed: the switch lives in Settings,
    /// and the window is rebuilt on its next opening anyway.
    private static var uniformRows: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.clipboardUniformRows)
    }

    @ViewBuilder
    private func entryContent(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            Text(entry.preview)
                .font(.system(size: 12))
                .lineLimit(Self.uniformRows ? 1 : 2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            HStack(alignment: .center, spacing: 8) {
                if let name = entry.imageFile,
                   let thumbnail = ClipboardImageStore.thumbnail(named: name) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: Self.uniformRows ? .fill : .fit)
                        .frame(maxWidth: Self.uniformRows ? 30 : 240, maxHeight: Self.uniformRows ? 30 : 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                Text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
        case .files:
            if entry.filePaths.count == 1,
               let path = entry.filePaths.first,
               ClipboardImageStore.isImageFile(atPath: path),
               let thumbnail = ClipboardImageStore.fileThumbnail(atPath: path) {
                HStack(alignment: .center, spacing: 8) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: Self.uniformRows ? .fill : .fit)
                        .frame(maxWidth: Self.uniformRows ? 30 : 240, maxHeight: Self.uniformRows ? 30 : 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.fileNames.first ?? entry.preview)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let dim = ClipboardImageStore.imageDimensionsLabel(atPath: path) {
                            Text("\(text.imageEntryLabel) · \(dim)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(path)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileTitle(entry))
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if entry.filePaths.count > 1 {
                        Text(entry.preview)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.filePaths.joined(separator: "\n"))
            }
        }
    }

    private static let trailingWidth: CGFloat = 92

    @ViewBuilder
    private func entryTrailing(_ entry: ClipboardHistoryEntry,
                               shortcutIndex: Int?,
                               isHovered: Bool) -> some View {
        if isHovered {
            HStack(spacing: 4) {
                Button {
                    history.copyOnlyQuickEntry(entry)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(text.copy)
                Menu {
                    entryActions(entry)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        } else {
            VStack(alignment: .trailing, spacing: 3) {
                Text(ClipboardKindPresentation.label(entry, text: text))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ClipboardKindPresentation.tint(entry.displayKind))
                    .lineLimit(1)
                    .frame(maxWidth: 90, alignment: .trailing)
                Text(entry.copiedAt, style: .time)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                if let shortcutIndex {
                    Text("⌘\(shortcutIndex + 1)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func entryActions(_ entry: ClipboardHistoryEntry) -> some View {
        Button(l10n.s.menuPaste) {
            history.copyQuickEntry(entry)
        }
        Button(text.copy) {
            history.copyOnlyQuickEntry(entry)
        }
        Divider()
        Button(entry.isPinned ? text.unpin : text.pin) {
            history.togglePin(entry)
        }
        Button(text.moveUp) {
            history.move(entry, .up)
        }
        .disabled(!canReorderEntries || !history.canMove(entry, .up))
        Button(text.moveDown) {
            history.move(entry, .down)
        }
        .disabled(!canReorderEntries || !history.canMove(entry, .down))
        Divider()
        Button(text.delete, role: .destructive) {
            history.remove(entry)
        }
    }

    private func activate(_ entry: ClipboardHistoryEntry) {
        // Finder muscle memory: ⌘-click and ⇧-click build a selection.
        // A plain click pastes; on a selected row it pastes the selection.
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

    private func fileTitle(_ entry: ClipboardHistoryEntry) -> String {
        if entry.filePaths.count == 1 {
            return entry.fileNames.first ?? entry.preview
        }
        return String(format: text.fileCountFormat, entry.filePaths.count)
    }

    @ViewBuilder
    private func leadingMarker(entry: ClipboardHistoryEntry,
                               isBatchSelected: Bool,
                               isHovered: Bool) -> some View {
        if isBatchSelected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 25, height: 25)
        } else if isHovered {
            Image(systemName: "circle")
                .foregroundStyle(Color.accentColor.opacity(0.7))
                .frame(width: 25, height: 25)
        } else if entry.kind == .files,
                  entry.filePaths.count == 1,
                  let path = entry.filePaths.first,
                  ClipboardImageStore.isImageFile(atPath: path) {
            Image(systemName: entry.isPinned ? "pin.fill" : "photo")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(entry.isPinned ? Color.accentColor : Color.secondary)
                .frame(width: 25, height: 25)
        } else if let icon = fileIcon(for: entry) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .frame(width: 25, height: 25)
        } else {
            Image(systemName: entry.isPinned ? "pin.fill" : kindSymbol(entry.kind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(entry.isPinned ? Color.accentColor : Color.secondary)
                .frame(width: 25, height: 25)
        }
    }

    private func fileIcon(for entry: ClipboardHistoryEntry) -> NSImage? {
        guard entry.kind == .files,
              let path = entry.filePaths.first(where: { FileManager.default.fileExists(atPath: $0) })
        else { return nil }
        return ClipboardImageStore.fileIcon(atPath: path)
    }

    private func kindSymbol(_ kind: ClipboardHistoryEntryKind) -> String {
        switch kind {
        case .text: return "doc.text"
        case .image: return "photo"
        case .files: return "folder"
        }
    }

    private func rowBackground(isSelected: Bool,
                               isBatchSelected: Bool,
                               isHovered: Bool) -> Color {
        if isBatchSelected { return Color.accentColor.opacity(isHovered ? 0.17 : 0.13) }
        if isSelected { return Color.accentColor.opacity(isHovered ? 0.13 : 0.09) }
        if isHovered { return Color.primary.opacity(0.055) }
        return .clear
    }
}

/// Files and images drag out of their row as real files; text only when
/// Settings allows it, otherwise the row is left alone.
private struct FileDraggable: ViewModifier {
    let entry: ClipboardHistoryEntry
    let activate: (ClipboardHistoryEntry) -> Void

    func body(content: Content) -> some View {
        let items = ClipboardHistoryService.dragItems(for: entry)
        if items.isEmpty {
            content
        } else {
            content.overlay(
                ClipboardFileDragSource(items: items) { _ in activate(entry) }
            )
        }
    }
}

/// Turns off the rubber-band bounce of the enclosing scroll view. SwiftUI's
/// `scrollBounceBehavior` still bounces once the content is taller than the
/// view, and a list of rows has nothing to show past its ends.
private struct ScrollBounceDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> BounceDisablingView { BounceDisablingView() }
    func updateNSView(_ view: BounceDisablingView, context: Context) { view.apply() }

    final class BounceDisablingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            // The scroll view is an ancestor only once SwiftUI has placed
            // this view, which is after the current layout pass.
            DispatchQueue.main.async { [weak self] in
                self?.enclosingScrollView?.verticalScrollElasticity = .none
            }
        }
    }
}
