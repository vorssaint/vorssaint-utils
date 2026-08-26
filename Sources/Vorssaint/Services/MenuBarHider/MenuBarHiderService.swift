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
    private let hotkey = QuickToolHotkey(id: 30)
    private var isShowingAll: Bool = false
    private var trackingArea: NSTrackingArea?
    private var scrollMonitor: Any?
    private var lastScrollToggleTime: TimeInterval = 0

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

        // 1. Toggle Item
        if toggleItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = MenuBarHiderSupport.toggleAutosaveName
            item.behavior = []
            item.isVisible = true
            toggleItem = item
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
        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)

        // 1. Toggle button (Always on the right)
        if let toggleButton = toggleItem?.button {
            toggleButton.subviews.removeAll(where: { $0 is MenuBarHiderSeparatorView })
            toggleButton.target = self
            toggleButton.action = #selector(toggleClicked)
            toggleButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            toggleButton.title = ""
            let symbolName = MenuBarHiderSupport.toggleSymbolName(isCollapsed: isCollapsed, style: style)
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Menu Bar Hider") {
                image.isTemplate = true
                toggleButton.image = image
            }
            toggleButton.toolTip = MenuBarHiderSupport.toggleTooltip(
                isCollapsed: isCollapsed,
                isShowingAll: isShowingAll,
                alwaysHiddenEnabled: alwaysHiddenEnabled
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
            separatorButton.toolTip = "Vorssaint: Menu bar separator (⌘-drag items to the left)"

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
            alwaysHiddenButton.toolTip = "Vorssaint: Always-hidden separator"

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
        let wasCollapsed = isCollapsed
        isCollapsed = false
        isShowingAll = false
        updateItemAppearances()
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
        isCollapsed = true
        isShowingAll = false
        updateItemAppearances()
        if wasExpanded {
            triggerHapticFeedback()
        }
    }

    func showAll(startTimer: Bool = true) {
        isCollapsed = false
        isShowingAll = true
        updateItemAppearances()
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

    private var screenWidth: Double {
        let screen = toggleItem?.button?.window?.screen ?? NSScreen.main
        return Double(screen?.frame.width ?? 2560.0)
    }

    private func updateItemAppearances() {
        autoHealItemOrdering()
        configureItemButtons()

        let state = currentDisplayState
        let width = screenWidth
        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)

        // Update main separator length
        if let separatorItem {
            let length = MenuBarHiderSupport.separatorLength(state: state, screenWidth: width)
            separatorItem.length = CGFloat(length)
        }

        // Update always-hidden separator length
        if let alwaysHiddenItem {
            let length = MenuBarHiderSupport.alwaysHiddenLength(state: state, screenWidth: width, isEnabled: alwaysHiddenEnabled)
            alwaysHiddenItem.length = CGFloat(length)
        }
    }

    @objc private func screenParametersChanged() {
        updateItemAppearances()
    }

    // MARK: - Tracking Area & Hover

    private func setupTrackingArea() {
        guard let button = toggleItem?.button else { return }
        removeTrackingArea()
        let area = NSTrackingArea(rect: button.bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        button.addTrackingArea(area)
        trackingArea = area
    }

    private func removeTrackingArea() {
        if let trackingArea, let button = toggleItem?.button {
            button.removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        let expandOnHover = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderExpandOnHover)
        if expandOnHover, isCollapsed {
            expand(startTimer: true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        if !isCollapsed && !isConfiguring {
            restartAutoCollapseTimerIfNeeded()
        }
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

        // 3. Double-click or Option+Click -> Toggle Always Hidden section
        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)
        if alwaysHiddenEnabled && (event.clickCount >= 2 || event.modifierFlags.contains(.option)) {
            if isShowingAll {
                collapse()
            } else {
                showAll()
            }
            return
        }

        // 4. Normal click
        if isShowingAll {
            collapse()
        } else {
            toggle()
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
            if isShowingAll {
                collapse()
            } else {
                showAll()
            }
            return
        }
        if event.modifierFlags.contains(.command) {
            return
        }
        if isShowingAll {
            collapse()
        } else {
            showAll()
        }
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


