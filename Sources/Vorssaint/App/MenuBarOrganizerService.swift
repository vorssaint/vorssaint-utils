// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine

/// Native per-app sections on macOS 27; physical dividers on earlier systems.
final class MenuBarOrganizerService: NSObject, ObservableObject, NSMenuDelegate {
    static let shared = MenuBarOrganizerService()
    private static let toggleName = "VorssaintMenuBarOrganizer"
    private static let hiddenName = "VorssaintMenuBarOrganizerHidden"
    private static let alwaysName = "VorssaintMenuBarOrganizerAlwaysHidden"
    private var toggleItem: NSStatusItem?
    private var hiddenItem: NSStatusItem?
    private var alwaysItem: NSStatusItem?
    @Published private(set) var isEnabled = false
    @Published private(set) var visibility = MenuBarOrganizerVisibility()
    @Published private(set) var failure: MenuBarNativeVisibility.Failure?
    @Published private(set) var isUpdating = false
    @Published private(set) var rules = MenuBarOrganizerRules()
    @Published private(set) var applications: [NSRunningApplication] = []
    @Published private(set) var items: [OrganizerMenuBarItem] = []
    @Published private(set) var accessibilityAvailable = AXIsProcessTrusted()
    @Published private(set) var presentedSection: MenuBarOrganizerSection?
    private var requestedVisibility = MenuBarOrganizerVisibility()
    private let nativeVisibility = MenuBarNativeVisibility()
    private let catalog = MenuBarItemCatalog()
    private let hiddenBar = MenuBarHiddenBarController()
    private let clockMonitor = MenuBarClockMonitor()
    private var clockInteractionActive = false
    private var clockRestore: DispatchWorkItem?
    private var refreshTimer: Timer?
    private var isRefreshing = false
    private var refreshGeneration = 0
    private var refreshCompletions: [() -> Void] = []
    private var activationGeneration = 0
    private var temporaryBundle: String?
    private var activationTimer: Timer?
    private var pressToken: MenuBarItemPressToken?
    private var legacyRestoreState: MenuBarOrganizerVisibility?
    private var legacySections: [String: MenuBarOrganizerSection] = [:]
    private weak var lastAnchor: NSStatusBarButton?
    private var screenFrames = NSScreen.screens.map(\.frame)
    var usesNativeVisibility: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }
    var failureMessage: String {
        let text = MenuBarOrganizerStrings.localized(L10n.shared.language)
        return failure == .applicationLocation ? text.applicationLocationNeeded : text.visibilityError
    }
    var onOpenSettings: (() -> Void)?
    private var subscriptions = Set<AnyCancellable>()

    private override init() {
        super.init()
        clockMonitor.onChange = { [weak self] overClock in
            self?.clockHoverChanged(overClock)
        }
        hiddenBar.onDismiss = { [weak self] in
            self?.presentedSection = nil
            self?.updateSections()
        }
        L10n.shared.$language.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateSections()
                if self?.presentedSection != nil { self?.presentHiddenBar() }
            }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                // Native hiding itself can change the usable menu bar area.
                // Explicit app rules do not need reclassification on that event.
                guard let self else { return }
                let frames = NSScreen.screens.map(\.frame)
                guard frames != self.screenFrames else { return }
                self.screenFrames = frames
                self.closeHiddenBar()
                if !self.usesNativeVisibility { self.revealAll() }
                if self.isEnabled { self.refreshApplications() }
            }
            .store(in: &subscriptions)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard self?.isEnabled == true else { return }
                    self?.refreshApplications { self?.synchronizeVisibility() }
                }.store(in: &subscriptions)
        }
    }

    func syncWithPreferences() {
        rules = MenuBarOrganizerRules(storage: UserDefaults.standard.dictionary(forKey: DefaultsKey.menuBarOrganizerSections) as? [String: String] ?? [:])
        setEnabled(UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerEnabled))
    }

    func setEnabled(_ requested: Bool) {
        let enabled = requested && AppFeature.menuBarOrganizer.isAvailable
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        failure = nil
        isUpdating = false
        refreshGeneration += 1
        clockRestore?.cancel()
        clockRestore = nil
        clockMonitor.stop()
        clockInteractionActive = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshCompletions = []
        isRefreshing = false
        cancelActivation(restoringLegacyState: false)
        closeHiddenBar()
        nativeVisibility.release()
        // Physical dividers start revealed for arranging. Native rules can
        // safely keep only the explicitly selected always-hidden apps folded.
        visibility.revealAll()
        requestedVisibility = visibility
        if enabled && usesNativeVisibility { requestedVisibility.toggleHidden() }
        if enabled {
            installItems()
            if usesNativeVisibility { clockMonitor.start() }
            // Discover real items while they are still visible,
            // before applying the saved hidden/always-hidden rules.
            refreshApplications { [weak self] in self?.synchronizeVisibility() }
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                self?.refreshApplications()
                if self?.usesNativeVisibility == true { self?.clockMonitor.refreshFrames() }
            }
        } else {
            applications = []
            items = []
            removeItems()
        }
    }

    @objc func toggleHiddenSection() {
        toggleHiddenBar(section: .hidden)
    }

    @objc func toggleAlwaysHiddenSection() {
        toggleHiddenBar(section: .alwaysHidden)
    }

    func revealAll() {
        cancelActivation(restoringLegacyState: false)
        closeHiddenBar()
        requestedVisibility.revealAll()
        synchronizeVisibility { [weak self] _ in self?.refreshApplications() }
    }

    func section(for bundle: String) -> MenuBarOrganizerSection { rules.section(for: bundle) }

    func hasApps(in section: MenuBarOrganizerSection) -> Bool {
        items.contains { self.section(for: $0.bundleID) == section }
    }

    func setSection(_ section: MenuBarOrganizerSection, for bundle: String) {
        guard !bundle.isEmpty, bundle != Bundle.main.bundleIdentifier, !bundle.hasPrefix("com.apple.") else { return }
        rules.set(section, for: bundle)
        UserDefaults.standard.set(rules.storage, forKey: DefaultsKey.menuBarOrganizerSections)
        cancelActivation(restoringLegacyState: true)
        // Selecting Hidden should hide immediately, even after Reveal All.
        if section != .visible, usesNativeVisibility {
            requestedVisibility.revealAll()
            requestedVisibility.toggleHidden()
        }
        synchronizeVisibility { [weak self] _ in
            self?.refreshApplications()
            if self?.presentedSection != nil { self?.presentHiddenBar() }
        }
    }

    func refreshApplications(completion: (() -> Void)? = nil) {
        guard isEnabled else { return }
        if let completion { refreshCompletions.append(completion) }
        guard !isRefreshing else { return }
        isRefreshing = true
        let generation = refreshGeneration
        catalog.scan { [weak self] current, trusted in
            guard let self, self.isEnabled, self.refreshGeneration == generation else { return }
            let permissionChanged = self.accessibilityAvailable != trusted
            self.accessibilityAvailable = trusted
            let previous = self.items
            let old = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let hidden = self.usesNativeVisibility
                ? self.rules.hiddenBundles(state: self.requestedVisibility,
                    ownBundleID: Bundle.main.bundleIdentifier ?? "com.vorssaint.utils")
                : Set(previous.filter { self.legacySections[$0.id] != .visible
                    && (!self.visibility.hiddenShown || !self.visibility.alwaysShown) }.map(\.bundleID))
            let alive = Set(previous.filter { !$0.application.isTerminated }.map { $0.descriptor.pid })
            let descriptors = MenuBarItemSupport.retainedItems(current: current.map(\.descriptor),
                previous: previous.map(\.descriptor), runningPIDs: alive, hiddenBundles: hidden)
            let fresh = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.items = descriptors.compactMap { fresh[$0.id] ?? old[$0.id] }
                .sorted { $0.descriptor.frame.minX < $1.descriptor.frame.minX }
            if !self.usesNativeVisibility, self.visibility.hiddenShown,
               let hidden = self.dividerX(self.hiddenItem), let always = self.dividerX(self.alwaysItem) {
                for item in current {
                    if self.visibility.alwaysShown || item.descriptor.frame.midX > always {
                        self.legacySections[item.id] = MenuBarItemSupport.section(at: item.descriptor.frame.midX,
                            hiddenBoundary: hidden, alwaysBoundary: always)
                    }
                }
            }
            var seen = Set<String>()
            self.applications = self.items.filter { seen.insert($0.bundleID).inserted }.map(\.application)
                .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
            self.isRefreshing = false
            if self.presentedSection != nil, previous.map(\.id) != self.items.map(\.id) { self.presentHiddenBar() }
            self.completeRefresh(permissionChanged: permissionChanged)
        }
    }

    private func completeRefresh(permissionChanged: Bool) {
        let callbacks = refreshCompletions
        refreshCompletions = []
        // Retry a failed launch and reconcile owners discovered after the
        // initial scan. Native visibility skips an unchanged active plan.
        if callbacks.isEmpty, permissionChanged || (usesNativeVisibility && !isUpdating) {
            synchronizeVisibility()
        }
        callbacks.forEach { $0() }
    }

    private func synchronizeVisibility(completion: ((Bool) -> Void)? = nil) {
        guard isEnabled, toggleItem != nil else { completion?(false); return }
        let target = requestedVisibility
        failure = nil
        guard usesNativeVisibility else {
            visibility = target
            updateSections()
            completion?(true)
            return
        }
        isUpdating = true
        guard accessibilityAvailable else {
            nativeVisibility.release()
            isUpdating = false
            visibility.revealAll()
            updateSections()
            completion?(false)
            return
        }
        // Assessment mode suppresses Notification Center. Release it before
        // the user clicks the clock without changing their requested sections.
        if clockInteractionActive {
            nativeVisibility.release()
            isUpdating = false
            visibility = target
            updateSections()
            completion?(true)
            return
        }
        var hidden = rules.hiddenBundles(state: target,
            ownBundleID: Bundle.main.bundleIdentifier ?? "com.vorssaint.utils")
        if let temporaryBundle { hidden.remove(temporaryBundle) }
        nativeVisibility.apply(hiddenBundles: hidden, menuBarOwners: applications) { [weak self] error in
            guard let self else { return }
            self.isUpdating = false
            if let error {
                self.failure = error as? MenuBarNativeVisibility.Failure ?? .activation
                self.nativeVisibility.release()
                // Keep the requested plan so a transient startup/XPC failure
                // can recover on the next refresh without a system restart.
                self.visibility.revealAll()
            } else {
                self.visibility = target
            }
            self.updateSections()
            completion?(error == nil)
        }
    }

    private func clockHoverChanged(_ overClock: Bool) {
        guard isEnabled, usesNativeVisibility else { return }
        clockRestore?.cancel()
        clockRestore = nil
        if overClock {
            clockInteractionActive = true
            nativeVisibility.release()
            isUpdating = false
        } else {
            // Let the system finish opening the panel before restoring hiding.
            let restore = DispatchWorkItem { [weak self] in
                guard let self, self.isEnabled else { return }
                self.clockInteractionActive = false
                self.clockRestore = nil
                self.synchronizeVisibility()
            }
            clockRestore = restore
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: restore)
        }
    }

    private func closeHiddenBar() {
        hiddenBar.hide()
        presentedSection = nil
        updateSections()
    }

    private func toggleHiddenBar(section: MenuBarOrganizerSection) {
        guard isEnabled else { return }
        if presentedSection == section { closeHiddenBar(); return }
        cancelActivation(restoringLegacyState: true)
        // Keep the main bar folded. Reveal All remains an explicit arranging
        // command; clicking the arrow presents the separate shelf instead.
        requestedVisibility.revealAll()
        requestedVisibility.toggleHidden()
        presentedSection = section
        refreshApplications { [weak self] in
            guard let self, self.presentedSection == section else { return }
            self.synchronizeVisibility()
            self.presentHiddenBar()
        }
    }

    private func presentHiddenBar(message: String? = nil) {
        guard let presentedSection, isEnabled else { return }
        let text = MenuBarOrganizerStrings.localized(L10n.shared.language)
        let selected = items.filter { item in
            if usesNativeVisibility {
                let section = section(for: item.bundleID)
                return section == .hidden || (presentedSection == .alwaysHidden && section == .alwaysHidden)
            }
            // Older systems assign sections by the physical Command-drag
            // boundaries. Use cached positions from before they were folded.
            let section = legacySections[item.id] ?? .visible
            return section == .hidden || (presentedSection == .alwaysHidden && section == .alwaysHidden)
        }
        hiddenBar.show(items: selected, anchor: lastAnchor ?? toggleItem?.button,
            message: accessibilityAvailable ? message : text.accessibilityNeeded,
            needsAccessibility: !accessibilityAvailable,
            activate: { [weak self] in self?.activateItem($0) }, menu: { [weak self] item in
                self?.itemMenu(item) ?? NSMenu()
            })
        updateSections()
    }

    private func itemMenu(_ item: OrganizerMenuBarItem) -> NSMenu {
        let text = MenuBarOrganizerStrings.localized(L10n.shared.language)
        let menu = NSMenu(title: item.name)
        menu.autoenablesItems = false
        menu.userInterfaceLayoutDirection = MenuBarOrganizerStrings.isRightToLeft(L10n.shared.language) ? .rightToLeft : .leftToRight
        if usesNativeVisibility {
            for (section, title) in [(MenuBarOrganizerSection.visible, text.visible),
                                     (.hidden, text.hiddenSection), (.alwaysHidden, text.alwaysHiddenSection)] {
                let choice = NSMenuItem(title: title, action: #selector(selectSection(_:)), keyEquivalent: "")
                choice.target = self
                choice.representedObject = ["bundle": item.bundleID, "section": section.rawValue]
                choice.state = self.section(for: item.bundleID) == section ? .on : .off
                choice.isEnabled = !isUpdating
                menu.addItem(choice)
            }
            menu.addItem(.separator())
        }
        let reveal = NSMenuItem(title: text.revealAll, action: #selector(revealAllFromMenu), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        return menu
    }

    private func activateItem(_ item: OrganizerMenuBarItem) {
        guard isEnabled, accessibilityAvailable else { return }
        cancelActivation(restoringLegacyState: true)
        closeHiddenBar()
        temporaryBundle = item.bundleID
        if !usesNativeVisibility {
            legacyRestoreState = requestedVisibility
            requestedVisibility.revealAll()
        }
        let generation = activationGeneration
        let existing = Set(WindowServerSupport.onScreenWindowInfo().compactMap {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })
        synchronizeVisibility { [weak self] success in
            guard let self, self.isEnabled, self.activationGeneration == generation else { return }
            guard success else { self.finishActivation(); return }
            let token = MenuBarItemPressToken()
            self.pressToken = token
            self.catalog.press(item, token: token) { [weak self] opened in
                guard let self, self.isEnabled, self.activationGeneration == generation else { return }
                guard let opened else {
                    self.finishActivation()
                    self.presentedSection = .hidden
                    self.presentHiddenBar(message: MenuBarOrganizerStrings.localized(L10n.shared.language).itemUnavailable)
                    return
                }
                let started = ProcessInfo.processInfo.systemUptime
                let agentPID = NSWorkspace.shared.runningApplications.first {
                    $0.bundleIdentifier == "com.apple.MenuBarAgent"
                }?.processIdentifier
                var querying = false
                self.activationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    let elapsed = ProcessInfo.processInfo.systemUptime - started
                    guard elapsed > 1, !querying else { return }
                    querying = true
                    let hasPopup = WindowServerSupport.onScreenWindowInfo().contains { window in
                        let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                        let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
                        let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
                        return (pid == item.descriptor.pid || pid == agentPID) && !existing.contains(id)
                            && layer >= Int(CGWindowLevelForKey(.floatingWindow))
                            && (WindowServerSupport.bounds(from: window)?.height ?? 0) > 40
                    }
                    self.catalog.menuIsOpen(for: opened) { [weak self] menuOpen in
                        querying = false
                        guard let self, self.activationGeneration == generation else { return }
                        if (!menuOpen && !hasPopup) || item.application.isTerminated { self.finishActivation() }
                    }
                }
            }
        }
    }

    private func cancelActivation(restoringLegacyState: Bool) {
        activationGeneration += 1
        pressToken?.cancel()
        pressToken = nil
        activationTimer?.invalidate()
        activationTimer = nil
        temporaryBundle = nil
        if restoringLegacyState, let legacyRestoreState { requestedVisibility = legacyRestoreState }
        legacyRestoreState = nil
    }

    private func finishActivation() {
        cancelActivation(restoringLegacyState: true)
        synchronizeVisibility { [weak self] _ in self?.refreshApplications() }
    }

    private func dividerX(_ item: NSStatusItem?) -> CGFloat? {
        guard let button = item?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).midX
    }

    @objc private func controlClicked() {
        lastAnchor = toggleItem?.button
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() }
        else if NSApp.currentEvent?.modifierFlags.contains(.option) == true { toggleAlwaysHiddenSection() }
        else { toggleHiddenSection() }
    }

    @objc private func hiddenClicked() {
        lastAnchor = hiddenItem?.button
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() }
        else { toggleHiddenSection() }
    }

    @objc private func alwaysClicked() {
        lastAnchor = alwaysItem?.button
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() }
        else { toggleAlwaysHiddenSection() }
    }

    private func installItems() {
        // Migrate our old seed, which left the recovery arrow in system overflow.
        let positionKey = Self.positionKey(Self.toggleName)
        if UserDefaults.standard.double(forKey: positionKey) == 200 {
            UserDefaults.standard.set(24, forKey: positionKey)
        }
        toggleItem = makeItem(Self.toggleName, position: 24, title: "", action: #selector(controlClicked))
        if !usesNativeVisibility {
            hiddenItem = makeItem(Self.hiddenName, position: 224, title: "│", action: #selector(hiddenClicked))
            alwaysItem = makeItem(Self.alwaysName, position: 248, title: "‖", action: #selector(alwaysClicked))
        }
        updateSections()
    }

    private func makeItem(_ name: String, position: Double, title: String, action: Selector) -> NSStatusItem {
        let key = Self.positionKey(name)
        // Preferred Position is a distance from the right edge, not an index.
        // Replace only the unusable 0/1/2 seeds from the initial implementation.
        if UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.double(forKey: key) <= 2 {
            UserDefaults.standard.set(position, forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Visible \(name)")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC \(name)")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = name
        item.behavior = []
        item.isVisible = true
        item.button?.title = title
        item.button?.target = self
        item.button?.action = action
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return item
    }

    private func updateSections() {
        guard let toggleItem else { return }
        let text = MenuBarOrganizerStrings.localized(L10n.shared.language)
        let length = MenuBarOrganizerVisibility.collapsedLength(
            systemMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            displayWidths: NSScreen.screens.map { $0.frame.width })
        toggleItem.length = NSStatusItem.squareLength
        let image = NSImage(systemSymbolName: presentedSection == nil ? "chevron.down" : "chevron.up",
                            accessibilityDescription: text.title)
        image?.isTemplate = true
        toggleItem.button?.image = image
        toggleItem.button?.imagePosition = .imageOnly
        toggleItem.button?.toolTip = text.title
        toggleItem.button?.setAccessibilityLabel(text.title)
        if let hiddenItem, let alwaysItem {
            apply(hiddenItem, shown: visibility.hiddenShown, title: "│", label: text.hiddenSection, length: length)
            apply(alwaysItem, shown: visibility.alwaysShown, title: "‖", label: text.alwaysHiddenSection, length: length)
        }
    }

    private func apply(_ item: NSStatusItem, shown: Bool, title: String, label: String, length: CGFloat) {
        let native = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        item.length = shown || native ? NSStatusItem.squareLength : length
        item.button?.title = shown || native ? title : ""
        item.button?.cell?.isEnabled = shown || native
        item.button?.toolTip = label
        item.button?.setAccessibilityLabel(label)
    }

    private func removeItems() {
        for item in [toggleItem, hiddenItem, alwaysItem].compactMap({ $0 }) {
            let key = Self.positionKey(item.autosaveName)
            let position = UserDefaults.standard.object(forKey: key)
            NSStatusBar.system.removeStatusItem(item)
            if let position { UserDefaults.standard.set(position, forKey: key) }
        }
        toggleItem = nil
        hiddenItem = nil
        alwaysItem = nil
    }

    private static func positionKey(_ name: String) -> String {
        "NSStatusItem Preferred Position \(name)"
    }

    /// Shared by the dedicated arrow and every Vorssaint status item's menu.
    /// A control in the system's overflow must never force a trip to Settings.
    func makeMenu(anchor: NSStatusBarButton? = nil) -> NSMenu {
        if let anchor { lastAnchor = anchor }
        refreshApplications()
        let text = MenuBarOrganizerStrings.localized(L10n.shared.language)
        let menu = NSMenu(title: text.title)
        menu.userInterfaceLayoutDirection = MenuBarOrganizerStrings.isRightToLeft(L10n.shared.language) ? .rightToLeft : .leftToRight
        menu.autoenablesItems = false
        if !isEnabled {
            let enable = NSMenuItem(title: text.enabled, action: #selector(enableFromMenu), keyEquivalent: "")
            enable.target = self
            menu.addItem(enable)
            return menu
        }
        for (title, action, enabled) in [
            (presentedSection == .hidden ? text.hideSection : text.showSection, #selector(toggleHiddenSection), true),
            (presentedSection == .alwaysHidden ? text.hideAlwaysHidden : text.showAlwaysHidden, #selector(toggleAlwaysHiddenSection), true),
            (text.revealAll, #selector(revealAllFromMenu), true),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            menu.addItem(item)
        }
        if usesNativeVisibility {
            menu.addItem(.separator())
            let applicationsItem = NSMenuItem(title: text.applications, action: nil, keyEquivalent: "")
            let applicationsMenu = NSMenu(title: text.applications)
            applicationsMenu.userInterfaceLayoutDirection = menu.userInterfaceLayoutDirection
            for app in applications {
                guard let bundle = app.bundleIdentifier else { continue }
                let appItem = NSMenuItem(title: app.localizedName ?? bundle, action: nil, keyEquivalent: "")
                let icon = app.icon?.copy() as? NSImage
                icon?.size = NSSize(width: 16, height: 16)
                appItem.image = icon
                let sections = NSMenu(title: appItem.title)
                sections.autoenablesItems = false
                sections.userInterfaceLayoutDirection = menu.userInterfaceLayoutDirection
                for (section, title) in [(MenuBarOrganizerSection.visible, text.visible),
                                         (.hidden, text.hiddenSection), (.alwaysHidden, text.alwaysHiddenSection)] {
                    let choice = NSMenuItem(title: title, action: #selector(selectSection(_:)), keyEquivalent: "")
                    choice.target = self
                    choice.representedObject = ["bundle": bundle, "section": section.rawValue]
                    choice.state = self.section(for: bundle) == section ? .on : .off
                    choice.isEnabled = !isUpdating
                    sections.addItem(choice)
                }
                appItem.submenu = sections
                applicationsMenu.addItem(appItem)
            }
            applicationsItem.submenu = applicationsMenu
            menu.addItem(applicationsItem)
        }
        if failure != nil {
            menu.addItem(.separator())
            let error = NSMenuItem(title: failureMessage, action: nil, keyEquivalent: "")
            error.isEnabled = false
            menu.addItem(error)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: text.settings, action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        return menu
    }

    func makeDynamicMenu() -> NSMenu {
        let menu = NSMenu(title: MenuBarOrganizerStrings.localized(L10n.shared.language).title)
        menu.delegate = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let fresh = makeMenu()
        menu.autoenablesItems = false
        menu.userInterfaceLayoutDirection = fresh.userInterfaceLayoutDirection
        menu.removeAllItems()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }

    @objc private func enableFromMenu() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.menuBarOrganizerEnabled)
        setEnabled(true)
    }

    private func showMenu() {
        guard let toggleItem else { return }
        toggleItem.menu = makeMenu()
        toggleItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak toggleItem] in toggleItem?.menu = nil }
    }

    @objc private func revealAllFromMenu() { revealAll() }

    @objc private func selectSection(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? [String: String],
              let bundle = choice["bundle"], let raw = choice["section"],
              let section = MenuBarOrganizerSection(rawValue: raw) else { return }
        setSection(section, for: bundle)
    }

    @objc private func openSettings() { onOpenSettings?() }
}
