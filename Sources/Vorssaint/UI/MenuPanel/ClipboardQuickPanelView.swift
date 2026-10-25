// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardQuickPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @FocusState private var searchFocused: Bool
    @State private var previewSelection = QuickPreviewSelection()
    @State private var previewIsEditing = false
    @State private var clearingIDs: [UUID: Date]?

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var filtered: [ClipboardHistoryEntry] {
        history.filteredQuickEntries
    }

    private var canReorderEntries: Bool {
        history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchTokens: [String] {
        ClipboardHistorySearch.searchTokens(for: history.quickQuery)
    }

    private var layout: ClipboardHistoryLayout {
        history.quickLayout
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                content
                if history.quickPreviewPresented {
                    Divider()
                    QuickPreviewPane(text: text,
                                     selection: previewSelection,
                                     isEditing: $previewIsEditing,
                                     onClose: { history.setQuickPreviewPresented(false) })
                        .frame(width: 280)
                        .transition(.opacity)
                }
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            previewSelection.select(history.selectedQuickEntryID)
            DispatchQueue.main.async { searchFocused = true }
        }
        .onDisappear {
            previewSelection.select(nil)
            previewIsEditing = false
        }
        .onChange(of: history.quickSelectionID) { _, _ in
            previewSelection.select(history.selectedQuickEntryID)
        }
        .onChange(of: history.quickQuery) { _, _ in
            previewSelection.select(history.selectedQuickEntryID)
        }
        .onChange(of: history.quickWindowPresentationID) { _, _ in
            previewSelection.select(history.selectedQuickEntryID)
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
            .disabled(history.selectedQuickEntry == nil && !history.quickPreviewPresented)
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
                // A plain stack for an ordinary history: with every entry
                // already laid out, scrolling is the clip view moving and
                // nothing else, which is what makes it smooth. Only a very
                // large history goes lazy, where building every entry (and
                // decoding every thumbnail) on open would cost more than the
                // placement work a lazy stack does per tick.
                Group {
                    if layout == .list {
                        ScrollView {
                            Group {
                                if filtered.count <= Self.eagerRowLimit {
                                    VStack(alignment: .leading, spacing: 0) { topAnchor; sections }
                                } else {
                                    LazyVStack(alignment: .leading, spacing: 0) { topAnchor; sections }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, Self.listVerticalInset)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ScrollView(.horizontal) {
                            Group {
                                if filtered.count <= Self.eagerRowLimit {
                                    HStack(spacing: Self.cardSpacing) { topAnchor; sections }
                                } else {
                                    LazyHStack(spacing: Self.cardSpacing) { topAnchor; sections }
                                }
                            }
                            .padding(.trailing, Self.listInset)
                            .frame(maxHeight: .infinity)
                        }
                    }
                }
                .background(ScrollBounceDisabler())
                .onChange(of: history.quickSelectionID) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
                .onChange(of: history.quickSelectionIsVisible) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
                .onChange(of: history.quickQuery) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
                // The preview takes its width out of the strip, so a card
                // near the trailing edge would slide out of view under it.
                // The next pass has the strip at its new width.
                .onChange(of: history.quickPreviewPresented) { _, _ in
                    guard layout == .cards else { return }
                    DispatchQueue.main.async { scrollSelectedEntry(with: proxy) }
                }
                // The window is only hidden between uses, so without this it
                // reopens wherever it was scrolled, while the selection and
                // ⌘1 to ⌘9 already start from the first entries.
                .onChange(of: history.quickWindowPresentationID) { _, _ in
                    proxy.scrollTo(Self.topAnchorID, anchor: layout == .list ? .top : .leading)
                }
            }
        }
    }

    /// Emits the headers, rows and cards straight into the enclosing lazy
    /// stack. If wrapped, the whole section becomes one lazy unit and builds
    /// every entry.
    private static let eagerRowLimit = 300

    private static let listVerticalInset: CGFloat = 6
    private static let listInset: CGFloat = 16
    private static let cardSpacing: CGFloat = 12

    /// The list's top inset, above the first section's header that
    /// scrolling to the first row would leave cut off, or the strip's
    /// leading inset. Scrolling it into place lands exactly where a first
    /// open starts.
    private static let topAnchorID = "clipboard-list-top"

    private var topAnchor: some View {
        Color.clear
            .frame(width: layout == .list ? nil : Self.listInset - Self.cardSpacing,
                   height: layout == .list ? Self.listVerticalInset : 1)
            .id(Self.topAnchorID)
    }

    /// Pinned entries first, then a rule, then the recent ones; the list
    /// heads each group with its name. A search lists its matches by
    /// relevance with no rule.
    @ViewBuilder
    private var sections: some View {
        if history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if layout == .list {
                rows(title: text.pinned, entries: history.pinnedEntries)
                rows(title: text.recent, entries: history.recentEntries,
                     followsSection: !history.pinnedEntries.isEmpty)
            } else {
                cards(history.pinnedEntries)
                if !history.pinnedEntries.isEmpty, !history.recentEntries.isEmpty {
                    Divider().frame(height: QuickEntryView.cardSize.height - 24)
                }
                cards(history.recentEntries)
            }
        } else if layout == .list {
            rows(title: nil, entries: filtered)
        } else {
            cards(filtered)
        }
    }

    @ViewBuilder
    private func rows(title: String?, entries: [ClipboardHistoryEntry],
                      followsSection: Bool = false) -> some View {
        if !entries.isEmpty {
            if followsSection {
                Divider()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                entryView(entry)
                if index < entries.count - 1 {
                    Divider()
                        .padding(.leading, 43)
                        .padding(.trailing, 8)
                }
            }
        }
    }

    private func cards(_ entries: [ClipboardHistoryEntry]) -> some View {
        ForEach(entries) { entry in
            entryView(entry)
        }
    }

    private func entryView(_ entry: ClipboardHistoryEntry) -> some View {
        QuickEntryView(layout: layout,
                       entry: entry,
                       tokens: searchTokens,
                       shortcutIndex: shortcutIndex(for: entry),
                       isSelected: history.quickSelectionIsVisible
                          && history.selectedQuickEntryID == entry.id,
                       isBatchSelected: history.isQuickBatchSelected(entry),
                       canReorderEntries: canReorderEntries,
                       previewIsEditing: previewIsEditing,
                       presentationID: history.quickWindowPresentationID,
                       language: l10n.language,
                       previewSelection: previewSelection)
            .equatable()
            .id(entry.id)
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
                Button(String(format: text.deleteSelectedFormat, history.quickBatchCount), role: .destructive) {
                    history.removeSelectedQuickEntries()
                }
                Button(text.clearSelection) {
                    history.clearQuickBatchSelection()
                }
            } else {
                Button {
                    clearingIDs = history.recentEntriesSnapshot
                } label: {
                    Label(text.clearRecent, systemImage: "trash")
                }
                .disabled(history.recentEntries.isEmpty)
                .modifier(ClipboardClearRecentConfirmation(entryIDs: $clearingIDs))
            }
            Spacer()
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

    private func shortcutIndex(for entry: ClipboardHistoryEntry) -> Int? {
        filtered.prefix(9).firstIndex(where: { $0.id == entry.id })
    }

    private func scrollSelectedEntry(with proxy: ScrollViewProxy) {
        guard history.quickSelectionIsVisible, let id = history.selectedQuickEntryID else { return }
        // No anchor and no animation: the list moves only when the selected
        // row is off screen, and then straight to it, so every arrow press
        // costs the same and the rows never redraw mid-slide.
        proxy.scrollTo(id)
    }
}

