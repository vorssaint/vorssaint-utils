// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The command bar: one floating field, summoned by a global shortcut, that
/// finds and runs everything the app can do. The panel never activates, so
/// the app the person was using keeps focus the whole time; actions that type
/// or paste land exactly where the caret already is. Closed, it keeps one
/// prepared panel, with no polling or observers.
final class CommandBarService: ObservableObject {
    static let shared = CommandBarService()

    /// What the field is asking for right now. Argument mode asks for the
    /// number of a command like "brilho"; confirm guards a destructive one.
    enum Mode: Equatable {
        case search
        case argument(entryID: String)
        case confirm(entryID: String)
        /// The list of things that can be done to one row: pin it, name it,
        /// hide it, forget it. Everything the person controls lives here, one
        /// key away from whatever they were looking at.
        case actions(entryID: String)
        case naming(entryID: String)
        /// Waiting for the person to press the combination they want for one
        /// row. Every other key is theirs while this lasts.
        case capturingShortcut(entryID: String)
    }

    /// One line in the actions list.
    struct RowAction: Identifiable {
        let id: String
        let title: String
        let symbolName: String
        let isDestructive: Bool
        let run: () -> Void

        init(id: String,
             title: String,
             symbolName: String,
             isDestructive: Bool = false,
             run: @escaping () -> Void) {
            self.id = id
            self.title = title
            self.symbolName = symbolName
            self.isDestructive = isDestructive
            self.run = run
        }
    }

    @Published var query = "" {
        didSet { if query != oldValue { refreshResults() } }
    }
    @Published private(set) var rows: [CommandBarEntry] = []
    @Published private(set) var isShowingSuggestions = false
    /// The heading that belongs above a row, by its position. What was pinned
    /// deserves to be seen as pinned, and what is selected deserves to be seen
    /// as the thing being acted on, instead of both being mixed into a list of
    /// guesses.
    @Published private(set) var sectionTitles: [Int: String] = [:]
    /// One line of whatever is selected, for the heading to show what the rows
    /// above the list are about to act on.
    @Published private(set) var selectionPreview = ""
    @Published private(set) var selectedIndex = 0
    @Published private(set) var mode: Mode = .search
    @Published private(set) var presentationID = UUID()
    @Published private(set) var shortcutRegistrationFailed = false
    /// Rows whose own combination the system refused, because another app got
    /// there first. Shown in Settings so the key is not a mystery.
    @Published private(set) var refusedRowShortcutKeys: Set<String> = []
    /// The one kind of result the list is narrowed to, or nil for everything.
    /// This is the drill-in the launchers people know: one tap on Apps and the
    /// bar becomes a list of every app, still searchable, still one Esc from
    /// home.
    @Published private(set) var activeCategory: CommandBarSource?
    /// The categories worth offering right now, in a fixed order, only the
    /// ones with something in them.
    @Published private(set) var categoryChips: [CommandBarSource] = []

    /// True while Command is held down. The bar can already run the first nine
    /// rows with ⌘1…⌘9, but nothing ever said so; holding the key now shows the
    /// numbers, which teaches it without a single pixel of permanent clutter.
    @Published private(set) var commandIsHeld = false

    /// True when the bar was dragged off the spot it opens on by default,
    /// so Settings can offer the way back.
    @Published private(set) var hasCustomPosition = false

