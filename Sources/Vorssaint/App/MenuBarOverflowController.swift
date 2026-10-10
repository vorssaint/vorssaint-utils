// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import SwiftUI
import MenuBarVisibilityBridge

/// One Icon Drawer control, with a compact dropdown or a paged menu-bar strip.
/// Native visibility hides the originals; Accessibility opens their menus.
final class MenuBarOverflowController: NSObject, ObservableObject, NSMenuDelegate {
    static let shared = MenuBarOverflowController()
    var onChooseIcons: (() -> Void)?
    @Published var isChoosingIcons = false
    struct OverflowItem: Identifiable {
        let id: String
        let bundle: String
        let name: String
        let icon: NSImage
        let element: AXUIElement
        let frame: CGRect
    }
    @Published private(set) var items: [OverflowItem] = []
    @Published private(set) var availableItems: [OverflowItem] = []
    @Published private(set) var isCollapsed = false
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    private var toggleItem: NSStatusItem?
    private var spacerItem: NSStatusItem?
    private var drawer: MenuBarOverflowPanel?
    private var drawerLocalMonitor: Any?
    private var drawerGlobalMonitor: Any?
    private var arrowAXFrame = CGRect.zero
    private var lastClickPoint: CGPoint?
    private var systemCache: [String: MenuBarOverflowInventory.Record] = [:]
    private var systemMenuTimer: Timer?
    private var wantsDrawerVisible = false
    private var assertion: Any?
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var syncScheduled = false
    private var started = false
    private var requestedPermission = false
    private var lastSelection: Set<String> = []
    private var nativeMenuItem: OverflowItem?
    private var nativeMenuMonitor: Any?
    private var nativeMenuLocalMonitor: Any?
    private let images = MenuBarOverflowImages()
    private var lastMonochrome = true
    private var monochrome: Bool {
        UserDefaults.standard.object(forKey: DefaultsKey.menuBarOverflowMonochrome) as? Bool ?? true
    }
    private var inlinePageStart = 0
    private var pointerMonitor: Any?
    private var pointerDown: (point: CGPoint, time: TimeInterval)?
    private var toggleButton: NSStatusBarButton? { toggleItem?.button }
    private var inlineExpanded = false
    private var inlineVisibleCount = 0
    private var inlineHasMore = false
    private var lastLayout = MenuBarOverflowSupport.Layout.dropdown
    private var layout: MenuBarOverflowSupport.Layout {
        .resolved(UserDefaults.standard.string(forKey: DefaultsKey.menuBarOverflowLayout) ?? "")
    }
    private var configuredBundles: Set<String> {
        Set(UserDefaults.standard.string(forKey: DefaultsKey.menuBarOverflowBundles)?
            .split(separator: ",").map(String.init) ?? [])
    }
    private var usesNativeVisibility: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    func start() {
        guard !started else { return }
        started = true
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, !self.syncScheduled else { return }
            self.syncScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.syncScheduled = false
                self?.syncEnabled()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.closeDrawer()
            if self.usesNativeVisibility, !self.configuredBundles.isEmpty {
                self.collectAndHide(openDrawer: false)
            }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.toggleItem != nil,
                      !self.configuredBundles.isEmpty else { return }
                self.collectAndHide(openDrawer: false, preserveInline: self.inlineExpanded)
            })
        }
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let cgPoint = event.cgEvent?.location
            let point = cgPoint.map { CGPoint(x: $0.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - $0.y) } ?? NSEvent.mouseLocation
            self?.pointerDown = (point, ProcessInfo.processInfo.systemUptime)
        }
        syncEnabled()
    }

    private func syncEnabled() {
        if lastMonochrome != monochrome {
            lastMonochrome = monochrome
            if inlineExpanded { drawInline() }
        }
        if lastLayout != layout {
            lastLayout = layout
            closeInline()
            configureButton()
            if drawer?.isVisible == true { presentDrawer() }
        }
        if UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOverflowEnabled) {
            if toggleItem != nil {
                let selection = configuredBundles
                guard selection != lastSelection else { return }
                lastSelection = selection
                if selection.isEmpty { stopHiding(); items = [] }
                else { collectAndHide(openDrawer: false, refreshInventory: !usesNativeVisibility || availableItems.isEmpty) }
                return
            }
            lastSelection = configuredBundles
            let placement = UserDefaults.standard.integer(forKey: DefaultsKey.menuBarOverflowPlacementGeneration)
            let identity = "VorssaintOverflowToggle" + (placement == 0 ? "" : ".\(placement)")
            let positionKey = "NSStatusItem Preferred Position " + identity
            // A first-time overflow control belongs next to the right-side system
            // controls, where the camera notch cannot swallow it. Later launches
            // preserve the position the user arranged.
            if UserDefaults.standard.object(forKey: positionKey) == nil {
                UserDefaults.standard.set(0, forKey: positionKey)
            }
            let item = NSStatusBar.system.statusItem(withLength: 26)
            item.autosaveName = identity
            item.behavior = []
            item.isVisible = true
            toggleItem = item
            if !usesNativeVisibility {
                let spacer = NSStatusBar.system.statusItem(withLength: 18)
                spacer.autosaveName = "VorssaintOverflowBoundary"
                spacer.behavior = []
                spacer.button?.title = "│"
                spacer.button?.toolTip = "Command-drag less-used icons to the left of this divider."
                spacerItem = spacer
            }
            item.button?.target = self
            item.button?.action = #selector(clicked)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            message = nil
            configureButton()
            if !configuredBundles.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.toggleItem != nil else { return }
                    self.collectAndHide(openDrawer: false)
                }
            }
        } else if toggleItem != nil {
            stopHiding()
            if let item = toggleItem { NSStatusBar.system.removeStatusItem(item) }
            if let item = spacerItem { NSStatusBar.system.removeStatusItem(item) }
            toggleItem = nil
            spacerItem = nil
            items = []
            message = nil
        }
    }

    private func openInlineAtPointer() {
        let point = recentPointerPoint()
        guard inlineExpanded else { lastClickPoint = point; showDrawer(); return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let frame = MenuBarOverflowInventory.drawerFrame()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.inlineExpanded, let frame else { return }
                let distance = frame.maxX - point.x
                if distance < 26 { self.closeInline(); return }
                let index = self.inlinePageStart + Int((distance - 26) / 24)
                if index < self.inlinePageStart + self.inlineVisibleCount, self.items.indices.contains(index) {
                    self.open(self.items[index])
                } else if self.inlineHasMore { self.nextInlinePage() }
            }
        }
    }

    @objc private func clicked() {
        lastClickPoint = recentPointerPoint()
        if NSApp.currentEvent?.type == .rightMouseUp {
            dismissNativeMenu()
            let menu = NSMenu()
            let open = menu.addItem(withTitle: "Open Icon Drawer", action: #selector(showDrawer), keyEquivalent: "")
            open.target = self
            if layout == .menuBar {
                let icons = NSMenuItem(title: "Icons", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                addInlineItems(to: submenu, start: 0)
                icons.submenu = submenu
                menu.addItem(icons)
            }
            menu.addItem(.separator())
            let settings = menu.addItem(withTitle: "Open settings", action: #selector(chooseIcons), keyEquivalent: "")
            settings.target = self
            menu.addItem(.separator())
            let disable = menu.addItem(withTitle: "Turn off Icon Drawer", action: #selector(disable), keyEquivalent: "")
            disable.target = self
            // Explicitly disabled setup actions must stay disabled.
            menu.autoenablesItems = false
            menu.delegate = self
            toggleItem?.menu = menu
            toggleButton?.performClick(nil)
        } else if inlineExpanded { openInlineAtPointer() }
        else { showDrawer() }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard toggleItem?.menu === menu else { return }
        toggleItem?.menu = nil
        toggleButton?.target = self
        toggleButton?.action = #selector(clicked)
    }

    @objc private func disable() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.menuBarOverflowEnabled)
        syncEnabled()
    }

    func loadAvailableIcons() {
        collectAndHide(openDrawer: false)
    }

    func setIncluded(_ bundle: String, included: Bool) {
        var selection = configuredBundles
        if included { selection.insert(bundle) } else { selection.remove(bundle) }
        UserDefaults.standard.set(selection.sorted().joined(separator: ","),
                                  forKey: DefaultsKey.menuBarOverflowBundles)
    }

    private func orderedItems(_ values: [OverflowItem]) -> [OverflowItem] {
        let saved = UserDefaults.standard.string(forKey: DefaultsKey.menuBarOverflowOrder)?
            .split(separator: ",").map(String.init) ?? []
        let byID = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return MenuBarOverflowSupport.stableOrder(previous: saved, current: values.map(\.id))
            .compactMap { byID[$0] }
    }

    func moveItem(_ id: String, offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + offset) else { return }
        items.swapAt(index, index + offset)
        UserDefaults.standard.set(items.map(\.id).joined(separator: ","), forKey: DefaultsKey.menuBarOverflowOrder)
        if inlineExpanded { drawInline() }
    }

    @objc func chooseIcons() {
        closeDrawer()
        isChoosingIcons = true
        onChooseIcons?()
    }

    @objc func showDrawer() {
        if layout == .menuBar, !items.isEmpty, !isBusy {
            if inlineExpanded { closeInline() } else { expandInline() }
            return
        }
        if drawer?.isVisible == true { closeDrawer(); return }
        wantsDrawerVisible = true
        presentDrawer()
        if !isCollapsed && !isBusy {
            collectAndHide(openDrawer: true)
        }
    }

    func stopHiding() {
        systemMenuTimer?.invalidate()
        systemMenuTimer = nil
        generation += 1
        closeDrawer()
        if let assertion { VSMenuBarVisibilityRelease(assertion) }
        assertion = nil
        spacerItem?.length = 18
        isCollapsed = false
        isBusy = false
    }

    private func collectAndHide(openDrawer: Bool, refreshInventory: Bool = true, preserveInline: Bool = false) {
        if !preserveInline { closeInline() }
        systemMenuTimer?.invalidate()
        systemMenuTimer = nil
        guard toggleItem != nil else { return }
        let windowFrame = toggleButton?.window?.frame ?? .zero
        guard AXIsProcessTrusted() else {
            message = "Allow Vorssaint in System Settings → Privacy & Security → Accessibility, then click Icon Drawer again."
            if !requestedPermission {
                requestedPermission = true
                _ = AXIsProcessTrustedWithOptions([
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                ] as CFDictionary)
            }
            presentDrawer()
            return
        }
        if usesNativeVisibility, !VSMenuBarVisibilityAvailable() {
            message = "Menu bar hiding is unavailable on this macOS version. All icons remain visible."
            presentDrawer()
            return
        }
        if !usesNativeVisibility {
            guard let divider = spacerItem?.button?.window?.frame, divider.maxX <= windowFrame.minX else {
                message = "Command-drag the divider to the left of the Icon Drawer arrow first."
                presentDrawer()
                return
            }
        }
        message = nil
        isBusy = refreshInventory && availableItems.isEmpty
        generation += 1
        let request = generation
        let saved = configuredBundles
        let ownBundle = Bundle.main.bundleIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSWorkspace.shared.runningApplications
        // Inventory only scans app bundles, but visibility must also preserve
        // unselected UI services and extensions that can own status items.
        let runningBundles = Set(runningApps.compactMap(\.bundleIdentifier))
        let apps = runningApps.filter {
            $0.bundleURL?.pathExtension == "app"
                && $0.bundleIdentifier != MenuBarOverflowInventory.menuBarAgentBundle
                && $0.processIdentifier != ownPID
        }
        var descriptors = apps.compactMap { app -> MenuBarOverflowInventory.Application? in
            guard let bundle = app.bundleIdentifier else { return nil }
            return .init(pid: app.processIdentifier, bundle: bundle, name: app.localizedName ?? bundle)
        }
        if let agent = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.MenuBarAgent" || $0.localizedName == "MenuBarAgent"
        }) {
            descriptors.append(.init(pid: agent.processIdentifier, bundle: MenuBarOverflowInventory.menuBarAgentBundle, name: "System"))
        }
        // Checkbox changes need a new allowlist, not a new inventory. Keep the
        // chooser's image objects, identities and row positions intact.
        let cachedInventory = availableItems.map {
            MenuBarOverflowInventory.Record(identifier: nil, id: $0.id, bundle: $0.bundle, name: $0.name, element: $0.element, frame: $0.frame)
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scannedInventory = refreshInventory ? MenuBarOverflowInventory.read(descriptors) : cachedInventory
            let ownItems = refreshInventory ? MenuBarOverflowInventory.read([.init(pid: ownPID, bundle: ownBundle ?? "", name: "Vorssaint")]) : []
            let hidden = saved
            let allowed = MenuBarOverflowSupport.allowedBundles(running: runningBundles, selection: hidden, ownBundle: ownBundle)
            DispatchQueue.main.async { [weak self] in
                guard let self, request == self.generation else { return }
                if let arrow = ownItems.first(where: { $0.identifier == "vorssaint.icon-drawer" }) {
                    self.arrowAXFrame = arrow.frame
                }
                if refreshInventory { self.refreshAvailableItems(from: scannedInventory) }
                self.items = self.orderedItems(self.availableItems.filter { hidden.contains($0.bundle) })
                if self.inlineExpanded { self.drawInline() }
                guard !hidden.isEmpty else {
                    let reopen = openDrawer && self.wantsDrawerVisible
                    self.stopHiding()
                    self.wantsDrawerVisible = reopen
                    self.message = "Icon Drawer is empty. Open Settings → Menu bar → Choose icons and select the icons you want here."
                    if openDrawer && self.wantsDrawerVisible { self.presentDrawer() }
                    return
                }
                if !self.usesNativeVisibility {
                    self.spacerItem?.length = min(10_000, max(500, (NSScreen.screens.map { $0.frame.width }.max() ?? 2000) * 2))
                    self.isBusy = false
                    self.isCollapsed = true
                    if openDrawer && self.wantsDrawerVisible { self.presentDrawer() }
                    return
                }
                self.activateVisibility(allowedBundles: allowed, selection: hidden, request: request) { [weak self] activated, error in
                    guard let self else { return }
                    self.isBusy = false
                    if activated {
                        self.isCollapsed = true
                    } else {
                        let reopen = openDrawer && self.wantsDrawerVisible
                        self.stopHiding()
                        self.wantsDrawerVisible = reopen
                        self.message = error?.localizedDescription ?? "Could not move icons into Icon Drawer."
                    }
                    if openDrawer && self.wantsDrawerVisible { self.presentDrawer() }
                }
            }
        }
    }

    private func refreshAvailableItems(from records: [MenuBarOverflowInventory.Record]) {
        images.removeAll()
        // NSImage belongs to the UI thread. Resolve images here,
        // after the background accessibility read has completed.
        let appIcons = Dictionary(NSWorkspace.shared.runningApplications.compactMap { app -> (String, NSImage)? in
            guard let bundle = app.bundleIdentifier, let icon = app.icon else { return nil }
            return (bundle, icon)
        }, uniquingKeysWith: { first, _ in first })
        for record in records where record.bundle.hasPrefix("system:") {
            systemCache[record.bundle] = record
        }
        // Saved system controls may already be hidden while MenuBarAgent is
        // settling after launch. Their menu action always resolves a fresh AX
        // element after revealing them, so retain a selectable placeholder.
        for control in MenuBarOverflowSupport.systemControls
            where configuredBundles.contains(control.selectionKey) && systemCache[control.selectionKey] == nil {
            systemCache[control.selectionKey] = .init(identifier: control.identifier,
                id: control.selectionKey, bundle: control.selectionKey, name: control.name,
                element: AXUIElementCreateSystemWide(), frame: .zero)
        }
        let inventory = records.filter { !$0.bundle.hasPrefix("system:") }
            + systemCache.values.sorted { $0.name < $1.name }
        let refreshed = inventory.map { record in
            let symbol = MenuBarOverflowSupport.systemControl(selectionKey: record.bundle)?.symbol ?? "app"
            let icon = appIcons[record.bundle] ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
            return OverflowItem(id: record.id, bundle: record.bundle, name: record.name,
                                icon: icon, element: record.element, frame: record.frame)
        }
        if monochrome {
            for item in refreshed where configuredBundles.contains(item.bundle) { _ = templateIcon(for: item) }
        }
        let byID = Dictionary(refreshed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        availableItems = MenuBarOverflowSupport.stableOrder(previous: availableItems.map(\.id),
            current: refreshed.map(\.id)).compactMap { byID[$0] }
    }

    private func presentDrawer() {
        guard toggleItem != nil else { return }
        let point = lastClickPoint
        let screen = point.flatMap { point in NSScreen.screens.first { $0.frame.contains(point) } }
            ?? toggleButton?.window?.screen ?? NSScreen.main
        guard let screen else { return }
        let reported = toggleButton?.window?.frame ?? .zero
        let x = point?.x ?? (StatusItemAnchorSupport.isTrustworthyStatusFrame(reported)
            ? reported.midX : screen.visibleFrame.maxX - 120)
        // The dropdown belongs below both the menu bar and the camera housing,
        // including when the menu bar is configured to auto-hide.
        let top = min(screen.visibleFrame.maxY,
                      screen.frame.maxY - max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)) - 6
        let columns = items.count > 9 ? 4 : 3
        let width = CGFloat(columns) * 80 + 24
        let rows = max(1, Int(ceil(Double(items.count) / Double(columns))))
        let height = min(360, max(150, CGFloat(rows) * 58 + (message == nil && !items.isEmpty && AXIsProcessTrusted() ? 84 : 126)))
        let frame = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: width, height: height),
            anchorMidX: x, anchorTop: top, visibleFrame: screen.visibleFrame)
        let panel: MenuBarOverflowPanel
        if let drawer { panel = drawer }
        else {
            panel = MenuBarOverflowPanel(contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Icon Drawer"
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let hosting = NSHostingView(rootView: MenuBarOverflowDrawer(controller: self))
            hosting.frame = CGRect(origin: .zero, size: frame.size)
            // The controller sizes the grid; intrinsic SwiftUI sizing must not
            // shrink the glass content to a single scroll-view row.
            hosting.sizingOptions = []
            hosting.autoresizingMask = [.width, .height]
            // Clip hosted content as well as the glass: NSGlassEffectView does
            // not mask arbitrary content backing layers to its rounded shape.
            hosting.wantsLayer = true
            hosting.layer?.cornerRadius = 18
            hosting.layer?.masksToBounds = true
            panel.contentView = Self.drawerBackdrop(content: hosting)
            drawer = panel
        }
        panel.appearance = NSApp.appearance
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        installDrawerMonitors()
    }

    /// Use the system glass renderer rather than a tinted imitation. Older
    /// systems retain their native popover material and the same geometry.
    private static func drawerBackdrop(content: NSView) -> NSView {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: content.frame)
            glass.style = .regular
            glass.cornerRadius = 18
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 18
            glass.layer?.masksToBounds = true
            glass.contentView = content
            return glass
        }
