// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardQuickPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @AppStorage(DefaultsKey.clipboardHistoryShowSourceAppIcons) private var showSourceAppIcons = false
    @AppStorage(DefaultsKey.clipboardShelfPrivacyMode) private var privacyMode = false
    @AppStorage(DefaultsKey.clipboardShelfSuggestions) private var suggestionsEnabled = true
    @FocusState private var searchFocused: Bool
    @FocusState private var filterChoiceFocus: FilterChoice?

    private enum FilterChoice: Hashable {
        case source(String)
        case type(ClipboardShelfContentType?)
    }
    @State private var previewSelection = QuickPreviewSelection()
    @State private var previewIsEditing = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clearingIDs: [UUID: Date]?
    @State private var shelfScrollerStyle = NSScroller.preferredScrollerStyle
    @State private var boardEditor: PinboardEditor.Mode?
    @State private var deletingBoard: ClipboardPinboard?

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var shelfText: ClipboardShelfStrings { .forLanguage(l10n.language) }
    private var vertical: Bool { history.quickShelfIsVertical }

    private var filtered: [ClipboardHistoryEntry] {
        history.filteredQuickEntries
    }

    private var canReorderEntries: Bool {
        !history.quickSearchIsActive
    }

    private var searchTokens: [String] {
        ClipboardHistorySearch.searchTokens(for: history.quickQuery)
    }

    private var layout: ClipboardHistoryLayout {
        history.quickLayout
    }

    var body: some View {
        GeometryReader { geometry in
            let inEdgeShelf = layout == .cards
            let concealed = inEdgeShelf && !reduceMotion && !history.quickShelfPresented
            Group {
                if privacyMode { protectedContent } else { shelfContent }
            }
            .padding(.top, inEdgeShelf ? history.quickShelfTopInset : 0)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background {
                if inEdgeShelf {
                    ClipboardShelfBackdrop(edge: history.quickShelfEdge)
                } else {
                    Rectangle().fill(.regularMaterial)
                }
            }
            .environment(\.colorScheme, inEdgeShelf ? .dark : colorScheme)
            .offset(concealed ? history.quickShelfEdge.hiddenOffset(for: geometry.size) : .zero)
            .allowsHitTesting(!concealed)
            .accessibilityHidden(concealed)
        }
        .clipped()
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)) { _ in
            shelfScrollerStyle = NSScroller.preferredScrollerStyle
        }
        .onChange(of: privacyMode) { _, enabled in
            if enabled { history.closeShelfPreview() }
        }
    }

    private var protectedContent: some View {
        ZStack(alignment: .topTrailing) {
            Label(shelfText.clipboardHidden, systemImage: "lock.shield")
                .font(.headline)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(l10n.s.menuClose, systemImage: "xmark") { history.hideHistoryWindow() }
                .labelStyle(.iconOnly)
                .padding(12)
        }
    }

    private var shelfContent: some View {
        VStack(spacing: 0) {
            toolbar.disabled(boardEditor != nil)
            if layout == .list { filterChoices }
            Divider()
            shelfResults
            Divider()
            footer.disabled(boardEditor != nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(shelfText.deletePinboard, isPresented: showingBoardDeletion, presenting: deletingBoard) { board in
            Button(shelfText.deletePinboard, role: .destructive) { history.deletePinboard(board.id) }
            Button(text.cancel, role: .cancel) {}
        } message: { board in
            Text(board.name)
        }
        .onAppear {
            previewSelection.select(history.selectedQuickEntryID)
            DispatchQueue.main.async { searchFocused = true }
        }
        .onDisappear {
            previewSelection.select(nil)
            previewIsEditing = false
            closeBoardEditor(restoreSearch: false)
            history.quickFilterChoiceIsFocused = false
        }
        .onChange(of: filterChoiceFocus) { _, choice in
            history.quickFilterChoiceIsFocused = choice != nil
        }
        .onChange(of: history.quickSelectionID) { _, _ in
            previewSelection.select(history.selectedQuickEntryID)
        }
        .onChange(of: history.quickQuery) { _, _ in
            previewSelection.select(history.selectedQuickEntryID)
        }
        .onChange(of: history.quickFilter) { _, _ in
            previewSelection.select(history.selectedQuickEntryID)
        }
        .onChange(of: history.quickWindowPresentationID) { _, _ in
            closeBoardEditor(restoreSearch: false)
            deletingBoard = nil
            previewSelection.select(history.selectedQuickEntryID)
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: suggestionsEnabled) { _, enabled in
            if !enabled, case .suggestions = history.quickFilter.collection {
                history.setQuickCollection(.history)
            }
        }
    }

    private var shelfResults: some View {
        contentWithPreview
            .allowsHitTesting(boardEditor == nil)
            .accessibilityHidden(boardEditor != nil)
            .overlay(alignment: .topLeading) { filterFlyout }
            .overlay(alignment: .topTrailing) {
                if let mode = boardEditor { boardEditorFlyout(mode) }
            }
    }

    @ViewBuilder
    private var filterFlyout: some View {
        if layout == .cards, boardEditor == nil, hasFilterChoices {
            filterChoices
                .padding(.vertical, 8)
                .background(ShelfFlyout())
                .frame(maxWidth: vertical ? nil : 480)
                .padding(8)
        }
    }

    private var showsSourceSuggestions: Bool { searchFocused || filterChoiceFocus != nil }

    private var hasFilterChoices: Bool {
        history.quickTypePickerPresented || history.quickSourcePickerPresented
            || (showsSourceSuggestions && !history.quickSourceSuggestions.isEmpty)
    }

    @ViewBuilder
    private var filterChoices: some View {
        if history.quickTypePickerPresented { typeChoices } else { sourceChoices }
    }

    private func boardEditorFlyout(_ mode: PinboardEditor.Mode) -> some View {
        PinboardEditor(mode: mode, shelfText: shelfText, text: text,
                       emojiLabel: FeatureStrings.commandBar(l10n.language).sourceEmoji,
                       onCancel: { closeBoardEditor() }) { name, emoji in
            guard boardEditor?.id == mode.id else { return }
            if let board = mode.board {
                history.renamePinboard(board.id, to: name, emoji: emoji)
            } else {
                history.createPinboard(named: name, emoji: emoji)
            }
            closeBoardEditor()
        }
        .id(mode.id)
        .background(ShelfFlyout())
        .padding(8)
    }

    private func editPinboard(_ board: ClipboardPinboard?) {
        history.quickSourcePickerPresented = false
        history.quickTypePickerPresented = false
        history.quickPinboardEditorIsActive = true
        searchFocused = false
        boardEditor = .init(board: board)
    }

    private func closeBoardEditor(restoreSearch: Bool = true) {
        guard boardEditor != nil else { return }
        boardEditor = nil
        history.quickPinboardEditorIsActive = false
        if restoreSearch { searchFocused = true }
    }

    private var showingBoardDeletion: Binding<Bool> {
        Binding(get: { deletingBoard != nil }, set: { if !$0 { deletingBoard = nil } })
    }

    private var contentWithPreview: some View {
        HStack(spacing: 0) {
            content
            if layout == .list && history.quickPreviewPresented {
                Divider()
                QuickPreviewPane(text: text,
                                 selection: previewSelection,
                                 isEditing: $previewIsEditing,
                                 onClose: { history.setQuickPreviewPresented(false) })
                    .frame(width: 280)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            if layout == .cards && !vertical {
                searchField.frame(minWidth: 120, idealWidth: 220, maxWidth: 280)
                pinboardBar
            } else {
                searchField.layoutPriority(1)
                if vertical { compactPinboardMenu }
            }

            if vertical {
                compactActions
            } else {
                sourceFilter
                typeFilter
                if layout == .cards && suggestionsEnabled { suggestionsButton }
                previewButton
            }
            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var searchField: some View {
        TextField(text.search, text: $history.quickQuery)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
    }

    private var previewButton: some View {
        let inspectorVisible = layout == .list && history.quickPreviewPresented
        return Button(text.previewLabel, systemImage: inspectorVisible ? "sidebar.right" : "eye") {
            history.previewQuickSelection()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .foregroundStyle(inspectorVisible ? Color.accentColor : Color.secondary)
        .disabled(history.selectedQuickEntry == nil && !inspectorVisible)
        .help(text.previewLabel)
    }

    private var closeButton: some View {
        Button(l10n.s.menuClose, systemImage: "xmark") { history.hideHistoryWindow() }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .help(l10n.s.menuClose)
    }

    private var activePinboard: ClipboardPinboard? {
        guard case let .pinboard(id) = history.quickFilter.collection else { return nil }
        return history.pinboards.first { $0.id == id }
    }

    private var compactPinboardMenu: some View {
        Menu {
            Button(shelfText.history, systemImage: "clock") { history.setQuickCollection(.history) }
            Button(text.pinned, systemImage: "pin") { history.setQuickCollection(.pinned) }
            ForEach(history.pinboards) { board in
                Button(board.label) { history.setQuickCollection(.pinboard(board.id)) }
            }
            Divider()
            Button(shelfText.newPinboard, systemImage: "plus") { editPinboard(nil) }
            if let board = activePinboard {
                Button(shelfText.renamePinboard) { editPinboard(board) }
                Button(shelfText.deletePinboard, role: .destructive) { deletingBoard = board }
            }
        } label: {
            if let emoji = activePinboard?.emoji {
                Text(emoji)
            } else {
                Image(systemName: history.quickFilter.collection == .pinned ? "pin" : "square.on.square")
            }
        }
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(shelfText.pinboards)
        .accessibilityValue(activePinboard?.name ?? (history.quickFilter.collection == .pinned ? text.pinned : shelfText.history))
        .help(shelfText.pinboards)
    }

    private var compactActions: some View {
        Menu {
            if history.quickSourceBundleID != nil {
                Button(text.clearAppFilter) { selectSourceApp(nil) }
            } else {
                Button(text.filterBySourceApp, systemImage: "line.3.horizontal.decrease.circle") {
                    history.quickTypePickerPresented = false
                    history.quickSourcePickerPresented.toggle()
                }
                .disabled(!history.hasQuickSourceApps)
            }
            Button(shelfText.filterByType, systemImage: "slider.horizontal.3") {
                history.quickSourcePickerPresented = false
                history.quickTypePickerPresented.toggle()
            }
            if suggestionsEnabled {
                Button(shelfText.suggestions, systemImage: "sparkles") { history.toggleQuickSuggestions() }
                    .disabled(!history.canSuggestQuickEntries)
            }
            Button(text.previewLabel, systemImage: "eye") { history.previewQuickSelection() }
                .disabled(history.selectedQuickEntry == nil)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(history.quickSearchIsActive ? Color.accentColor : Color.primary)
        }
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(FeatureStrings.mixer(l10n.language).actions)
        .help(FeatureStrings.mixer(l10n.language).actions)
    }

    private var sourceFilter: some View {
        let sourceName = history.quickSourceBundleID.map { bundleID in
            history.quickSourceApps.first(where: { $0.id == bundleID })?.name ?? bundleID
        }
        let label = sourceName == nil ? text.filterBySourceApp : text.clearAppFilter
        return Button {
            if sourceName != nil {
                selectSourceApp(nil)
            } else {
                history.quickTypePickerPresented = false
                history.quickSourcePickerPresented.toggle()
            }
        } label: {
            if let sourceName {
                Label(sourceName, systemImage: "xmark.circle.fill")
                    .lineLimit(1)
                    .frame(maxWidth: vertical ? 95 : nil)
            } else {
                Image(systemName: history.quickSourcePickerPresented ? "line.3.horizontal.decrease.circle.fill"
                                                                      : "line.3.horizontal.decrease.circle")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(sourceName == nil && !history.hasQuickSourceApps)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(sourceName ?? "")
    }

    private var suggestionsButton: some View {
        Button(shelfText.suggestions, systemImage: "sparkles") {
            history.toggleQuickSuggestions()
            searchFocused = true
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .foregroundStyle(isShowingSuggestions ? Color.accentColor : Color.primary)
        .accessibilityAddTraits(isShowingSuggestions ? .isSelected : [])
        .help(shelfText.suggestions)
        .disabled(!history.canSuggestQuickEntries)
    }

    private var isShowingSuggestions: Bool {
        if case .suggestions = history.quickFilter.collection { return true }
        return false
    }

    private var pinboardBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    collectionButton(shelfText.history, symbol: "clock", collection: .history)
                    collectionButton(text.pinned, symbol: "pin", collection: .pinned)
                    ForEach(history.pinboards, content: pinboardButton)
                }
            }
            .scrollIndicators(.hidden)
            Button { editPinboard(nil) } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .help(shelfText.newPinboard)
            .accessibilityLabel(shelfText.newPinboard)
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(shelfText.pinboards)
    }

    private func pinboardButton(_ board: ClipboardPinboard) -> some View {
        collectionButton(board.name, symbol: "square.on.square",
                         collection: .pinboard(board.id), emoji: board.emoji)
            .contextMenu {
                Button(shelfText.renamePinboard) { editPinboard(board) }
                Button(shelfText.deletePinboard, role: .destructive) { deletingBoard = board }
            }
    }

    private func collectionButton(_ name: String, symbol: String,
                                  collection: ClipboardShelfCollection, emoji: String? = nil) -> some View {
        let selected = history.quickFilter.collection == collection
        return Button {
            history.setQuickCollection(collection)
        } label: {
            HStack(spacing: 4) {
                if let emoji {
                    Text(emoji).accessibilityHidden(true)
                } else {
                    Image(systemName: symbol).accessibilityHidden(true)
                }
                Text(name)
            }
            .font(.system(size: 11, weight: selected ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selected ? Color.accentColor.opacity(0.17) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var typeFilter: some View {
        Button {
            history.quickSourcePickerPresented = false
            history.quickTypePickerPresented.toggle()
        } label: {
            Image(systemName: history.quickFilter.type?.symbol ?? "slider.horizontal.3")
                .foregroundStyle(history.quickFilter.type == nil ? Color.primary : Color.accentColor)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(shelfText.filterByType)
        .accessibilityLabel(shelfText.filterByType)
        .accessibilityValue(history.quickFilter.type.map(shelfText.typeName) ?? shelfText.allTypes)
    }

    private var typeChoices: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                typeChoice(nil, label: shelfText.allTypes)
                ForEach(ClipboardShelfContentType.allCases, id: \.self) { type in
                    typeChoice(type, label: shelfText.typeName(type))
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .frame(height: 24)
        .padding(.bottom, layout == .list ? 8 : 0)
    }

    private func typeChoice(_ type: ClipboardShelfContentType?, label: String) -> some View {
        let selected = history.quickFilter.type == type
        return Button {
            selectContentType(type)
        } label: {
            Label(label, systemImage: selected ? "checkmark" : type?.symbol ?? "square.grid.2x2")
        }
        .focused($filterChoiceFocus, equals: .type(type))
        .onKeyPress(keys: ClipboardHistoryFocus.buttonConfirmationKeys) { _ in
            selectContentType(type)
            return .handled
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectContentType(_ type: ClipboardShelfContentType?) {
        history.setQuickContentType(type)
        history.quickTypePickerPresented = false
        searchFocused = true
    }

    @ViewBuilder
    private var sourceChoices: some View {
        let isPickerPresented = history.quickSourcePickerPresented
        let suggestions = showsSourceSuggestions ? history.quickSourceSuggestions : []
        let apps = isPickerPresented ? history.quickSourceApps : suggestions
        if !apps.isEmpty {
            sourceChoiceStrip(apps, completingQuery: !isPickerPresented, firstSuggestion: suggestions.first?.id)
        }
    }

    private func sourceChoiceStrip(_ apps: [ClipboardHistorySourceApp],
                                   completingQuery: Bool, firstSuggestion: String?) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 6) {
                ForEach(apps) { app in
                    sourceChoice(app, isCompletion: completingQuery,
                                 showTabKey: completingQuery && firstSuggestion == app.id)
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .frame(height: 24)
        .padding(.bottom, layout == .list ? 8 : 0)
    }

    private func sourceChoice(_ app: ClipboardHistorySourceApp,
                              isCompletion: Bool, showTabKey: Bool) -> some View {
        Button { selectSourceApp(app.id, completingQuery: isCompletion) } label: {
            HStack(spacing: 4) {
                sourceAppLabel(app)
                if showTabKey { Text("⇥").foregroundStyle(.secondary) }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .focused($filterChoiceFocus, equals: .source(app.id))
        .onKeyPress(keys: ClipboardHistoryFocus.buttonConfirmationKeys) { _ in
            selectSourceApp(app.id, completingQuery: isCompletion)
            return .handled
        }
        .help(text.filterBySourceApp)
    }

    private func sourceAppLabel(_ app: ClipboardHistorySourceApp) -> some View {
        Label {
            Text(app.name).lineLimit(1)
        } icon: {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "app")
            }
        }
    }

    private func selectSourceApp(_ bundleID: String?, completingQuery: Bool = false) {
        history.setQuickSourceApp(bundleID, completingQuery: completingQuery)
        searchFocused = true
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
                resultsScroll
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
                // The window is only hidden between uses, so without this it
                // reopens wherever it was scrolled, while the selection and
                // ⌘1 to ⌘9 already start from the first entries.
                .onChange(of: history.quickFilter) { _, _ in
                    proxy.scrollTo(Self.topAnchorID, anchor: vertical || layout == .list ? .top : .leading)
                }
                .onChange(of: history.quickWindowPresentationID) { _, _ in
                    proxy.scrollTo(Self.topAnchorID, anchor: vertical || layout == .list ? .top : .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var resultsScroll: some View {
        if layout == .list {
            listScroll
        } else {
            cardStrip
        }
    }

    private var listScroll: some View {
        ScrollView {
            Group {
                if filtered.count <= Self.eagerRowLimit {
                    VStack(alignment: .leading, spacing: 0) { listStart; listSections }
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) { listStart; listSections }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, Self.listVerticalInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cardStrip: some View {
        GeometryReader { geometry in
            let entries = filtered
            let size = ClipboardShelfCardLayout.cardSize(in: geometry.size, entryCount: entries.count,
                                                         vertical: vertical, legacyScrollerWidth: shelfScrollerWidth)
            let inset = ClipboardShelfCardLayout.inset
            let spacing = ClipboardShelfCardLayout.spacing

            if vertical {
                ScrollView {
                    LazyVStack(spacing: spacing) { cardStart; cards(entries, size: size) }
                        .padding(.horizontal, inset)
                        .padding(.top, inset - spacing)
                        .padding(.bottom, inset)
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: spacing) { cardStart; cards(entries, size: size) }
                        .padding(.vertical, inset)
                        .padding(.leading, inset - spacing)
                        .padding(.trailing, inset)
                }
            }
        }
    }

    private var shelfScrollerWidth: CGFloat {
        guard shelfScrollerStyle == .legacy else { return 0 }
        return NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    }

    private static let eagerRowLimit = 300
    private static let listVerticalInset: CGFloat = 6
    private static let topAnchorID = "clipboard-list-top"

    private var listStart: some View {
        Color.clear.frame(height: Self.listVerticalInset).id(Self.topAnchorID)
    }

    private var cardStart: some View {
        Color.clear.frame(width: 0, height: 0).id(Self.topAnchorID)
    }

    @ViewBuilder
    private var listSections: some View {
        if history.quickSearchIsActive {
            rows(title: nil, entries: filtered)
        } else {
            rows(title: text.pinned, entries: history.pinnedEntries)
            rows(title: text.recent, entries: history.recentEntries,
                 followsSection: !history.pinnedEntries.isEmpty)
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

    private func cards(_ entries: [ClipboardHistoryEntry], size: CGSize) -> some View {
        let firstRecentID = recentBoundary(in: entries)
        return ForEach(entries) { entry in
            entryView(entry, cardSize: size)
                .overlay(alignment: vertical ? .top : .leading) {
                    if entry.id == firstRecentID { cardGroupDivider }
                }
        }
    }

    private func recentBoundary(in entries: [ClipboardHistoryEntry]) -> UUID? {
        guard !history.quickSearchIsActive, entries.first?.isPinned == true else { return nil }
        return entries.first { !$0.isPinned }?.id
    }

    private var cardGroupDivider: some View {
        let offset = -ClipboardShelfCardLayout.spacing / 2
        return Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: vertical ? nil : 1, height: vertical ? 1 : nil)
            .padding(vertical ? .horizontal : .vertical, 12)
            .offset(x: vertical ? 0 : offset, y: vertical ? offset : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func entryView(_ entry: ClipboardHistoryEntry, cardSize: CGSize = .zero) -> some View {
        QuickEntryView(layout: layout,
                       vertical: vertical,
                       cardSize: cardSize,
                       linkSnapshot: entry.shelfLink.flatMap { history.quickLinkSnapshots[$0] },
                       click: history.quickShelfClick,
                       pinboards: history.pinboards,
                       showSourceAppIcons: showSourceAppIcons,
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

private struct ClipboardShelfBackdrop: View {
    let edge: ClipboardShelfEdge
    @AppStorage(DefaultsKey.notchLiquidGlassEnabled) private var glass = false
    @AppStorage(DefaultsKey.notchTranslucentBackground) private var translucent = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: edge.cornerRadii(22), style: .continuous)
        material(in: shape).clipShape(shape)
    }

    @ViewBuilder
    private func material(in shape: UnevenRoundedRectangle) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, *), glass && !reduceTransparency {
            Color.clear
                .glassEffect(.clear, in: shape)
                .environment(\.appearsActive, true)
                .materialActiveAppearance(.active)
                .overlay(Color.black.opacity(0.72))
        } else {
            opaqueOrTranslucent
        }
#else
        opaqueOrTranslucent
#endif
    }

    @ViewBuilder
    private var opaqueOrTranslucent: some View {
        if translucent && !reduceTransparency {
            Rectangle().fill(.regularMaterial).overlay(Color.black.opacity(0.77))
        } else {
            Color.black
        }
    }
}

private struct ShelfFlyout: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        shape.fill(Color(white: 0.10))
            .overlay { shape.strokeBorder(.white.opacity(0.12)) }
            .shadow(color: .black.opacity(0.32), radius: 8, y: 4)
    }
}

private struct PinboardEditor: View {
    struct Mode: Identifiable {
        let id = UUID()
        let board: ClipboardPinboard?
    }

    let mode: Mode
    let shelfText: ClipboardShelfStrings
    let text: ClipboardFeatureStrings
    let emojiLabel: String
    let onCancel: () -> Void
    let onSave: (String, String?) -> Void
    @FocusState private var focusedField: Field?
    @State private var name = ""
    @State private var emoji = ""
    @State private var showsEmojiChoices = false

    private static let emojiChoices = [
        "📁", "📚", "🧩", "🚀", "💻", "📝", "📌", "🔖",
        "💡", "🔧", "🎨", "🎯", "✅", "⭐️", "🔥", "❤️",
        "🌱", "🏠", "💼", "🗓️", "📍", "📷", "🎵", "✨",
    ]

    private enum Field { case name, emoji }

    private var emojiValue: String? { ClipboardPinboard.emoji(from: emoji) }

    private var canSave: Bool {
        ClipboardPinboard.name(from: name) != nil
            && (emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || emojiValue != nil)
    }

    private func save() {
        if canSave { onSave(name, emojiValue) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode.board == nil ? shelfText.newPinboard : shelfText.renamePinboard)
                .font(.headline)
            HStack {
                TextField(shelfText.pinboardName, text: $name)
                    .focused($focusedField, equals: .name)
                TextField(emojiLabel, text: $emoji)
                    .focused($focusedField, equals: .emoji)
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
                Button(emojiLabel, systemImage: "face.smiling") { showsEmojiChoices.toggle() }
                    .labelStyle(.iconOnly)
                    .accessibilityAddTraits(showsEmojiChoices ? .isSelected : [])
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit(save)
            if showsEmojiChoices { emojiGrid }
            HStack {
                Spacer()
                Button(text.cancel, action: onCancel)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Button(text.save, action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(14)
        .frame(width: 288)
        .onExitCommand(perform: onCancel)
        .onAppear {
            name = mode.board?.name ?? ""
            emoji = mode.board?.emoji ?? ""
            focusedField = .name
        }
    }

    private var emojiGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 8), spacing: 3) {
            ForEach(Self.emojiChoices, id: \.self) { character in
                Button(character) {
                    emoji = character
                    showsEmojiChoices = false
                    focusedField = .name
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(emojiLabel)
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
    let layout: ClipboardHistoryLayout
    let vertical: Bool
    let cardSize: CGSize
    let linkSnapshot: ClipboardShelfLinkSnapshot?
    let click: ClipboardShelfClick
    let pinboards: [ClipboardPinboard]
    let showSourceAppIcons: Bool
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
            && lhs.vertical == rhs.vertical
            && lhs.cardSize == rhs.cardSize
            && lhs.linkSnapshot == rhs.linkSnapshot
            && lhs.click == rhs.click
            && lhs.pinboards == rhs.pinboards
            && lhs.showSourceAppIcons == rhs.showSourceAppIcons
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
        if isRow || click == .paste {
            entrySurface.onTapGesture { activate(entry, paste: true) }
        } else {
            entrySurface
                .onTapGesture(count: 2) { activate(entry, paste: true) }
                .simultaneousGesture(TapGesture().onEnded { activate(entry, paste: false) })
        }
    }

    private var entrySurface: some View {
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
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 9) {
            selectionButton
            if showSourceAppIcons, let app = sourceApp {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .help(app.name)
                    .accessibilityLabel(app.name)
            }
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
            cardContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            Divider()
            cardFooter
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    @ViewBuilder
    private var cardContent: some View {
        if let color = entry.color {
            ClipboardShelfColorPreview(color: color)
        } else if let url = entry.shelfLink {
            ClipboardShelfLinkCard(entryID: entry.id, url: url, linkText: entry.cardPreview,
                                   tokens: tokens, text: .forLanguage(language), previewLabel: text.previewLabel,
                                   snapshot: linkSnapshot) { load in
                history.selectQuickEntry(entry)
                history.showShelfPreview(entry, loadLinkImmediately: load)
            }
        } else {
            entryContent(entry).padding(10)
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
        let app = sourceApp
        let type = ClipboardShelfStrings.forLanguage(language).typeName(entry.shelfContentType)
        return HStack(spacing: 7) {
            if let app {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: entry.shelfContentType.symbol).frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app?.name ?? type)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                if app != nil {
                    Text(type).font(.system(size: 10)).lineLimit(1)
                }
            }
            Spacer(minLength: 1)
            entryTrailing(entry, isHovered: isHovered)
            if isBatchSelected || isHovered { selectionButton }
        }
        .padding(.horizontal, 9)
        .frame(height: 42)
        .foregroundStyle(app?.tint == nil ? Color.primary : Color.white)
        .background(app?.tint ?? Color(nsColor: .controlBackgroundColor))
    }

    private static var sourceApps: [String: (name: String, icon: NSImage, tint: Color?)] = [:]

    private var sourceApp: (name: String, icon: NSImage, tint: Color?)? {
        guard let bundleID = entry.sourceBundleID else { return nil }
        if let cached = Self.sourceApps[bundleID] { return cached }
        let source = ClipboardHistorySourceApp.resolve(bundleID)
        guard let icon = source.icon else { return nil }
        let app = (source.name, icon, ClipboardSourceTint.color(from: icon))
        Self.sourceApps[bundleID] = app
        return app
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
                    ColorSwatch(color: color)
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
        } else if entry.isPinned {
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
        if !isRow {
            Button(text.previewLabel) { history.showShelfPreview(entry) }
        }
        Divider()
        Button(entry.isPinned ? text.unpin : text.pin) {
            history.togglePin(entry)
        }
        if !isRow { pinboardActions(entry) }
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

    @ViewBuilder
    private func pinboardActions(_ entry: ClipboardHistoryEntry) -> some View {
        let shelfText = ClipboardShelfStrings.forLanguage(language)
        if !pinboards.isEmpty {
            Menu(shelfText.moveToPinboard) {
                ForEach(pinboards) { board in
                    Button(board.label) { history.assignPinboard(board.id, to: entry) }
                        .disabled(entry.pinboardID == board.id)
                }
            }
        }
        if entry.pinboardID != nil {
            Button(shelfText.removeFromPinboard) { history.assignPinboard(nil, to: entry) }
        }
    }

    private func activate(_ entry: ClipboardHistoryEntry, paste: Bool) {
        // ⌘-click and ⇧-click extend the batch in either click mode.
        let modifiers = NSEvent.modifierFlags.intersection([.command, .shift])
        if modifiers.contains(.command) {
            history.toggleQuickBatchSelection(entry)
        } else if modifiers.contains(.shift) {
            history.extendQuickBatchSelection(to: entry)
        } else if !paste {
            history.selectQuickEntry(entry)
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