    private let hotkey = QuickToolHotkey(id: 20)
    private var rowHotkeys: [QuickToolHotkey] = []
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var flagsMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    private var catalog: [CommandBarEntry] = []
    let scriptRunner = CommandBarScriptRunner()
    let fileSearch = CommandBarFileSearch()
    /// Which row answered which few letters, for as long as the app runs. Not
    /// stored: the bar forgets everything typed into it when it goes.
    private var queryMemory = CommandBarQueryMemory()
    /// Counts choices, so the memory can order its own entries without a clock.
    private var queryMemoryStep = 0
    private var entriesByID: [String: CommandBarEntry] = [:]
    private var normalizedByID: [String: (title: String, keywords: String)] = [:]
    private var entriesByStableKey: [String: CommandBarEntry] = [:]
    private var presentationLifecycle = CommandBarPresentationLifecycle()
    private var deferredRowShortcut = CommandBarDeferredRowShortcut()
    private var appEntries: [CommandBarEntry] = []
    private var windowEntries: [CommandBarEntry] = []
    private var quitEntries: [CommandBarEntry] = []
    /// The raw scan is what gets cached; the rows are rebuilt on every open so
    /// the live dot and the running apps are never a stale picture.
    private var cachedApps: [InstalledApps.InstalledApp] = []
    private var appsLoading = false
    private var windowsLoading = false
    private var windowsLoadedAt: Date?
    private var menuEntries: [CommandBarEntry] = []
    private var emojiEntries: [CommandBarEntry] = []
    /// The Mac's own Settings panes, scanned once per launch. The language
    /// they were built in comes with them, because the words they answer to
    /// are translated and a change of language has to reread them.
    private var macSettingsEntries: [CommandBarEntry] = []
    private var macSettingsLanguage: AppLanguage?
    private var macSettingsLoading = false
    /// Rows that act on what was selected when the bar opened. Read once per
    /// opening and thrown away on close: a selection is a moment, not a state.
    private var selectionEntries: [CommandBarEntry] = []
    private var selectionLoading = false
    /// One row per running process. Read once per opening through
    /// `KillProcessService`'s own cache, same lifetime as `selectionEntries`.
    private var killProcessEntries: [CommandBarEntry] = []
    private var killProcessEntriesLoading = false
    /// True while the bar is closing, so nothing is rebuilt on the way out.
    private var isTearingDown = false
    private var menusLoading = false
    private var menusLoadedAt: Date?
    private var menuOwnerPID: pid_t?
    /// The language the rows were built in, so a change of language while the
    /// bar is open rebuilds them instead of mixing two languages in one list.
    private var builtLanguage: AppLanguage?
    /// Cached off the main thread on show(): the Apple Event status check
    /// blocks, and the Trash row wants to be honest about a denied consent.
    private var finderAutomationDenied = false
    /// The query to restore when Esc leaves argument or confirm mode.
    private var savedQuery = ""
    /// The last thing typed, kept only in memory so reopening can offer it.
    private var lastQuery = ""
    /// Where the pointer sat when the bar opened. A row under a pointer that
    /// has not moved must not steal the selection from the keyboard.
    private var lastPointerLocation = NSPoint.zero
    private var panelScreen: NSRect?
    /// The selected row's id, so a rebuilt list keeps the selection on the
    /// same command instead of on the same position.
    private var selectedID: String?
    /// What the ranking last ran on, to tell a keystroke apart from a list
    /// rebuilt underneath by a background load.
    private var lastRankedQuery: String?
    /// The system only shows its Accessibility prompt once; after that a
    /// refusal is a beep, the pattern the other quick tools follow.
    private var promptedForAccessibility = false
    private var restartObserver: NSObjectProtocol?
    private var restartPID: pid_t?
    private var restartURL: URL?

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
        scriptRunner.onResult = { [weak self] in self?.refreshResults() }
        fileSearch.onResult = { [weak self] in self?.refreshResults() }
    }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        let available = AppFeature.commandBar.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.commandBarShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.commandBarShortcut,
                                            fallback: .commandBarDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
        reloadPreferenceCaches()
        syncRowHotkeys()
        if available {
            // Build the one view tree after launch, outside the keystroke that
            // asks to see it for the first time.
            DispatchQueue.main.async { [weak self] in
                guard AppFeature.commandBar.isAvailable, let self else { return }
                _ = self.ensurePanel()
            }
        }
        if !available {
            hide()
            panel = nil
            // Uninstalled means uninstalled: the catalog, the app scan and the
            // window list all go, not just the window.
            catalog = []
            appEntries = []
            windowEntries = []
            quitEntries = []
            menuEntries = []
            emojiEntries = []
            macSettingsEntries = []
            macSettingsLanguage = nil
            CommandBarSystemSettings.clearCache()
            presentationLifecycle.hide()
            menuOwnerPID = nil
            menusLoadedAt = nil
            entriesByID = [:]
            normalizedByID = [:]
            entriesByStableKey = [:]
            cachedApps = []
            windowsLoadedAt = nil
            rows = []
            cancelPendingRestart()
        }
    }

    func suspend() {
        hotkey.unregister()
        for hotkey in rowHotkeys { hotkey.unregister() }
        rowHotkeys = []
        hide()
        cancelPendingRestart()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        show(promptingFor: nil)
    }

    private func show(promptingFor stableKey: String?) {
        guard AppFeature.commandBar.isAvailable else { return }
        let panel = ensurePanel()
        if AppFeature.textSnippets.isAvailable {
            TextSnippetService.shared.setCommandBarVisible(true)
        }
        let id = beginPresentation()
        if let stableKey { deferredRowShortcut.schedule(stableKey, for: id) }
        reloadPreferenceCaches()
        query = ""
        refreshResults()
        present(panel)
        // Ordering the prepared panel is the keystroke path. Home is filled on
        // the next main-loop turn, when a close or newer opening can supersede it.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.presentationLifecycle.completeHomeHydration(
                    id, isVisible: self.isVisible) else { return }
            self.prepareHomeForCurrentPresentation()
            self.refreshResults()
            self.runDeferredRowShortcutIfReady(for: id)
        }
    }

    @discardableResult
    private func beginPresentation() -> UUID {
        deferredRowShortcut.cancel()
        scriptRunner.reset()
        fileSearch.reset()
        let id = UUID()
        presentationID = id
        presentationLifecycle.beginHome(id)
        clearIndex()
        rows = []
        sectionTitles = [:]
        mode = .search
        savedQuery = ""
        queryWhenRun = ""
        selectionWhenRun = ""
        lastPointerLocation = NSEvent.mouseLocation
        selectedID = nil
        lastRankedQuery = nil
        activeCategory = nil
        return id
    }

    private func prepareHomeForCurrentPresentation() {
        reloadPreferenceCaches()
        // Windows, menus and selection belong to the presentation that read
        // them. Home starts without those runnable rows and lets guarded scans
        // add fresh ones after the panel is already visible.
        windowEntries = []
        windowsLoadedAt = nil
        menuEntries = []
        menuOwnerPID = nil
        menusLoadedAt = nil
        selectionEntries = []
        selectionPreview = ""
        selectedText = ""
        killProcessEntries = []
        rebuildCatalog(index: false)
        rebuildRunningEntries()
        startBackgroundLoads(for: presentationID)
    }

    private func startBackgroundLoads(for id: UUID) {
        refreshAutomationStatus(for: id)
        refreshStorageAnswer(for: id)
        refreshWiFiState(for: id)
        loadAppsIfNeeded(for: id)
        loadMacSettingsIfNeeded(for: id)
        loadWindowsIfNeeded(for: id)
        loadMenusIfNeeded(for: id)
        loadSelection(for: id)
        loadKillProcessEntries(for: id)
    }

    private func present(_ panel: NSPanel) {
        position(panel)
        installMonitors(for: panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        if AppFeature.textSnippets.isAvailable {
            TextSnippetService.shared.setCommandBarVisible(false)
        }
        deferredRowShortcut.cancel()
        scriptRunner.reset()
        fileSearch.reset()
        // Closing while listening for a combination must give every global key
        // back, or the whole app would go quiet until the next relaunch.
        if case .capturingShortcut = mode { endCapturingShortcut() }
        // Clearing the field on the way out would otherwise rebuild the whole
        // browse list for a panel nobody can see.
        isTearingDown = true
        defer {
            isTearingDown = false
            rows = []
            sectionTitles = [:]
        }
        removeMonitors()
        panel?.orderOut(nil)
        mode = .search
        // A selection belongs to the moment the bar was opened. Keeping it
        // would offer to act on text the person may have replaced since.
        if !selectionEntries.isEmpty {
            selectionEntries = []
            selectionPreview = ""
            selectedText = ""
            indexEntries()
        }
        if !killProcessEntries.isEmpty {
            killProcessEntries = []
            indexEntries()
        }
        // What was typed is remembered for the next opening, where the first
        // keystroke replaces it. It never reaches disk: the promise is that
        // nothing typed here is saved, and memory is not saving.
        lastQuery = query
        query = ""
        presentationLifecycle.hide()
        clearIndex()
    }

    /// Re-fits the panel to its content as the result list grows and
    /// shrinks, keeping the top edge and horizontal center still so the
    /// field itself never jumps under the caret.
    func refreshPanelLayout() {
        guard let panel, panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
            let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
            let screen = self.panelScreen ?? NSScreen.pointerVisibleFrame
            var frame = panel.frame
            frame.origin.x = frame.midX - size.width / 2
            frame.origin.y = frame.maxY - size.height
            frame.size = size
            // Growing downward must stop at the screen edge; the list scrolls
            // instead of hiding its own footer below the bezel.
            frame.origin.y = max(frame.origin.y, screen.minY + 16)
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: - Results

    /// The number typed after the verb ("brilho 40"), read from the field at
    /// the moment it is used. Never stored: a value cached during a search
    /// pass outlives the text it came from.
    private var typedNumber: Int? {
        CommandBarSearch.splitTrailingNumber(query.trimmingCharacters(in: .whitespaces)).number
    }

    // MARK: - What the person decided

    private var disabledSourcesRaw: String {
        UserDefaults.standard.string(forKey: DefaultsKey.commandBarDisabledSources) ?? ""
    }

    private var aliases: [String: String] {
        CommandBarPreferences.decodeAliases(
            UserDefaults.standard.string(forKey: DefaultsKey.commandBarAliases))
    }

    private var pins: [String] {
        CommandBarPreferences.decodePins(
            UserDefaults.standard.string(forKey: DefaultsKey.commandBarPins) ?? "")
    }

    var rowShortcuts: [String: GlobalShortcut] {
        CommandBarRowShortcuts.decode(
            UserDefaults.standard.string(forKey: DefaultsKey.commandBarRowShortcuts))
    }

    func rowShortcut(for entry: CommandBarEntry) -> GlobalShortcut? {
        shortcutCache[entry.stableKey]
    }

    /// Binds (or with nil clears) one row's own combination and registers it
    /// straight away, so the key works before the bar is even closed.
    func setRowShortcut(_ shortcut: GlobalShortcut?, for entry: CommandBarEntry) {
        let next = CommandBarRowShortcuts.setting(shortcut, for: entry.stableKey, in: rowShortcuts)
        UserDefaults.standard.set(CommandBarRowShortcuts.encode(next),
                                  forKey: DefaultsKey.commandBarRowShortcuts)
        syncRowHotkeys()
        refreshAfterPreferenceChange()
    }

    /// One Carbon key per binding, and not one more. Ids start well past the
    /// quick tools so the two can never collide.
    private func syncRowHotkeys() {
        let wanted = AppFeature.commandBar.isAvailable ? rowShortcuts : [:]
        for hotkey in rowHotkeys { hotkey.unregister() }
        rowHotkeys = []
        var index: UInt32 = 0
        var refused: Set<String> = []
        for (key, shortcut) in wanted.sorted(by: { $0.key < $1.key })
        where CommandBarRowShortcuts.isUsable(shortcut) {
            let hotkey = QuickToolHotkey(id: 200 + index)
            hotkey.onPress = { [weak self] in self?.runRow(withStableKey: key) }
            // A combination another app already holds is refused by the system.
            // Saying so beats a row that shows a key it will never answer to.
            if !hotkey.sync(enabled: true, shortcut: shortcut) { refused.insert(key) }
            rowHotkeys.append(hotkey)
            index += 1
        }
        if refused != refusedRowShortcutKeys { refusedRowShortcutKeys = refused }
    }

    /// Runs a row from its own combination, with no bar involved. Runnable
    /// closures are rebuilt from current state before the shortcut uses them.
    private func runRow(withStableKey key: String) {
        guard let entry = freshFullEntry(forStableKey: key) else {
            if CommandBarPreferences.source(ofRowID: key) == .macSettings {
                show(promptingFor: key)
                return
            }
            NSSound.beep()
            return
        }
        // A row that would confirm, ask for input, or keep the field visible
        // needs a real presentation just as it does when chosen from the bar.
        // Emptying the Trash on one keypress with nothing asked is not a
        // shortcut, it is an accident with a name.
        guard !entry.needsPrompt, !entry.keepsBarOpen else {
            show(promptingFor: key)
            return
        }
        if isVisible { hide() }
        finish(entry, value: nil)
    }

    private var hiddenKeys: Set<String> {
        CommandBarPreferences.decodeHidden(
            UserDefaults.standard.string(forKey: DefaultsKey.commandBarHidden) ?? "")
    }

    /// What was in the field, and what was selected, at the instant a row ran.
    /// Closing the bar wipes both before the row's own closure gets to work,
    /// so they are handed over here instead of being read back from a panel
    /// that is already gone.
    private(set) var queryWhenRun = ""
    private(set) var selectionWhenRun = ""

    /// The text the person had selected when the bar opened, for the rows and
    /// the saved destinations that act on it.
    private(set) var selectedText = ""

    /// Puts text in the field and leaves the bar open, so the person can finish
    /// typing what a saved search needs.
    func prefill(_ text: String) {
        if !isVisible { show() }
        query = text
    }

    /// The chip order. Fixed, so the row never reshuffles under a pointer.
    private static let chipOrder: [CommandBarSource] = [
        .actions, .apps, .clipboard, .windows, .menus, .settingsPages, .macSettings,
        .snippets, .emoji, .folders, .links,
    ]

    /// Walks the chips with the arrow keys. Only while the field is empty:
    /// with text in it the same keys belong to the caret, and taking them
    /// would make the field unusable for editing what was typed.
    ///
    /// Returns whether it handled the key, so the caller can pass it on.
    @discardableResult
    func moveCategory(_ delta: Int) -> Bool {
        guard case .search = mode,
              query.trimmingCharacters(in: .whitespaces).isEmpty,
              !categoryChips.isEmpty else { return false }
        // Home is the first stop, so the row of chips and the walk agree.
        var stops: [CommandBarSource?] = [nil]
        stops.append(contentsOf: categoryChips.map { Optional($0) })
        let current = stops.firstIndex(where: { $0 == activeCategory }) ?? 0
        let next = (current + delta % stops.count + stops.count) % stops.count
        setCategory(stops[next])
        return true
    }

    /// Back to the unfiltered bar: clears whatever was typed and leaves the
    /// category. What the no-results state offers, so an empty category is
    /// never a room without a door.
    func goHome() {
        if !query.isEmpty { query = "" }
        if activeCategory != nil { setCategory(nil) }
    }

    func setCategory(_ source: CommandBarSource?) {
        guard activeCategory != source else { return }
        activeCategory = source
        selectedID = nil
        lastRankedQuery = nil
        refreshResults()
    }
    /// Whether a category is worth a chip.
    ///
    /// The three that come from background loads are decided by whether they
    /// COULD have rows, not by whether the rows have arrived: asking the
    /// arrays would draw a short row of chips and then grow it a moment later,
    /// moving every chip under whoever was already reaching for one. The rest
    /// are built synchronously, so they answer with the same filter the
    /// content path applies, hidden rows included.
    private func categoryHasContent(_ source: CommandBarSource) -> Bool {
        let bar = FeatureStrings.commandBar(L10n.shared.language)
        switch source {
        case .apps, .macSettings:
            // Every Mac has applications and Settings panes; the scan only
            // decides when.
            return true
        case .windows:
            return (AppFeature.switcher.isAvailable || AppFeature.windowLayout.isAvailable)
                && Permissions.shared.accessibility
        case .menus:
            return Permissions.shared.accessibility
                && NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    != Bundle.main.bundleIdentifier
        case .clipboard:
            return !categoryContent(source, bar: bar, limit: 1).isEmpty
        case .emoji:
            let hidden = hiddenKeys
            return emojiEntries.contains { !hidden.contains($0.stableKey) }
        case .actions, .settingsPages, .snippets, .folders, .links:
            // Asked once per chip on every pass with an empty field, so it
            // stops at the first row that qualifies instead of building a copy
            // of the catalog five times over.
            let hidden = hiddenKeys
            return catalog.contains {
                CommandBarPreferences.source(ofRowID: $0.id) == source
                    && !hidden.contains($0.stableKey)
            }
        case .killProcess:
            return AppFeature.killProcess.isAvailable
        case .quitApps, .answers, .calculator, .selection, .files:
            return false
        }
    }

    /// Every row of one kind, the whole point of drilling in: no caps, no
    /// guesses, everything the bar knows of that kind.
    private func categoryContent(_ source: CommandBarSource,
                                 bar: CommandBarFeatureStrings,
                                 limit: Int = 60) -> [CommandBarEntry] {
        let hidden = hiddenKeys
        let rows: [CommandBarEntry]
        switch source {
        case .actions:
            rows = catalog.filter { CommandBarPreferences.source(ofRowID: $0.id) == .actions }
        case .apps: rows = appEntries
        case .macSettings: rows = macSettingsEntries
        case .windows: rows = windowEntries
        case .menus: rows = menuEntries
        case .emoji: rows = emojiEntries
        case .settingsPages, .snippets, .folders, .links:
            rows = catalog.filter { CommandBarPreferences.source(ofRowID: $0.id) == source }
        case .clipboard:
            rows = CommandBarCatalog.clipboardBrowseEntries(limit: limit, bar: bar) { [weak self] entry in
                self?.paste(entry)
            }
        case .killProcess: rows = killProcessEntries
        case .quitApps, .answers, .calculator, .selection, .files:
            rows = []
        }
        return rows.filter { !hidden.contains($0.stableKey) }
    }

    /// The heading a category shows above its rows, with how many there are.
    private func categoryHeading(_ source: CommandBarSource, count: Int) -> String {
        categoryTitle(source) + " · \(count)"
    }

    /// The localized name of a category. Mostly the words the Settings toggles
    /// use, so the two surfaces agree; the two that are written there as a
    /// sentence ("menu commands of the app in front") borrow the short name
    /// the rows themselves carry, because a chip is a label and not a
    /// description.
    func categoryTitle(_ source: CommandBarSource) -> String {
        let bar = FeatureStrings.commandBar(L10n.shared.language)
        switch source {
        case .actions: return bar.sourceActions
        case .apps: return bar.sourceApps
        case .menus: return bar.kindMenu
        case .windows: return bar.sourceWindows
        case .quitApps: return bar.sourceQuitApps
        case .settingsPages: return bar.sourceSettingsPages
        case .macSettings: return bar.sourceMacSettings
        case .snippets: return bar.sourceSnippets
        case .clipboard: return bar.sourceClipboard
        case .emoji: return bar.sourceEmoji
        case .folders: return bar.sourceFolders
        case .answers: return bar.sourceAnswers
        case .calculator: return bar.sourceCalculator
        case .selection: return bar.sourceSelection
        case .files: return bar.sourceFiles
        case .links: return bar.linksTitle
        case .killProcess: return FeatureStrings.killProcess(L10n.shared.language).pageTitle
        }
    }

    func isEnabled(_ source: CommandBarSource) -> Bool {
        CommandBarPreferences.isEnabled(source, disabledRaw: disabledSourcesRaw)
    }

    /// What the person pinned and what they bound, kept in memory. Both are
    /// asked once per row on every single render of the list, and reading them
    /// from disk there means parsing the same JSON ninety times for one frame.
    private var pinCache: Set<String> = []
    private var shortcutCache: [String: GlobalShortcut] = [:]
    /// The folders a file search looks in, already resolved, and the names it
    /// never shows. Resolving reads the home folder, which is far too much to
    /// do on a keystroke and never changes between two of them.
    private var fileScopeCache: [String] = []
    private var fileIgnoreCache: [String] = []
    private var fileSearchPreferenceSignature: String?
    private var fileScopeLoadGeneration = 0

    private func reloadPreferenceCaches() {
        pinCache = Set(pins)
        shortcutCache = rowShortcuts
        hasCustomPosition = positionOffset != .zero
        reloadFileSearchCaches()
    }

    private func reloadFileSearchCaches() {
        // A cached answer belongs to the scopes and ignores that produced it.
        // Changing either invalidates pending and completed searches together.
        let scopesRaw = UserDefaults.standard.string(forKey: DefaultsKey.commandBarFileScopes) ?? ""
        let ignoresRaw = UserDefaults.standard.string(forKey: DefaultsKey.commandBarFileIgnores) ?? ""
        let enabled = isEnabled(.files)
        let signature = "\(enabled)\0\(scopesRaw)\0\(ignoresRaw)"
        guard signature != fileSearchPreferenceSignature else { return }
        fileSearchPreferenceSignature = signature
        fileScopeLoadGeneration &+= 1
        let loadGeneration = fileScopeLoadGeneration
        fileSearch.reset()
        fileScopeCache = []
        fileIgnoreCache = enabled
            ? CommandBarFileSearchSupport.shippedIgnores
                + CommandBarFileSearchSupport.decodeList(ignoresRaw)
            : []
        let saved = CommandBarFileSearchSupport.decodeList(scopesRaw)
        guard enabled, !saved.isEmpty else { return }
        let home = NSHomeDirectory()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let children = (try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []
            let scopes = CommandBarFileSearchSupport.resolvedScopes(
                saved,
                homeDirectory: home,
                homeChildren: children,
                isSearchableDirectory: CommandBarFileSearch.isSearchableDirectory)
            DispatchQueue.main.async {
                guard let self, self.fileScopeLoadGeneration == loadGeneration else { return }
                self.fileScopeCache = scopes
                if self.isVisible { self.refreshResults() }
            }
        }
    }

    func isPinned(_ entry: CommandBarEntry) -> Bool {
        pinCache.contains(entry.stableKey)
    }

    /// The readable name of whatever a stored key points at, so the Settings
    /// lists never show a bare id. Builds the catalog once if this loading
    /// presentation has not prepared it yet.
    func entryTitle(forStableKey key: String) -> String? {
        if entriesByStableKey.isEmpty {
            rebuildCatalog()
            rebuildRunningEntries()
        }
        return entriesByStableKey[key]?.title
    }

    func alias(for entry: CommandBarEntry) -> String? {
        aliases[entry.stableKey]
    }

    /// Pinning, naming, hiding and forgetting all write through here so the
    /// list refreshes the instant the person changes their mind.
    func togglePin(_ entry: CommandBarEntry) {
        let next = CommandBarPreferences.togglingPin(entry.stableKey, in: pins)
        UserDefaults.standard.set(CommandBarPreferences.encodePins(next), forKey: DefaultsKey.commandBarPins)
        refreshAfterPreferenceChange()
    }

    func setAlias(_ alias: String, for entry: CommandBarEntry) {
        let next = CommandBarPreferences.settingAlias(alias, for: entry.stableKey, in: aliases)
        UserDefaults.standard.set(CommandBarPreferences.encodeAliases(next),
                                  forKey: DefaultsKey.commandBarAliases)
        refreshAfterPreferenceChange()
    }

    /// The row that already answers to this name, so the bar can say so
    /// instead of quietly taking the name away from it.
    func rowAlreadyNamed(_ alias: String, excluding entry: CommandBarEntry) -> String? {
        guard let key = CommandBarPreferences.rowUsingAlias(alias, in: aliases,
                                                            excluding: entry.stableKey)
        else { return nil }
        return entriesByStableKey[key]?.title
    }

    func toggleHidden(_ entry: CommandBarEntry) {
        let next = CommandBarPreferences.togglingHidden(entry.stableKey, in: hiddenKeys)
        UserDefaults.standard.set(CommandBarPreferences.encodeHidden(next),
                                  forKey: DefaultsKey.commandBarHidden)
        refreshAfterPreferenceChange()
    }

    /// Forgets how often this one row was used, so a command run a lot last
    /// month stops crowding the top today. The whole habit can be cleared in
    /// Settings; this is the surgical version, which is what people actually
    /// ask for.
    func resetRanking(_ entry: CommandBarEntry) {
        var usage = CommandBarUsage.decode(
            UserDefaults.standard.string(forKey: DefaultsKey.commandBarUsage))
        usage.removeValue(forKey: entry.id)
        UserDefaults.standard.set(CommandBarUsage.encode(usage), forKey: DefaultsKey.commandBarUsage)
        queryMemory.forget(id: entry.id)
        refreshAfterPreferenceChange()
    }

    /// Forgets the whole habit, for the button in Settings that offers it.
    /// What one session noticed about what was typed goes with it, or clearing
    /// the ranking would leave half of it standing.
    func forgetLearnedRanking() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.commandBarUsage)
        queryMemory.clear()
        refreshAfterPreferenceChange()
    }

    private func refreshAfterPreferenceChange() {
        reloadPreferenceCaches()
        indexEntries()
        refreshResults()
    }

    private func rebuildCatalog(index: Bool = true) {
        catalog = CommandBarCatalog.build(automationDenied: finderAutomationDenied)
        emojiEntries = CommandBarCatalog.emojiEntries(bar: FeatureStrings.commandBar(L10n.shared.language))
        builtLanguage = L10n.shared.language
        if index { indexEntries() }
    }

    /// Global shortcuts need fresh runnable closures. This deliberately never
    /// borrows the title cache, whose entries are metadata and may be stale.
    private func freshFullEntry(forStableKey key: String) -> CommandBarEntry? {
        rebuildCatalog(index: false)
        rebuildRunningEntries(index: false)
        return indexableEntries.last { $0.stableKey == key }
    }

    /// Every row the bar can rank right now, in the order the pool builds
    /// them: what the Mac holds first, what is borrowed after.
    private var indexableEntries: [CommandBarEntry] {
        selectionEntries + killProcessEntries + catalog + appEntries + macSettingsEntries + windowEntries
            + quitEntries + menuEntries + emojiEntries
    }

    private func indexEntries() {
        index(indexableEntries)
    }

    private func clearIndex() {
        entriesByID = [:]
        normalizedByID = [:]
        entriesByStableKey = [:]
    }

    private func index(_ entries: [CommandBarEntry]) {
        entriesByID = [:]
        for entry in entries {
            entriesByID[entry.id] = entry
        }
        // Folding a thousand titles on every keystroke is the one thing that
        // could make typing feel heavy. It happens here instead, once per
        // rebuild.
        normalizedByID = [:]
        entriesByStableKey = [:]
        let names = aliases
        for entry in entries {
            entriesByStableKey[entry.stableKey] = entry
            // A name the person gave is searchable text like any other, so the
            // row surfaces even when its real title shares nothing with it.
            let alias = names[entry.stableKey]
                .map { " " + CommandBarSearch.normalized($0) } ?? ""
            normalizedByID[entry.id] = (
                CommandBarSearch.normalized(entry.matchTitle ?? entry.title),
                CommandBarSearch.normalized(entry.keywords) + alias)
        }
    }

    /// The rows that depend on what is running right now. Cheap enough to
    /// redo on every open, which is the only way the live dot tells the truth.
    private func rebuildRunningEntries(index: Bool = true) {
        let bar = FeatureStrings.commandBar(L10n.shared.language)
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        quitEntries = CommandBarCatalog.quitEntries(running, bar: bar)
        let bundleIDs = Set(running.compactMap(\.bundleIdentifier))
        let paths = Set(running.compactMap { $0.bundleURL?.standardizedFileURL.path })
        appEntries = CommandBarCatalog.appEntries(cachedApps,
                                                  runningBundleIDs: bundleIDs,
                                                  runningPaths: paths,
                                                  bar: bar)
        if index { indexEntries() }
    }

    private func refreshResults() {
        guard !isTearingDown else { return }
        if presentationLifecycle.isLoadingHome {
            rows = []
            sectionTitles = [:]
            categoryChips = []
            return
        }
        if let builtLanguage, builtLanguage != L10n.shared.language {
            rebuildCatalog(index: false)
            rebuildRunningEntries()
        }
        switch mode {
        case .search:
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                let disabled = CommandBarPreferences.disabledSources(from: disabledSourcesRaw)
                categoryChips = Self.chipOrder.filter {
                    !disabled.contains($0) && categoryHasContent($0)
                }
                if let category = activeCategory {
                    let bar = FeatureStrings.commandBar(L10n.shared.language)
                    rows = CommandBarService.uniqued(categoryContent(category, bar: bar))
                    sectionTitles = rows.isEmpty
                        ? [:]
                        : [0: categoryHeading(category, count: rows.count)]
                } else {
                    let suggestions = suggestionRows()
                    rows = suggestions.rows
                    sectionTitles = suggestions.titles
                }
                isShowingSuggestions = !rows.isEmpty
            } else {
                // Two rows with one id is undefined behaviour in a SwiftUI
                // list: the wrong one gets the click and the selection jumps.
                // The providers are careful, but the list is stitched from six
                // of them plus whatever the person saved, so the last word is
                // here. Only on the typed list: the headings of the browse list
                // are keyed by position, and dropping a row under them would
                // shift every heading below it.
                rows = CommandBarService.uniqued(searchRows(for: trimmed))
                // A typed query is one ranked list, so it carries no headings
                // of its own. Inside a category it carries exactly one, because
                // a filtered search that looks unfiltered turns "nothing here"
                // into a lie about the whole bar.
                sectionTitles = activeCategory.map { [0: categoryHeading($0, count: rows.count)] }
                    ?? [:]
                isShowingSuggestions = false
            }
            // Typing always lands on the best match; a background load never
            // moves the selection at all.
            //
            // Those are two different refreshes and they were treated as one:
            // keeping the selection by id across a KEYSTROKE meant the row
            // picked at "f" stayed picked all the way through "fire", so the
            // list showed the flame on top and Return opened the browser.
            let queryChanged = trimmed != lastRankedQuery
            lastRankedQuery = trimmed
            if queryChanged {
                selectedIndex = 0
            } else if let keepID = selectedID,
                      let index = rows.firstIndex(where: { $0.id == keepID }) {
                selectedIndex = index
            } else {
                selectedIndex = 0
            }
            selectedID = rows.indices.contains(selectedIndex) ? rows[selectedIndex].id : nil
        case .argument, .confirm, .actions, .naming, .capturingShortcut:
            break
        }
        refreshPanelLayout()
    }

    /// The same rows with any repeated id dropped, keeping the first, which is
    /// the better ranked one.
    static func uniqued(_ rows: [CommandBarEntry]) -> [CommandBarEntry] {
        let keep = CommandBarSearch.firstOccurrences(of: rows.map(\.id))
        return keep.count == rows.count ? rows : keep.map { rows[$0] }
    }

    /// Whether some command that takes a number answers to this text, which
    /// is what makes a trailing number an argument instead of search text.
    private func numericCommandMatches(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return catalog.contains { entry in
            entry.numericRange != nil
                && CommandBarSearch.matches(title: entry.title,
                                            keywords: entry.keywords,
                                            query: text)
        }
    }

    private func suggestionRows() -> (rows: [CommandBarEntry], titles: [Int: String]) {
        let bar = FeatureStrings.commandBar(L10n.shared.language)
        let hidden = hiddenKeys
        // Read once. The browse list walks the whole catalog, and asking the
        // preferences for every row would parse the same string ninety times.
        let disabled = CommandBarPreferences.disabledSources(from: disabledSourcesRaw)
        func allowed(_ entry: CommandBarEntry) -> Bool {
            let source = CommandBarPreferences.source(ofRowID: entry.id)
            return source.isAlwaysOn || !disabled.contains(source)
        }
        var rows: [CommandBarEntry] = []
        var titles: [Int: String] = [:]

        // What is selected leads the empty bar: it is the thing the person is
        // already looking at, and the heading shows it so there is no doubt
        // about what the rows underneath would act on.
        if !selectionEntries.isEmpty {
            titles[0] = selectionPreview.isEmpty
                ? bar.selectedTitle
                : bar.selectedTitle + " · " + selectionPreview
            rows.append(contentsOf: selectionEntries)
        }

        let offerable = (catalog + appEntries + macSettingsEntries + windowEntries).filter {
            !hidden.contains($0.stableKey) && allowed($0)
        }
        // On the empty bar there is no ranking to respect, so what the person
        // pinned leads, in the order they pinned it.
        let byKey = Dictionary(offerable.map { ($0.stableKey, $0) },
                               uniquingKeysWith: { first, _ in first })
        let pinnedRows = CommandBarPreferences.leadingPins(pins, available: Set(byKey.keys))
            .compactMap { byKey[$0] }
        if !pinnedRows.isEmpty {
            titles[rows.count] = bar.pinnedTitle
            rows.append(contentsOf: pinnedRows)
        }

        let usage = CommandBarUsage.decode(
            UserDefaults.standard.string(forKey: DefaultsKey.commandBarUsage))
        let pinnedIDs = Set(pinnedRows.map(\.id))
        let ids = CommandBarUsage.suggestionIDs(usage: usage,
                                                available: offerable.map(\.id).filter { !pinnedIDs.contains($0) },
                                                curated: CommandBarCatalog.curatedSuggestionIDs,
                                                limit: max(0, 7 - pinnedRows.count))
        let suggestions = ids.compactMap { entriesByID[$0] }
        if !suggestions.isEmpty {
            titles[rows.count] = bar.suggestionsLabel
            rows.append(contentsOf: suggestions)
        }

        // And then everything else, grouped by where it lives. Seven guesses
        // never say how big the app is; this is where someone opening the bar
        // for the first time finds out, by scrolling, with every row runnable.
        // Apps and windows stay out: hundreds of them would bury the commands
        // and they are what search is for.
        var shown = Set(rows.map(\.id))
        var order: [String] = []
        var groups: [String: [CommandBarEntry]] = [:]
        for entry in catalog where !shown.contains(entry.id) && !hidden.contains(entry.stableKey) {
            guard allowed(entry) else { continue }
            shown.insert(entry.id)
            let group = browseGroup(for: entry, bar: bar)
            if groups[group] == nil { order.append(group) }
            // The heading already says it; the row saying it again is noise.
            groups[group, default: []].append(entry.subtitle == group
                                              ? entry.withSubtitle("") : entry)
        }
        for group in order {
            guard let members = groups[group], !members.isEmpty else { continue }
            titles[rows.count] = group
            // Snippets and saved places are made by the person and have no
            // natural end; fifty of one kind would bury every other group
            // below it. Browsing shows a taste of each, and search finds
            // the rest.
            rows.append(contentsOf: members.prefix(Self.browseGroupLimit))
        }

        // What was copied comes last, behind a scroll: it belongs in the bar,
        // but not on screen over whatever the person is doing every time it
        // opens.
        if !disabled.contains(.clipboard) {
            let copied = CommandBarCatalog.clipboardBrowseEntries(limit: 6, bar: bar) {
                [weak self] entry in
                self?.paste(entry)
            }.filter { !hidden.contains($0.stableKey) && shown.insert($0.id).inserted }
            if !copied.isEmpty {
                titles[rows.count] = bar.kindClipboard
                rows.append(contentsOf: copied)
            }
        }
        return (rows, titles)
    }

    /// The heading a row browses under. Most rows already carry the name of
    /// their area as their caption; the ones whose caption is a live detail
    /// (a battery reading, a folder path) are grouped by what they are.
    private func browseGroup(for entry: CommandBarEntry,
                             bar: CommandBarFeatureStrings) -> String {
        switch CommandBarPreferences.source(ofRowID: entry.id) {
        case .answers: return bar.kindAnswer
        case .links: return bar.kindLink
        case .snippets: return bar.kindSnippet
        case .folders: return bar.kindFolder
        case .actions, .apps, .menus, .windows, .quitApps, .settingsPages, .macSettings,
             .clipboard, .emoji, .calculator, .selection, .files, .killProcess:
            return entry.subtitle.isEmpty ? bar.everythingTitle : entry.subtitle
        }
    }

    /// How many rows one group may show while browsing.
    private static let browseGroupLimit = 12

    /// How many rows each kind may contribute, so one provider never floods
    /// the list. Actions have no cap: they are what the bar is for.
    private static let kindLimits: [(prefix: String, limit: Int)] = [
        ("app.", 5), ("window.", 4), ("quit.", 3), ("menu.", 5), ("emoji.", 6),
        ("settings.", 4), ("macsettings.", 4), ("clipboard.", 4), ("snippet.", 4),
        ("file.", 4),
        // Every switch answers to the same verb, so searching that verb would
        // otherwise fill the list with twenty rows that all read alike.
        ("toggle.", 5),
    ]

    /// The folded text a row is ranked against. Almost every row answers to
    /// its own title, folded once when the catalog was built. A row that reads
    /// an argument answers to the whole query instead: scored against its name
    /// alone, it would leave the list the moment the argument was typed, which
    /// is exactly when it was about to run.
    private func rankingTitle(for entry: CommandBarEntry,
                              folded: (title: String, keywords: String)?,
                              query: String) -> String {
        guard entry.takesArgument else {
            return folded?.title ?? CommandBarSearch.normalized(entry.matchTitle ?? entry.title)
        }
        // Not cacheable by design: what this row answers to changes with every
        // keystroke. Only the handful of saved searches pay for it.
        return CommandBarSearch.normalized(
            CommandBarLinks.rankingTitle(name: entry.title, query: query))
    }

    private func searchRows(for trimmed: String) -> [CommandBarEntry] {
        let bar = FeatureStrings.commandBar(L10n.shared.language)
        // Inside a category, typing filters that category and nothing else:
        // no answer row, no caps per kind, just the ranking over one list.
        if let category = activeCategory {
            // A search inside one category is not a search for files, so any
            // pending one goes: it would land on a list that has no room for
            // it and refresh the bar for nothing.
            fileSearch.cancelPending()
            let hidden = hiddenKeys
            let pool = category == .clipboard
                ? CommandBarCatalog.clipboardEntries(matching: trimmed, bar: bar, limit: 40) {
                    [weak self] entry in self?.paste(entry)
                }
                // A row the person hid stays hidden here too; the browse path
                // filters it and searching inside the category must agree.
                .filter { !hidden.contains($0.stableKey) }
                : categoryContent(category, bar: bar)
            let candidates = pool.enumerated().map { index, entry in
                let folded = normalizedByID[entry.id]
                return CommandBarCandidate(index: index,
                                           normalizedTitle: rankingTitle(for: entry, folded: folded,
                                                                         query: trimmed),
                                           normalizedKeywords: folded?.keywords
                                               ?? CommandBarSearch.normalized(entry.keywords),
                                           boost: 0)
            }
            let ranked = CommandBarSearch.rankedIndexes(candidates: candidates, matching: trimmed)
            return ranked.prefix(40).map { pool[$0] }
        }
        // A sum is answered, not searched: the result leads and the rest of
        // the list carries on underneath. Its row carries no id prefix of its
        // own, so the switch has to be read here or it would do nothing.
        let answer = isEnabled(.calculator)
            ? CommandBarCatalog.answerEntry(for: trimmed, bar: bar)
            : nil
        // A web address typed into the bar is opened, not searched: the row
        // leads so Return opens it at once, the way a sum's answer does.
        let openURL = CommandBarCatalog.openURLEntry(for: trimmed, bar: bar)

        // A saved script answers the same way a sum does, once it has run:
        // the row leads, and Return copies what it printed. Same as any
        // other saved link, it stays quiet while the Links source is off or
        // that one link is hidden - a switched-off source must not still
        // spawn a process behind it.
        let savedLinks = CommandBarLinks.decode(
            UserDefaults.standard.data(forKey: DefaultsKey.commandBarLinks))
        let scriptMatch = isEnabled(.links)
            ? CommandBarLinks.matchingScriptLink(in: savedLinks, query: trimmed)
            : nil
        var scriptAnswer: CommandBarEntry?
        if let scriptMatch, !hiddenKeys.contains("link.\(scriptMatch.link.id.uuidString)") {
            if let result = scriptRunner.cachedResult(linkID: scriptMatch.link.id,
                                                       argument: scriptMatch.argument) {
                scriptRunner.cancelPending()
                scriptAnswer = CommandBarCatalog.scriptAnswerEntry(link: scriptMatch.link,
                                                                   result: result, bar: bar)
            } else {
                scriptRunner.schedule(link: scriptMatch.link, argument: scriptMatch.argument)
            }
        } else {
            scriptRunner.cancelPending()
        }

        // Files, once the person has named a folder to look in. Asked for
        // rather than waited on: the answer lands a moment later and refreshes
        // the list, the way a saved script's answer does.
        var fileRows: [CommandBarEntry] = []
        if isEnabled(.files), !fileScopeCache.isEmpty {
            if let paths = fileSearch.cachedPaths(for: trimmed) {
                fileSearch.cancelPending()
                fileRows = CommandBarCatalog.fileEntries(paths, bar: bar)
            } else {
                fileSearch.schedule(query: trimmed,
                                    scopes: fileScopeCache,
                                    patterns: fileIgnoreCache)
            }
        } else {
            fileSearch.cancelPending()
        }

        // "brilho 40" is a command with a value; "code 1234" is a search for
        // something copied. The number is only taken off when a command that
        // actually takes one answers to what is left.
        let split = CommandBarSearch.splitTrailingNumber(trimmed)
        let effectiveQuery = split.number != nil && numericCommandMatches(split.text)
            ? split.text
            : trimmed

        let usage = CommandBarUsage.decode(
            UserDefaults.standard.string(forKey: DefaultsKey.commandBarUsage))
        let now = Date().timeIntervalSince1970

        // The clipboard is searched with everything that was typed: digits
        // are part of what people look for.
        let clipboard = CommandBarCatalog.clipboardEntries(matching: trimmed,
                                                           bar: bar) { [weak self] entry in
            self?.paste(entry)
        }

        let names = aliases
        let pinnedKeys = Set(pins)
        let hidden = hiddenKeys

        // What is selected comes first, so a tie goes to the thing the person
        // is already looking at.
        var pool = selectionEntries + catalog + appEntries + macSettingsEntries + windowEntries
        // Two script names can overlap ("run" and "run report"). Only the
        // longest matching one is eligible; otherwise the shorter row can win
        // a ranking tie and Return runs a different file from the answer shown.
        if let scriptMatch {
            let winnerID = "link.\(scriptMatch.link.id.uuidString)"
            let matchingScriptIDs = Set(savedLinks.compactMap { link -> String? in
                guard link.kind == .script,
                      CommandBarLinks.trailingArgument(query: trimmed, name: link.name) != nil
                else { return nil }
                return "link.\(link.id.uuidString)"
            })
            pool.removeAll {
                matchingScriptIDs.contains($0.id) && (scriptAnswer != nil || $0.id != winnerID)
            }
        }
        // Quitting an app is a rare, heavy verb: its rows only join the list
        // when the person actually asked to quit something, so they never
        // double the length of an ordinary app search.
        if CommandBarSearch.matchesVerb(trimmed, in: bar.quitFormat) {
            pool.append(contentsOf: quitEntries)
        }
        // Menu commands are a deep list; below two letters it would bury
        // everything the bar itself can do. Running processes are excluded
        // from ordinary typed search entirely - they only surface once you've
        // explicitly entered the Kill Process category (see categoryContent).
        if effectiveQuery.count >= 2 {
            pool.append(contentsOf: menuEntries)
            pool.append(contentsOf: emojiEntries)
        }
        pool.append(contentsOf: clipboard)
        pool.append(contentsOf: fileRows)

        // The kind of each surviving row, worked out once: the switches are
        // read from disk here instead of once per row per keystroke, and the
        // ranking below needs the same answer.
        let disabled = CommandBarPreferences.disabledSources(from: disabledSourcesRaw)
        var sources: [CommandBarSource] = []
        var kept: [CommandBarEntry] = []
        kept.reserveCapacity(pool.count)
        sources.reserveCapacity(pool.count)
        for entry in pool where !hidden.contains(entry.stableKey) {
            let source = CommandBarPreferences.source(ofRowID: entry.id)
            guard source.isAlwaysOn || !disabled.contains(source) else { continue }
            kept.append(entry)
            sources.append(source)
        }
        pool = kept

        let candidates = pool.enumerated().map { index, entry in
            let folded = normalizedByID[entry.id]
            // A name the person gave outranks every title in the catalog:
            // that is the whole point of giving it.
            let aliasBoost = names[entry.stableKey]
                .flatMap { CommandBarPreferences.aliasHit($0, query: effectiveQuery)?.rawValue } ?? 0
            return CommandBarCandidate(index: index,
                                normalizedTitle: rankingTitle(for: entry, folded: folded,
                                                              query: effectiveQuery),
                                normalizedKeywords: folded?.keywords
                                    ?? CommandBarSearch.normalized(entry.keywords),
                                // A running app is likelier to be the one
                                // wanted, but never enough to beat a better
                                // name match.
                                boost: (entry.countsUsage
                                        ? CommandBarUsage.boost(for: usage[entry.id], now: now)
                                        : 0)
                                    + (entry.isActive ? 20 : 0)
                                    + aliasBoost
                                    // What this session already answered with
                                    // for exactly these letters.
                                    + (entry.countsUsage
                                        ? queryMemory.boost(query: effectiveQuery, id: entry.id)
                                        : 0)
                                    // What the Mac itself holds leads what is
                                    // borrowed from the app in front.
                                    + CommandBarPreferences.rankBias(for: sources[index])
                                    // A pin breaks a tie between two equally
                                    // good matches; it never jumps over a
                                    // better one, or the list would go stale.
                                    + (pinnedKeys.contains(entry.stableKey)
                                        ? CommandBarPreferences.pinTieBreak : 0))
        }
        let ranked = CommandBarSearch.rankedIndexes(candidates: candidates, matching: effectiveQuery)

        // A fact about the Mac only shows when it was asked for by name:
        // "st" must not answer "Storage" over what the person meant.
        let firstToken = CommandBarSearch.normalized(effectiveQuery)
            .split(separator: " ").first.map(String.init) ?? ""

        var counts: [String: Int] = [:]
        var result: [CommandBarEntry] = []
        if let answer { result.append(answer) }
        if let openURL { result.append(openURL) }
        if let scriptAnswer { result.append(scriptAnswer) }
        for index in ranked {
            let entry = pool[index]
            if entry.id.hasPrefix("answer."),
               firstToken.count < 3 || !CommandBarSearch.normalized(entry.title).hasPrefix(firstToken) {
                continue
            }
            if let kind = Self.kindLimits.first(where: { entry.id.hasPrefix($0.prefix) }) {
                let used = counts[kind.prefix, default: 0]
                guard used < kind.limit else { continue }
                counts[kind.prefix] = used + 1
            }
            result.append(entry)
            if result.count >= 12 { break }
        }
        return result
    }

    // MARK: - Selection

    /// Moving past either end comes back around: at the bottom of a short
    /// list, one more press should not feel like the key stopped working.
    func moveSelection(_ delta: Int) {
        guard !rows.isEmpty else { return }
        let next = (selectedIndex + delta) % rows.count
        select(next < 0 ? next + rows.count : next)
    }

    /// Tab completes what is selected into the field, the way every launcher
    /// does, so the next keystroke refines instead of starting over.
    func completeSelection() {
        guard case .search = mode, let entry = selectedEntry, !entry.isAnswer else { return }
        query = entry.title
    }

    func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        selectedIndex = index
        selectedID = rows[index].id
    }

    /// Hover selection, ignored until the pointer really moves. SwiftUI
    /// reports a hover for whatever row slides under a still cursor, and the
    /// list slides on every keystroke, so a resting pointer would keep
    /// stealing the selection back from the keyboard.
    func selectFromHover(_ index: Int) {
        let location = NSEvent.mouseLocation
        guard location != lastPointerLocation else { return }
        lastPointerLocation = location
        select(index)
    }

    var selectedEntry: CommandBarEntry? {
        rows.indices.contains(selectedIndex) ? rows[selectedIndex] : nil
    }

    /// A row by its id, from the catalog first and from what is on screen
    /// otherwise: the clipboard and the calculator build rows that never enter
    /// the index, and ⌘K on one of those used to open an empty list.
    func entry(withID id: String) -> CommandBarEntry? {
        entriesByID[id] ?? rows.first { $0.id == id }
    }

    /// Which letters of a row's title the query literally matched. Empty while
    /// showing suggestions: nothing was typed, so nothing should look matched.
    func highlightOffsets(for entry: CommandBarEntry) -> Set<Int> {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard case .search = mode, !trimmed.isEmpty, !entry.isAnswer else { return [] }
        let split = CommandBarSearch.splitTrailingNumber(trimmed)
        return CommandBarSearch.highlightOffsets(title: entry.title,
                                                 query: split.number != nil ? split.text : trimmed)
    }

    // MARK: - App controls

    /// The actions offered for the selected row, built fresh so pin reads
    /// "unpin" the moment it is pinned.
    var actionRows: [RowAction] {
        guard case .actions(let entryID) = mode, let entry = entry(withID: entryID) else { return [] }
        return actions(for: entry)
    }

    /// Whether the selected row has anything to offer here. A clipboard item
    /// is a passing thing with no lasting id, so it is not in the index and
    /// there is nothing to pin, name or hide about it: the bar says so by not
    /// offering the panel at all instead of opening an empty one.
    var canOpenActions: Bool {
        guard case .search = mode, let entry = selectedEntry, !entry.isAnswer,
              entriesByID[entry.id] != nil else { return false }
        return !actions(for: entry).isEmpty
    }

    private func actions(for entry: CommandBarEntry) -> [RowAction] {
        let bar = FeatureStrings.commandBar(L10n.shared.language)
        var actions: [RowAction] = []
        if let app = installedApp(for: entry) {
            if let running = runningApplication(for: app) {
                actions.append(RowAction(id: "quitApp",
                                         title: String(format: bar.quitFormat, app.name),
                                         symbolName: "xmark.circle") { [weak self] in
                    self?.quit(running)
                })
                actions.append(RowAction(id: "restartApp",
                                         title: String(format: bar.restartAppFormat, app.name),
                                         symbolName: "arrow.clockwise") { [weak self] in
                    self?.restart(running, at: app.url)
                })
                actions.append(RowAction(id: "forceQuitApp",
                                         title: String(format: bar.forceQuitAppFormat, app.name),
                                         symbolName: "exclamationmark.octagon",
                                         isDestructive: true) { [weak self] in
                    self?.confirmForceQuit(running, name: app.name)
                })
            }
            if AppFeature.uninstaller.isAvailable, !app.isSystem {
                actions.append(RowAction(id: "uninstallApp",
                                         title: String(format: bar.uninstallAppFormat, app.name),
                                         symbolName: "trash") { [weak self] in
                    self?.openUninstaller(for: app.url)
                })
            }
        }
        if entry.canRevealInFinder {
            actions.append(RowAction(id: "reveal",
                                     title: bar.actionRevealInFinder,
                                     symbolName: "folder") { [weak self] in
                self?.revealInFinder(entry)
            })
        }
        if let process = killProcessEntry(for: entry), !process.isProtected {
            let killStrings = FeatureStrings.killProcess(L10n.shared.language)
            actions.append(RowAction(id: "forceKillProcess",
                                     title: killStrings.forceKillButton,
                                     symbolName: "exclamationmark.octagon",
                                     isDestructive: true) { [weak self] in
                self?.confirmForceKillProcess(process)
            })
            actions.append(RowAction(id: "killAllProcess",
                                     title: String(format: killStrings.killAllFormat, process.name),
                                     symbolName: "xmark.octagon",
                                     isDestructive: true) { [weak self] in
                self?.confirmKillAllProcesses(process)
            })
            actions.append(RowAction(id: "killProcessTree",
                                     title: killStrings.killTreeButton,
                                     symbolName: "xmark.octagon",
                                     isDestructive: true) { [weak self] in
                self?.confirmKillProcessTree(process)
            })
            if KillProcessService.shared.canRestart(process) {
                actions.append(RowAction(id: "restartProcess",
                                         title: killStrings.restartButton,
                                         symbolName: "arrow.clockwise") { [weak self] in
                    self?.hide()
                    KillProcessService.shared.restart(process)
                })
            }
        }
        if CommandBarPreferences.acceptsPin(rowID: entry.id) {
            actions.append(RowAction(id: "pin",
                                     title: isPinned(entry) ? bar.actionUnpin : bar.actionPin,
                                     symbolName: isPinned(entry) ? "pin.slash" : "pin") { [weak self] in
                self?.togglePin(entry)
                self?.leaveActions()
            })
        }
        if CommandBarPreferences.acceptsAlias(rowID: entry.id) {
            let named = alias(for: entry) != nil
            actions.append(RowAction(id: "name",
                                     title: named ? bar.actionRename : bar.actionName,
                                     symbolName: "character.cursor.ibeam") { [weak self] in
                self?.beginNaming(entry)
            })
        }
        if CommandBarPreferences.acceptsAlias(rowID: entry.id) {
            let bound = rowShortcut(for: entry) != nil
            actions.append(RowAction(id: "shortcut",
                                     title: bound ? bar.actionShortcutChange : bar.actionShortcut,
                                     symbolName: "keyboard") { [weak self] in
                self?.beginCapturingShortcut(entry)
            })
            if bound {
                actions.append(RowAction(id: "shortcutClear",
                                         title: bar.actionShortcutRemove,
                                         symbolName: "keyboard.badge.ellipsis") { [weak self] in
                    self?.setRowShortcut(nil, for: entry)
                    self?.leaveActions()
                })
            }
        }
        actions.append(RowAction(id: "hide", title: bar.actionHide, symbolName: "eye.slash") { [weak self] in
            self?.toggleHidden(entry)
            self?.leaveActions()
        })
        if entry.countsUsage {
            actions.append(RowAction(id: "forget",
                                     title: bar.actionForget,
                                     symbolName: "arrow.counterclockwise") { [weak self] in
                self?.resetRanking(entry)
                self?.leaveActions()
            })
        }
        return actions
    }

    /// Shows a row where it lives instead of running it. An app that was
    /// moved or deleted since the scan says so rather than opening a Finder
    /// window on nothing, the same answer a saved folder already gives.
    func revealInFinder(_ entry: CommandBarEntry) {
        guard let path = entry.revealPath else {
            NSSound.beep()
            return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            hide()
            QuickToolHUD.show(icon: "folder.badge.questionmark", message: entry.title)
            return
        }
        hide()
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func installedApp(for entry: CommandBarEntry) -> InstalledApps.InstalledApp? {
        guard entry.id.hasPrefix("app.") else { return nil }
        return cachedApps.first { "app.\($0.id)" == entry.id }
    }

    private func killProcessEntry(for entry: CommandBarEntry) -> KillProcessEntry? {
        guard entry.id.hasPrefix("kill."), let pid = pid_t(entry.id.dropFirst("kill.".count)) else { return nil }
        return KillProcessService.shared.entries.first { $0.pid == pid }
    }

    private func runningApplication(for app: InstalledApps.InstalledApp) -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        let path = app.url.resolvingSymlinksInPath().standardizedFileURL.path
        if let exact = running.first(where: {
            $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == path
        }) {
            return exact
        }
        guard let bundleID = app.bundleID,
              cachedApps.lazy.filter({ $0.bundleID == bundleID }).prefix(2).count == 1 else {
            return nil
        }
        return running.first { $0.bundleIdentifier == bundleID }
    }

    private func quit(_ app: NSRunningApplication) {
        hide()
        let pid = app.processIdentifier
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard let running = NSRunningApplication(processIdentifier: pid),
                  !running.isTerminated, running.terminate() else {
                NSSound.beep()
                return
            }
        }
    }

    private func restart(_ app: NSRunningApplication, at url: URL) {
        hide()
        cancelPendingRestart()
        let pid = app.processIdentifier
        restartPID = pid
        restartURL = url
        let center = NSWorkspace.shared.notificationCenter
        restartObserver = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                             object: nil,
                                             queue: .main) { [weak self] note in
            guard let terminated = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  terminated.processIdentifier == self?.restartPID else { return }
            self?.completeRestart()
        }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard self?.restartPID == pid,
                  let running = NSRunningApplication(processIdentifier: pid),
                  !running.isTerminated, running.terminate() else {
                self?.cancelPendingRestart()
                NSSound.beep()
                return
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard self?.restartPID == pid else { return }
            self?.cancelPendingRestart()
        }
    }

    private func completeRestart() {
        guard let url = restartURL else {
            cancelPendingRestart()
            return
        }
        cancelPendingRestart()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSWorkspace.shared.openApplication(at: url,
                                               configuration: NSWorkspace.OpenConfiguration()) {
                _, error in
                if error != nil { DispatchQueue.main.async { NSSound.beep() } }
            }
        }
    }

    private func cancelPendingRestart() {
        if let restartObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(restartObserver)
        }
        restartObserver = nil
        restartPID = nil
        restartURL = nil
    }

    private func confirmForceQuit(_ app: NSRunningApplication, name: String) {
        hide()
        let bar = FeatureStrings.commandBar(L10n.shared.language)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(format: bar.forceQuitAppConfirmFormat, name)
        let actionTitle = String(format: bar.forceQuitAppFormat, name)
        alert.addButton(withTitle: actionTitle.hasSuffix("…")
                        ? String(actionTitle.dropLast()) : actionTitle)
        alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let running = NSRunningApplication(processIdentifier: app.processIdentifier),
              !running.isTerminated, running.forceTerminate() else {
            NSSound.beep()
            return
        }
    }

    private func confirmForceKillProcess(_ process: KillProcessEntry) {
        hide()
        let killStrings = FeatureStrings.killProcess(L10n.shared.language)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(format: killStrings.confirmForceKillFormat, process.name)
        alert.informativeText = process.path
        alert.addButton(withTitle: killStrings.forceKillButton)
        alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        KillProcessService.shared.kill(process, force: true)
    }

    private func confirmKillAllProcesses(_ process: KillProcessEntry) {
        hide()
        let killStrings = FeatureStrings.killProcess(L10n.shared.language)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(format: killStrings.confirmKillAllFormat, process.name)
        alert.addButton(withTitle: killStrings.killButton)
        alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        KillProcessService.shared.killAll(named: process.name, force: false)
    }

    private func confirmKillProcessTree(_ process: KillProcessEntry) {
        hide()
        let killStrings = FeatureStrings.killProcess(L10n.shared.language)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(format: killStrings.confirmKillTreeFormat, process.name)
        alert.informativeText = process.path
        alert.addButton(withTitle: killStrings.killTreeButton)
        alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        KillProcessService.shared.killTree(process, force: false)
    }

    private func openUninstaller(for url: URL) {
        hide()
        AppUninstaller.shared.select(appURL: url)
        SettingsRouter.shared.page = .uninstaller
        appDelegate()?.openSettingsWindow()
    }

    func openActions() {
        guard canOpenActions, let entry = selectedEntry else { return }
        savedQuery = query
        mode = .actions(entryID: entry.id)
        actionIndex = 0
        refreshPanelLayout()
    }

    private func leaveActions() {
        if case .capturingShortcut = mode { endCapturingShortcut() }
        mode = .search
        query = savedQuery
        refreshResults()
    }

    /// While the bar listens for a combination, every global key the app holds
    /// steps aside: otherwise a combination already taken would fire its own
    /// feature instead of reaching the bar. This is the same pair the shortcut
    /// fields in Settings use, and it gives every key back, not only ours.
    private func beginCapturingShortcut(_ entry: CommandBarEntry) {
        ShortcutCapture.begin()
        mode = .capturingShortcut(entryID: entry.id)
        refreshPanelLayout()
    }

    private func endCapturingShortcut() {
        ShortcutCapture.end()
    }

    private func beginNaming(_ entry: CommandBarEntry) {
        mode = .naming(entryID: entry.id)
        query = alias(for: entry) ?? ""
        aliasWarning = nil
        refreshPanelLayout()
    }

    @Published private(set) var actionIndex = 0
    /// Set when the name being typed already belongs to another row.
    @Published private(set) var aliasWarning: String?

    func moveActionSelection(_ delta: Int) {
        let count = actionRows.count
        guard count > 0 else { return }
        let next = (actionIndex + delta) % count
        actionIndex = next < 0 ? next + count : next
    }

    func runSelectedAction() {
        let actions = actionRows
        guard actions.indices.contains(actionIndex) else { return }
        actions[actionIndex].run()
    }

    func runAction(_ action: RowAction) {
        action.run()
    }

    private func commitName() {
        guard case .naming(let entryID) = mode, let entry = entry(withID: entryID) else { return }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty, let owner = rowAlreadyNamed(typed, excluding: entry) {
            aliasWarning = String(format: FeatureStrings.commandBar(L10n.shared.language)
                                    .aliasTakenFormat, owner)
            return
        }
        setAlias(typed, for: entry)
        aliasWarning = nil
        leaveActions()
    }

    func runSelected() {
        switch mode {
        case .actions:
            runSelectedAction()
            return
        case .naming:
            commitName()
            return
        case .capturingShortcut:
            // Return is a combination like any other while listening.
            return
        case .confirm(let id):
            guard let entry = entry(withID: id) else { return }
            finish(entry, value: nil)
        case .argument(let id):
            guard let entry = entry(withID: id), let range = entry.numericRange,
                  let value = CommandBarSearch.argumentValue(query, in: range) else {
                NSSound.beep()
                return
            }
            finish(entry, value: value)
        case .search:
            guard let entry = selectedEntry else {
                // The no-results state promises a way out; Return takes it.
                if !query.isEmpty { query = "" }
                return
            }
            run(entry)
        }
    }

    func run(at index: Int) {
        guard case .search = mode, rows.indices.contains(index) else { return }
        run(rows[index])
    }

    /// Runs the row the person actually clicked, by identity: between the
    /// click and this call the list may have been rebuilt by a background
    /// load, and a position would then point at a different command.
    func run(_ entry: CommandBarEntry, fromClick: Bool) {
        guard case .search = mode, fromClick else { return }
        run(entry)
    }

    private func run(_ entry: CommandBarEntry) {
        if case .needsSetup(_, let page) = entry.trouble {
            hide()
            SettingsRouter.shared.page = page
            appDelegate()?.openSettingsWindow()
            return
        }
        if entry.confirmationPrompt != nil {
            savedQuery = query
            mode = .confirm(entryID: entry.id)
            refreshPanelLayout()
            return
        }
        if let range = entry.numericRange {
            if let typedNumber {
                finish(entry, value: min(max(typedNumber, range.lowerBound), range.upperBound))
            } else if entry.numericIsOptional {
                finish(entry, value: nil)
            } else {
                savedQuery = query
                mode = .argument(entryID: entry.id)
                query = ""
                refreshPanelLayout()
            }
            return
        }
        finish(entry, value: nil)
    }

    /// Esc in argument or confirm mode returns to the search as it was; in
    /// plain search it closes the bar.
    func stepBack() {
        switch mode {
        case .actions:
            leaveActions()
        case .naming(let entryID):
            aliasWarning = nil
            if let entry = entry(withID: entryID) {
                mode = .actions(entryID: entry.id)
                query = ""
                refreshPanelLayout()
            } else {
                leaveActions()
            }
        case .capturingShortcut(let entryID):
            endCapturingShortcut()
            if let entry = entry(withID: entryID) {
                mode = .actions(entryID: entry.id)
                refreshPanelLayout()
            } else {
                leaveActions()
            }
        case .argument, .confirm:
            mode = .search
            query = savedQuery
            refreshResults()
        case .search:
            // A long query typed by mistake should be clearable without
            // throwing the whole session away; then Esc leaves the category,
            // and only from home does it close.
            if !query.isEmpty {
                query = ""
            } else if activeCategory != nil {
                setCategory(nil)
            } else {
                hide()
            }
        }
    }

    private func finish(_ entry: CommandBarEntry, value: Int?) {
        if entry.countsUsage, isVisible {
            // Only what is on screen teaches anything: a row run from its own
            // combination was never typed for.
            queryMemoryStep &+= 1
            queryMemory.record(query: query, id: entry.id, step: queryMemoryStep)
        }
        if entry.countsUsage {
            let stored = UserDefaults.standard.string(forKey: DefaultsKey.commandBarUsage)
            let next = CommandBarUsage.recording(CommandBarUsage.decode(stored),
                                                 id: entry.id,
                                                 now: Date().timeIntervalSince1970)
            UserDefaults.standard.set(CommandBarUsage.encode(next), forKey: DefaultsKey.commandBarUsage)
        }
        // Handed over before hiding, which wipes the field and the selection.
        queryWhenRun = query
        selectionWhenRun = selectedText
        guard !entry.keepsBarOpen else {
            entry.run(value)
            return
        }
        hide()
        entry.run(value)
    }

    // MARK: - Clipboard paste

    /// Pastes one history item at the caret. The panel never activated, so
    /// the target app still has focus; all this does is put the item on the
    /// clipboard, wait for a clean keyboard and press ⌘V for the person.
    private func paste(_ entry: ClipboardHistoryEntry) {
        hide()
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier {
            NSSound.beep()
            return
        }
        // Without Accessibility the synthetic paste is dropped by the system.
        // Asking first matters: writing the item to the clipboard and then
        // failing would throw away what the person had copied, for nothing.
        guard AXIsProcessTrusted() else {
            if promptedForAccessibility {
                NSSound.beep()
            } else {
                promptedForAccessibility = true
                Permissions.shared.requestAccessibility()
            }
            return
        }
        guard ClipboardHistoryService.shared.copy(entry) else {
            NSSound.beep()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.postPasteWhenModifiersReleased(attempt: 0)
        }
    }

    /// The proven dance: ⌘V posted while the summoning chord is still held
    /// merges with those modifiers and stops being a paste in the target
    /// app, so wait for a clean keyboard first (15 ms polls, ~1.5 s cap,
    /// then a settle beat). Secure input means a password field; leave it be.
    private static func postPasteWhenModifiersReleased(attempt: Int) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if attempt >= 100 {
            NSSound.beep()
            return
        }
        guard held.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
                postPasteWhenModifiersReleased(attempt: attempt + 1)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard !IsSecureEventInputEnabled() else {
                NSSound.beep()
                return
            }
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let keyDown = CGEvent(keyboardEventSource: source,
                                        virtualKey: CGKeyCode(kVK_ANSI_V),
                                        keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source,
                                      virtualKey: CGKeyCode(kVK_ANSI_V),
                                      keyDown: false)
            else { return }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Background loads

    /// Installed apps are enumerated off the main thread on every opening.
    /// The previous list stays visible until the fresh one lands, so a newly
    /// installed app appears promptly without a watcher living in the
    /// background or a loading pause. Icons are resolved lazily by the rows.
    private func loadAppsIfNeeded(for id: UUID) {
        guard !appsLoading else { return }
        appsLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let apps = SpotlightNames.enriching(InstalledApps.installedApplications(
                includeSystemApplications: true,
                spotlightPaths: Self.spotlightApplicationPaths()))
            DispatchQueue.main.async {
                guard let self else { return }
                self.cachedApps = apps
                self.appsLoading = false
                guard self.presentationLifecycle.acceptsSharedCacheCompletion(
                    startedBy: id, currentID: self.presentationID,
                    isVisible: self.isVisible) else { return }
                self.rebuildRunningEntries()
                self.refreshResults()
            }
        }
    }

    /// The Mac's own Settings panes, read off the main thread the first time
    /// the bar opens and reused after: they only change when macOS does. The
    /// switch is honoured here rather than only in the ranking, so a source
    /// nobody wants costs no scan at all.
    private func loadMacSettingsIfNeeded(for id: UUID) {
        let pendingShortcut = deferredRowShortcut.key(for: id)
            .map { CommandBarPreferences.source(ofRowID: $0) == .macSettings } == true
        guard (isEnabled(.macSettings) || pendingShortcut), !macSettingsLoading,
              macSettingsLanguage != L10n.shared.language
        else { return }
        macSettingsLoading = true
        let language = L10n.shared.language
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let panes = CommandBarSystemSettings.panes(language: language)
            DispatchQueue.main.async {
                guard let self else { return }
                self.macSettingsLoading = false
                self.macSettingsLanguage = language
                self.macSettingsEntries = CommandBarCatalog.macSettingsEntries(
                    panes, bar: FeatureStrings.commandBar(language))
                self.indexEntries()
                guard self.presentationLifecycle.acceptsSharedCacheCompletion(
                    startedBy: id, currentID: self.presentationID,
                    isVisible: self.isVisible) else { return }
                if !self.runDeferredRowShortcutIfReady(for: id) { self.refreshResults() }
            }
        }
    }

    /// A row whose provider loads in the background keeps its shortcut until
    /// that provider has indexed the row. Closing or opening a newer bar still
    /// cancels it through the presentation id.
    @discardableResult
    private func runDeferredRowShortcutIfReady(for id: UUID) -> Bool {
        guard let key = deferredRowShortcut.key(for: id),
              let entry = entriesByStableKey[key]
        else { return false }
        _ = deferredRowShortcut.take(for: id)
        run(entry)
        return true
    }

    private static func spotlightApplicationPaths() -> [String] {
        let result = Shell.run(
            "/usr/bin/mdfind",
            ["-onlyin", NSHomeDirectory(),
             "kMDItemContentType == 'com.apple.application-bundle'"])
        guard result.status == 0 else { return [] }
        return result.output.split(separator: "\n").map(String.init)
    }

    /// Open windows, listed away from the main thread because the walk asks
    /// Accessibility. Titles only exist with Screen Recording granted, so
    /// without it there is nothing to show and the rows stay out rather than
    /// filling the list with repeated app names.
    /// The menu bar of the app that was in front when the bar opened, walked
    /// away from the main thread and kept per app for a few seconds. Nothing
    /// is read while the bar is closed, and nothing is read for our own app.
    private func loadMenusIfNeeded(for id: UUID) {
        guard Permissions.shared.accessibility,
              let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier,
              front.activationPolicy == .regular else {
            if !menuEntries.isEmpty {
                menuEntries = []
                menuOwnerPID = nil
                indexEntries()
            }
            return
        }
        let pid = front.processIdentifier
        let name = front.localizedName ?? ""
        if menuOwnerPID == pid, let loadedAt = menusLoadedAt,
           Date().timeIntervalSince(loadedAt) < 8 { return }
        // Menu rows belong to the app they were read from. The moment another
        // app is in front they go, instead of staying runnable until the new
        // walk lands: pressing one would act on an app nobody is looking at.
        if menuOwnerPID != pid, !menuEntries.isEmpty {
            menuEntries = []
            indexEntries()
        }
        guard !menusLoading else { return }
        menusLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = CommandBarMenus.items(for: pid)
            DispatchQueue.main.async {
                guard let self else { return }
                self.menusLoading = false
                // A walk that finished after the person moved on is worth
                // nothing; the current presentation asks again.
                guard self.presentationLifecycle.acceptsHomeUpdates(
                    id, isVisible: self.isVisible),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                else {
                    let current = self.presentationID
                    if self.presentationLifecycle.acceptsHomeUpdates(
                        current, isVisible: self.isVisible) {
                        self.loadMenusIfNeeded(for: current)
                    }
                    return
                }
                self.menuOwnerPID = pid
                self.menusLoadedAt = Date()
                let bar = FeatureStrings.commandBar(L10n.shared.language)
                self.menuEntries = CommandBarCatalog.menuEntries(items, appName: name, bar: bar)
                self.indexEntries()
                self.refreshResults()
            }
        }
    }

    /// What the person had selected when the bar opened. Read away from the
    /// main thread (it asks Accessibility) and only while the bar is open, so
    /// nothing is ever read from anyone's screen in the background.
    private func loadSelection(for id: UUID) {
        guard isEnabled(.selection), Permissions.shared.accessibility else { return }
        guard !selectionLoading else { return }
        selectionLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = CommandBarSelectionReader.readSelectedText()
            DispatchQueue.main.async {
                guard let self else { return }
                self.selectionLoading = false
                guard self.presentationLifecycle.acceptsHomeUpdates(
                    id, isVisible: self.isVisible) else {
                    let current = self.presentationID
                    if self.presentationLifecycle.acceptsHomeUpdates(
                        current, isVisible: self.isVisible) {
                        self.loadSelection(for: current)
                    }
                    return
                }
                let bar = FeatureStrings.commandBar(L10n.shared.language)
                self.selectedText = text
                self.selectionEntries = CommandBarCatalog.selectionEntries(text, bar: bar) {
                    [weak self] selected in
                    // The bar stays open: the point is to convert, add up or
                    // look up what was selected without retyping it.
                    self?.query = selected
                }
                self.selectionPreview = text.isEmpty ? "" : CommandBarText.preview(text)
                self.indexEntries()
                self.refreshResults()
            }
        }
    }

    /// Every running process, so a name typed directly finds and can kill it.
    /// Reads through `KillProcessService`'s own cache - shared with the
    /// Settings page, so this never shells out to `ps` twice - and only
    /// while the bar is open, same lifetime and guard shape as
    /// `loadSelection(for:)`.
    private func loadKillProcessEntries(for id: UUID) {
        guard AppFeature.killProcess.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.killProcessCommandBarEnabled) else { return }
        guard !killProcessEntriesLoading else { return }
        killProcessEntriesLoading = true
        KillProcessService.shared.refresh { [weak self] in
            guard let self else { return }
            self.killProcessEntriesLoading = false
            guard self.presentationLifecycle.acceptsHomeUpdates(id, isVisible: self.isVisible) else {
                let current = self.presentationID
                if self.presentationLifecycle.acceptsHomeUpdates(current, isVisible: self.isVisible) {
                    self.loadKillProcessEntries(for: current)
                }
                return
            }
            let killStrings = FeatureStrings.killProcess(L10n.shared.language)
            self.killProcessEntries = CommandBarCatalog.killProcessEntries(
                KillProcessService.shared.entries, killStrings: killStrings)
            self.indexEntries()
            self.refreshResults()
        }
    }

    private func loadWindowsIfNeeded(for id: UUID) {
        // Accessibility is the real requirement: the window walk reads titles
        // through AX when the window server withholds them, so asking for
        // Screen Recording here would demand the heaviest permission on the
        // Mac for nothing.
        let allowed = (AppFeature.switcher.isAvailable || AppFeature.windowLayout.isAvailable)
            && Permissions.shared.accessibility
        guard allowed else {
            // Any reason to stop offering windows clears the ones already
            // listed: a revoked permission or a feature switched off must not
            // leave rows behind that no longer work.
            if !windowEntries.isEmpty {
                windowEntries = []
                windowsLoadedAt = nil
                indexEntries()
            }
            return
        }
        // The walk asks Accessibility about every running app and the AX
        // timeout is process wide, so a hung app would make every open wait.
        // One walk per few seconds is plenty for a list of windows.
        if let loadedAt = windowsLoadedAt, Date().timeIntervalSince(loadedAt) < 4 { return }
        guard !windowsLoading else { return }
        windowsLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let windows = WindowEnumerator.listWindowsForCommandBar()
            DispatchQueue.main.async {
                guard let self else { return }
                self.windowsLoading = false
                guard self.presentationLifecycle.acceptsHomeUpdates(
                    id, isVisible: self.isVisible) else {
                    let current = self.presentationID
                    if self.presentationLifecycle.acceptsHomeUpdates(
                        current, isVisible: self.isVisible) {
                        self.loadWindowsIfNeeded(for: current)
                    }
                    return
                }
                self.windowsLoadedAt = Date()
                let bar = FeatureStrings.commandBar(L10n.shared.language)
                self.windowEntries = CommandBarCatalog.windowEntries(windows, bar: bar)
                self.indexEntries()
                self.refreshResults()
            }
        }
    }

    /// Free space on the boot volume asks the storage daemon what is
    /// purgeable, which can take a moment on a full disk. It is read away
    /// from the main thread and the row picks it up on the next pass.
    private func refreshStorageAnswer(for id: UUID) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let space = CommandBarCatalog.readBootVolumeSpace()
            DispatchQueue.main.async {
                guard let self, CommandBarCatalog.cachedBootVolumeSpace?.free != space?.free
                else { return }
                CommandBarCatalog.cachedBootVolumeSpace = space
                if self.presentationLifecycle.acceptsSharedCacheCompletion(
                    startedBy: id, currentID: self.presentationID,
                    isVisible: self.isVisible) {
                    self.rebuildCatalog()
                    self.refreshResults()
                }
            }
        }
    }

    /// Asking CoreWLAN crosses to the Wi-Fi daemon, so the row reads a value
    /// gathered in the background instead of paying for it on the keystroke
    /// that opens the bar.
    private func refreshWiFiState(for id: UUID) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let state = CommandBarExtras.readWiFiPowerState()
            DispatchQueue.main.async {
                guard let self, CommandBarExtras.cachedWiFiPower != state else { return }
                CommandBarExtras.cachedWiFiPower = state
                if self.presentationLifecycle.acceptsSharedCacheCompletion(
                    startedBy: id, currentID: self.presentationID,
                    isVisible: self.isVisible) {
                    self.rebuildCatalog()
                    self.refreshResults()
                }
            }
        }
    }

    /// The blocking Apple Event check runs away from the main thread; the
    /// Trash row reads the cached answer.
    private func refreshAutomationStatus(for id: UUID) {
        guard AppFeature.quickToggles.isAvailable else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let denied = Permissions.automationStatus(for: .finder) == .denied
            DispatchQueue.main.async {
                guard let self, self.finderAutomationDenied != denied else { return }
                self.finderAutomationDenied = denied
                if self.presentationLifecycle.acceptsSharedCacheCompletion(
                    startedBy: id, currentID: self.presentationID,
                    isVisible: self.isVisible) {
                    self.rebuildCatalog()
                    self.refreshResults()
                }
            }
        }
    }

    // MARK: - Panel

    /// Borderless panels refuse key status by default, and the bar's field
    /// needs it for typing while the target app stays active.
    private final class KeyableBarPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableBarPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                                    styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered,
                                    defer: false)
        panel.title = "Vorssaint"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: CommandBarView())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    /// Centered, a bit above the middle of the screen the pointer is on:
    /// where the eye already is, and where the system's own search field
    /// puts itself. Anchored by the top edge so the list can grow and shrink
    /// below a field that never moves. Wherever the person dragged the bar
    /// away from that spot is added on, so the choice survives the close.
    private func position(_ panel: NSPanel, animated: Bool = false) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 560, height: 380)
        // Decided once, here: moving the pointer to another display while
        // typing must not clamp the panel against a screen it is not on.
        let screen = NSScreen.pointerVisibleFrame
        panelScreen = screen
        let offset = positionOffset
        let origin = CommandBarPreferences.clampedPanelOrigin(
            size: size, in: screen, offset: offset)
        panel.setFrame(NSRect(origin: origin, size: size),
                       display: true,
                       animate: animated)
    }

    /// How far the person dragged the bar from the spot it would otherwise
    /// open on.
    private var positionOffset: CGSize {
        CommandBarPreferences.decodePositionOffset(
            UserDefaults.standard.string(forKey: DefaultsKey.commandBarPositionOffset) ?? "")
    }

    // MARK: - Moving the bar

    /// Clamps and saves only after the person's drag has ended. Programmatic
    /// positioning and content-driven resizing never rewrite this preference.
    func finishPanelDrag() {
        guard let panel else { return }
        let screen = panel.screen?.visibleFrame ?? panelScreen ?? NSScreen.pointerVisibleFrame
        panelScreen = screen
        let draggedOffset = CGSize(
            width: panel.frame.midX - screen.midX,
            height: panel.frame.maxY - (screen.minY + screen.height * 0.72))
        let origin = CommandBarPreferences.clampedPanelOrigin(
            size: panel.frame.size, in: screen, offset: draggedOffset)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        let offset = CGSize(width: panel.frame.midX - screen.midX,
                            height: panel.frame.maxY - (screen.minY + screen.height * 0.72))
        let encoded = CommandBarPreferences.encodePositionOffset(offset)
        if encoded.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.commandBarPositionOffset)
        } else {
            UserDefaults.standard.set(encoded, forKey: DefaultsKey.commandBarPositionOffset)
        }
        hasCustomPosition = !encoded.isEmpty
    }

    /// The way back: a double-click on the mark, or the button in Settings,
    /// returns the bar to the spot it opens on by default, with the same
    /// short slide it took on the way there.
    func resetPanelPosition() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.commandBarPositionOffset)
        hasCustomPosition = false
        guard let panel, panel.isVisible else { return }
        position(panel, animated: true)
    }

    // MARK: - Monitors

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }

            // While a language is composing a character (Japanese, Korean,
            // Chinese, and dead keys for accents) Return confirms the
            // candidate and the arrows walk it. Taking those keys here would
            // make the field unusable in five of the languages the app
            // speaks, so composition always wins.
            if self.fieldIsComposing(in: panel) { return event }

            // Listening for a combination: every key belongs to the person,
            // except the two that mean "never mind" and "take it off".
            if case .capturingShortcut(let entryID) = self.mode {
                switch Int(event.keyCode) {
                case kVK_Escape:
                    self.stepBack()
                case kVK_Delete, kVK_ForwardDelete:
                    if let entry = self.entry(withID: entryID) {
                        self.setRowShortcut(nil, for: entry)
                    }
                    self.stepBack()
                default:
                    let modifiers = GlobalShortcutModifiers(eventFlags: event.modifierFlags)
                    let shortcut = GlobalShortcut(keyCode: Int64(event.keyCode),
                                                  modifiers: modifiers)
                    // A bare letter would take that letter away from every app
                    // on the Mac, so the bar waits for a real combination.
                    guard CommandBarRowShortcuts.isUsable(shortcut) else {
                        NSSound.beep()
                        return nil
                    }
                    guard let entry = self.entry(withID: entryID) else {
                        self.stepBack()
                        return nil
                    }
                    // Full means full: the card stays up rather than closing on
                    // a combination that was never stored.
                    guard CommandBarRowShortcuts.hasRoom(for: entry.stableKey,
                                                         in: self.rowShortcuts) else {
                        NSSound.beep()
                        return nil
                    }
                    self.setRowShortcut(shortcut, for: entry)
                    self.stepBack()
                }
                return nil
            }

            if event.modifierFlags.contains(.command) {
                switch Int(event.keyCode) {
                case kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_M, kVK_ANSI_H:
                    // The app's menu owns these combinations and the panel is
                    // key, so they would quit, close or hide Vorssaint while
                    // the person believes they are acting on the app the bar
                    // is floating over.
                    return nil
                case kVK_ANSI_Comma:
                    self.hide()
                    SettingsRouter.shared.page = .commandBar
                    appDelegate()?.openSettingsWindow()
                    return nil
                default:
                    break
                }
            }
            if event.modifierFlags.contains(.command), Int(event.keyCode) == kVK_ANSI_K {
                self.openActions()
                return nil
            }
            // ⌘Return shows the selected row where it lives. Guarded by the
            // row's own rule, so a row with nowhere to go hands the keys back
            // and Return goes on meaning what it always did.
            if event.modifierFlags.contains(.command),
               Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter {
                if case .search = self.mode, let entry = self.selectedEntry,
                   entry.canRevealInFinder {
                    self.revealInFinder(entry)
                    return nil
                }
            }
            if event.modifierFlags.contains(.command), Int(event.keyCode) == kVK_ANSI_P {
                if let entry = self.selectedEntry, !entry.isAnswer,
                   CommandBarPreferences.acceptsPin(rowID: entry.id) {
                    self.togglePin(entry)
                }
                return nil
            }
            switch Int(event.keyCode) {
            case kVK_Escape:
                self.stepBack()
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.runSelected()
                return nil
            case kVK_UpArrow:
                if case .actions = self.mode { self.moveActionSelection(-1) } else { self.moveSelection(-1) }
                return nil
            case kVK_DownArrow:
                if case .actions = self.mode { self.moveActionSelection(1) } else { self.moveSelection(1) }
                return nil
            case kVK_LeftArrow:
                // Handed back untouched when the field has text in it.
                return self.moveCategory(-1) ? nil : event
            case kVK_RightArrow:
                return self.moveCategory(1) ? nil : event
            case kVK_Tab:
                self.completeSelection()
                return nil
            default:
                // ⌘1…⌘9 run by position; plain digits belong to the field.
                if event.modifierFlags.contains(.command),
                   let index = Self.digitIndex(for: event.keyCode) {
                    self.run(at: index)
                    return nil
                }
                let navigationModifiers = event.modifierFlags
                    .intersection([.command, .option, .shift, .control])
                if navigationModifiers == [.control],
                   let key = event.charactersIgnoringModifiers?.lowercased() {
                    // Match the typed letter so alternate keyboard layouts
                    // follow the keys the person sees.
                    switch key {
                    case "n":
                        if case .actions = self.mode { self.moveActionSelection(1) } else { self.moveSelection(1) }
                        return nil
                    case "p":
                        if case .actions = self.mode { self.moveActionSelection(-1) } else { self.moveSelection(-1) }
                        return nil
                    default:
                        break
                    }
                }
                // Typing while a confirmation is up takes the confirmation
                // down. Otherwise a destructive Return stays armed behind
                // what looks like an ordinary search.
                if case .confirm = self.mode { self.stepBack() }
                if case .naming = self.mode { self.aliasWarning = nil }
                return event
            }
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            let held = event.modifierFlags.contains(.command)
            if held != self.commandIsHeld { self.commandIsHeld = held }
            return event
        }
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hide()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel) {
                self.hide()
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            self.hide()
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        commandIsHeld = false
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    /// True while an input method is still composing in the field. The panel
    /// edits through a field editor, so the marked range lives there.
    private func fieldIsComposing(in panel: NSPanel) -> Bool {
        guard let responder = panel.firstResponder as? NSTextView else { return false }
        return responder.hasMarkedText()
    }

    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private static func digitIndex(for keyCode: UInt16) -> Int? {
        switch Int(keyCode) {
        case kVK_ANSI_1: return 0
        case kVK_ANSI_2: return 1
        case kVK_ANSI_3: return 2
        case kVK_ANSI_4: return 3
        case kVK_ANSI_5: return 4
        case kVK_ANSI_6: return 5
        case kVK_ANSI_7: return 6
        case kVK_ANSI_8: return 7
        case kVK_ANSI_9: return 8
        default: return nil
        }
    }
}