/// The sidebar alone observes hover selection. Changing its entry never
/// invalidates the enclosing list.
private final class QuickPreviewSelection: ObservableObject {
    @Published private(set) var entryID: UUID?

    func select(_ id: UUID?) {
        guard entryID != id else { return }
        entryID = id
    }
}

private struct QuickPreviewPane: View {
    let text: ClipboardFeatureStrings
    @ObservedObject var selection: QuickPreviewSelection
    @Binding var isEditing: Bool
    let onClose: () -> Void
    @ObservedObject private var history = ClipboardHistoryService.shared

    var body: some View {
        ClipboardEntryPreviewSidebar(text: text,
                                     entry: ClipboardHistorySelection.previewEntry(
                                        preferredID: selection.entryID,
                                        visibleEntries: history.filteredQuickEntries,
                                        selectedEntry: history.selectedQuickEntry),
                                     isEditing: $isEditing,
                                     onClose: onClose)
    }
}

/// One entry, as a row of the list or a card of the shelf. Keep hover within
/// it so moving the pointer does not rebuild the others. Value inputs let
/// SwiftUI skip entries unaffected by selection or history changes.
private struct QuickEntryView: View, Equatable {
    static let cardSize = CGSize(width: 184, height: 210)
    let layout: ClipboardHistoryLayout
    let entry: ClipboardHistoryEntry
    let tokens: [String]
    let shortcutIndex: Int?
    let isSelected: Bool
    let isBatchSelected: Bool
    let canReorderEntries: Bool
    let previewIsEditing: Bool
    let presentationID: UUID
    let language: AppLanguage
    let previewSelection: QuickPreviewSelection
    @State private var isHovered = false
    /// The pane follows a row only once the pointer has rested on it: while
    /// rows stream under a still pointer during a scroll, every one of them
    /// would otherwise redraw the pane, and a long entry costs a frame or two
    /// each time.
    @State private var previewFollowTask: Task<Void, Never>?
    private static let previewFollowDelay: Duration = .milliseconds(120)

