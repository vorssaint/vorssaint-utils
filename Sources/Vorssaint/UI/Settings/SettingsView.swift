// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Directory construction is much more expensive than selecting an existing
/// row. Rebuild only when its language, icon source or availability changes.
private final class SettingsDirectoryCache {
    private struct Key: Equatable {
        let language: AppLanguage
        let superKeySource: SuperKeySource
        let featureRevision: Int
    }

    private var navigationKey: Key?
    private(set) var sections: [SettingsSidebarSection] = []
    private(set) var items: [SettingsSidebarItem] = []
    private var searchKey: Key?
    private var searchItems: [SettingsSearchItem] = []

    func navigation(strings: Strings, language: AppLanguage,
                    superKeySource: SuperKeySource, featureRevision: Int,
                    isAvailable: (AppFeature) -> Bool) -> [SettingsSidebarSection] {
        let key = Key(language: language, superKeySource: superKeySource,
                      featureRevision: featureRevision)
        if navigationKey != key {
            sections = SettingsDirectory.sidebarSections(
                strings, language: language, superKeySource: superKeySource,
                isAvailable: isAvailable)
            items = sections.flatMap(\.items)
            navigationKey = key
        }
        return sections
    }

    func search(strings: Strings, language: AppLanguage,
                superKeySource: SuperKeySource, featureRevision: Int) -> [SettingsSearchItem] {
        let key = Key(language: language, superKeySource: superKeySource,
                      featureRevision: featureRevision)
        if searchKey != key {
            searchItems = SettingsDirectory.searchItems(
                strings, language: language, superKeySource: superKeySource)
            searchKey = key
        }
        return searchItems
    }
}

