// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardQuickPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @FocusState private var searchFocused: Bool
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassEnabled = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var previewSelection = QuickPreviewSelection()
    @State private var previewIsEditing = false
    @State private var clearingIDs: [UUID: Date]?
    /// The shelf's search starts as a magnifier. Typing opens it too: the
    /// field keeps the keyboard while it is folded away.
    @State private var searchExpanded = false
    @State private var creatingPinboard = false
    @State private var editingPinboardID: UUID?

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
            if layout == .list { Divider() }
            HStack(spacing: 0) {
                content
                if history.quickPreviewPresented, layout == .list {
                    Divider()
                    QuickPreviewPane(text: text,
                                     selection: previewSelection,
                                     isEditing: $previewIsEditing,
                                     onClose: { history.setQuickPreviewPresented(false) })
                        .frame(width: 280)
                        .transition(.opacity)
                }
            }
            if layout == .list {
                Divider()
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { panelBackground }
        .clipShape(RoundedRectangle(cornerRadius: layout == .cards ? Self.shelfCornerRadius : 0,
                                    style: .continuous))
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
            searchExpanded = false
            creatingPinboard = false
            editingPinboardID = nil
        }
    }

    private static let shelfCornerRadius: CGFloat = 24

    /// The shelf follows the app's Liquid Glass choice, like its other
    /// panels; without it, and for the list, the system material.
    @ViewBuilder
    private var panelBackground: some View {
        if layout == .cards {
            if HUDBackdrop.drawsLiquidGlass(enabled: liquidGlassEnabled, reduceTransparency: reduceTransparency) {
                HUDBackdrop(cornerRadius: Self.shelfCornerRadius)
            } else {
                RoundedRectangle(cornerRadius: Self.shelfCornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            }
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        if layout == .cards { shelfToolbar } else { listToolbar }
    }

    /// The shelf keeps one slim row above the cards: the search and the
    /// group tabs in the middle, the window's own controls behind a menu on
    /// the right.
    private var shelfToolbar: some View {
        // The tabs sit in the exact middle whatever the menu at the right
        // measures.
        ZStack {
            HStack(spacing: 4) {
                shelfSearch
                pinboardTab(nil)
                ForEach(history.pinboards) { board in
                    pinboardTab(board)
                }
                Button {
                    creatingPinboard = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(history.pinboards.count >= ClipboardPinboard.limit)
                .help(text.pinboardNew)
                .accessibilityLabel(text.pinboardNew)
                .popover(isPresented: $creatingPinboard, arrowEdge: .top) {
                    PinboardEditor(text: text, name: "",
                                   tint: ClipboardPinboard.nextTint(after: history.pinboards),
                                   actionTitle: text.pinboardCreate) { name, tint in
                        if let board = history.createPinboard(named: name, tint: tint) {
                            history.quickPinboardID = board.id
                        }
                        creatingPinboard = false
                    }
                }
            }
            .fixedSize()
            HStack {
                Spacer(minLength: 0)
                shelfMenu
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .modifier(ClipboardClearRecentConfirmation(entryIDs: $clearingIDs))
    }

    /// The window's own controls wait behind one menu at the right.
    private var shelfMenu: some View {
        Menu {
            Toggle(text.previewLabel, isOn: Binding(get: { history.quickPreviewPresented },
                                                    set: { history.setQuickPreviewPresented($0) }))
            Divider()
            Button(text.clearRecent, role: .destructive) {
                clearingIDs = history.recentEntriesSnapshot
            }
            .disabled(history.recentEntries.isEmpty)
            Divider()
            Button(l10n.s.menuSettings) { history.openClipboardSettings() }
            Button(l10n.s.menuClose) { history.hideHistoryWindow() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help(l10n.s.menuSettings)
    }

    private var searchIsOpen: Bool {
        searchExpanded || !history.quickQuery.isEmpty
    }

    private var shelfSearch: some View {
        HStack(spacing: 4) {
            Button {
                searchExpanded = true
                searchFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(searchIsOpen ? .secondary : .primary)
            .help(text.search)
            .accessibilityLabel(text.search)
            TextField(text.search, text: $history.quickQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .frame(width: searchIsOpen ? 190 : 0)
                .opacity(searchIsOpen ? 1 : 0)
                .accessibilityHidden(!searchIsOpen)
            if searchIsOpen {
                Button {
                    history.quickQuery = ""
                    searchExpanded = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(l10n.s.menuClose)
                .padding(.trailing, 5)
            }
        }
        .frame(height: 28)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(searchIsOpen ? 0.07 : 0)))
        .animation(.easeOut(duration: 0.15), value: searchIsOpen)
    }

    /// One tab of the shelf: the whole history, or a group with its color.
    private func pinboardTab(_ board: ClipboardPinboard?) -> some View {
        let selected = history.quickPinboardID == board?.id
        return Button {
            history.quickPinboardID = board?.id
        } label: {
            HStack(spacing: 5) {
                if let board {
                    Circle()
                        .fill(PinboardEditor.color(board.tint))
                        .frame(width: 8, height: 8)
                } else {
                    Image(systemName: "clock")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                Text(board?.name ?? text.pinboardAll)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule(style: .continuous).fill(selected ? Color.primary.opacity(0.12) : .clear))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .contextMenu {
            if let board {
                Button(text.rename) { editingPinboardID = board.id }
                Divider()
                Button(text.pinboardDelete, role: .destructive) { history.deletePinboard(board.id) }
            }
        }
        .popover(isPresented: Binding(get: { board != nil && editingPinboardID == board?.id },
                                      set: { if !$0 { editingPinboardID = nil } }),
                 arrowEdge: .top) {
            if let board {
                PinboardEditor(text: text, name: board.name, tint: board.tint,
                               actionTitle: text.rename.replacingOccurrences(of: "…", with: "")) { name, tint in
                    history.renamePinboard(board.id, to: name)
                    history.recolorPinboard(board.id, to: tint)
                    editingPinboardID = nil
                }
            }
        }
    }

    private var listToolbar: some View {
        HStack(spacing: 8) {
            TextField(text.search, text: $history.quickQuery)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            previewButton
            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var previewButton: some View {
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
    }

    private var closeButton: some View {
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

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState(history.quickPinboardID != nil && history.quickQuery.isEmpty ? text.pinboardEmpty
                       : history.entries.isEmpty ? text.empty : text.noResults)
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
                        ScrollView(.horizontal, showsIndicators: false) {
                            Group {
                                if filtered.count <= Self.eagerRowLimit {
                                    HStack(spacing: Self.cardSpacing) { topAnchor; sections }
                                } else {
                                    LazyHStack(spacing: Self.cardSpacing) { topAnchor; sections }
                                }
                            }
                            .padding(.trailing, Self.listInset)
                            .padding(.vertical, 10)
                            .frame(maxHeight: .infinity)
                            // A copy made while the shelf is open slides in at
                            // the front and pushes the others along.
                            .animation(.spring(response: 0.35, dampingFraction: 0.86),
                                       value: filtered.map(\.id))
                        }
                    }
                }
                .background(ScrollBounceDisabler(turnsVerticalWheel: layout == .cards))
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
    private static let listInset: CGFloat = 20
    private static let cardSpacing: CGFloat = 18

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
        let context = renderContext
        if history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           history.quickPinboardID == nil {
            let pinned = history.pinnedEntries
            let recent = history.recentEntries
            if layout == .list {
                rows(title: text.pinned, entries: pinned, context: context)
                rows(title: text.recent, entries: recent, followsSection: !pinned.isEmpty, context: context)
            } else {
                cards(pinned, context: context)
                if !pinned.isEmpty, !recent.isEmpty {
                    Divider().frame(height: QuickEntryView.cardSize.height - 24)
                }
                cards(recent, context: context)
            }
        } else if layout == .list {
            rows(title: nil, entries: context.filtered, context: context)
        } else {
            cards(context.filtered, context: context)
        }
    }

    /// What every entry of one render shares, worked out once rather than
    /// once per entry: on a long history the per-entry lookups, each a walk
    /// through the whole history, made every click wait.
    private struct RenderContext {
        let filtered: [ClipboardHistoryEntry]
        let selectedID: UUID?
        let previewID: UUID?
        let shortcutIndexes: [UUID: Int]
        let tokens: [String]
    }

    private var renderContext: RenderContext {
        let filtered = self.filtered
        let selected = history.selectedQuickEntryID
        let showsShortcuts = layout == .list || history.quickCommandHeld
        return RenderContext(
            filtered: filtered,
            selectedID: history.quickSelectionIsVisible ? selected : nil,
            previewID: layout == .cards && history.quickPreviewPresented ? selected : nil,
            shortcutIndexes: showsShortcuts
                ? Dictionary(uniqueKeysWithValues: filtered.prefix(9).enumerated().map { ($1.id, $0) }) : [:],
            tokens: searchTokens)
    }

    @ViewBuilder
    private func rows(title: String?, entries: [ClipboardHistoryEntry],
                      followsSection: Bool = false, context: RenderContext) -> some View {
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
                entryView(entry, context: context)
                if index < entries.count - 1 {
                    Divider()
                        .padding(.leading, 43)
                        .padding(.trailing, 8)
                }
            }
        }
    }

    private func cards(_ entries: [ClipboardHistoryEntry], context: RenderContext) -> some View {
        ForEach(entries) { entry in
            entryView(entry, context: context)
                .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal: .opacity))
        }
    }

    private func entryView(_ entry: ClipboardHistoryEntry, context: RenderContext) -> some View {
        QuickEntryView(layout: layout,
                       entry: entry,
                       pinboard: entry.pinboardID == nil ? nil : history.pinboard(for: entry),
                       tokens: context.tokens,
                       shortcutIndex: context.shortcutIndexes[entry.id],
                       isSelected: context.selectedID == entry.id,
                       showsPreview: context.previewID == entry.id,
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
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
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
    static let cardSize = CGSize(width: 236, height: 236)
    private static let cardCornerRadius: CGFloat = 13
    private static let cardHeaderHeight: CGFloat = 48
    let layout: ClipboardHistoryLayout
    let entry: ClipboardHistoryEntry
    /// The entry's group, passed in so a renamed or recolored group redraws it.
    let pinboard: ClipboardPinboard?
    let tokens: [String]
    let shortcutIndex: Int?
    let isSelected: Bool
    /// The shelf's Quick Look: the chosen card opens a large preview over itself.
    let showsPreview: Bool
    let isBatchSelected: Bool
    let canReorderEntries: Bool
    let previewIsEditing: Bool
    let presentationID: UUID
    let language: AppLanguage
    let previewSelection: QuickPreviewSelection
    @State private var isHovered = false
    @State private var previewIsEditingHere = false
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
            && lhs.pinboard == rhs.pinboard
            && lhs.tokens == rhs.tokens
            && lhs.shortcutIndex == rhs.shortcutIndex
            && lhs.isSelected == rhs.isSelected
            && lhs.showsPreview == rhs.showsPreview
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
        .popover(isPresented: Binding(get: { showsPreview },
                                      set: { if !$0, showsPreview { history.setQuickPreviewPresented(false) } }),
                 arrowEdge: .top) {
            ClipboardEntryPreviewSidebar(text: text, entry: entry, isEditing: $previewIsEditingHere,
                                         onClose: { history.setQuickPreviewPresented(false) })
                .frame(width: 520, height: 420)
        }
        .modifier(EntryClicks(pastesOnDoubleClick: !isRow,
                              onClick: { activate(entry) },
                              onDoubleClick: { history.copyQuickEntry(entry) }))
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

    /// A card: a header in the source app's color naming the kind and the
    /// time, the content on a plain body, and one line of detail under it.
    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
        let marked = isBatchSelected || isSelected
        return VStack(spacing: 0) {
            cardHeader
            // A fixed box: however much the content asks for, the header and
            // the footer keep their places.
            cardBody
                .frame(width: Self.cardSize.width, height: bodyHeight, alignment: .topLeading)
                .clipped()
            cardFooter
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            if marked {
                Color.accentColor.opacity(isBatchSelected ? 0.10 : 0.06).allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(isHovered ? 0.22 : 0.12), radius: isHovered ? 8 : 4,
                y: isHovered ? 3 : 1.5)
        .overlay {
            if marked {
                RoundedRectangle(cornerRadius: Self.cardCornerRadius + 4, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(-5)
                    .allowsHitTesting(false)
            }
        }
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
        HStack(alignment: .center, spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text(cardKindTitle)
                    .font(.system(size: 13.5, weight: .bold))
                Text(Self.relativeTime(of: entry.copiedAt, language: language))
                    .font(.system(size: 10.5, weight: .medium))
                    .opacity(0.85)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if isHovered {
                cardHoverActions
                    .padding(.trailing, 5)
            } else {
                cardHeaderIcon
            }
        }
        .foregroundStyle(.white)
        .padding(.leading, 11)
        .padding(.trailing, 2)
        .frame(height: Self.cardHeaderHeight)
        .background(headerColor)
    }

    /// The source app's icon in the corner, or a file's own icon, or the
    /// kind's symbol when the app is unknown.
    @ViewBuilder
    private var cardHeaderIcon: some View {
        if showsFileIcon, let icon = fileIcon(for: entry) {
            Image(nsImage: icon).resizable().frame(width: 44, height: 44)
        } else if let app = sourceApp {
            Image(nsImage: app.icon).resizable().frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        } else {
            Image(systemName: entry.linkURL != nil ? "link" : kindSymbol(entry.kind))
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
        }
    }

    private var cardHoverActions: some View {
        HStack(spacing: 4) {
            if entry.kind == .image, AppFeature.screenshot.isAvailable {
                headerAction("pencil", help: text.edit) { history.editImage(entry) }
            }
            headerAction("doc.on.doc", help: text.copy) { history.copyOnlyQuickEntry(entry) }
            Menu {
                entryActions(entry)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func headerAction(_ symbol: String, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var cardKindTitle: String {
        ClipboardCardAppearance.kindTitle(for: entry, language: language)
    }

    private static var relativeFormatters: [AppLanguage: RelativeDateTimeFormatter] = [:]

    /// "2 minutes ago" in the app's language. The window re-renders each card
    /// on every opening, which is as fresh as a glance at the shelf needs.
    private static func relativeTime(of date: Date, language: AppLanguage) -> String {
        let formatter = relativeFormatters[language] ?? {
            let made = RelativeDateTimeFormatter()
            made.locale = Locale(identifier: language.rawValue)
            made.unitsStyle = .full
            relativeFormatters[language] = made
            return made
        }()
        return formatter.localizedString(for: min(date, Date()), relativeTo: Date())
    }

    private var headerColor: Color {
        ClipboardCardAppearance.headerColor(for: entry)
    }

    @ViewBuilder
    private var cardBody: some View {
        if let color = entry.color {
            ZStack {
                Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
                SearchHighlightText.text(entry.preview, tokens: tokens, fontSize: 12)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule(style: .continuous))
            }
        } else if let url = entry.linkURL {
            LinkCardBody(url: url, tint: headerColor, tokens: tokens)
        } else {
            switch entry.kind {
            case .text:
                textCardBody
            case .image:
                if let name = entry.imageFile {
                    ClipboardThumbnailImage(source: .stored(name: name),
                                            aspectRatio: entry.imageAspectRatio)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(10)
                        .help("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                }
            case .files:
                if entry.filePaths.count == 1, let path = entry.filePaths.first,
                   ClipboardImageStore.isImageFile(atPath: path) {
                    ClipboardThumbnailImage(source: .file(path: path),
                                            aspectRatio: ClipboardImageStore.imageAspectRatio(atPath: path))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(10)
                        .help(path)
                } else {
                    entryContent(entry)
                        .padding(11)
                }
            }
        }
    }

    /// A short first line over more text reads as a title, like a note's
    /// heading above its body.
    @ViewBuilder
    private var textCardBody: some View {
        let parts = entry.cardPreview.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        VStack(alignment: .leading, spacing: 4) {
            if parts.count == 2, parts[0].count <= 60,
               !parts[0].trimmingCharacters(in: .whitespaces).isEmpty,
               !parts[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SearchHighlightText.text(String(parts[0]), tokens: tokens, fontSize: 13.5)
                    .font(.system(size: 13.5, weight: .bold))
                    .lineLimit(2)
                SearchHighlightText.text(String(parts[1]).trimmingCharacters(in: .newlines),
                                         tokens: tokens, fontSize: 11.5)
                    .font(.system(size: 11.5))
                    .lineLimit(8)
            } else {
                SearchHighlightText.text(entry.cardPreview, tokens: tokens, fontSize: 12)
                    .font(.system(size: 12))
                    .lineLimit(10)
            }
        }
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(11)
    }

    private var sourceApp: (name: String, icon: NSImage)? {
        ClipboardCardAppearance.sourceApp(for: entry)
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

    /// What the content measures, centered between the pin and the paste
    /// shortcut.
    private var cardFooter: some View {
        ZStack {
            Text(cardDetail)
                .multilineTextAlignment(.center)
                .lineLimit(entry.kind == .files ? 2 : 1)
                .truncationMode(entry.kind == .files ? .head : .middle)
                .padding(.horizontal, 34)
            HStack(spacing: 6) {
                if let board = pinboard {
                    Circle()
                        .fill(PinboardEditor.color(board.tint))
                        .frame(width: 8, height: 8)
                        .help(board.name)
                } else if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 4)
                if let shortcutIndex {
                    Text("⌘\(shortcutIndex + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(Color.accentColor))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.12), value: shortcutIndex)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: cardFooterHeight)
    }

    /// Two lines for a file's folder, one for anything else.
    private var cardFooterHeight: CGFloat { entry.kind == .files ? 34 : 26 }

    private var bodyHeight: CGFloat { Self.cardSize.height - Self.cardHeaderHeight - cardFooterHeight }

    private var cardDetail: String {
        switch entry.kind {
        case .text:
            return entry.color != nil ? "" : String(format: text.cardCharacterCountFormat, entry.text.count)
        case .image:
            return entry.imageDimensionsLabel
        case .files:
            // Where the file lives; the name is in the body.
            guard let path = entry.filePaths.first else { return "" }
            let folder = ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
            return entry.filePaths.count == 1 ? folder
                : String(format: text.fileCountFormat, entry.filePaths.count)
        }
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
        Button(text.previewLabel) {
            history.previewQuickEntry(entry)
        }
        Divider()
        Button(entry.isPinned ? text.unpin : text.pin) {
            history.togglePin(entry)
        }
        // Groups show only on the shelf, so the list does not offer them.
        if !isRow {
            Menu(text.pinboardAddTo) {
                ForEach(history.pinboards) { board in
                    Button {
                        history.file(entry, in: board.id)
                    } label: {
                        if entry.pinboardID == board.id {
                            Label(board.name, systemImage: "checkmark")
                        } else {
                            Text(board.name)
                        }
                    }
                }
                if !history.pinboards.isEmpty { Divider() }
                Button(text.pinboardNew) {
                    let name = String(format: text.pinboardDefaultNameFormat, history.pinboards.count + 1)
                    if let board = history.createPinboard(named: name) {
                        history.file(entry, in: board.id)
                    }
                }
                .disabled(history.pinboards.count >= ClipboardPinboard.limit)
            }
            if entry.pinboardID != nil {
                Button(text.pinboardRemoveFrom) {
                    history.file(entry, in: nil)
                }
            }
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
        // A card of the shelf is chosen alone; a double click pastes it.
        if !isRow {
            history.selectQuickEntry(entry)
            return
        }
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
    var turnsVerticalWheel = false

    func makeNSView(context: Context) -> BounceDisablingView { BounceDisablingView() }
    func updateNSView(_ view: BounceDisablingView, context: Context) {
        view.turnsVerticalWheel = turnsVerticalWheel
        view.apply()
    }

    final class BounceDisablingView: NSView {
        /// The strip of cards only scrolls sideways, so a mouse wheel's up
        /// and down moves it along. Trackpad swipes that already go sideways
        /// pass through untouched.
        var turnsVerticalWheel = false
        private var wheelMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let wheelMonitor {
                NSEvent.removeMonitor(wheelMonitor)
                self.wheelMonitor = nil
            }
            if window != nil {
                wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    self?.turnWheel(event) == true ? nil : event
                }
            }
            apply()
        }

        private func turnWheel(_ event: NSEvent) -> Bool {
            guard turnsVerticalWheel, let window, event.window === window,
                  let scrollView = enclosingScrollView, let documentView = scrollView.documentView,
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil))
            else { return false }
            let clip = scrollView.contentView
            let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
            var origin = clip.bounds.origin
            origin.x = max(0, min(origin.x - step, documentView.frame.width - clip.bounds.width))
            clip.scroll(to: origin)
            scrollView.reflectScrolledClipView(clip)
            return true
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

/// Names a group and picks its color, for a new group or an existing one.
private struct PinboardEditor: View {
    let text: ClipboardFeatureStrings
    @State var name: String
    @State var tint: ClipboardPinboard.Tint
    let actionTitle: String
    let onCommit: (String, ClipboardPinboard.Tint) -> Void
    @FocusState private var nameFocused: Bool

    static func color(_ tint: ClipboardPinboard.Tint) -> Color {
        let rgb = tint.rgb
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    private var canCommit: Bool { ClipboardPinboard.sanitizedName(name) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(text.pinboardNameLabel, text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { if canCommit { onCommit(name, tint) } }
            HStack(spacing: 8) {
                ForEach(ClipboardPinboard.Tint.allCases, id: \.self) { choice in
                    Button {
                        tint = choice
                    } label: {
                        Circle()
                            .fill(Self.color(choice))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.8),
                                                           lineWidth: tint == choice ? 2 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(text.pinboardColor)
                    .accessibilityAddTraits(tint == choice ? .isSelected : [])
                }
            }
            HStack {
                Spacer()
                Button(actionTitle) { onCommit(name, tint) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCommit)
            }
        }
        .padding(14)
        .frame(width: 250)
        .onAppear { nameFocused = true }
    }
}

/// A row pastes on a click. A card of the shelf is chosen by a click and
/// pasted by a double click, so a stray click never pastes. The click is
/// answered the moment it lands: a separate double-tap gesture
/// would hold every single click back for the double-click interval, which
/// made choosing a card feel late. The system's click count tells the second
/// click of a double click instead.
private struct EntryClicks: ViewModifier {
    let pastesOnDoubleClick: Bool
    let onClick: () -> Void
    let onDoubleClick: () -> Void

    func body(content: Content) -> some View {
        content.onTapGesture {
            if pastesOnDoubleClick, (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                onDoubleClick()
            } else {
                onClick()
            }
        }
    }
}

/// A link's card body: a globe in the card's color over the page's host
/// and address.
private struct LinkCardBody: View {
    let url: URL
    let tint: Color
    let tokens: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: "globe")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(tint)
            }
            .frame(maxHeight: .infinity)
            .padding([.horizontal, .top], 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                SearchHighlightText.text(url.absoluteString, tokens: tokens, fontSize: 11)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding([.horizontal, .bottom], 10)
        }
    }
}

/// How a card looks: the source app, the header color taken from its icon,
/// and the kind's name.
enum ClipboardCardAppearance {
    /// Looked up once per app. An app removed since the copy has nothing to
    /// show, and the card keeps the kind's symbol. A miss is not kept, so an
    /// app installed later shows up without a restart.
    private static var sourceApps: [String: (name: String, icon: NSImage)] = [:]
    /// The source app's color, read once per app from its icon.
    private static var appTints: [String: Color] = [:]

    static func sourceApp(for entry: ClipboardHistoryEntry) -> (name: String, icon: NSImage)? {
        guard let bundleID = entry.sourceBundleID else { return nil }
        if let cached = sourceApps[bundleID] { return cached }
        let app = InstalledApps.url(for: bundleID).map {
            (name: InstalledApps.name(for: bundleID), icon: NSWorkspace.shared.icon(forFile: $0.path))
        }
        if let app { sourceApps[bundleID] = app }
        return app
    }

    /// A copy with no known app, or an app whose icon has no color, takes
    /// its kind's.
    static func headerColor(for entry: ClipboardHistoryEntry) -> Color {
        if let bundleID = entry.sourceBundleID {
            if let cached = appTints[bundleID] { return cached }
            if let app = sourceApp(for: entry), let tint = tint(of: app.icon) {
                appTints[bundleID] = tint
                return tint
            }
        }
        if entry.linkURL != nil { return Color(nsColor: .systemTeal) }
        switch entry.kind {
        case .text: return Color(nsColor: .systemBlue)
        case .image: return Color(nsColor: .systemPink)
        case .files: return Color(nsColor: .systemOrange)
        }
    }

    static func kindTitle(for entry: ClipboardHistoryEntry, language: AppLanguage) -> String {
        let text = FeatureStrings.clipboard(language)
        if entry.color != nil { return text.cardKindColor }
        if entry.linkURL != nil { return text.cardKindLink }
        switch entry.kind {
        case .text: return text.cardKindText
        case .image: return text.imageEntryLabel
        case .files:
            return entry.filePaths.count == 1 ? text.cardKindFile
                : String(format: text.fileCountFormat, entry.filePaths.count)
        }
    }

    private static func tint(of icon: NSImage) -> Color? {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = icon.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn, let color = ClipboardCardTint.headerColor(rgba: pixels) else { return nil }
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: 1)
    }
}