    private var history: ClipboardHistoryService { .shared }
    private var l10n: L10n { .shared }
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(language) }

    private var isRow: Bool { layout == .list }

    // Preview selection is a channel to the sidebar, not part of this row's
    // appearance, so it stays out of the comparison.
    static func == (lhs: QuickEntryView, rhs: QuickEntryView) -> Bool {
        lhs.layout == rhs.layout
            && lhs.entry == rhs.entry
            && lhs.tokens == rhs.tokens
            && lhs.shortcutIndex == rhs.shortcutIndex
            && lhs.isSelected == rhs.isSelected
            && lhs.isBatchSelected == rhs.isBatchSelected
            && lhs.canReorderEntries == rhs.canReorderEntries
            && lhs.previewIsEditing == rhs.previewIsEditing
            && lhs.presentationID == rhs.presentationID
            && lhs.language == rhs.language
    }

    var body: some View {
        Group {
            if isRow { row } else { card }
        }
        .contentShape(Rectangle())
        .contextMenu { entryActions(entry) }
        .onHover { hovering in
            // A row arriving under a pointer that has not moved since the
            // arrow keys took over is not a hover.
            if hovering, NSEvent.mouseLocation == history.keyboardSelectionPointer { return }
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
            previewFollowTask?.cancel()
            guard hovering, !previewIsEditing else { return }
            let id = entry.id
            previewFollowTask = Task { @MainActor in
                try? await Task.sleep(for: Self.previewFollowDelay)
                guard !Task.isCancelled else { return }
                previewSelection.select(id)
            }
        }
        .onChange(of: previewIsEditing) { _, editing in
            if editing { previewFollowTask?.cancel() }
        }
        .onChange(of: presentationID) { _, _ in
            isHovered = false
            previewFollowTask?.cancel()
        }
        .onDisappear {
            isHovered = false
            previewFollowTask?.cancel()
        }
        .onTapGesture { activate(entry) }
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 9) {
            selectionButton
            entryContent(entry)
            Spacer(minLength: 8)
            entryTrailing(entry, isHovered: isHovered)
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
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            Divider()
            entryContent(entry)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            Divider()
            cardFooter
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(rowBackground(isSelected: isSelected,
                                        isBatchSelected: isBatchSelected,
                                        isHovered: isHovered)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isBatchSelected || isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                              lineWidth: isBatchSelected || isSelected ? 2.5 : 0.5)
        )
    }

    private var selectionButton: some View {
        Button {
            history.toggleQuickBatchSelection(entry)
        } label: {
            leadingMarker(entry: entry,
                          isBatchSelected: isBatchSelected,
                          isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .help(isBatchSelected ? text.unselectMultiple : text.selectMultiple)
    }

    private var cardHeader: some View {
        HStack(spacing: 6) {
            selectionButton
            if let app = sourceApp {
                Text(app.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            entryTrailing(entry, isHovered: isHovered)
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
    }

    /// Looked up once per app. An app removed since the copy has nothing to
    /// show, and the card keeps the kind's symbol. A miss is not kept, so an
    /// app installed later shows up without a restart.
    private static var sourceApps: [String: (name: String, icon: NSImage)] = [:]

    private var sourceApp: (name: String, icon: NSImage)? {
        guard let bundleID = entry.sourceBundleID else { return nil }
        if let cached = Self.sourceApps[bundleID] { return cached }
        let app = InstalledApps.url(for: bundleID).map {
            (name: InstalledApps.name(for: bundleID), icon: NSWorkspace.shared.icon(forFile: $0.path))
        }
        if let app { Self.sourceApps[bundleID] = app }
        return app
    }

    /// A copied file keeps its own icon over the app's: that app is nearly
    /// always the file manager, and the card's one line of name tells files
    /// apart no better. A single picture shows itself in the card instead.
    private var showsFileIcon: Bool {
        guard entry.kind == .files else { return false }
        if entry.filePaths.count == 1, let path = entry.filePaths.first,
           ClipboardImageStore.isImageFile(atPath: path) { return false }
        return fileIcon(for: entry) != nil
    }

    private var cardFooter: some View {
        HStack(spacing: 6) {
            Text(entry.copiedAt, style: .time)
            Spacer(minLength: 4)
            if let shortcutIndex {
                Text("⌘\(shortcutIndex + 1)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 10)
        .frame(height: 26)
    }

    /// A row puts a picture beside its label, a card above it.
    private var pictureStack: AnyLayout {
        isRow ? AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
    }

    /// A row keeps its picture small, a card gives it the room it has.
    private var pictureMaxSize: CGSize {
        isRow ? CGSize(width: 240, height: 120) : CGSize(width: CGFloat.infinity, height: .infinity)
    }

    @ViewBuilder
    private func entryContent(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            HStack(alignment: isRow ? .center : .top, spacing: 8) {
                if let color = entry.color {
                    ColorSwatch(color: color, size: 14)
                }
                SearchHighlightText.text(isRow ? entry.preview : entry.cardPreview, tokens: tokens, fontSize: 12)
                    .font(.system(size: 12))
                    .lineLimit(isRow ? 2 : 7)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            pictureStack {
                if let name = entry.imageFile {
                    ClipboardThumbnailImage(source: .stored(name: name),
                                            aspectRatio: entry.imageAspectRatio)
                        .frame(maxWidth: pictureMaxSize.width, maxHeight: pictureMaxSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                SearchHighlightText.text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)",
                                         tokens: tokens, fontSize: 11.5)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
        case .files:
            if entry.filePaths.count == 1,
               let path = entry.filePaths.first,
               ClipboardImageStore.isImageFile(atPath: path) {
                pictureStack {
                    ClipboardThumbnailImage(source: .file(path: path),
                                            aspectRatio: ClipboardImageStore.imageAspectRatio(atPath: path))
                        .frame(maxWidth: pictureMaxSize.width, maxHeight: pictureMaxSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        SearchHighlightText.text(entry.fileNames.first ?? entry.preview, tokens: tokens, fontSize: 12)
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
                    // A count of several files is no text the search reads.
                    SearchHighlightText.text(fileTitle(entry),
                                             tokens: entry.filePaths.count == 1 ? tokens : [],
                                             fontSize: 12)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if entry.filePaths.count > 1 {
                        SearchHighlightText.text(entry.preview, tokens: tokens, fontSize: 10)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(isRow ? 1 : 5)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.filePaths.joined(separator: "\n"))
            }
        }
    }

    @ViewBuilder
    private func entryTrailing(_ entry: ClipboardHistoryEntry, isHovered: Bool) -> some View {
        if isHovered {
            HStack(spacing: 4) {
                if entry.kind == .image, AppFeature.screenshot.isAvailable {
                    Button { history.editImage(entry) } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(text.edit)
                    .accessibilityLabel(text.edit)
                }
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
        } else if isRow {
            // A card shows these in its footer.
            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.copiedAt, style: .time)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                if let shortcutIndex {
                    Text("⌘\(shortcutIndex + 1)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        } else if entry.isPinned, sourceApp != nil || showsFileIcon {
            // The app's or the file's icon took the pin's place on the left.
            Image(systemName: "pin.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
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
        } else if !isRow, let app = sourceApp, !showsFileIcon {
            // A row keeps the kind's symbol, as the list always showed.
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 18, height: 18)
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

/// Turns off the rubber-band bounce of the enclosing scroll view. SwiftUI's
/// `scrollBounceBehavior` still bounces once the content is larger than the
/// view, and neither the list nor the strip of cards has anything to show
/// past its ends.
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
                guard let scrollView = self?.enclosingScrollView else { return }
                scrollView.verticalScrollElasticity = .none
                scrollView.horizontalScrollElasticity = .none
            }
        }
    }
}
