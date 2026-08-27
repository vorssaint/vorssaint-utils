// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Service managing the Menu Bar Hider feature.
/// Operates exclusively through native AppKit NSStatusItem mechanisms with
/// 0% CPU overhead at rest and zero invasive permissions.
final class MenuBarHiderService: NSResponder, ObservableObject {
    static let shared = MenuBarHiderService()

    @Published private(set) var isCollapsed: Bool = false
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var isConfiguring: Bool = false

    private var toggleItem: NSStatusItem?
    private var separatorItem: NSStatusItem?
    private var alwaysHiddenItem: NSStatusItem?

    private var autoCollapseTimer: Timer?
    private var hoverWatchdogTimer: Timer?
    private var didExpandFromHover = false
    private var pointerLeftToggleAt: TimeInterval?
    private let hotkey = QuickToolHotkey(id: 30)
    private var isShowingAll: Bool = false
    private var trackingArea: NSTrackingArea?
    private weak var trackingButton: NSStatusBarButton?
    private var scrollMonitor: Any?
    private var lastScrollToggleTime: TimeInterval = 0
    private var lastToggleClickTimestamp: TimeInterval = 0
    private var didRevealInClickSequence = false

    override private init() {
        super.init()
        hotkey.onPress = { [weak self] in
            self?.toggle()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        removeScrollMonitor()
    }

    // MARK: - Lifecycle & Preferences Sync

    func syncWithPreferences() {
        let isAvailable = AppFeature.menuBarHider.isAvailable
        let enabled = isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderEnabled)
        isEnabled = enabled

        syncHotkey()

        if enabled {
            installOrUpdateItems()
            setupScrollMonitor()
            // Arm the idle timer for the state we are actually in. Installing
            // the items does not do it, so a relaunch that restores an expanded
            // bar never collapsed, and switching auto-collapse on only took
            // effect after the next manual expand.
            if !isCollapsed && !isConfiguring {
                restartAutoCollapseTimerIfNeeded()
            }
        } else {
            teardown()
        }
    }

