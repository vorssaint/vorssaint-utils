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
    @AppStorage(DefaultsKey.superKeySource) private var superKeySourceRaw =
        SuperKeySource.capsLock.rawValue
    @State private var searchQuery = ""
    @State private var activeSearchIndex: Int?
    @State private var directoryCache = SettingsDirectoryCache()
    @State private var navigationFromSidebar = false
    /// The row just picked in the sidebar, until the router has taken it.
    @State private var sidebarPick: SettingsSidebarItem.ID?
    @State private var searchPresented = false
    @State private var sidebarWidth = SettingsShellLayout.storedSidebarWidth()

    private struct SearchResultsSnapshot: Equatable {
        let query: String
        let hits: [SettingsSearchHit]

        var isBlank: Bool {
            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var ids: [SettingsSearchSuggestion.ID] { hits.map(\.id) }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.query == rhs.query && lhs.ids == rhs.ids
        }
    }

    private var sidebarSections: [SettingsSidebarSection] {
        directoryCache.navigation(
            strings: l10n.s, language: l10n.language,
            superKeySource: SuperKeySource.sanitized(superKeySourceRaw),
            featureRevision: features.revision,
            isAvailable: { features.isAvailable($0) })
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
            guard hasSearchQuery else { return SearchResultsSnapshot(query: searchQuery, hits: []) }
            let groups = SettingsSearchSupport.groupedMatchingItems(
                query: searchQuery,
                items: searchCatalogItems,
                isAvailable: { features.isAvailable($0) })
            return SearchResultsSnapshot(
                query: searchQuery,
                hits: SettingsSearchSupport.flatHits(
                    query: searchQuery, groups: groups,
                    categoryTitle: categoryTitle(for:)))
        }()

        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebarList(searchResults: searchResults)
                .navigationSplitViewColumnWidth(
                    min: SettingsShellLayout.sidebarMinWidth,
                    ideal: sidebarWidth,
                    max: SettingsShellLayout.sidebarMaxWidth)
                .background(SettingsSidebarWidthRestorer(width: sidebarWidth))
        } detail: {
            // Lists must receive a viewport, not propose their full row height
            // as the window's ideal size when a destination changes.
            GeometryReader { geometry in
                detail
                    .settingsSectionFocus(for: router.page)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            .frame(minWidth: SettingsShellLayout.minDetailWidth)
            .navigationTitle(pageTitle)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    let strings = SettingsNavigationStrings.localized(l10n.language)
                    Button(strings.back, systemImage: "chevron.backward") {
                        router.goBack(isPageVisible: isPageVisible)
                    }
                    .disabled(!router.canGoBack(isPageVisible: isPageVisible))
                    .help(strings.back)
                    Button(strings.forward, systemImage: "chevron.forward") {
                        router.goForward(isPageVisible: isPageVisible)
                    }
                    .disabled(!router.canGoForward(isPageVisible: isPageVisible))
                    .help(strings.forward)
                }
            }
        }
        .toolbar(removing: .sidebarToggle)
        .searchable(text: $searchQuery, isPresented: $searchPresented,
                    placement: .sidebar, prompt: l10n.s.settingsSearchPlaceholder)
        .searchSuggestions {
            if !hasSearchQuery {
                let strings = SettingsShellStrings.localized(l10n.language)
                Section(strings.suggestions) {
                    ForEach(suggestedDestinations) { entry in
                        searchSuggestion(entry)
                    }
                }
                if !recentDestinations.isEmpty {
                    Section(strings.recents) {
                        ForEach(recentDestinations) { entry in
                            searchSuggestion(entry)
                        }
                    }
                }
            }
        }
        .background(SettingsWindowTitle(title: pageTitle))
        .frame(minWidth: SettingsWindowSupport.minContentWidth, maxWidth: .infinity,
               minHeight: SettingsWindowSupport.minContentHeight, maxHeight: .infinity)
        .onAppear {
            ensureVisiblePage()
        }
        .onChange(of: features.revision) { _, _ in ensureVisiblePage() }
        .onChange(of: searchResults, initial: true) { previous, current in
            updateSearchSelection(previous: previous, current: current)
        }
        .onChange(of: router.requestID) { _, _ in
            searchQuery = ""
            activeSearchIndex = nil
            searchPresented = false
            ensureVisiblePage()
        }
    }

    private var pageTitle: String {
        sidebarItems.first(where: { $0.id == selectedSidebarItem })?.title
            ?? l10n.s.settingsTitle
    }

    private var searchCatalogItems: [SettingsSearchItem] {
        directoryCache.search(strings: l10n.s, language: l10n.language,
                              superKeySource: SuperKeySource.sanitized(superKeySourceRaw),
                              featureRevision: features.revision)
    }

    private var suggestedDestinations: [SettingsSearchSuggestions.Entry] {
        SettingsSearchSuggestions.suggestions(items: searchCatalogItems,
                                              isAvailable: { features.isAvailable($0) })
    }

    private var recentDestinations: [SettingsSearchSuggestions.Entry] {
        SettingsSearchSuggestions.recents(items: searchCatalogItems,
                                         isAvailable: { features.isAvailable($0) })
    }

    private func searchSuggestion(_ entry: SettingsSearchSuggestions.Entry) -> some View {
        Button {
            requestSearchSuggestion(entry)
        } label: {
            Label(entry.title, systemImage: entry.icon)
        }
    }

    private var hasSearchQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func categoryTitle(for page: SettingsPage) -> String? {
        sidebarSections.first { section in
            section.items.contains { $0.destination.page == page }
        }?.title
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
            .scrollContentBackground(.hidden)
            .onChange(of: sidebarPick) { _, selectedID in routeSidebarPick(selectedID) }
            .onChange(of: activeSearchIndex) { _, index in
                guard let index, searchResults.hits.indices.contains(index) else { return }
                let id = searchResults.hits[index].id
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
                DispatchQueue.main.async { scrollSidebarToSelection(proxy) }
            }
            .onChange(of: router.requestID) { _, _ in
                // A click in the sidebar is already visible. Only external
                // routes need to reveal and scroll to their destination.
                let fromSidebar = navigationFromSidebar
                navigationFromSidebar = false
                guard !fromSidebar else { return }
                DispatchQueue.main.async { scrollSidebarToSelection(proxy) }
            }
            .background {
                SearchKeyMonitor { keyCode, window in
                    handleSearchKey(keyCode, in: window, searchResults: searchResults.hits)
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

    private func scrollSidebarToSelection(_ proxy: ScrollViewProxy) {
        guard !hasSearchQuery, let selected = selectedSidebarItem else { return }
        proxy.scrollTo(selected, anchor: .center)
    }

    @ViewBuilder
    private var normalSidebarRows: some View {
        let sections = sidebarSections
        let items = directoryCache.items
        let selectedID = SettingsSidebarSupport.selection(for: router.destination, in: items,
                                                          preferredID: router.sidebarFeature.map { .feature($0) })
        ForEach(sections) { section in
            Section {
                ForEach(section.items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: item.icon)
                            .foregroundStyle(selectedID == item.id
                                ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                            .frame(width: 18)
                        Text(item.title)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tag(item.id)
                    .id(item.id)
                    .help(item.title)
                }
            } header: {
                Text(section.title)
            }
        }
    }

    @ViewBuilder
    private func searchResultRows(_ searchResults: SearchResultsSnapshot) -> some View {
        ForEach(searchResults.hits) { hit in
            searchResultRow(hit, searchResults: searchResults)
        }
    }

    private func searchResultRow(_ hit: SettingsSearchHit,
                                 searchResults: SearchResultsSnapshot) -> some View {
        let selectionIndex = searchResults.hits.firstIndex { $0.id == hit.id }
        let isSelected = selectionIndex == activeSearchIndex
        return Button {
            requestSearchItem(hit.suggestion)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: hit.icon)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.title)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = hit.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .opacity(0.8)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .settingsSearchRowStyle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(hit.id)
    }

    private func handleSearchKey(_ keyCode: UInt16, in window: NSWindow,
                                  searchResults: [SettingsSearchHit]) -> Bool {
        // Native suggestions own their selection and keyboard interaction.
        // Only typed results in our sidebar need a custom selection driver.
        guard hasSearchQuery || keyCode == 53 else { return false }
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
            requestSearchItem(searchResults[index].suggestion)
            return true
        case 53: // Escape
            return escapeSearch(in: window)
        default:
            return false
        }
    }

    /// Clear the query before dismissing search on a second Escape.
    private func escapeSearch(in window: NSWindow) -> Bool {
        if hasSearchQuery {
            searchQuery = ""
            activeSearchIndex = nil
            return true
        }
        searchPresented = false
        window.makeFirstResponder(nil)
        return true
    }

    private func updateSearchSelection(previous: SearchResultsSnapshot,
                                       current: SearchResultsSnapshot) {
        guard !current.isBlank, !current.hits.isEmpty else {
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

    /// Intercepts typed-result navigation before the native field editor handles it.
    private struct SearchKeyMonitor: NSViewRepresentable {
        var handleKey: (UInt16, NSWindow) -> Bool

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.install(for: view)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            context.coordinator.handleKey = handleKey
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(handleKey: handleKey)
        }

        static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
            coordinator.removeMonitor()
        }

        final class Coordinator: NSObject {
            var handleKey: (UInt16, NSWindow) -> Bool
            private var monitor: Any?

            init(handleKey: @escaping (UInt16, NSWindow) -> Bool) {
                self.handleKey = handleKey
            }

            func install(for view: NSView) {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                    [weak self, weak view] event in
                    guard let self, let view, let window = view.window,
                          event.window === window,
                          Self.isSearchKey(event),
                          let editor = window.firstResponder as? NSTextView,
                          editor.isFieldEditor,
                          Self.isSidebarSearchEditor(editor, near: view),
                          // An input method composing text owns its own keys.
                          !editor.hasMarkedText() else { return event }
                    return handleKey(event.keyCode, window) ? nil : event
                }
            }

            func removeMonitor() {
                guard let monitor else { return }
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }

            private static func isSearchKey(_ event: NSEvent) -> Bool {
                let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
                guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return false }
                return [UInt16(126), 125, 36, 76, 53].contains(event.keyCode)
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

    private func requestSearchSuggestion(_ entry: SettingsSearchSuggestions.Entry) {
        switch entry.kind {
        case .suggestion(let suggestion):
            requestSearchItem(suggestion)
        case .recent(let recent):
            openSearchDestination(destination: recent.destination,
                                  targetFeature: recent.targetFeature,
                                  sidebarFeature: recent.sidebarFeature)
        }
    }

    private func requestSearchItem(_ suggestion: SettingsSearchSuggestion) {
        let routed = SettingsSearchSupport.route(for: suggestion)
        openSearchDestination(destination: routed.destination,
                              targetFeature: routed.targetFeature,
                              sidebarFeature: suggestion.item.feature)
    }

    private func openSearchDestination(destination: FeatureSettingsDestination,
                                       targetFeature: AppFeature?,
                                       sidebarFeature: AppFeature?) {
        activeSearchIndex = nil
        searchQuery = ""
        searchPresented = false
        SettingsSearchHistory.record(destination: destination, targetFeature: targetFeature,
                                     sidebarFeature: sidebarFeature)
        router.request(destination, targetFeature: targetFeature, sidebarFeature: sidebarFeature)
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
        case .radialMenu: RadialMenuSettings()
        case .commandBar: CommandBarSettings()
        case .energy: EnergySettings(focus: router.destination.sectionAnchor)
        case .monitor: MonitorSettings()
        case .mouse: MouseSettings()
        case .switcher: SwitcherSettings()
        case .dock: DockSettings()
        case .keyDebounce: KeyboardDebounceSettings()
        case .superKey: SuperKeySettings()
        case .cutPaste: CutPasteSettings()
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
        case .clipboard: ClipboardSettings()
        case .quickTools: QuickToolsSettings()
        case .screenshot: ScreenCaptureSettings()
        case .windowLayout: WindowLayoutSettings()
        case .shelf: ShelfSettings()
        case .shortcuts: ShortcutsSettings()
        case .advanced: AdvancedSettings()
        case .about: AboutSettings()
        case .releaseNotes: ReleaseNotesSettings()
        case .support: SupportSettings()
        }
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
        .settingsFormFrame()
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
            Text(l10n.s.aboutDescription)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
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
            SettingsPageDescription(text: versionLine)
                .padding(.horizontal, SettingsPageLayout.margin)
                .padding(.top, SettingsPageLayout.margin)

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
                .padding(.horizontal, SettingsPageLayout.margin)
                .padding(.bottom, SettingsPageLayout.margin)
            }
        }
        .settingsPageWidth()
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