#endif
        let material = NSVisualEffectView(frame: content.frame)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 18
        material.layer?.masksToBounds = true
        material.addSubview(content)
        return material
    }

    private func installDrawerMonitors() {
        guard drawerLocalMonitor == nil else { return }
        drawerLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.closeDrawer()
                return nil
            }
            if event.type != .keyDown, self.drawer?.frame.contains(NSEvent.mouseLocation) != true {
                // Let the arrow's own mouse-up toggle the dropdown once.
                if event.window !== self.toggleButton?.window { self.closeDrawer() }
            }
            return event
        }
        drawerGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            // On macOS 27 the menu bar belongs to MenuBarAgent, so our arrow's
            // mouse-down is a global event. Leave its mouse-up to toggle once.
            let screen = NSScreen.screens.first { $0.frame.contains(point) }
            let inBar = screen.map { point.y >= $0.frame.maxY - max(33, $0.safeAreaInsets.top) } ?? false
            let anchorX = self.lastClickPoint?.x ?? self.arrowAXFrame.midX
            if inBar && abs(point.x - anchorX) < 24 { return }
            self.closeDrawer()
        }
    }

    private func closeDrawer() {
        closeInline()
        wantsDrawerVisible = false
        drawer?.orderOut(nil)
        if let drawerLocalMonitor { NSEvent.removeMonitor(drawerLocalMonitor) }
        if let drawerGlobalMonitor { NSEvent.removeMonitor(drawerGlobalMonitor) }
        drawerLocalMonitor = nil
        drawerGlobalMonitor = nil
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func open(_ item: OverflowItem) {
        if inlineExpanded {
            drawer?.orderOut(nil)
            installNativeMenuDismissal(for: item)
        } else { closeDrawer() }
        if item.bundle.hasPrefix("system:"), usesNativeVisibility {
            openSystemMenu(item)
            return
        }
        // Let the transient drawer relinquish focus before the other app opens
        // its native status menu. No synthetic pointer events or app launches.
        let request = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, request == self.generation else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
                DispatchQueue.main.async { [weak self] in
                    // Some status menus enter a tracking loop before replying to AXPress.
                    // cannotComplete can mean that the menu opened, so never dismiss
                    // it or reveal the whole bar in response to that timeout.
                    guard let self, request == self.generation,
                          result != .success, result != .cannotComplete else { return }
                    self.stopHiding()
                    self.message = "\(item.name) could not open its menu from Icon Drawer. Its original icon is visible again; click it in the menu bar."
                }
            }
        }
    }

    /// Install a replacement before releasing the old assertion. Obsolete
    /// completions release their handles without changing current UI state.
    private func activateVisibility(allowedBundles: [String], selection: Set<String>, request: Int,
                                    completion: @escaping (Bool, Error?) -> Void) {
        VSMenuBarVisibilityActivate(allowedBundles, MenuBarOverflowSupport.allowedSystemItems(selection: selection)) { [weak self] handle, error in
            guard let self, request == self.generation else {
                if let handle { VSMenuBarVisibilityRelease(handle) }
                return
            }
            if let handle {
                let previous = self.assertion
                self.assertion = handle
                if let previous { VSMenuBarVisibilityRelease(previous) }
                completion(true, nil)
            } else {
                completion(false, error)
            }
        }
    }

    private func openSystemMenu(_ item: OverflowItem) {
        systemMenuTimer?.invalidate()
        generation += 1
        let request = generation
        let selection = configuredBundles.subtracting([item.bundle])
        let allowed = MenuBarOverflowSupport.allowedBundles(
            running: Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }),
            selection: selection, ownBundle: Bundle.main.bundleIdentifier)
        activateVisibility(allowedBundles: allowed, selection: selection, request: request) { [weak self] activated, error in
            guard let self else { return }
            guard activated else {
                self.message = error?.localizedDescription ?? "Could not open \(item.name)."
                return
            }
            let agents = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == "com.apple.MenuBarAgent" || $0.localizedName == "MenuBarAgent"
            }.map { MenuBarOverflowInventory.Application(pid: $0.processIdentifier, bundle: MenuBarOverflowInventory.menuBarAgentBundle, name: "System") }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25) { [weak self] in
                let fresh = MenuBarOverflowInventory.read(agents).first { $0.bundle == item.bundle }
                let result = fresh.map { AXUIElementPerformAction($0.element, kAXPressAction as CFString) } ?? .invalidUIElement
                DispatchQueue.main.async { [weak self] in
                    guard let self, request == self.generation else { return }
                    if result != .success && result != .cannotComplete {
                        self.collectAndHide(openDrawer: false, preserveInline: self.inlineExpanded)
                        self.message = "Could not open \(item.name). Try again from Icon Drawer."
                    } else { self.waitForSystemMenuToClose(request: request) }
                }
            }
        }
    }

    private func waitForSystemMenuToClose(request: Int) {
        let owners = Set(NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier?.hasPrefix("com.apple.controlcenter") == true || $0.bundleIdentifier == "com.apple.MenuBarAgent"
        }.map { $0.processIdentifier })
        var sawMenu = false
        let started = Date()
        systemMenuTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self, request == self.generation else { timer.invalidate(); return }
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            let visible = windows.contains { window in
                guard let pid = window[kCGWindowOwnerPID as String] as? Int32, owners.contains(pid),
                      let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                      let width = bounds["Width"], let height = bounds["Height"] else { return false }
                return height > 60 && width > 100 && width < 800
            }
            sawMenu = sawMenu || visible
            if (!visible && sawMenu) || (!sawMenu && Date().timeIntervalSince(started) > 3) {
                timer.invalidate()
                self.systemMenuTimer = nil
                self.collectAndHide(openDrawer: false, preserveInline: self.inlineExpanded)
            }
        }
    }

    /// Add native icon slots beside a fixed-size arrow, bounded by the
    /// available right-side menu-bar space.
    private func expandInline() {
        closeDrawer()
        guard let screen = toggleButton?.window?.screen ?? NSScreen.main else { return }
        let rightArea = screen.auxiliaryTopRightArea
            ?? CGRect(x: screen.frame.minX, y: screen.frame.maxY - NSStatusBar.system.thickness,
                      width: screen.frame.width, height: NSStatusBar.system.thickness)
        let request = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let frame = MenuBarOverflowInventory.drawerFrame()
            DispatchQueue.main.async { [weak self] in
                guard let self, request == self.generation, self.toggleItem != nil else { return }
                guard let frame, frame.minX >= rightArea.minX, frame.maxX <= rightArea.maxX else {
                    self.showInlineMenu(start: 0); return
                }
                let free = MenuBarOverflowSupport.inlineFreeWidth(rightArea: rightArea, arrowFrame: frame)
                let plan = MenuBarOverflowSupport.inlinePlan(itemCount: self.items.count, freeWidth: free)
                guard !plan.usesMenuOnly else { self.showInlineMenu(start: 0); return }
                self.inlineVisibleCount = plan.visibleCount
                self.inlinePageStart = 0
                self.inlineHasMore = plan.hasMore
                self.inlineExpanded = true
                self.drawInline()
            }
        }
    }

    private func closeInline() {
        guard inlineExpanded else { return }
        dismissNativeMenu()
        inlineExpanded = false
        inlinePageStart = 0
        inlineVisibleCount = 0
        inlineHasMore = false
        toggleItem?.length = 26
        configureButton()
    }

    private func recentPointerPoint() -> CGPoint {
        if let pointerDown, ProcessInfo.processInfo.systemUptime - pointerDown.time < 2 { return pointerDown.point }
        return NSEvent.mouseLocation
    }

    private func drawInline() {
        let page = Array(items.dropFirst(inlinePageStart).prefix(inlineVisibleCount))
        let icons = page.map { monochrome ? templateIcon(for: $0) : $0.icon }
        let size = max(1, inlineVisibleCount)
        let pageNumber = inlineHasMore
            ? "\(inlinePageStart / size + 1)/\((items.count + size - 1) / size)" : nil
        toggleButton?.image = images.inlineImage(icons: icons, capacity: inlineVisibleCount,
                                                pageNumber: pageNumber, monochrome: monochrome)
        toggleItem?.length = CGFloat(inlineVisibleCount) * 24 + (inlineHasMore ? 32 : 0) + 26
        toggleButton?.toolTip = "Icon Drawer — click an icon; « collapses; the page number advances through excess icons."
    }

    private func nextInlinePage() {
        let size = max(1, inlineVisibleCount)
        inlinePageStart = MenuBarOverflowSupport.nextPageStart(current: inlinePageStart, pageSize: size, count: items.count)
        drawInline()
    }

    private func showInlineMenu(start: Int) {
        let menu = NSMenu()
        addInlineItems(to: menu, start: start)
        menu.addItem(.separator())
        let choose = menu.addItem(withTitle: "Open settings", action: #selector(chooseIcons), keyEquivalent: "")
        choose.target = self
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func addInlineItems(to menu: NSMenu, start: Int) {
        for index in items.indices where index >= start {
            let item = menu.addItem(withTitle: items[index].name, action: #selector(openInlineMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = items[index]
            let source = monochrome ? templateIcon(for: items[index]) : items[index].icon
            let icon = source.copy() as? NSImage
            icon?.size = NSSize(width: 18, height: 18)
            item.image = icon
        }
    }

    @objc private func openInlineMenuItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? OverflowItem else { return }
        open(item)
    }

    private func templateIcon(for item: OverflowItem) -> NSImage {
        images.monochrome(item.icon, cacheKey: item.id)
    }

    private func installNativeMenuDismissal(for item: OverflowItem) {
        dismissNativeMenu()
        nativeMenuItem = item
        nativeMenuMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissNativeMenuIfOutside()
        }
        nativeMenuLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissNativeMenuIfOutside()
            return event
        }
    }

    private func dismissNativeMenuIfOutside() {
        guard let item = nativeMenuItem else { return }
        let point = NSEvent.mouseLocation
        let menuBarPoint = point.y >= (NSScreen.screens.first { $0.frame.contains(point) }?.frame.maxY ?? .infinity) - 40
        if menuBarPoint {
            let itemID = item.id
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let frame = MenuBarOverflowInventory.drawerFrame()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.nativeMenuItem?.id == itemID else { return }
                    if frame.map({ point.x >= $0.minX && point.x <= $0.maxX }) != true { self.dismissNativeMenu() }
                }
            }
            return
        }
        let cgPoint = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
        if !MenuBarOverflowNativeMenus.contains(point: cgPoint, for: item.element) { dismissNativeMenu() }
    }

    private func dismissNativeMenu() {
        if let nativeMenuMonitor { NSEvent.removeMonitor(nativeMenuMonitor) }
        nativeMenuMonitor = nil
        if let nativeMenuLocalMonitor { NSEvent.removeMonitor(nativeMenuLocalMonitor) }
        nativeMenuLocalMonitor = nil
        guard let item = nativeMenuItem else { return }
        nativeMenuItem = nil
        DispatchQueue.global(qos: .userInitiated).async {
            MenuBarOverflowNativeMenus.cancel(item.element)
        }
    }

    private func configureButton() {
        toggleButton?.image = layout == .menuBar
            ? images.inlineImage(icons: [], capacity: 0, pageNumber: nil, monochrome: true)
            : NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Icon Drawer menu bar icons")
        toggleButton?.toolTip = "Icon Drawer — open your hidden menu bar icons."
        toggleButton?.setAccessibilityLabel("Icon Drawer menu bar icons")
        toggleButton?.setAccessibilityIdentifier("vorssaint.icon-drawer")
    }
}

private final class MenuBarOverflowPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