    func resetSeparatorPositions() {
        teardown()
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(MenuBarHiderSupport.toggleAutosaveName)")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(MenuBarHiderSupport.separatorAutosaveName)")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(MenuBarHiderSupport.alwaysHiddenAutosaveName)")
        UserDefaults.standard.synchronize()
        installOrUpdateItems()
        setupScrollMonitor()
        beginConfigurationMode()
        triggerHapticFeedback()
    }

    private func syncHotkey() {
        let shortcutEnabled = AppFeature.menuBarHider.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.menuBarHiderShortcut,
                                            fallback: .menuBarHiderDefault)
        hotkey.sync(enabled: shortcutEnabled, shortcut: shortcut)
    }

    private func installOrUpdateItems() {
        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)
        var didCreateToggle = false

        // 1. Toggle Item
        if toggleItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = MenuBarHiderSupport.toggleAutosaveName
            item.behavior = []
            item.isVisible = true
            toggleItem = item
            didCreateToggle = true
        }

        // 2. Main Separator Item
        if separatorItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: CGFloat(MenuBarHiderSupport.normalSeparatorWidth))
            item.autosaveName = MenuBarHiderSupport.separatorAutosaveName
            item.behavior = []
            item.isVisible = true
            separatorItem = item
        }

        // 3. Always Hidden Separator Item
        if alwaysHiddenEnabled {
            if alwaysHiddenItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: CGFloat(MenuBarHiderSupport.normalAlwaysHiddenWidth))
                item.autosaveName = MenuBarHiderSupport.alwaysHiddenAutosaveName
                item.behavior = []
                item.isVisible = true
                alwaysHiddenItem = item
            }
        } else {
            if let alwaysHiddenItem {
                NSStatusBar.system.removeStatusItem(alwaysHiddenItem)
                self.alwaysHiddenItem = nil
            }
        }

        // Pick the collapse state back up from the previous run, but only when
        // the items were just created: syncWithPreferences() runs on every
        // settings change and must not clobber the state on screen right now.
        if didCreateToggle {
            isCollapsed = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderCollapsed)
            isShowingAll = false
        }

        configureItemButtons()
        updateItemAppearances()
    }

    // MARK: - Auto-Healing Status Item Ordering

    private func autoHealItemOrdering() {
        guard isEnabled else { return }

        var activeItems: [NSStatusItem] = []
        if let alwaysHiddenItem { activeItems.append(alwaysHiddenItem) }
        if let separatorItem { activeItems.append(separatorItem) }
        if let toggleItem { activeItems.append(toggleItem) }

        guard activeItems.count >= 2 else { return }

        let itemsWithX = activeItems.compactMap { item -> (item: NSStatusItem, x: CGFloat)? in
            guard let window = item.button?.window else { return nil }
            return (item, window.frame.origin.x)
        }

        guard itemsWithX.count == activeItems.count else { return }
        let distinctPositions = Set(itemsWithX.map(\.x))
        guard distinctPositions.count == itemsWithX.count else { return }

        let sorted = itemsWithX.sorted { $0.x < $1.x }.map(\.item)

        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)

        if alwaysHiddenEnabled && sorted.count >= 3 {
            alwaysHiddenItem = sorted[0]
            separatorItem = sorted[1]
            toggleItem = sorted[2]
        } else if sorted.count >= 2 {
            separatorItem = sorted[sorted.count - 2]
            toggleItem = sorted[sorted.count - 1]
        }
    }

    private func configureItemButtons() {
        let style = currentIconStyle
        let strings = FeatureStrings.menuBarHider(L10n.shared.language)
        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)

        // 1. Toggle button (Always on the right)
        if let toggleButton = toggleItem?.button {
            toggleButton.subviews.removeAll(where: { $0 is MenuBarHiderSeparatorView })
            toggleButton.target = self
            toggleButton.action = #selector(toggleClicked)
            toggleButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // A symbol name the running system does not ship resolves to nil,
            // and a variable-length item with neither image nor title collapses
            // to zero width — the toggle would simply vanish. Fall back to the
            // chevron, and to a text glyph if even that is unavailable.
            let symbolName = MenuBarHiderSupport.toggleSymbolName(isCollapsed: isCollapsed, style: style)
            let fallbackName = MenuBarHiderSupport.toggleSymbolName(isCollapsed: isCollapsed, style: .chevron)
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: strings.pageTitle)
                ?? NSImage(systemSymbolName: fallbackName, accessibilityDescription: strings.pageTitle)
            if let image {
                image.isTemplate = true
                toggleButton.image = image
                toggleButton.title = ""
            } else {
                toggleButton.image = nil
                toggleButton.title = isCollapsed ? "‹" : "›"
            }
            toggleButton.toolTip = MenuBarHiderSupport.toggleTooltip(
                isCollapsed: isCollapsed,
                isShowingAll: isShowingAll,
                alwaysHiddenEnabled: alwaysHiddenEnabled,
                strings: strings
            )
            setupTrackingArea()
        }

        // 2. Main separator (To the left of toggle)
        if let separatorButton = separatorItem?.button {
            separatorButton.target = self
            separatorButton.action = #selector(separatorClicked)
            separatorButton.sendAction(on: [.leftMouseUp])
            separatorButton.image = nil
            separatorButton.title = ""
            separatorButton.toolTip = strings.tooltipSeparator

            var drawView = separatorButton.subviews.first(where: { $0 is MenuBarHiderSeparatorView }) as? MenuBarHiderSeparatorView
            if drawView == nil {
                let v = MenuBarHiderSeparatorView(frame: separatorButton.bounds)
                separatorButton.addSubview(v)
                drawView = v
            }
            drawView?.symbol = "|"
            drawView?.isBold = false
            drawView?.isVisibleGlyph = true
        }

        // 3. Always hidden separator (Leftmost)
        if let alwaysHiddenButton = alwaysHiddenItem?.button {
            alwaysHiddenButton.target = self
            alwaysHiddenButton.action = #selector(alwaysHiddenClicked)
            alwaysHiddenButton.sendAction(on: [.leftMouseUp])
            alwaysHiddenButton.image = nil
            alwaysHiddenButton.title = ""
            alwaysHiddenButton.toolTip = strings.tooltipAlwaysHidden

            var drawView = alwaysHiddenButton.subviews.first(where: { $0 is MenuBarHiderSeparatorView }) as? MenuBarHiderSeparatorView
            if drawView == nil {
                let v = MenuBarHiderSeparatorView(frame: alwaysHiddenButton.bounds)
                alwaysHiddenButton.addSubview(v)
                drawView = v
            }
            drawView?.symbol = "‖"
            drawView?.isBold = true
            drawView?.isVisibleGlyph = true
        }
    }

    @objc private func windowDidMove(_ notification: Notification) {
        guard isEnabled else { return }
        guard let movedWindow = notification.object as? NSWindow else { return }
        let isOurWindow = (movedWindow == toggleItem?.button?.window) ||
                          (movedWindow == separatorItem?.button?.window) ||
                          (movedWindow == alwaysHiddenItem?.button?.window)
        if isOurWindow {
            autoHealItemOrdering()
            updateItemAppearances()
        }
    }

    private func teardown() {
        stopAutoCollapseTimer()
        stopHoverWatchdog()
        didExpandFromHover = false
        removeTrackingArea()
        removeScrollMonitor()
        if let toggleItem {
            NSStatusBar.system.removeStatusItem(toggleItem)
            self.toggleItem = nil
        }
        if let separatorItem {
            NSStatusBar.system.removeStatusItem(separatorItem)
            self.separatorItem = nil
        }
        if let alwaysHiddenItem {
            NSStatusBar.system.removeStatusItem(alwaysHiddenItem)
            self.alwaysHiddenItem = nil
        }
        isCollapsed = false
        isShowingAll = false
        isConfiguring = false
    }

    // MARK: - Haptic Feedback

    private func triggerHapticFeedback() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderHapticFeedback) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    // MARK: - State Management

    func toggle() {
        if isCollapsed {
            expand()
        } else {
            collapse()
        }
    }

    func expand(startTimer: Bool = true) {
        didExpandFromHover = false
        let wasCollapsed = isCollapsed
        isCollapsed = false
        isShowingAll = false
        updateItemAppearances()
        persistCollapsedState()
        if wasCollapsed {
            triggerHapticFeedback()
        }

        if startTimer && !isConfiguring {
            restartAutoCollapseTimerIfNeeded()
        } else {
            stopAutoCollapseTimer()
        }
    }

    func collapse() {
        let wasExpanded = !isCollapsed || isShowingAll
        stopAutoCollapseTimer()
        stopHoverWatchdog()
        didExpandFromHover = false
        isCollapsed = true
        isShowingAll = false
        updateItemAppearances()
        persistCollapsedState()
        if wasExpanded {
            triggerHapticFeedback()
        }
    }

    func showAll(startTimer: Bool = true) {
        didExpandFromHover = false
        isCollapsed = false
        isShowingAll = true
        updateItemAppearances()
        persistCollapsedState()
        triggerHapticFeedback()

        if startTimer && !isConfiguring {
            restartAutoCollapseTimerIfNeeded()
        } else {
            stopAutoCollapseTimer()
        }
    }

    func beginConfigurationMode() {
        isConfiguring = true
        stopAutoCollapseTimer()
        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)
        if alwaysHiddenEnabled {
            showAll(startTimer: false)
        } else {
            expand(startTimer: false)
        }
    }

    func endConfigurationMode() {
        isConfiguring = false
        if !isCollapsed {
            restartAutoCollapseTimerIfNeeded()
        }
    }

    /// Carries the collapse state across relaunches. `isShowingAll` deliberately
    /// does not persist: revealing the always-hidden section is a momentary
    /// action, not a layout the app should come back in.
    private func persistCollapsedState() {
        UserDefaults.standard.set(isCollapsed, forKey: DefaultsKey.menuBarHiderCollapsed)
    }

    private var currentIconStyle: MenuBarHiderIconStyle {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.menuBarHiderIconStyle) ?? ""
        return MenuBarHiderIconStyle(rawValue: raw) ?? .chevron
    }

    private var currentDisplayState: MenuBarHiderSupport.DisplayState {
        if isShowingAll {
            return .showAll
        }
        return isCollapsed ? .collapsed : .expanded
    }

    /// Width of the menu bar strip the status items actually occupy. On a
    /// notched Mac that is the area left of the notch, which is far narrower
    /// than the screen; sizing the separators off `frame.width` there asks for
    /// an item many times wider than the bar it lives in.
    private var usableMenuBarWidth: Double {
        guard let screen = toggleItem?.button?.window?.screen ?? NSScreen.main else {
            return MenuBarHiderSupport.fallbackUsableWidth
        }
        if let leftOfNotch = screen.auxiliaryTopLeftArea {
            return Double(leftOfNotch.width)
        }
        return Double(screen.frame.width)
    }

    private func updateItemAppearances() {
        autoHealItemOrdering()
        configureItemButtons()

        let state = currentDisplayState
        let width = usableMenuBarWidth
        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)

        // The toggle can have inherited a role whose length was expanded to
        // 10,000 px, so it has to be reset alongside the separators or a ⌘-drag
        // reorder leaves it eating the whole menu bar.
        toggleItem?.length = NSStatusItem.variableLength

        // Update main separator length
        if let separatorItem {
            let length = MenuBarHiderSupport.separatorLength(state: state, usableWidth: width)
            separatorItem.length = CGFloat(length)
        }

        // Update always-hidden separator length
        if let alwaysHiddenItem {
            let length = MenuBarHiderSupport.alwaysHiddenLength(state: state, usableWidth: width, isEnabled: alwaysHiddenEnabled)
            alwaysHiddenItem.length = CGFloat(length)
        }
    }

    @objc private func screenParametersChanged() {
        updateItemAppearances()
    }

    // MARK: - Tracking Area & Hover

    private func setupTrackingArea() {
        guard let button = toggleItem?.button else { return }
        // Rebuilding this on every appearance update tore the area down with the
        // cursor inside it and installed a fresh one, which AppKit does not
        // consider entered — so the matching mouseExited never arrived and a
        // hover-expanded bar stayed open. The area tracks `inVisibleRect`, so it
        // follows the button through length changes on its own.
        if trackingArea != nil, trackingButton === button { return }
        removeTrackingArea()
        let area = NSTrackingArea(rect: button.bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        button.addTrackingArea(area)
        trackingArea = area
        trackingButton = button
    }

    private func removeTrackingArea() {
        // Not toggleItem?.button: auto-healing may have rebound the toggle to a
        // different status item since the area was installed, and the area
        // belongs to whichever button actually received it.
        if let trackingArea, let trackingButton {
            trackingButton.removeTrackingArea(trackingArea)
        }
        trackingArea = nil
        trackingButton = nil
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        // Deliberately does not stop the watchdog: re-entering a bar that hover
        // already opened would otherwise leave it with nothing watching, and it
        // would never close again. The watchdog clears its own timestamp when it
        // sees the pointer back inside.
        let expandOnHover = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderExpandOnHover)
        if expandOnHover, isCollapsed {
            expand(startTimer: true)
            // Set after expanding: expand() clears the flag so that a bar opened
            // any other way is not closed by the cursor wandering off.
            didExpandFromHover = true
            startHoverWatchdog()
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        guard !isCollapsed, !isConfiguring else { return }
        if didExpandFromHover { return }
        restartAutoCollapseTimerIfNeeded()
    }

    /// Watches where the pointer actually is while the bar is open on hover.
    ///
    /// Opening on hover has to close on leave, and mouseExited alone cannot
    /// carry that: expanding changes the status item lengths, and AppKit is free
    /// to rebuild the item windows underneath, so the exit event for the button
    /// the cursor started on may never arrive. Asking for the pointer position
    /// does not depend on any of that. It runs only while a hover-opened bar is
    /// showing and stops the moment it closes.
    private func startHoverWatchdog() {
        stopHoverWatchdog()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.collapseIfPointerLeftToggle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverWatchdogTimer = timer
    }

    private func collapseIfPointerLeftToggle() {
        guard isEnabled, didExpandFromHover, !isConfiguring, !isCollapsed else {
            stopHoverWatchdog()
            return
        }
        guard let window = toggleItem?.button?.window else { return }
        if window.frame.contains(NSEvent.mouseLocation) {
            pointerLeftToggleAt = nil
            return
        }
        let now = Date().timeIntervalSince1970
        guard let leftAt = pointerLeftToggleAt else {
            pointerLeftToggleAt = now
            return
        }
        // Grace period so brushing past on the way somewhere else does not
        // snap the bar shut.
        if now - leftAt >= MenuBarHiderSupport.hoverCollapseDelay {
            stopHoverWatchdog()
            collapse()
        }
    }

    private func stopHoverWatchdog() {
        hoverWatchdogTimer?.invalidate()
        hoverWatchdogTimer = nil
        pointerLeftToggleAt = nil
    }

    // MARK: - Scroll to Toggle

    private func setupScrollMonitor() {
        removeScrollMonitor()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event)
            return event
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    private func handleScrollEvent(_ event: NSEvent) {
        guard isEnabled else { return }
        let scrollToToggle = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderScrollToToggle)
        guard scrollToToggle else { return }
        guard let button = toggleItem?.button, let window = button.window else { return }

        // Check if mouse is over the toggle status item
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = window.frame
        guard windowFrame.contains(mouseLocation) else { return }

        let delta = abs(event.scrollingDeltaY) > 0 ? event.scrollingDeltaY : event.scrollingDeltaX
        guard abs(delta) > 1.5 else { return }

        let now = Date().timeIntervalSince1970
        guard now - lastScrollToggleTime > 0.35 else { return }
        lastScrollToggleTime = now

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if delta > 0 {
                if self.isCollapsed {
                    self.expand()
                }
            } else {
                if !self.isCollapsed {
                    self.collapse()
                }
            }
        }
    }


    // MARK: - Actions

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggle()
            return
        }

        // 1. Ignore clicks while holding Command (the user is dragging/reordering icons)
        if event.modifierFlags.contains(.command) {
            return
        }

        // 2. Right-click or Control+Click -> Context Menu
        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            showContextMenu(from: sender)
            return
        }

        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)

        // 3. Option+Click reveals the always-hidden section outright. It stays
        //    out of the click-sequence bookkeeping below: it is a complete
        //    gesture on its own, and a plain click right after it should still
        //    collapse rather than be swallowed as a gesture tail.
        if alwaysHiddenEnabled && event.modifierFlags.contains(.option) {
            lastToggleClickTimestamp = event.timestamp
            toggleAlwaysHiddenSection()
            return
        }

        // 4. The button sends one action per mouse-up, so a double click cannot
        //    be told from the first half of one without either holding every
        //    single click for the double-click interval or letting the second
        //    click supersede the first. Holding taxes the gesture people make
        //    constantly, so this acts immediately and escalates instead: no
        //    click ever waits, and the first click's outcome is a state the
        //    person asked for rather than a guess that has to be undone.
        //
        //    The sequence comes from `clickCount`, which AppKit resets only
        //    after the interval passes with no further click; timing the pairing
        //    here instead re-armed it on every click, so a rapid burst escalated
        //    on every second one. The gap is checked as well, because AppKit
        //    counts against the system double-click interval and that is far
        //    wider than the gesture: two deliberate collapse/expand presses fall
        //    inside it and must stay two toggles, not one reveal.
        let gap = event.timestamp - lastToggleClickTimestamp
        lastToggleClickTimestamp = event.timestamp
        let withinGesture = gap <= MenuBarHiderSupport.revealGestureInterval(
            systemDoubleClickInterval: NSEvent.doubleClickInterval)

        if event.clickCount <= 1 {
            didRevealInClickSequence = false
            performSingleClickToggle()
            return
        }
        // Once a sequence has revealed, further clicks in it are the tail of a
        // gesture already carried out.
        guard !didRevealInClickSequence else { return }
        if event.clickCount == 2, alwaysHiddenEnabled, !isShowingAll, withinGesture {
            didRevealInClickSequence = true
            showAll()
            return
        }
        performSingleClickToggle()
    }

    private func performSingleClickToggle() {
        if isShowingAll {
            collapse()
        } else {
            toggle()
        }
    }

    private func toggleAlwaysHiddenSection() {
        if isShowingAll {
            collapse()
        } else {
            showAll()
        }
    }

    @objc private func separatorClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggle()
            return
        }
        if event.modifierFlags.contains(.command) {
            return
        }
        toggle()
    }

    @objc private func alwaysHiddenClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleAlwaysHiddenSection()
            return
        }
        if event.modifierFlags.contains(.command) {
            return
        }
        toggleAlwaysHiddenSection()
    }

    private func showContextMenu(from sender: NSStatusBarButton) {
        let strings = FeatureStrings.menuBarHider(L10n.shared.language)
        let menu = NSMenu()

        if isCollapsed {
            let expandItem = NSMenuItem(title: strings.contextMenuExpand, action: #selector(contextMenuExpand), keyEquivalent: "")
            expandItem.target = self
            menu.addItem(expandItem)
        } else {
            let collapseItem = NSMenuItem(title: strings.contextMenuCollapse, action: #selector(contextMenuCollapse), keyEquivalent: "")
            collapseItem.target = self
            menu.addItem(collapseItem)
        }

        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)
        if alwaysHiddenEnabled {
            if isShowingAll {
                let hideAlwaysItem = NSMenuItem(title: strings.contextMenuHideAlways, action: #selector(contextMenuCollapse), keyEquivalent: "")
                hideAlwaysItem.target = self
                menu.addItem(hideAlwaysItem)
            } else {
                let showAllItem = NSMenuItem(title: strings.contextMenuShowAll, action: #selector(contextMenuShowAll), keyEquivalent: "")
                showAllItem.target = self
                menu.addItem(showAllItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: strings.contextMenuSettings, action: #selector(contextMenuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func contextMenuExpand() { expand() }
    @objc private func contextMenuCollapse() { collapse() }
    @objc private func contextMenuShowAll() { showAll() }

    @objc private func contextMenuOpenSettings() {
        SettingsRouter.shared.request(FeatureSettingsDestination(.menuBarHider))
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }

    // MARK: - Auto-Collapse Timer

    private func restartAutoCollapseTimerIfNeeded() {
        stopAutoCollapseTimer()
        if isConfiguring { return }

        let autoCollapse = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAutoCollapse)
        guard autoCollapse else { return }

        let delaySeconds = MenuBarHiderSupport.sanitizeAutoCollapseDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.menuBarHiderAutoCollapseDelay))

        let timer = Timer(timeInterval: Double(delaySeconds), repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collapse()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoCollapseTimer = timer
    }

    private func stopAutoCollapseTimer() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }
}

/// Custom subview for separator status items that always renders the separator
/// symbol ("|" or "‖") pinned to the trailing edge of the item bounds, ensuring
/// that the separator glyph remains perfectly visible on-screen even when the
/// status item length is expanded to 10,000px to hide adjacent menu bar icons.
final class MenuBarHiderSeparatorView: NSView {
    var symbol: String = "|" {
        didSet { if oldValue != symbol { needsDisplay = true } }
    }
    var isBold: Bool = false {
        didSet { if oldValue != isBold { needsDisplay = true } }
    }
    var isVisibleGlyph: Bool = true {
        didSet { if oldValue != isVisibleGlyph { needsDisplay = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        self.autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.autoresizingMask = [.width, .height]
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isVisibleGlyph else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: isBold ? .bold : .regular)
        let text = symbol as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.controlTextColor.withAlphaComponent(0.85)
        ]
        let size = text.size(withAttributes: attrs)
        let rect = NSRect(
            x: bounds.maxX - size.width - 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        text.draw(in: rect, withAttributes: attrs)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}


