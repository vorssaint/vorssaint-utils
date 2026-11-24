// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardQuickPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @AppStorage(DefaultsKey.clipboardHistoryShowSourceAppIcons) private var showSourceAppIcons = false
    @AppStorage(DefaultsKey.clipboardShelfPrivacyMode) private var privacyMode = false
    @AppStorage(DefaultsKey.clipboardShelfLinkPreviews) private var linkPreviewsEnabled = false
    @FocusState private var searchFocused: Bool
    @FocusState private var filterChoiceFocus: FilterChoice?

    private enum FilterChoice: Hashable {
        case source(String)
        case collection(ClipboardShelfCollection)
        case search, closeSearch, filters, addBoard, actions, pasteStack
        case type(ClipboardShelfContentType?)
    }
    @State private var previewSelection = QuickPreviewSelection()
    @State private var previewIsEditing = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clearingIDs: [UUID: Date]?
    @State private var shelfScrollerStyle = NSScroller.preferredScrollerStyle
    @State private var boardEditor: PinboardEditor.Mode?
    @State private var historyRevealEntryID: UUID?
    @State private var deletingBoard: ClipboardPinboard?
    @State private var visibleShelfLinks: [URL] = []
    @State private var failedShelfLinks: Set<URL> = []

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
        .coordinateSpace(name: Self.shelfCoordinates)
        .clipped()
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)) { _ in
            shelfScrollerStyle = NSScroller.preferredScrollerStyle
        }
        .onChange(of: history.quickWindowPresentationID) { _, _ in
            failedShelfLinks.removeAll()
        }
        .onChange(of: linkPreviewsEnabled) { _, _ in
            failedShelfLinks.removeAll()
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
            toolbar
                .modifier(ClipboardClearRecentConfirmation(entryIDs: $clearingIDs))
            if layout == .list {
                filterChoices.disabled(boardEditor != nil)
                Divider()
            }
            shelfResults
            if layout == .list {
                Divider()
                footer.disabled(boardEditor != nil)
            }
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
        .onChange(of: boardEditorTargetAvailable) { _, available in
            if !available { closeBoardEditor() }
        }
        .onChange(of: history.quickFilter.collection) { _, _ in
            guard layout == .cards, boardEditor == nil else { return }
            filterChoiceFocus = nil
            searchFocused = true
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
            historyRevealEntryID = nil
            previewSelection.select(history.selectedQuickEntryID)
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var shelfResults: some View {
        contentWithPreview
            .allowsHitTesting(boardEditor == nil)
            .accessibilityHidden(boardEditor != nil)
            .overlay(alignment: .top) { filterFlyout }
            .overlay(alignment: .topTrailing) {
                if let mode = boardEditor, usesBoardEditorFlyout {
                    pinboardEditor(mode)
                        .background(ShelfFlyout())
                        .padding(8)
                }
            }
    }

    @ViewBuilder
    private var filterFlyout: some View {
        if layout == .cards, boardEditor == nil, hasFilterChoices {
            Group {
                if history.quickSourcePickerPresented || history.quickTypePickerPresented {
                    shelfFilterPicker
                } else {
                    sourceChoices.padding(.vertical, 8)
                }
            }
            .frame(maxWidth: vertical ? .infinity : 430)
            .background(ShelfFlyout())
            .padding(.horizontal, 12)
        }
    }

    private var shelfFilterPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(shelfText.filterByType).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: filterColumns, alignment: .leading, spacing: 6) {
                    typeChoice(nil, label: shelfText.allTypes)
                    ForEach(ClipboardShelfContentType.allCases, id: \.self) { type in
                        typeChoice(type, label: shelfText.typeName(type))
                    }
                }
                if !history.quickSourceApps.isEmpty {
                    Text(text.filterBySourceApp).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: filterColumns, alignment: .leading, spacing: 6) {
                        ForEach(history.quickSourceApps) { app in
                            sourceChoice(app, isCompletion: false, showTabKey: false)
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(height: 205)
    }

    private var filterColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 110), spacing: 5, alignment: .leading)]
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

    private var usesBoardEditorFlyout: Bool { layout != .cards || vertical }

    private var boardEditorTargetAvailable: Bool {
        guard let mode = boardEditor else { return true }
        if let id = mode.entryID { return history.entries.contains { $0.id == id } }
        if let board = mode.board { return history.pinboards.contains { $0.id == board.id } }
        return true
    }

    private func pinboardEditor(_ mode: PinboardEditor.Mode) -> some View {
        PinboardEditor(mode: mode, inline: !usesBoardEditorFlyout, shelfText: shelfText, text: text,
                       emojiLabel: FeatureStrings.commandBar(l10n.language).sourceEmoji,
                       onCancel: { closeBoardEditor() }) { name, emoji in
            guard boardEditor?.id == mode.id, boardEditorTargetAvailable else { return }
            if let board = mode.board {
                history.renamePinboard(board.id, to: name, emoji: emoji)
            } else {
                guard let board = history.createPinboard(named: name, emoji: emoji,
                                                         assigningEntryID: mode.entryID) else { return }
                history.browseQuickCollection(.pinboard(board.id))
            }
            closeBoardEditor()
        }
        .id(mode.id)
    }

    private func editPinboard(_ board: ClipboardPinboard? = nil, assigning entryID: UUID? = nil) {
        history.quickSourcePickerPresented = false
        history.quickTypePickerPresented = false
        history.quickPinboardEditorIsActive = true
        filterChoiceFocus = nil
        searchFocused = false
        boardEditor = .init(board: board, entryID: entryID)
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

    @ViewBuilder
    private var toolbar: some View {
        if layout == .cards {
            GeometryReader { bar in
                shelfToolbar(width: bar.size.width)
                    .frame(height: bar.size.height)
            }
            .padding(.horizontal, vertical ? 10 : 18)
            .frame(height: 44)
        } else {
            HStack(spacing: 6) {
                searchField.layoutPriority(1)
                sourceFilter
                typeFilter
                previewButton
                closeButton
            }
            .disabled(boardEditor != nil)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
    }

    private func shelfToolbar(width: CGFloat) -> some View {
        let expanded = shelfSearchExpanded
        let fieldWidth = expanded ? min(520, max(80, width - 96), max(220, width * 0.4)) : 28
        let leading = expanded ? (width - fieldWidth) / 2 : 0

        return ZStack(alignment: .leading) {
            HStack(spacing: 6) {
                if vertical && expanded {
                    compactPinboardMenu.disabled(boardEditor != nil)
                    Spacer(minLength: 0)
                } else {
                    pinboardBar.padding(.leading, leading + fieldWidth + 6)
                }
                if history.pasteStackCount > 0 && !(vertical && expanded) {
                    ClipboardPasteStackMenu(language: l10n.language)
                        .focused($filterChoiceFocus, equals: .pasteStack)
                        .disabled(boardEditor != nil)
                }
                compactActions.disabled(boardEditor != nil)
            }
            shelfSearch
                .disabled(boardEditor != nil)
                .frame(width: fieldWidth)
                .offset(x: leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shelfSearchExpanded: Bool {
        history.quickShelfSearchExpanded || !history.quickQuery.isEmpty
            || history.quickSourceBundleID != nil || history.quickFilter.type != nil
            || history.quickTypePickerPresented
    }

    private var shelfSearch: some View {
        let expanded = shelfSearchExpanded
        return HStack(spacing: expanded ? 5 : 0) {
            Button {
                history.beginQuickShelfSearch()
                searchFocused = true
            } label: {
                Image(systemName: "magnifyingglass").frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f")
            .help(text.search)
            .accessibilityLabel(text.search)
            .focused($filterChoiceFocus, equals: .search)

            // Keep the native editor focused while collapsed so the first keystroke,
            // including the start of an IME composition, still goes to search.
            TextField(expanded ? text.search : "", text: $history.quickQuery)
                .textFieldStyle(.plain)
                .accessibilityLabel(text.search)
                .focused($searchFocused)
                .frame(width: expanded ? nil : 1)
                .opacity(expanded ? 1 : 0.01)
            if expanded {
                shelfFilterButton
                Button {
                    history.clearQuickShelfSearch()
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(l10n.s.menuClose)
                .accessibilityLabel(l10n.s.menuClose)
                .focused($filterChoiceFocus, equals: .closeSearch)
            }
        }
        .padding(.horizontal, expanded ? 6 : 0)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(expanded ? Color.primary.opacity(0.09) : .clear, in: Capsule())
    }

    private var shelfFilterButton: some View {
        let name = history.quickSourceBundleID.map { bundleID in
            history.quickSourceApps.first { $0.id == bundleID }?.name ?? bundleID
        }
        let type = history.quickFilter.type.map(shelfText.typeName)
        let active = [name, type].compactMap { $0 }.joined(separator: " · ")
        return Button {
            history.quickTypePickerPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: active.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                if !active.isEmpty && !vertical { Text(active).lineLimit(1).frame(maxWidth: 100) }
            }
            .foregroundStyle(active.isEmpty ? Color.secondary : Color.accentColor)
            .padding(.horizontal, 5)
            .frame(height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shelfText.filterByType + ", " + text.filterBySourceApp)
        .accessibilityValue(active)
        .help(active.isEmpty ? shelfText.filterByType + " · " + text.filterBySourceApp : active)
        .focused($filterChoiceFocus, equals: .filters)
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
            Button(shelfText.history, systemImage: "clock") { selectCollection(.history) }
            Button(text.pinned, systemImage: "pin") { selectCollection(.pinned) }
            ForEach(history.pinboards) { board in
                Button(board.label) { selectCollection(.pinboard(board.id)) }
            }
            Divider()
            Button(shelfText.newPinboard, systemImage: "plus") { editPinboard(nil) }
            if let board = activePinboard {
                Button(shelfText.renamePinboard) { editPinboard(board) }
                Button(shelfText.deletePinboard, role: .destructive) { deletingBoard = board }
            }
        } label: {
            if let board = activePinboard {
                Text(board.emoji ?? "📌")
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
            if vertical && shelfSearchExpanded && history.pasteStackCount > 0 {
                ClipboardPasteStackMenu(language: l10n.language, showsName: true)
            }
            if history.quickBatchCount > 0 {
                batchActions
                Divider()
            }
            Button(shelfText.newPinboard, systemImage: "plus") { editPinboard(nil) }
            Button(text.previewLabel, systemImage: "eye") { history.previewQuickSelection() }
                .disabled(history.selectedQuickEntry == nil)
            Button(text.clearRecent, systemImage: "trash") { clearingIDs = history.recentEntriesSnapshot }
                .disabled(history.recentEntries.isEmpty)
            Divider()
            Button(l10n.s.menuClose) { history.hideHistoryWindow() }
        } label: {
            HStack(spacing: 3) {
                if history.quickBatchCount > 0 { Text("\(history.quickBatchCount)") }
                Image(systemName: "ellipsis")
            }
            .frame(minWidth: 22, minHeight: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .focused($filterChoiceFocus, equals: .actions)
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

    @ViewBuilder
    private var newPinboardButton: some View {
        if let mode = boardEditor, mode.board == nil, !usesBoardEditorFlyout {
            pinboardEditor(mode)
        } else {
            Button { editPinboard() } label: {
                Image(systemName: "plus").frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .focused($filterChoiceFocus, equals: .addBoard)
            .help(shelfText.newPinboard)
            .accessibilityLabel(shelfText.newPinboard)
            .disabled(boardEditor != nil)
        }
    }

    private var pinboardBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    collectionButton(shelfText.history, symbol: "clock.arrow.circlepath", collection: .history)
                    collectionButton(text.pinned, symbol: "pin", collection: .pinned)
                    ForEach(history.pinboards, content: pinboardButton)
                    newPinboardButton
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: history.quickFilter.collection, initial: true) { _, collection in
                proxy.scrollTo(collection)
            }
            .onChange(of: boardEditor?.id) { _, id in
                guard !usesBoardEditorFlyout else { return }
                if let id {
                    proxy.scrollTo(id, anchor: .trailing)
                } else {
                    proxy.scrollTo(history.quickFilter.collection)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(shelfText.pinboards)
    }

    private func selectCollection(_ collection: ClipboardShelfCollection) {
        history.browseQuickCollection(collection)
        searchFocused = true
    }

    @ViewBuilder
    private func pinboardButton(_ board: ClipboardPinboard) -> some View {
        if let mode = boardEditor, mode.board?.id == board.id, !usesBoardEditorFlyout {
            pinboardEditor(mode)
        } else {
            collectionButton(board.name, symbol: "square.on.square",
                             collection: .pinboard(board.id), emoji: board.emoji ?? "📌")
                .contextMenu {
                    Button(shelfText.renamePinboard) { editPinboard(board) }
                    Button(shelfText.deletePinboard, role: .destructive) { deletingBoard = board }
                }
                .disabled(boardEditor != nil)
        }
    }

    private func collectionButton(_ name: String, symbol: String,
                                  collection: ClipboardShelfCollection, emoji: String? = nil) -> some View {
        let selected = !history.quickShelfSearchIsActive && history.quickFilter.collection == collection
        return Button {
            selectCollection(collection)
        } label: {
            HStack(spacing: 4) {
                if let emoji {
                    Text(emoji).accessibilityHidden(true)
                } else {
                    Image(systemName: symbol).accessibilityHidden(true)
                }
                if collection == .history && !vertical && !shelfSearchExpanded { Text(name) }
            }
            .font(.system(size: emoji == nil ? 12 : 16, weight: selected ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selected ? Color.primary.opacity(0.14) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .focused($filterChoiceFocus, equals: .collection(collection))
        .disabled(boardEditor != nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .id(collection)
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
        history.quickSourcePickerPresented = false
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
                if app.id == history.quickSourceBundleID {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
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
        .accessibilityAddTraits(app.id == history.quickSourceBundleID ? .isSelected : [])
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
        let deselecting = layout == .cards && !completingQuery && bundleID == history.quickSourceBundleID
        history.setQuickSourceApp(deselecting ? nil : bundleID, completingQuery: completingQuery)
        history.quickSourcePickerPresented = false
        history.quickTypePickerPresented = false
        searchFocused = true
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState(history.entries.isEmpty ? text.empty : text.noResults)
        } else {
            scrollableResults
        }
    }

    private var scrollableResults: some View {
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
            .onChange(of: historyRevealEntryID) { _, id in
                guard let id else { return }
                DispatchQueue.main.async {
                    guard historyRevealEntryID == id else { return }
                    proxy.scrollTo(id)
                    historyRevealEntryID = nil
                }
            }
            .onChange(of: history.quickQuery) { _, _ in
                if layout == .cards {
                    proxy.scrollTo(Self.topAnchorID, anchor: vertical ? .top : .leading)
                } else {
                    scrollSelectedEntry(with: proxy)
                }
            }
            .onChange(of: history.quickShelfSearchIsActive) { _, _ in
                proxy.scrollTo(Self.topAnchorID, anchor: vertical ? .top : .leading)
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
            let viewport = CGRect(origin: .zero, size: geometry.size)

            ScrollView(vertical ? .vertical : .horizontal) {
                cardStack(entries, size: size, viewport: viewport)
                    .padding(vertical ? .horizontal : .vertical, inset)
                    .padding(vertical ? .top : .leading, inset - ClipboardShelfCardLayout.spacing)
                    .padding(vertical ? .bottom : .trailing, inset)
            }
            .coordinateSpace(name: Self.cardViewport)
            .onPreferenceChange(VisibleCardFrames.self) { history.quickCardFrames = $0 }
            .onPreferenceChange(VisibleShelfLinks.self) { visibleShelfLinks = $0 }
            .background { shelfThumbnail }
            .onDisappear { visibleShelfLinks = [] }
        }
    }

    @ViewBuilder
    private func cardStack(_ entries: [ClipboardHistoryEntry], size: CGSize, viewport: CGRect) -> some View {
        let spacing = ClipboardShelfCardLayout.spacing
        if vertical {
            LazyVStack(spacing: spacing) { cardStart; cards(entries, size: size, viewport: viewport) }
        } else {
            LazyHStack(spacing: spacing) { cardStart; cards(entries, size: size, viewport: viewport) }
        }
    }

    private var nextShelfThumbnail: URL? {
        guard linkPreviewsEnabled, !privacyMode, history.canLoadShelfThumbnails else { return nil }
        return visibleShelfLinks.first {
            history.quickLinkSnapshots[$0] == nil && !failedShelfLinks.contains($0)
        }
    }

    @ViewBuilder
    private var shelfThumbnail: some View {
        if let url = nextShelfThumbnail {
            let presentation = history.quickWindowPresentationID
            ClipboardShelfThumbnail(url: url) { snapshot in
                guard history.quickWindowPresentationID == presentation, nextShelfThumbnail == url else { return }
                if let snapshot, snapshot.image != nil {
                    history.rememberLinkSnapshot(snapshot, for: url, keeping: visibleShelfLinks)
                } else {
                    failedShelfLinks.insert(url)
                }
            }
            .id(url)
            .id(presentation)
        }
    }

    private var shelfScrollerWidth: CGFloat {
        guard shelfScrollerStyle == .legacy else { return 0 }
        return NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    }

    private static let eagerRowLimit = 300
    private static let listVerticalInset: CGFloat = 6
    private static let topAnchorID = "clipboard-list-top"
    private static let cardViewport = "clipboard-card-viewport"

    private static let shelfCoordinates = "clipboard-shelf-panel"

    private struct VisibleCardFrames: PreferenceKey {
        static let defaultValue: [UUID: CGRect] = [:]

        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
        }
    }

    private struct VisibleShelfLinks: PreferenceKey {
        static let defaultValue: [URL] = []

        static func reduce(value: inout [URL], nextValue: () -> [URL]) {
            value.append(contentsOf: nextValue())
        }
    }

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

    private func cards(_ entries: [ClipboardHistoryEntry], size: CGSize, viewport: CGRect) -> some View {
        let firstRecentID = recentBoundary(in: entries)
        return ForEach(entries) { entry in
            entryView(entry, cardSize: size)
                .overlay(alignment: vertical ? .top : .leading) {
                    if entry.id == firstRecentID { cardGroupDivider }
                }
                .background { cardGeometry(for: entry, in: viewport) }
        }
    }

    private func cardGeometry(for entry: ClipboardHistoryEntry, in viewport: CGRect) -> some View {
        GeometryReader { card in
            let visible = card.frame(in: .named(Self.cardViewport)).intersects(viewport)
            let frame = card.frame(in: .named(Self.shelfCoordinates))
            let link = visible && linkPreviewsEnabled ? entry.shelfLink : nil
            Color.clear
                .preference(key: VisibleCardFrames.self, value: visible ? [entry.id: frame] : [:])
                .preference(key: VisibleShelfLinks.self, value: link.map { [$0] } ?? [])
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
                       previewSelection: previewSelection,
                       onCreatePinboard: { editPinboard(assigning: $0) },
                       onRevealInHistory: revealInHistory)
            .equatable()
            .id(entry.id)
    }

    private func revealInHistory(_ entry: ClipboardHistoryEntry) {
        history.browseQuickCollection(.history)
        history.selectQuickEntry(entry)
        historyRevealEntryID = entry.id
        searchFocused = true
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


    @ViewBuilder
    private var batchActions: some View {
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
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if history.quickBatchCount > 0 {
                batchActions
            } else {
                Button {
                    clearingIDs = history.recentEntriesSnapshot
                } label: {
                    Label(text.clearRecent, systemImage: "trash")
                }
                .disabled(history.recentEntries.isEmpty)
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
        let entryID: UUID?
    }

    let mode: Mode
    let inline: Bool
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
        Group {
            if inline { inlineEditor } else { flyoutEditor }
        }
        .onSubmit(save)
        .onExitCommand(perform: onCancel)
        .onAppear {
            name = mode.board?.name ?? ""
            emoji = mode.board?.emoji ?? ""
            focusedField = .name
        }
    }

    private var inlineEditor: some View {
        HStack(spacing: 4) {
            emojiField.frame(width: 20)
            Menu {
                ForEach(Self.emojiChoices, id: \.self, content: emojiChoice)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 13, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(emojiLabel)
            .help(emojiLabel)

            nameField
                .frame(width: 112)
            Button(text.cancel, systemImage: "xmark", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .help(text.cancel)
            Button(text.save, systemImage: "checkmark", action: save)
                .keyboardShortcut(.defaultAction)
                .help(text.save)
                .disabled(!canSave)
        }
        .font(.system(size: 12))
        .buttonStyle(.plain)
        .textFieldStyle(.plain)
        .labelStyle(.iconOnly)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Color.primary.opacity(0.14), in: Capsule())
    }

    private var flyoutEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode.board == nil ? shelfText.newPinboard : shelfText.renamePinboard)
                .font(.headline)
            HStack {
                nameField
                emojiField.frame(width: 60)
                Button(emojiLabel, systemImage: "face.smiling") { showsEmojiChoices.toggle() }
                    .labelStyle(.iconOnly)
                    .accessibilityAddTraits(showsEmojiChoices ? .isSelected : [])
            }
            .textFieldStyle(.roundedBorder)
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
        .frame(maxWidth: 288)
    }

    private var nameField: some View {
        TextField(shelfText.pinboardName, text: $name)
            .focused($focusedField, equals: .name)
    }

    private var emojiField: some View {
        TextField(emojiLabel, text: $emoji, prompt: Text("📌"))
            .focused($focusedField, equals: .emoji)
            .multilineTextAlignment(.center)
    }

    private func selectEmoji(_ character: String) {
        emoji = character
        showsEmojiChoices = false
        focusedField = .name
    }

    private func emojiChoice(_ character: String) -> some View {
        Button(character) { selectEmoji(character) }
    }

    private var emojiGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 8), spacing: 3) {
            ForEach(Self.emojiChoices, id: \.self) { character in
                emojiChoice(character)
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
    let onCreatePinboard: (UUID) -> Void
    let onRevealInHistory: (ClipboardHistoryEntry) -> Void
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var titleDraft = ""
    /// The pane follows a row only once the pointer has rested on it: while
    /// rows stream under a still pointer during a scroll, every one of them
    /// would otherwise redraw the pane, and a long entry costs a frame or two
    /// each time.
    @State private var previewFollowTask: Task<Void, Never>?
    private static let previewFollowDelay: Duration = .milliseconds(120)

    private var history: ClipboardHistoryService { .shared }
    private var l10n: L10n { .shared }
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(language) }
    private var shelfText: ClipboardShelfStrings { .forLanguage(language) }

    private var isRow: Bool { layout == .list }

    // These callbacks affect the panel, while the inputs below determine the row's appearance.
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
        .alert(shelfText.renameClip, isPresented: $isRenaming) {
            TextField(shelfText.clipName, text: $titleDraft)
            Button(text.cancel, role: .cancel) {}
            Button(text.save) {
                if !history.renameEntry(entry.id, to: titleDraft) { NSSound.beep() }
            }
        }
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
            rowContent(entry)
            Spacer(minLength: 8)
            rowTrailing(entry)
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
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        let selected = isSelected || isBatchSelected
        return VStack(spacing: 0) {
            cardHeader
            cardContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .background(Color(white: 0.16))
        .overlay(alignment: .bottom) { cardAccessories }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                selected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.20 : 0.10),
                lineWidth: selected ? 3.5 : 1
            )
            .allowsHitTesting(false)
        }
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
            .padding(.bottom, cardAccessoryHeight)
        } else {
            switch entry.kind {
            case .text:
                cardText
            case .image:
                cardImage.padding(.bottom, cardAccessoryHeight)
            case .files:
                cardFiles.padding(.bottom, cardAccessoryHeight)
            }
        }
    }

    private var cardHeaderHeight: CGFloat { min(48, cardSize.height * 0.44) }
    private var cardAccessoryHeight: CGFloat { min(37, (cardSize.height - cardHeaderHeight) * 0.42) }

    private var cardHeader: some View {
        let app = sourceApp
        let tint = app?.tint
        let locale = language.formattingLocale()
        let iconSize = max(1, cardHeaderHeight - 9)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                cardTitle
                TimelineView(.everyMinute) { _ in
                    Text(entry.copiedAt.formatted(.relative(presentation: .named).locale(locale)))
                }
                    .font(.system(size: 10.5))
                    .foregroundStyle(tint == nil ? Color.secondary : Color.white.opacity(0.92))
                    .lineLimit(1)
                    .help(entry.copiedAt.formatted(.dateTime.locale(locale)))
                    .environment(\.locale, locale)
            }
            Spacer(minLength: 0)
            if let app {
                Image(nsImage: app.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .help(app.name)
                    .accessibilityLabel(app.name)
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 9)
        .frame(height: cardHeaderHeight)
        .foregroundStyle(tint == nil ? Color.primary : Color.white)
        .background(tint ?? Color.primary.opacity(0.045))
    }

    private var cardTitle: some View {
        let title = entry.customTitle ?? shelfText.typeName(entry.shelfContentType)
        return HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityLabel(text.pinned)
            }
        }
    }

    private var cardText: some View {
        VStack(spacing: 0) {
            SearchHighlightText.text(entry.cardPreview, tokens: tokens, fontSize: 13)
                .font(.system(size: 13))
                .lineLimit(8)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 13)
                .padding(.top, 11)
            ClipboardShelfCharacterCount(content: entry.text, language: language)
                .opacity(isHovered || isBatchSelected ? 0 : 1)
                .accessibilityHidden(isHovered || isBatchSelected)
                .padding(.horizontal, 46)
                .frame(height: cardAccessoryHeight)
        }
    }

    private var cardImage: some View {
        VStack(spacing: 5) {
            if let name = entry.imageFile {
                cardThumbnail(.stored(name: name), aspectRatio: entry.imageAspectRatio)
            }
            if !entry.imageDimensionsLabel.isEmpty {
                Text(entry.imageDimensionsLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 9)
    }

    private var cardFiles: some View {
        let path = entry.filePaths.count == 1 ? entry.filePaths.first : nil
        let subtitle = path.map {
            let folder = ($0 as NSString).deletingLastPathComponent
            return (folder as NSString).abbreviatingWithTildeInPath
        } ?? entry.preview
        return VStack(spacing: 5) {
            cardFileArtwork(path: path)
            SearchHighlightText.text(fileTitle(entry), tokens: path == nil ? [] : tokens, fontSize: 12)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            SearchHighlightText.text(subtitle, tokens: path == nil ? tokens : [], fontSize: 10.5)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(path == nil ? .tail : .middle)
        }
        .padding(.horizontal, 11)
        .padding(.top, 9)
        .help(entry.filePaths.joined(separator: "\n"))
    }

    private func cardFileArtwork(path: String?) -> some View {
        Group {
            if let path, ClipboardImageStore.isImageFile(atPath: path) {
                cardThumbnail(.file(path: path))
            } else if path != nil, let icon = fileIcon(for: entry) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 62, height: 62)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: path == nil ? "doc.on.doc" : "doc")
                    .font(.system(size: 39, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cardThumbnail(_ source: ClipboardImageStore.ThumbnailSource,
                               aspectRatio: CGFloat? = nil) -> some View {
        ClipboardThumbnailImage(source: source, aspectRatio: aspectRatio)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cardAccessories: some View {
        HStack(spacing: 4) {
            if isHovered || isBatchSelected {
                HStack(spacing: 2) {
                    selectionButton
                    if isHovered { entryHoverActions(entry) }
                }
                .padding(2)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer(minLength: 0)
            if let shortcutIndex {
                Text("⌘\(shortcutIndex + 1)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 7)
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

    @ViewBuilder
    private func rowContent(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            HStack(spacing: 8) {
                if let color = entry.color {
                    ColorSwatch(color: color)
                }
                SearchHighlightText.text(entry.preview, tokens: tokens, fontSize: 12)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            HStack(spacing: 8) {
                if let name = entry.imageFile {
                    rowThumbnail(.stored(name: name), aspectRatio: entry.imageAspectRatio)
                }
                SearchHighlightText.text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)",
                                         tokens: tokens, fontSize: 11.5)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
        case .files:
            rowFiles(entry)
        }
    }

    private func rowFiles(_ entry: ClipboardHistoryEntry) -> some View {
        let path = entry.filePaths.count == 1 ? entry.filePaths.first : nil
        let imagePath = path.flatMap { ClipboardImageStore.isImageFile(atPath: $0) ? $0 : nil }
        return HStack(spacing: 8) {
            if let imagePath {
                rowThumbnail(.file(path: imagePath),
                             aspectRatio: ClipboardImageStore.imageAspectRatio(atPath: imagePath))
            }
            VStack(alignment: .leading, spacing: 2) {
                SearchHighlightText.text(fileTitle(entry), tokens: path == nil ? [] : tokens, fontSize: 12)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                rowFileDetail(entry, imagePath: imagePath)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(entry.filePaths.joined(separator: "\n"))
    }

    @ViewBuilder
    private func rowFileDetail(_ entry: ClipboardHistoryEntry, imagePath: String?) -> some View {
        if let imagePath, let dimensions = ClipboardImageStore.imageDimensionsLabel(atPath: imagePath) {
            Text("\(text.imageEntryLabel) · \(dimensions)")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        } else if entry.filePaths.count > 1 {
            SearchHighlightText.text(entry.preview, tokens: tokens, fontSize: 10)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func rowThumbnail(_ source: ClipboardImageStore.ThumbnailSource,
                              aspectRatio: CGFloat?) -> some View {
        ClipboardThumbnailImage(source: source, aspectRatio: aspectRatio)
            .frame(maxWidth: 240, maxHeight: 120)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func rowTrailing(_ entry: ClipboardHistoryEntry) -> some View {
        if isHovered {
            entryHoverActions(entry)
        } else {
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
        }
    }

    private func entryHoverActions(_ entry: ClipboardHistoryEntry) -> some View {
        HStack(spacing: 4) {
            if entry.kind == .image, AppFeature.screenshot.isAvailable {
                Button { history.editImage(entry) } label: {
                    entryActionIcon("pencil")
                }
                .buttonStyle(.plain)
                .help(text.edit)
                .accessibilityLabel(text.edit)
            }
            Button {
                history.copyOnlyQuickEntry(entry)
            } label: {
                entryActionIcon("doc.on.doc")
            }
            .buttonStyle(.plain)
            .help(text.copy)
            Menu {
                entryActions(entry)
            } label: {
                entryActionIcon("ellipsis", fontSize: 11)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func entryActionIcon(_ symbol: String, fontSize: CGFloat = 10.5) -> some View {
        Image(systemName: symbol)
            .font(.system(size: fontSize, weight: .semibold))
            .frame(width: 24, height: 24)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func entryActions(_ entry: ClipboardHistoryEntry) -> some View {
        Button(pasteActionTitle) { history.copyQuickEntry(entry) }
        Button(text.copy) { history.copyOnlyQuickEntry(entry) }
        if !isRow { cardActions(entry) }
        Divider()
        if isRow {
            Button(entry.isPinned ? text.unpin : text.pin) { history.togglePin(entry) }
        } else {
            pinboardActions(entry)
            if entry.isPinned {
                Button(text.unpin) { history.togglePin(entry) }
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

    private var pasteActionTitle: String {
        guard !isRow, let name = history.quickPasteTargetName else { return l10n.s.menuPaste }
        return String(format: shelfText.pasteToFormat, name)
    }

    @ViewBuilder
    private func cardActions(_ entry: ClipboardHistoryEntry) -> some View {
        if entry.plainTextForPaste != nil {
            Button(l10n.s.pastePlainName) { history.pastePlainTextQuickEntry(entry) }
        }
        ClipboardPasteStackEntryAction(entry: entry, language: language)
        Divider()
        Button(text.previewLabel) { history.showShelfPreview(entry) }
        if entry.kind == .text {
            Button(text.edit) { history.showShelfPreview(entry, editText: true) }
        } else if entry.kind == .image, AppFeature.screenshot.isAvailable {
            Button(text.edit) { history.editImage(entry) }
        }
        Button(shelfText.renameClip) {
            titleDraft = entry.customTitle ?? ""
            isRenaming = true
        }
        Button(shelfText.showInHistory) { onRevealInHistory(entry) }
    }

    private func pinboardActions(_ entry: ClipboardHistoryEntry) -> some View {
        Menu {
            pinboardDestination(text.pinned, id: nil, entry: entry)
            ForEach(pinboards) { board in
                pinboardDestination("\(board.emoji ?? "📌") \(board.name)", id: board.id, entry: entry)
            }
            Divider()
            Button(shelfText.newPinboard, systemImage: "plus") { onCreatePinboard(entry.id) }
        } label: {
            Label(text.pin, systemImage: "pin")
        }
    }

    private func pinboardDestination(_ title: String, id: UUID?, entry: ClipboardHistoryEntry) -> some View {
        Toggle(title, isOn: Binding(
            get: { entry.isPinned && entry.pinboardID == id },
            set: { selected in
                if selected { history.assignPinboard(id, to: entry) }
            }
        ))
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

private struct ClipboardShelfCharacterCount: View {
    let content: String
    let language: AppLanguage
    @State private var counted: (content: String, value: Int)?

    private var isShort: Bool { content.utf8.count <= ClipboardHistoryEntry.indexCharacters }

    private var count: Int? {
        if isShort { return content.count }
        return counted?.content == content ? counted?.value : nil
    }

    var body: some View {
        Group {
            if let count {
                Text(ClipboardShelfStrings.forLanguage(language).characters(count, locale: language.formattingLocale()))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .task(id: content) {
            guard !isShort, count == nil else { return }
            // Large documents count graphemes once, away from the render path.
            let value = await Task.detached(priority: .utility) { [content] in content.count }.value
            guard !Task.isCancelled else { return }
            counted = (content, value)
        }
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