/// Settings window with named tools in the sidebar. The detail keeps each
/// tool's existing settings and section anchor.
struct SettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var features = FeatureRuntime.shared
    private let sidebarUndoManager: UndoManager?
    @AppStorage(DefaultsKey.superKeySource) private var superKeySourceRaw =
        SuperKeySource.capsLock.rawValue
    @AppStorage(DefaultsKey.settingsSidebarFavorites) private var sidebarFavoritesRaw = ""
    @AppStorage(DefaultsKey.settingsSidebarOrder) private var sidebarOrderRaw = ""
    @AppStorage(DefaultsKey.settingsSidebarSort) private var sidebarSortRaw =
        SettingsSidebarSortMode.defaultOrder.rawValue
    @AppStorage(DefaultsKey.settingsSidebarUsage) private var sidebarUsageRaw = "{}"
    @AppStorage(DefaultsKey.notchEnabled) private var notchEnabled = false
    @AppStorage(DefaultsKey.shelfEnabled) private var shelfEnabled = false
    @ObservedObject private var keepAwake = KeepAwakeManager.shared
    @State private var searchQuery = ""
    @State private var activeSearchIndex: Int?
    @State private var directoryCache = SettingsDirectoryCache()
    @State private var sidebarUndoController = SettingsSidebarUndoController()
    @State private var collapsedSectionIDs: Set<Int> = []
    @State private var navigationFromSidebar = false
    /// The row just picked in the sidebar, until the router has taken it.
    @State private var sidebarPick: SettingsSidebarItem.ID?
    @State private var confirmingNotchUninstall = false
    @State private var confirmingFeatureUninstall: AppFeature?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @FocusState private var sidebarSearchFocused: Bool

    init(sidebarUndoManager: UndoManager? = nil) {
        self.sidebarUndoManager = sidebarUndoManager
    }

    private struct SearchResultsSnapshot: Equatable {
        let query: String
        let groups: [SettingsSearchGroup]

        var isBlank: Bool {
            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var items: [SettingsSearchSuggestion] {
            groups.flatMap { group in
                (group.parentMatches ? [group.parentSuggestion] : []) + group.suggestions
            }
        }

        var ids: [SettingsSearchSuggestion.ID] { items.map(\.id) }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.query == rhs.query && lhs.ids == rhs.ids
        }
    }

    private var sidebarSections: [SettingsSidebarSection] {
        let sections = directoryCache.navigation(
            strings: l10n.s, language: l10n.language,
            superKeySource: SuperKeySource.sanitized(superKeySourceRaw),
            featureRevision: features.revision,
            isAvailable: { features.isAvailable($0) })
        return SettingsSidebarSupport.organizedSections(
            sections,
            favorites: Set(SettingsSidebarSupport.keys(from: sidebarFavoritesRaw)),
            sortMode: SettingsSidebarSortMode(rawValue: sidebarSortRaw) ?? .defaultOrder,
            manualOrder: SettingsSidebarSupport.keys(from: sidebarOrderRaw),
            usage: SettingsSidebarSupport.usage(from: sidebarUsageRaw),
            favoritesTitle: SettingsSidebarStrings.localized(l10n.language).favorites
        )
    }

    private var sidebarItems: [SettingsSidebarItem] {
        _ = sidebarSections
        return directoryCache.items
    }

    private var sidebarSelection: Binding<SettingsSidebarItem.ID?> {
        Binding(
            get: {
                sidebarPick ?? SettingsSidebarSupport.selection(
                    for: router.destination, in: sidebarItems,
                    preferredID: router.sidebarFeature.map { .feature($0) })
            },
            // The list sets its selection during a view update, where the
            // router must not publish, so the pick is routed once it ends.
            set: { selectedID in
                guard let selectedID,
                      sidebarItems.contains(where: { $0.id == selectedID }) else { return }
                sidebarPick = selectedID
            }
        )
    }

    private func routeSidebarPick(_ selectedID: SettingsSidebarItem.ID?) {
        guard let selectedID else { return }
        sidebarPick = nil
        guard let item = sidebarItems.first(where: { $0.id == selectedID }) else { return }
        let feature: AppFeature?
        if case .feature(let selectedFeature) = selectedID {
            feature = selectedFeature
        } else {
            feature = nil
        }
        navigationFromSidebar = true
        router.request(item.destination, sidebarFeature: feature)
    }

    var body: some View {
        let searchResults: SearchResultsSnapshot = {
            guard hasSearchQuery else { return SearchResultsSnapshot(query: searchQuery, groups: []) }
            return SearchResultsSnapshot(
                query: searchQuery,
                groups: SettingsSearchSupport.groupedMatchingItems(
                    query: searchQuery,
                    items: directoryCache.search(
                        strings: l10n.s, language: l10n.language,
                        superKeySource: SuperKeySource.sanitized(superKeySourceRaw),
                        featureRevision: features.revision),
                    isAvailable: { features.isAvailable($0) }))
        }()

        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar(searchResults: searchResults)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            // NavigationSplitView's detail slot sometimes queries its content
            // for an unconstrained ideal size (settling the divider, or on a
            // page switch). `List` answers that with its full content height
            // rather than a viewport size the way `ScrollView` does, and
            // `.frame(maxHeight: .infinity)` only bounds a size it is given,
            // not one it is asked to report - so a few hundred rows (Kill
            // Process) grew the whole window. `GeometryReader` reports the
            // real space it was actually given for normal layout, and ~zero
            // when asked for an unconstrained ideal size, breaking the chain.
            GeometryReader { geometry in
                detail
                    .settingsSectionFocus(for: router.page)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(selectedSidebarTitle)
        .toolbar {
            // SwiftUI adds its sidebar button only to windows it creates, and
            // this one is AppKit's. Without it, a sidebar dragged shut could
            // only be dragged back from a one-point strip at the window's
            // edge, and a full-screen window could only peek at it.
            ToolbarItem(placement: .navigation) {
                let strings = SettingsNavigationStrings.localized(l10n.language)
                let title = sidebarShown ? strings.hideSidebar : strings.showSidebar
                Button(action: toggleSidebar) {
                    Label(title, systemImage: "sidebar.left")
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .help(title)
            }
            ToolbarItemGroup(placement: .navigation) {
                let strings = SettingsNavigationStrings.localized(l10n.language)
                Button {
                    router.goBack(isPageVisible: isPageVisible)
                } label: {
                    Label(strings.back, systemImage: "chevron.backward")
                }
                .disabled(!router.canGoBack(isPageVisible: isPageVisible))
                .help(strings.back)

                Button {
                    router.goForward(isPageVisible: isPageVisible)
                } label: {
                    Label(strings.forward, systemImage: "chevron.forward")
                }
                .disabled(!router.canGoForward(isPageVisible: isPageVisible))
                .help(strings.forward)
            }
        }
        .frame(minWidth: 772, maxWidth: .infinity, minHeight: 528, maxHeight: .infinity)
        .onAppear {
            ensureVisiblePage()
            expandSelectedSection()
        }
        .onChange(of: features.revision) { _, _ in ensureVisiblePage() }
        .onChange(of: searchResults, initial: true) { previous, current in
            updateSearchSelection(previous: previous, current: current)
        }
        .onChange(of: router.requestID) { _, _ in
            searchQuery = ""
            activeSearchIndex = nil
            recordSidebarUsage()
            ensureVisiblePage()
        }
    }

    private func sidebar(searchResults: SearchResultsSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                SidebarSearchField(query: $searchQuery, isFocused: $sidebarSearchFocused)
                    .frame(maxWidth: .infinity)
                sidebarOrganizationMenu
            }
            .padding(.trailing, 8)
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                sidebarList(searchResults: searchResults)
                    .scrollEdgeEffectStyle(.hard, for: .top)
            } else {
                sidebarList(searchResults: searchResults)
            }
            #else
            sidebarList(searchResults: searchResults)
            #endif
        }
    }

    private var sidebarOrganizationMenu: some View {
        let strings = SettingsSidebarStrings.localized(l10n.language)
        return Menu {
            Picker(strings.sortBy, selection: sidebarSortSelection) {
                Text(strings.defaultOrder).tag(SettingsSidebarSortMode.defaultOrder)
                Text(strings.mostUsed).tag(SettingsSidebarSortMode.mostUsed)
                Text(strings.name).tag(SettingsSidebarSortMode.name)
                Text(strings.manual).tag(SettingsSidebarSortMode.manual)
            }
            Divider()
            Button(SettingsSidebarStrings.resetUsageTitle(l10n.language)) {
                sidebarUsageRaw = "{}"
            }
            .disabled(SettingsSidebarSupport.usage(from: sidebarUsageRaw).isEmpty)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(strings.organize)
        .accessibilityLabel(strings.organize)
    }

    private var hasSearchQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A sidebar dragged shut reports `.detailOnly` here as well.
    private var sidebarShown: Bool { columnVisibility != .detailOnly }

    private var sidebarSortSelection: Binding<SettingsSidebarSortMode> {
        Binding(
            get: { SettingsSidebarSortMode(rawValue: sidebarSortRaw) ?? .defaultOrder },
            set: { sidebarSortRaw = $0.rawValue }
        )
    }

    private func recordSidebarUsage() {
        guard let selectedSidebarItem,
              let item = sidebarItems.first(where: { $0.id == selectedSidebarItem }) else { return }
        var usage = SettingsSidebarSupport.usage(from: sidebarUsageRaw)
        usage[item.stableKey, default: 0] += 1
        sidebarUsageRaw = SettingsSidebarSupport.usageStorage(usage)
    }

    private func toggleFavorite(_ item: SettingsSidebarItem) {
        var favorites = Set(SettingsSidebarSupport.keys(from: sidebarFavoritesRaw))
        if !favorites.insert(item.stableKey).inserted {
            favorites.remove(item.stableKey)
        }
        sidebarFavoritesRaw = SettingsSidebarSupport.storage(for: favorites.sorted())
    }

    private func moveSidebarItems(sectionID: Int, from source: IndexSet, to destination: Int) {
        guard let sectionIndex = sidebarSections.firstIndex(where: { $0.id == sectionID }) else { return }
        var sections = sidebarSections
        var movedItems = sections[sectionIndex].items
        movedItems.move(fromOffsets: source, toOffset: destination)
        sections[sectionIndex] = SettingsSidebarSection(
            id: sectionID, title: sections[sectionIndex].title, items: movedItems)
        let updatedOrder = SettingsSidebarSupport.storage(
            for: sections.flatMap(\.items).map(\.stableKey))
        guard updatedOrder != sidebarOrderRaw else { return }
        if let sidebarUndoManager {
            sidebarUndoController.registerUndo(for: sidebarOrderRaw, with: sidebarUndoManager)
        }
        sidebarOrderRaw = updatedOrder
    }

    private func toggleSidebar() {
        let next: NavigationSplitViewVisibility = sidebarShown ? .detailOnly : .all
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            columnVisibility = next
        } else {
            withAnimation { columnVisibility = next }
        }
    }

    @ViewBuilder
    private func sidebarList(searchResults: SearchResultsSnapshot) -> some View {
        ScrollViewReader { proxy in
            List(selection: sidebarSelection) {
                if hasSearchQuery {
                    searchResultRows(searchResults)
                } else {
                    normalSidebarRows
                }
            }
            .listStyle(.sidebar)
            .onChange(of: sidebarPick) { _, selectedID in routeSidebarPick(selectedID) }
            .onChange(of: activeSearchIndex) { _, index in
                guard let index, searchResults.items.indices.contains(index) else { return }
                let id = searchResults.items[index].id
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    proxy.scrollTo(id)
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id) }
                }
            }
            .onChange(of: hasSearchQuery) { _, searching in
                // The list stays in place across a search so the field keeps
                // focus, which also keeps the results' scroll offset. Centering
                // the chosen tool brings it back into view; near the top, the
                // pages clamp to where a fresh list starts, and a top anchor
                // would leave the list's inset hidden.
                guard !searching else { return }
                expandSelectedSection()
                DispatchQueue.main.async { scrollSidebarToSelection(proxy) }
            }
            .onChange(of: router.requestID) { _, _ in
                // A click in the sidebar is already visible. Only external
                // routes need to reveal and scroll to their destination.
                let fromSidebar = navigationFromSidebar
                navigationFromSidebar = false
                guard !fromSidebar else { return }
                expandSelectedSection()
                DispatchQueue.main.async { scrollSidebarToSelection(proxy) }
            }
            .background {
                SearchKeyMonitor(customSearchFocused: sidebarSearchFocused) { keyCode in
                    handleSearchKey(keyCode, searchResults: searchResults.items)
                }
            }
        }
    }

    private var selectedSidebarItem: SettingsSidebarItem.ID? {
        let items = sidebarItems
        return SettingsSidebarSupport.selection(for: router.destination, in: items,
                                                preferredID: router.sidebarFeature.map { .feature($0) })
            ?? items.first?.id
    }

    private var selectedSidebarTitle: String {
        guard let selectedSidebarItem,
              let item = sidebarItems.first(where: { $0.id == selectedSidebarItem }) else {
            return l10n.s.settingsTitle
        }
        return item.title
    }

    private var focusedFeature: AppFeature? {
        guard let selectedSidebarItem,
              let item = sidebarItems.first(where: { $0.id == selectedSidebarItem }) else { return nil }
        switch item.id {
        case .feature(let feature):
            return feature
        case .setting(.keyboardBrightnessShortcuts):
            return .brightness
        case .setting:
            return AppFeature.allCases.first { $0.settingsDestination == item.destination }
        case .page(let page):
            switch page {
            case .notch:
                return .notch
            case .general, .features, .energy, .monitor, .mouse:
                return nil
            default:
                let matches = AppFeature.allCases.filter {
                    $0.settingsDestination == item.destination
                }
                return matches.count == 1 ? matches.first : nil
            }
        }
    }

    private func scrollSidebarToSelection(_ proxy: ScrollViewProxy) {
        guard !hasSearchQuery, let selected = selectedSidebarItem else { return }
        proxy.scrollTo(selected, anchor: .center)
    }

    private func expandSelectedSection() {
        guard let selected = selectedSidebarItem,
              let section = sidebarSections.first(where: { section in
                  section.items.contains(where: { $0.id == selected })
              }) else { return }
        collapsedSectionIDs.remove(section.id)
    }

    @ViewBuilder
    private var normalSidebarRows: some View {
        let sections = sidebarSections
        ForEach(sections) { section in
            Section {
                if !collapsedSectionIDs.contains(section.id) {
                    ForEach(section.items) { item in
                        HStack(spacing: 9) {
                            SettingsIconTile(symbol: item.icon, accentGroup: item.accentGroup)
                            Text(item.title)
                                .fontWeight(item.id == selectedSidebarItem ? .semibold : .regular)
                        }
                        .tag(item.id)
                        .id(item.id)
                        .help(item.title)
                        .contextMenu {
                            let strings = SettingsSidebarStrings.localized(l10n.language)
                            Button {
                                toggleFavorite(item)
                            } label: {
                                Label(
                                    SettingsSidebarSupport.keys(from: sidebarFavoritesRaw)
                                        .contains(item.stableKey)
                                        ? strings.removeFromFavorites : strings.addToFavorites,
                                    systemImage: SettingsSidebarSupport.keys(from: sidebarFavoritesRaw)
                                        .contains(item.stableKey) ? "heart.slash" : "heart"
                                )
                            }
                        }
                    }
                    .onMove { source, destination in
                        guard SettingsSidebarSortMode(rawValue: sidebarSortRaw) == .manual else { return }
                        moveSidebarItems(sectionID: section.id, from: source, to: destination)
                    }
                }
            } header: {
                Button {
                    if !collapsedSectionIDs.insert(section.id).inserted {
                        collapsedSectionIDs.remove(section.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: collapsedSectionIDs.contains(section.id)
                            ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 12)
                        Text(section.title)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func searchResultRows(_ searchResults: SearchResultsSnapshot) -> some View {
        ForEach(searchResults.groups, id: \.parentSuggestion.id) { group in
            searchPageRow(group, searchResults: searchResults)
            ForEach(group.suggestions) { suggestion in
                searchSuggestionRow(suggestion, searchResults: searchResults)
            }
        }
    }

    private func searchPageRow(_ group: SettingsSearchGroup,
                               searchResults: SearchResultsSnapshot) -> some View {
        let suggestion = group.parentSuggestion
        let selectionIndex = searchResults.items.firstIndex { $0.id == suggestion.id }
        let isSelected = selectionIndex == activeSearchIndex
        return Button {
            requestSearchItem(suggestion)
        } label: {
            HStack(spacing: 9) {
                SettingsIconTile(symbol: group.pageItem.icon)
                Text(group.pageItem.title)
                .fontWeight(.semibold)
            }
            .searchResultRowStyle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(suggestion.id)
    }

    private func searchSuggestionRow(_ suggestion: SettingsSearchSuggestion,
                                     searchResults: SearchResultsSnapshot) -> some View {
        let selectionIndex = searchResults.items.firstIndex { $0.id == suggestion.id }
        let isSelected = selectionIndex == activeSearchIndex
        return Button {
            requestSearchItem(suggestion)
        } label: {
            HStack(spacing: 9) {
                SettingsIconTile(symbol: suggestion.icon)
                Text(suggestion.title)
            }
                .searchResultRowStyle(isSelected: isSelected)
                .padding(.leading, 18)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(suggestion.id)
    }

    private func handleSearchKey(_ keyCode: UInt16,
                                  searchResults: [SettingsSearchSuggestion]) -> Bool {
        switch keyCode {
        case 126: // Up
            guard !searchResults.isEmpty else { return false }
            activeSearchIndex = SettingsSearchSupport.moveSelection(
                index: activeSearchIndex, delta: -1, count: searchResults.count)
            return true
        case 125: // Down
            guard !searchResults.isEmpty else { return false }
            activeSearchIndex = SettingsSearchSupport.moveSelection(
                index: activeSearchIndex, delta: 1, count: searchResults.count)
            return true
        case 36, 76: // Return / Keypad Enter
            guard let index = activeSearchIndex,
                  searchResults.indices.contains(index) else { return false }
            requestSearchItem(searchResults[index])
            return true
        default:
            return false
        }
    }

    private func updateSearchSelection(previous: SearchResultsSnapshot,
                                       current: SearchResultsSnapshot) {
        guard !current.isBlank, !current.items.isEmpty else {
            activeSearchIndex = nil
            return
        }
        if previous.query != current.query {
            activeSearchIndex = 0
        } else if previous.ids != current.ids {
            activeSearchIndex = SettingsSearchSupport.reconciledSelection(
                index: activeSearchIndex,
                previousIDs: previous.ids,
                resultIDs: current.ids)
        }
    }

    private struct SearchKeyMonitor: NSViewRepresentable {
        var customSearchFocused: Bool
        var handleKey: (UInt16) -> Bool

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.install(for: view)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            context.coordinator.customSearchFocused = customSearchFocused
            context.coordinator.handleKey = handleKey
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(customSearchFocused: customSearchFocused, handleKey: handleKey)
        }

        static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
            coordinator.removeMonitor()
        }

        final class Coordinator: NSObject {
            var customSearchFocused: Bool
            var handleKey: (UInt16) -> Bool
            private var monitor: Any?

            init(customSearchFocused: Bool, handleKey: @escaping (UInt16) -> Bool) {
                self.customSearchFocused = customSearchFocused
                self.handleKey = handleKey
            }

            func install(for view: NSView) {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                    [weak self, weak view] event in
                    guard let self, let view, let window = view.window,
                          event.window === window,
                          Self.isNavigationKey(event),
                          let editor = window.firstResponder as? NSTextView,
                          editor.isFieldEditor,
                          (customSearchFocused || Self.isSidebarSearchEditor(editor, near: view)),
                          !editor.hasMarkedText() else { return event }
                    return handleKey(event.keyCode) ? nil : event
                }
            }

            func removeMonitor() {
                guard let monitor else { return }
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }

            private static func isNavigationKey(_ event: NSEvent) -> Bool {
                let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
                guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return false }
                return [UInt16(126), 125, 36, 76].contains(event.keyCode)
            }

            private static func isSidebarSearchEditor(_ editor: NSTextView,
                                                      near monitorView: NSView) -> Bool {
                guard let searchField = editor.delegate as? NSSearchField else { return false }
                let searchMidX = searchField.convert(searchField.bounds, to: nil).midX
                let sidebarFrame = monitorView.convert(monitorView.bounds, to: nil)
                return sidebarFrame.minX...sidebarFrame.maxX ~= searchMidX
            }
        }
    }

    private func requestSearchItem(_ suggestion: SettingsSearchSuggestion) {
        activeSearchIndex = nil
        let routed = SettingsSearchSupport.route(for: suggestion)
        router.request(routed.destination, targetFeature: routed.targetFeature,
                       sidebarFeature: suggestion.item.feature)
    }

    /// The selected page can leave the sidebar when its last feature is
    /// switched off in the hub; fall back to the hub itself, where the
    /// feature can be brought back.
    private func ensureVisiblePage() {
        if !isPageVisible(router.page) {
            router.page = .features
            return
        }
        guard router.destination.sectionAnchor != nil,
              !sidebarItems.contains(where: { $0.destination == router.destination }) else { return }
        switch router.page {
        case .general:
            // General stays visible when one of its tools is uninstalled.
            router.request(FeatureSettingsDestination(.general), replacingVisit: true)
        case .energy:
            // Energy has no overview row. A history visit to an uninstalled
            // tool should show another available tool, not an empty detail.
            if let available = sidebarItems.first(where: { $0.destination.page == .energy }) {
                router.request(available.destination, replacingVisit: true)
            }
        default:
            break
        }
    }

    private func isPageVisible(_ page: SettingsPage) -> Bool {
        FeatureVisibilitySupport.isPageVisible(page, isAvailable: { $0.isAvailable })
    }

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            if let item = selectedSidebarItem,
               let sidebarItem = sidebarItems.first(where: { $0.id == item }) {
                SettingsFeatureHeader(
                    symbol: sidebarItem.icon,
                    title: sidebarItem.title,
                    description: detailHeroDescription(for: sidebarItem),
                    accentGroup: sidebarItem.accentGroup
                ) {
                    featureHeroAccessory
                }
                .frame(maxWidth: 804)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 8)
            }
            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .environment(\.settingsFocusedFeature, focusedFeature)
            if let feature = focusedFeature, router.page != .features {
                featurePageFooter(feature)
            }
        }
        .alert(FeatureStrings.hub(l10n.language).notchUninstallTitle,
               isPresented: $confirmingNotchUninstall) {
            let hub = FeatureStrings.hub(l10n.language)
            Button(hub.notchUninstallWithExtensions, role: .destructive) {
                FeatureRuntime.shared.setAvailable(
                    [AppFeature.notch] + AppFeature.dynamicIslandExtensions.filter(\.isAvailable),
                    false)
            }
            Button(hub.notchUninstallKeepExtensions, role: .destructive) {
                FeatureRuntime.shared.setAvailable([.notch], false)
            }
            Button(hub.presetConfirmCancel, role: .cancel) {}
        } message: {
            let hub = FeatureStrings.hub(l10n.language)
            Text(String(format: hub.notchUninstallMessageFormat,
                        AppFeature.dynamicIslandExtensions.filter(\.isAvailable)
                            .map { $0.hubTitle(l10n.s, hub: hub) }.joined(separator: ", ")))
        }
        .confirmationDialog(FeatureStrings.hub(l10n.language).uninstallButton,
                            isPresented: Binding(
                                get: { confirmingFeatureUninstall != nil },
                                set: { if !$0 { confirmingFeatureUninstall = nil } }),
                            titleVisibility: .visible) {
            Button(FeatureStrings.hub(l10n.language).uninstallButton, role: .destructive) {
                guard let feature = confirmingFeatureUninstall else { return }
                confirmingFeatureUninstall = nil
                FeatureRuntime.shared.setAvailable([feature], false)
            }
            Button(FeatureStrings.hub(l10n.language).presetConfirmCancel, role: .cancel) {
                confirmingFeatureUninstall = nil
            }
        } message: {
            if let feature = confirmingFeatureUninstall {
                Text(feature.hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language)))
            }
        }
    }

    @ViewBuilder
    private var featureHeroAccessory: some View {
        if let feature = focusedFeature {
            HStack(spacing: 12) {
                if feature.hasHeroAction || feature == .screenshot {
                    Button {
                        performFeatureHeroAction(for: feature)
                    } label: {
                        Label(featureHeroActionTitle(for: feature),
                              systemImage: featureHeroActionSymbol(for: feature))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!canPerformFeatureHeroAction(feature))
                }
                if feature == .keepAwake || !feature.primaryEnabledKeys.isEmpty {
                    Toggle(isOn: featureActivationBinding(for: feature)) { EmptyView() }
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(feature.hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language)))
                    .disabled(!feature.isAvailable)
                }
            }
        }
    }

    private func featureHeroActionTitle(for feature: AppFeature) -> String {
        switch feature {
        case .screenshot: "Take Screenshot"
        case .cleaningMode: "Lock now"
        default: "Open"
        }
    }

    private func featureHeroActionSymbol(for feature: AppFeature) -> String {
        switch feature {
        case .screenshot: "camera.viewfinder"
        case .cleaningMode: "lock.fill"
        default: "arrow.up.right"
        }
    }

    private func canPerformFeatureHeroAction(_ feature: AppFeature) -> Bool {
        guard feature.isAvailable else { return false }
        switch feature {
        case .notch: return notchEnabled
        case .shelf: return shelfEnabled
        case .cleaningMode: return !CleaningModeManager.shared.isActive
        default: return true
        }
    }

    private func featureActivationBinding(for feature: AppFeature) -> Binding<Bool> {
        Binding(
            get: {
                if feature == .keepAwake { return keepAwake.isActive }
                return feature.primaryEnabledKeys.contains {
                    UserDefaults.standard.bool(forKey: $0)
                }
            },
            set: { isEnabled in
                if feature == .keepAwake {
                    if isEnabled {
                        keepAwake.startLastPick()
                    } else if keepAwake.isActive {
                        keepAwake.toggle()
                    }
                } else {
                    FeatureRuntime.shared.setPrimaryEnabled(feature, isEnabled)
                }
            }
        )
    }

    private func featurePageFooter(_ feature: AppFeature) -> some View {
        HStack(spacing: 10) {
            Button {
                router.request(FeatureSettingsDestination(.features), targetFeature: feature)
            } label: {
                Label("Show in Features", systemImage: "square.grid.2x2")
            }
            .buttonStyle(.borderless)
            .help("Find this feature in the Features page")
            Spacer(minLength: 8)
            Button(role: .destructive) {
                if feature == .notch,
                   AppFeature.dynamicIslandExtensions.contains(where: \.isAvailable) {
                    confirmingNotchUninstall = true
                } else {
                    confirmingFeatureUninstall = feature
                }
            } label: {
                Label("Uninstall", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: 804)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func performFeatureHeroAction(for feature: AppFeature) {
        switch feature {
        case .quickLauncher:
            QuickLauncherService.shared.show()
        case .quitApps:
            QuickTogglesService.shared.showQuitApps()
        case .cameraPreview:
            CameraPreviewService.shared.show()
        case .scratchpad:
            ScratchpadService.shared.show()
        case .commandBar:
            CommandBarService.shared.show()
        case .radialMenu:
            RadialMenuService.shared.presentPreview()
        case .shelf:
            ShelfService.shared.summon()
        case .notch:
            NotchService.shared.open()
        case .screenshot:
            ScreenCaptureService.shared.capture(initial: .screenshot)
        case .cleaningMode:
            CleaningModeManager.shared.activate()
        default:
            break
        }
    }

    private func detailHeroDescription(for item: SettingsSidebarItem) -> String? {
        let feature: AppFeature?
        switch item.id {
        case .feature(let selected): feature = selected
        case .setting(.keyboardBrightnessShortcuts): feature = .brightness
        case .setting(.panelConfiguration): feature = nil
        case .setting:
            feature = AppFeature.allCases.first {
                $0.settingsDestination.sectionAnchor == item.destination.sectionAnchor
                    && $0.settingsDestination.page == item.destination.page
            }
        case .page(let page):
            switch page {
            case .general, .features, .energy, .monitor, .mouse:
                feature = nil
            case .notch:
                feature = .notch
            default:
                let matches = AppFeature.allCases.filter {
                    $0.settingsDestination == item.destination
                }
                feature = matches.count == 1 ? matches.first : nil
            }
        }

        if let feature {
            return feature.hubDescription(FeatureStrings.hub(l10n.language))
        }
        switch item.destination.page {
        case .general: return FeatureStrings.generalSettings(l10n.language).pageDescription
        case .features: return FeatureStrings.hub(l10n.language).intro
        case .energy: return FeatureStrings.settingsPages(l10n.language).energyDescription
        case .monitor: return FeatureStrings.settingsPages(l10n.language).monitorDescription
        case .mouse: return FeatureStrings.settingsPages(l10n.language).mouseDescription
        case .notch: return FeatureStrings.notch(l10n.language).description
        case .shortcuts: return l10n.s.shortcutsPageCaption
        case .advanced: return FeatureStrings.settingsPages(l10n.language).advancedDescription
        case .about: return FeatureStrings.settingsPages(l10n.language).aboutDescription
        case .support: return FeatureStrings.settingsPages(l10n.language).supportDescription
        case .releaseNotes: return FeatureStrings.settingsPages(l10n.language).releaseNotesDescription
        default: return nil
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch router.page {
        case .general:
            if let anchor = router.destination.sectionAnchor,
               [.panelConfiguration, .mixer, .soundOutputSwitcher,
                .audioPriority, .musicBlocking].contains(anchor),
               sidebarItems.contains(where: { $0.destination == router.destination }) {
                GeneralToolSettings(anchor: anchor)
            } else {
                GeneralSettings()
            }
        case .features: FeatureHubSettings()
        case .textSnippets: TextSnippetsSettings()
        case .notch: NotchSettings()
        case .notchMascot: NotchMascotSettings()
        case .radialMenu: RadialMenuSettings(focus: focusedFeature)
        case .commandBar: CommandBarSettings()
        case .energy: EnergySettings(focus: router.destination.sectionAnchor)
        case .monitor: MonitorSettings(focus: focusedFeature)
        case .mouse: MouseSettings(focus: focusedFeature)
        case .switcher: SwitcherSettings()
        case .dock: DockSettings(focus: focusedFeature)
        case .keyDebounce: KeyboardDebounceSettings()
        case .keyRemapping: KeyboardRemappingSettings()
        case .superKey: SuperKeySettings()
        case .cutPaste: CutPasteSettings(focus: focusedFeature)
        case .autoQuit: AutoQuitSettings()
        case .quitProtection: QuitProtectionSettings()
        case .uninstaller: UninstallerView()
        case .killProcess: KillProcessView()
        case .portManager: PortManagerView()
        case .urlCleaner: URLCleanerSettings()
        case .cleaner: CleanerSettings()
        case .homebrew: HomebrewSettings()
        case .appUpdates: AppUpdatesSettings()
        case .media: MediaSettings()
        case .clipboard: ClipboardSettings(focus: focusedFeature)
        case .quickTools: QuickToolsSettings()
        case .screenshot: ScreenCaptureSettings()
        case .windowLayout: WindowLayoutSettings(focus: focusedFeature)
        case .shelf: ShelfSettings()
        case .shortcuts: ShortcutsSettings()
        case .advanced: AdvancedSettings()
        case .about: AboutSettings()
        case .releaseNotes: ReleaseNotesSettings()
        case .support: SupportSettings()
        }
    }
}

@MainActor
private final class SettingsSidebarUndoController {
    private weak var undoManager: UndoManager?

    func registerUndo(for previousOrder: String, with undoManager: UndoManager) {
        self.undoManager = undoManager
        undoManager.registerUndo(withTarget: self) { controller in
            controller.restore(previousOrder)
        }
        undoManager.setActionName("Reorder Sidebar")
    }

    private func restore(_ order: String) {
        guard let undoManager else { return }
        let currentOrder = UserDefaults.standard.string(forKey: DefaultsKey.settingsSidebarOrder) ?? ""
        guard currentOrder != order else { return }
        undoManager.registerUndo(withTarget: self) { controller in
            controller.restore(currentOrder)
        }
        undoManager.setActionName("Reorder Sidebar")
        UserDefaults.standard.set(order, forKey: DefaultsKey.settingsSidebarOrder)
    }
}

// MARK: - Updates

struct UpdatesView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var updates = UpdateService.shared
    @AppStorage(DefaultsKey.autoCheckUpdates) private var autoCheck = true
    @AppStorage(DefaultsKey.includeBetaUpdates) private var includeBetas = AppInfo.isBeta
    @AppStorage(DefaultsKey.showReleaseNotesBeforeUpdate) private var showReleaseNotesFirst = true
    @AppStorage(DefaultsKey.releaseNotesOnUpdate) private var showWhatsNewAfter = true

    var body: some View {
        Section(l10n.s.updatesSection) {
            Toggle(l10n.s.autoCheckToggle, isOn: $autoCheck)
                .onChange(of: autoCheck) { _, value in
                    UpdateService.shared.autoCheckEnabled = value
                }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(l10n.s.includeBetaUpdatesToggle, isOn: $includeBetas)
                    .onChange(of: includeBetas) { _, value in
                        UpdateService.shared.includeBetaUpdates = value
                    }
                SettingsCaptionText(l10n.s.includeBetaUpdatesCaption)
            }

            VStack(alignment: .leading, spacing: 4) {
                let whatsNew = FeatureStrings.whatsNew(l10n.language)
                Toggle(whatsNew.showPreviewToggle, isOn: $showReleaseNotesFirst)
                if showWhatsNewAfter {
                    SettingsCaptionText(whatsNew.showPreviewCaption)
                }
            }

            Toggle(l10n.s.releaseNotesOnUpdateToggle, isOn: $showWhatsNewAfter)

            statusRow

            HStack {
                Button(l10n.s.checkNowButton) {
                    updates.check(manual: true)
                }
                .disabled(isBusy)

                if case .available = updates.state {
                    Button(l10n.s.updateInstallButton) {
                        appDelegate()?.showUpdatePreview()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let lastChecked = updates.lastChecked {
                Text("\(l10n.s.updateLastChecked) \(Self.format(lastChecked))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch updates.state {
        case .idle:
            EmptyView()
        case .checking:
            label(l10n.s.updateChecking, system: "arrow.triangle.2.circlepath", tint: .secondary)
        case .upToDate:
            label(l10n.s.updateUpToDate, system: "checkmark.circle.fill", tint: .green)
        case let .available(version):
            label("\(l10n.s.updateAvailablePrefix) \(version)", system: "arrow.down.circle.fill", tint: .accentColor)
        case let .downloading(progress):
            if let progress {
                label("\(l10n.s.updateDownloading) \(Int(progress * 100))%",
                      system: "arrow.down.circle", tint: .secondary)
            } else {
                label(l10n.s.updateDownloading, system: "arrow.down.circle", tint: .secondary)
            }
        case .installing:
            label(l10n.s.updateInstalling, system: "gearshape.2.fill", tint: .secondary)
        case let .failed(reason):
            label("\(l10n.s.updateFailedPrefix) \(reason)", system: "exclamationmark.triangle.fill", tint: .orange)
        }
    }

    private func label(_ text: String, system: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system).foregroundStyle(tint)
            Text(text).font(.callout)
            Spacer()
        }
    }

    private var isBusy: Bool {
        switch updates.state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - About

struct AboutSettings: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Form {
            Section {
                aboutContent
            }

            UpdatesView()
        }
        .formStyle(.grouped)
    }

    private var aboutContent: some View {
        VStack(spacing: 14) {
            BrandBadge(size: 76)
            VStack(spacing: 3) {
                Text(AppInfo.name)
                    .font(.title2.bold())
                HStack(spacing: 6) {
                    Text("\(l10n.s.versionPrefix) \(AppInfo.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if AppInfo.isBeta {
                        Text(l10n.s.betaBadgeLabel)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                if AppInfo.isDeveloperBuild, let commit = AppInfo.buildCommit {
                    // Dev-only: which source commit this build came from. Never shipped.
                    Text(commit)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            HStack(spacing: 12) {
                Button(l10n.s.reviewIntro) {
                    appDelegate()?.showOnboarding()
                }
                Button(l10n.s.reviewHighlights) {
                    appDelegate()?.showUpdateHighlights(isReview: true)
                }
                Link(l10n.s.viewOnGitHub, destination: AppInfo.repositoryURL)
            }
            Text(AppInfo.copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Release notes

struct ReleaseNotesSettings: View {
    @ObservedObject private var l10n = L10n.shared
    private let notes = ReleaseNotes.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.s.obWhatsNewTitle)
                    .font(.title2.bold())
                Text(versionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if notes.sections.isEmpty {
                        fallbackNote
                    } else {
                        ForEach(Array(notes.sections.enumerated()), id: \.offset) { _, section in
                            releaseSection(section)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var versionLine: String {
        if let date = notes.date {
            return "v\(notes.version) · \(date)"
        }
        return "v\(notes.version)"
    }

    private var fallbackNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, alignment: .center)
            Text(l10n.s.obWhatsNewFallback)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func releaseSection(_ section: ReleaseNoteSection) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if !section.title.isEmpty {
                Text(section.title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }
            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                releaseItem(item, sectionTitle: section.title)
            }
        }
    }

    @ViewBuilder
    private func releaseItem(_ item: ReleaseNoteItem, sectionTitle: String) -> some View {
        switch item {
        case let .paragraph(text):
            Text(text)
                .font(.system(size: 12.8))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        case let .bullet(text):
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: iconName(for: sectionTitle))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18, alignment: .center)
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .image(image):
            if let nsImage = releaseNoteImage(image) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                    .accessibilityLabel(image.alt)
                    .padding(.leading, 27)
            }
        }
    }

    private func releaseNoteImage(_ image: ReleaseNoteImage) -> NSImage? {
        var path = image.path
        if let resourcesRange = path.range(of: "Resources/") {
            path = String(path[resourcesRange.lowerBound...])
        }
        if path.hasPrefix("Resources/") {
            path.removeFirst("Resources/".count)
        }
        let nsPath = path as NSString
        let ext = nsPath.pathExtension
        let name = (nsPath.deletingPathExtension as NSString).lastPathComponent
        let directory = nsPath.deletingLastPathComponent
        guard !name.isEmpty, !ext.isEmpty else { return nil }
        let subdirectory = directory.isEmpty || directory == "." ? nil : directory
        guard let url = Bundle.main.url(forResource: name,
                                        withExtension: ext,
                                        subdirectory: subdirectory) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func iconName(for title: String) -> String {
        switch title.lowercased() {
        case "added": return "plus.circle.fill"
        case "changed": return "slider.horizontal.3"
        case "fixed": return "checkmark.circle.fill"
        default: return "circle.fill"
        }
    }
}

// MARK: - Support

struct SupportSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    private var donateThanksText: String {
        let thanks = l10n.s.donateThanks
        return colorScheme == .dark
            ? thanks.replacingOccurrences(of: "🖤", with: "🤍")
            : thanks
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Theme.spaceGradient)
                        .frame(width: 78, height: 78)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 29, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 7) {
                    Text(l10n.s.donateHeading)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(l10n.s.donateMessage)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460)
                }

                Button {
                    openURL(AppInfo.coffeeURL)
                } label: {
                    Label(l10n.s.donateButton, systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.yellow)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.yellow.opacity(0.14)))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(l10n.s.supportIntroStarMessage)
                            .font(.system(size: 13.5, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            openURL(AppInfo.repositoryURL)
                        } label: {
                            Label(l10n.s.supportIntroStarButton, systemImage: "star.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .frame(maxWidth: 510)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45))
                )

                Text(donateThanksText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
        }
    }
}

// MARK: - Shared settings rows

private struct SettingsCaptionText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Shared permission row

enum PermissionKind {
    case accessibility
    case screenRecording
    case microphone
}

/// Status + actions for one TCC permission; shared by Settings and onboarding.
struct PermissionRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var pollingDemandID = UUID()
    let kind: PermissionKind

    private var granted: Bool {
        switch kind {
        case .accessibility: return permissions.accessibility
        case .screenRecording: return permissions.screenRecording
        case .microphone: return permissions.microphone == .granted
        }
    }

    private var monitorsActivePermission: Bool {
        switch kind {
        case .accessibility, .screenRecording: return true
        case .microphone: return false
        }
    }

    private var name: String {
        switch kind {
        case .accessibility: return l10n.s.permissionAccessibility
        case .screenRecording: return l10n.s.permissionScreenRecording
        case .microphone:
            return FeatureStrings.recorder(l10n.language).microphonePermissionName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                Text(name)
                Spacer()
                Text(granted ? l10n.s.permissionGranted : l10n.s.permissionMissing)
                    .font(.caption)
                    .foregroundStyle(granted ? .green : .orange)
            }
            if !granted {
                HStack(spacing: 8) {
                    Button(l10n.s.permissionRequest) {
                        switch kind {
                        case .accessibility:
                            permissions.requestAccessibility()
                        case .screenRecording:
                            permissions.requestScreenRecording()
                        case .microphone:
                            permissions.requestMicrophone()
                        }
                    }
                    Button(l10n.s.permissionOpenSettings) {
                        switch kind {
                        case .accessibility:
                            permissions.openAccessibilitySettings()
                        case .screenRecording:
                            permissions.openScreenRecordingSettings()
                        case .microphone:
                            permissions.openMicrophoneSettings()
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .onAppear {
            if monitorsActivePermission {
                permissions.setActivePermissionSurface(pollingDemandID, visible: true)
            }
        }
        .onDisappear {
            permissions.setActivePermissionSurface(pollingDemandID, visible: false)
        }
    }
}

/// Secure Event Input blocks every synthetic keystroke. Typing a snippet
/// trigger then does nothing at all, while the snippet library and the
/// Command Bar's typing actions beep; none of the four paths says what is
/// wrong or who is holding it. It also hides every key from the switcher's
/// tap, so the switcher hands ⌘Tab back to macOS for as long as it lasts and
/// the macOS switcher shows up instead. This row is the only place the app
/// explains either. macOS never names the holder, only the app that was
/// active when it turned on, so the row offers that app as a lead rather than
/// as the holder.
///
/// Every call site instantiates it only once secure input is on, and the
/// snippets and switcher pages wait for their own toggles as well, so the
/// `.off` branch below is there to keep the switch exhaustive and for nothing
/// else. What drives the feature is the polling demand on each page; see
/// `SecureInputObservation`.
struct SecureInputRow: View {
    /// What secure input blocks on the page showing the row, which is what
    /// its caption has to explain.
    enum Blocked {
        /// Snippets and the Command Bar's typing actions.
        case typing
        /// The switcher's shortcuts, which macOS's own switcher then answers.
        case switcher
    }

    var blocking: Blocked = .typing
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SecureInputMonitor.shared

    var body: some View {
        let switcher = blocking == .switcher
        switch monitor.holder {
        case .off:
            EmptyView()
        case .app(let name, _):
            row(caption: String(format: switcher ? l10n.s.secureInputSwitcherHeldFormat
                                                 : l10n.s.secureInputHeldFormat, name)) {
                Button(String(format: l10n.s.secureInputRevealFormat, name)) {
                    monitor.revealHolder()
                }
                .controlSize(.small)
            }
        case .unattributed:
            row(caption: switcher ? l10n.s.secureInputSwitcherUnattributed
                                  : l10n.s.secureInputUnattributed) { EmptyView() }
        case .unknown:
            row(caption: switcher ? l10n.s.secureInputSwitcherUnidentified
                                  : l10n.s.secureInputUnidentified) { EmptyView() }
        }
    }

    private func row<Action: View>(caption: String,
                                   @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text(l10n.s.secureInputTitle)
                Spacer()
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
    }
}

/// Keeps secure input polled for as long as the page is on screen and
/// `isActive` holds, e.g. the snippets page only while one of its own
/// toggles is on, since with both off nothing this row could report can
/// show. The demand cannot live on `SecureInputRow`: nothing would
/// register it until the state it reports had already been reached.
private struct SecureInputObservation: ViewModifier {
    let isActive: Bool
    @State private var demandID = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { SecureInputMonitor.shared.setObservingSurface(demandID, visible: isActive) }
            .onDisappear { SecureInputMonitor.shared.setObservingSurface(demandID, visible: false) }
            .onChange(of: isActive) { _, active in
                SecureInputMonitor.shared.setObservingSurface(demandID, visible: active)
            }
    }
}

extension View {
    func observesSecureInput(isActive: Bool = true) -> some View {
        modifier(SecureInputObservation(isActive: isActive))
    }
}

/// Search field for the macOS 26 sidebar, styled after the system pill.
/// It sits on a fixed header outside the List, so scrolling rows can never
/// cross it (issues #183, #254). Esc and the clear button empty the query,
/// matching the system field.
private struct SidebarSearchField: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(l10n.s.settingsSearchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.s.urlCleanerClearButton)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private extension View {
    func searchResultRowStyle(isSelected: Bool) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
            }
    }
}
