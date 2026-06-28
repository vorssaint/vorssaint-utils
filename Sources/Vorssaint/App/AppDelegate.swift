// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusController: StatusItemController!
    private let popover = NSPopover()
    private var popoverClosedAt = Date.distantPast
    private var popoverDismissMonitor: Any?
    private var popoverLocalDismissMonitor: Any?
    private var popoverKeyboardMonitor: Any?
    private var popoverIsClosing = false
    private var popoverIsSwitchingAnchor = false
    private var metricAnchorSwitchSerial = 0
    private var popoverCloseCompletions: [() -> Void] = []
    private var isTerminating = false
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var dockPreviewIntroWindow: NSWindow?
    private var supportIntroWindow: NSWindow?
    private var updateShowcaseWindow: NSWindow?
    private var updatePreviewWindow: NSWindow?
    private let popoverOpenDuration: TimeInterval = 0.18
    private let popoverCloseDuration: TimeInterval = 0.14

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Finish the on-disk rename for installs carried over from a pre-2.5
        // build, or retire a leftover old-named bundle. Returns true when we are
        // quitting to relaunch under the new name, so skip the rest of startup.
        if BundleMigration.run() { return }

        // An accessory (LSUIElement) app gets no default main menu, so the standard
        // keyboard shortcuts (Cmd+H/M/W/Q and the Edit shortcuts Cmd+C/V/X/A) have
        // no menu items to fire and do nothing in the Settings window. Install one.
        installMainMenu()
        PanelLayout.resetCollapsedSectionsOnce(for: "2.15.1")

        statusController = StatusItemController()
        statusController.onLeftClick = { [weak self] in self?.toggleMainPopover() }
        statusController.onRightClick = { [weak self] in self?.showContextMenu() }
        statusController.onMetricClick = { [weak self] metric, button in
            self?.showMetricPanel(for: metric, anchoredTo: button)
        }

        setUpPopover()
        bindManagers()

        HotkeyManager.shared.onActivate = { KeepAwakeManager.shared.toggle() }
        HotkeyManager.shared.syncWithPreferences()

        KeepAwakeManager.shared.recoverIfNeeded {
            KeepAwakeManager.shared.activateOnLaunchIfNeeded()
        }
        AppActivationTracker.shared.start()
        ScrollInverter.shared.syncWithPreferences()
        AppSwitcher.shared.syncWithPreferences()
        DockPreviewService.shared.syncWithPreferences()
        FinderCutPaste.shared.syncWithPreferences()
        AutoQuitService.shared.syncWithPreferences()
        ShelfService.shared.syncWithPreferences()
        URLCleanerService.shared.syncWithPreferences()
        WindowMaximizer.shared.syncWithPreferences()
        WindowLayoutService.shared.syncWithPreferences()
        ClipboardHistoryService.shared.syncWithPreferences()
        MonitorAlertService.shared.start()
        MaxCapacityProbe.shared.refreshIfStale()
        AudioInputDeviceManager.shared.start()
        AppVolumeMixer.shared.start()
        SoundOutputSwitcher.shared.syncWithPreferences()
        UpdateService.shared.startAutomaticChecks()
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)

        // If Accessibility is granted while the app is running (e.g. during
        // onboarding), bring the input features up without a relaunch.
        Permissions.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                ScrollInverter.shared.syncWithPreferences()
                AppSwitcher.shared.syncWithPreferences()
                DockPreviewService.shared.syncWithPreferences()
                FinderCutPaste.shared.syncWithPreferences()
                AutoQuitService.shared.syncWithPreferences()
                WindowMaximizer.shared.syncWithPreferences()
                WindowLayoutService.shared.syncWithPreferences()
            }
            .store(in: &cancellables)

        Permissions.shared.$screenRecording
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                DockPreviewService.shared.syncWithPreferences()
            }
            .store(in: &cancellables)

        // Keep the menu titles in step with the in-app language.
        L10n.shared.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.installMainMenu() }
            .store(in: &cancellables)

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: DefaultsKey.hasOnboarded) {
            showOnboarding(mode: .full)
        } else {
            // Keep the last seen version marker current without opening
            // post-update release notes; the update flow already previews them.
            defaults.set(OnboardingInfo.currentFeatureSet, forKey: DefaultsKey.featuresOnboardingVersion)
            defaults.set(AppInfo.version, forKey: DefaultsKey.lastUpdateIntroVersion)
            presentUpdateIntros()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        URLCleanerService.shared.stop()
        WindowMaximizer.shared.stop()
        DockPreviewService.shared.stop()
        SoundOutputSwitcher.shared.stop()
        AppVolumeMixer.shared.stopAll()
        KeepAwakeManager.shared.deactivate(reason: .quit)
    }

    /// The lifeline when the menu bar icon goes missing. Opening the app again
    /// from Finder, Spotlight or Launchpad while it's already running lands here:
    /// force the icon back and pop the panel so there's immediate proof the app is
    /// alive. Without this, a hidden icon would strand the app running with no way
    /// in. (A cold launch can't happen while running, so this is the recovery path.)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        // A deliberate reopen with no windows showing is the user's recovery action.
        // Rebuild the menu bar item unconditionally: macOS keeps the button's window
        // non-nil even when it has dropped the icon for lack of room, so there's no
        // cheap way to detect that, and only a fresh item makes the OS re-place it.
        statusController?.recreateStatusItem()
        // Decide on the next run-loop turn: a freshly rebuilt status item has no
        // laid-out on-screen frame yet this turn, so iconIsOnScreen() would read a
        // not-ready frame and wrongly skip the panel. After layout: pop the panel
        // when the icon is genuinely on screen, else fall back to the Settings
        // window. Either way the user ALWAYS gets back in.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.iconIsOnScreen(), !self.popover.isShown {
                self.popoverClosedAt = .distantPast
                self.togglePopover()
            }
            if !self.popover.isShown {
                self.openSettingsWindow()
            }
        }
        return true
    }

    /// Whether the menu bar icon is actually visible on a screen, rather than
    /// present in the status bar but clipped or dropped by a crowded/notched menu
    /// bar (in which case the button still has a window, just not an on-screen one).
    private func iconIsOnScreen() -> Bool {
        guard let frame = statusController?.statusItem.button?.window?.frame,
              frame.width > 0, frame.height > 0 else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func bindManagers() {
        KeepAwakeManager.shared.onSessionEnded = { reason in
            let strings = L10n.shared.s
            switch reason {
            case .timer:
                Notifier.post(title: strings.notifySessionEndedTitle, body: strings.notifySessionEndedBody)
            case .battery:
                Notifier.post(title: strings.notifyBatteryTitle, body: strings.notifyBatteryBody)
            default:
                break
            }
        }
    }

    // MARK: - Main panel

    private func setUpPopover() {
        // Application-defined (not .transient) so the panel stays open while the
        // user works in our own Settings window and sees changes live. Click
        // monitors below dismiss it when it would block that same Settings window.
        popover.behavior = .applicationDefined
        // We animate the underlying popover window ourselves so applicationDefined
        // dismissal, right-click menus and live Settings previews stay predictable.
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(rootView: MenuPanelView())
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        NotificationCenter.default.addObserver(self, selector: #selector(appResignedActive),
                                               name: NSApplication.didResignActiveNotification, object: nil)
    }

    private func togglePopover(anchor button: NSStatusBarButton? = nil) {
        if popover.isShown {
            closePopover()
            return
        }
        showPopover(anchor: button)
    }

    private func toggleMainPopover() {
        if !popover.isShown {
            MenuPanelFocus.shared.showNormalPanel()
        }
        togglePopover()
    }

    private func showMetricPanel(for metric: MenuBarMetric, anchoredTo button: NSStatusBarButton) {
        let detailKind = metric.detailKind
        if popover.isShown {
            if MenuPanelFocus.shared.activeMetric == detailKind {
                metricAnchorSwitchSerial &+= 1
                MenuPanelFocus.shared.clearMetricFocus()
                closePopover(animated: false)
                return
            }
            MenuPanelFocus.shared.focus(detailKind)
            scheduleMetricAnchorSwitch(to: detailKind, anchoredTo: button)
            return
        }
        MenuPanelFocus.shared.focus(detailKind)
        showPopover(anchor: button)
    }

    private func scheduleMetricAnchorSwitch(to detailKind: MetricDetailKind, anchoredTo button: NSStatusBarButton) {
        metricAnchorSwitchSerial &+= 1
        let serial = metricAnchorSwitchSerial
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self, weak button] in
            guard let self,
                  let button,
                  self.popover.isShown,
                  self.metricAnchorSwitchSerial == serial,
                  MenuPanelFocus.shared.activeMetric == detailKind else { return }
            self.reanchorMetricPopover(to: detailKind, anchoredTo: button)
        }
    }

    private func reanchorMetricPopover(to detailKind: MetricDetailKind, anchoredTo button: NSStatusBarButton) {
        guard popover.isShown else {
            MenuPanelFocus.shared.focus(detailKind)
            showPopover(anchor: button, allowRecentClose: true, animate: false, activate: false)
            return
        }
        popoverIsSwitchingAnchor = true
        MenuPanelFocus.shared.setSwitchingMetricAnchor(true)
        let expectedMidX = statusButtonMidX(button)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self, weak button] in
            guard let self,
                  let button,
                  self.popover.isShown,
                  self.metricAnchorSwitchSerial > 0,
                  MenuPanelFocus.shared.activeMetric == detailKind else {
                self?.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            if let expectedMidX,
               let popoverMidX = self.popover.contentViewController?.view.window?.frame.midX,
               abs(popoverMidX - expectedMidX) <= 34 {
                self.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            self.switchMetricPopover(to: detailKind, anchoredTo: button)
        }
    }

    private func statusButtonMidX(_ button: NSStatusBarButton) -> CGFloat? {
        guard let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).midX
    }

    private func switchMetricPopover(to detailKind: MetricDetailKind, anchoredTo button: NSStatusBarButton) {
        popoverIsSwitchingAnchor = true
        MenuPanelFocus.shared.setSwitchingMetricAnchor(true)
        removePopoverDismissMonitor()
        popoverIsClosing = true
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak button] in
            guard let self else {
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            guard let button else {
                self.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            self.popoverClosedAt = .distantPast
            MenuPanelFocus.shared.focus(detailKind)
            self.showPopover(anchor: button, allowRecentClose: true, animate: false, activate: false)
            DispatchQueue.main.async {
                self.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
            }
        }
    }

    private func showPopover(anchor button: NSStatusBarButton? = nil,
                             allowRecentClose: Bool = false,
                             animate: Bool = true,
                             activate: Bool = true) {
        guard !popover.isShown else { return }
        // The click that just transient-dismissed the popover also lands here;
        // reopening would make the panel look impossible to close.
        guard allowRecentClose || Date().timeIntervalSince(popoverClosedAt) > 0.35 else { return }
        guard let button = button ?? statusController.button else { return }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            // Keep the panel alive next to fullscreen apps and on any Space —
            // without this it blinks shut when another display is fullscreen.
            window.collectionBehavior.insert([.fullScreenAuxiliary, .canJoinAllSpaces])
            if let panel = window as? NSPanel {
                panel.hidesOnDeactivate = false
            }
            window.contentView?.layoutSubtreeIfNeeded()
            window.makeKey()
            if animate {
                animatePopoverOpen(window)
            } else {
                popoverIsClosing = false
                window.alphaValue = 1
            }
        }
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
        // Only arm the dismiss monitor if the popover actually presented — otherwise
        // popoverDidClose never fires and the global monitor would leak indefinitely.
        guard popover.isShown else { return }
        installPopoverDismissMonitor()
    }

    private func installPopoverDismissMonitor() {
        removePopoverDismissMonitor()
        // A global monitor only sees events delivered to OTHER apps, so a click in
        // another app or on the desktop dismisses the panel.
        popoverDismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            guard !PanelInteractionState.shared.keepsPopoverOpen else { return }
            guard self.statusController.containsStatusItem(at: NSEvent.mouseLocation) == false else { return }
            self.closePopover()
        }

        // Local events cover our own Settings window. Keep Settings + panel open
        // when they sit side by side for live reordering, but close the panel if it
        // overlaps Settings and the user clicks Settings to get it out of the way.
        popoverLocalDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if self.shouldDismissPopover(forLocalEvent: event) {
                self.closePopover()
            }
            return event
        }

        popoverKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handlePopoverKeyDown(event)
        }
    }

    private func removePopoverDismissMonitor() {
        if let monitor = popoverDismissMonitor {
            NSEvent.removeMonitor(monitor)
            popoverDismissMonitor = nil
        }
        if let monitor = popoverLocalDismissMonitor {
            NSEvent.removeMonitor(monitor)
            popoverLocalDismissMonitor = nil
        }
        if let monitor = popoverKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
            popoverKeyboardMonitor = nil
        }
    }

    private func shouldDismissPopover(forLocalEvent event: NSEvent) -> Bool {
        guard !PanelInteractionState.shared.keepsPopoverOpen else { return false }
        guard event.window === settingsWindow,
              let settingsFrame = settingsWindow?.frame,
              let popoverFrame = popover.contentViewController?.view.window?.frame else {
            return false
        }
        return settingsFrame.intersects(popoverFrame)
    }

    private func handlePopoverKeyDown(_ event: NSEvent) -> NSEvent? {
        guard popover.isShown,
              PanelInteractionState.shared.keepsPopoverOpen,
              isPlainPopoverHoldKey(event),
              let window = popover.contentViewController?.view.window else {
            return event
        }

        // Text controls inside the popover, especially the Homebrew search
        // field, need Space/Return delivered through AppKit's normal field
        // editor path so delegates and target/actions can submit correctly.
        if isTextEditingActive(in: window) {
            return event
        }

        if NSApp.keyWindow === window || event.window === window {
            window.firstResponder?.keyDown(with: event)
            return nil
        }
        return event
    }

    private func isPlainPopoverHoldKey(_ event: NSEvent) -> Bool {
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return false }
        return event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76
    }

    private func isTextEditingActive(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField {
            return true
        }
        guard let fieldEditor = window.fieldEditor(false, for: nil) else { return false }
        return responder === fieldEditor
    }

    @objc private func appResignedActive() {
        // Leaving the app entirely (e.g. ⌘Tab) dismisses the panel; switching to
        // our own Settings window keeps the app active, so it stays open.
        if popover.isShown, !PanelInteractionState.shared.keepsPopoverOpen {
            guard statusController.containsStatusItem(at: NSEvent.mouseLocation) == false else { return }
            closePopover()
        }
    }

    @objc private func appBecameActive() {
        // Coming back to the app is a good moment to surface a fresh release.
        // (Menu bar icon recovery happens on a deliberate reopen, not here: this
        // fires on every activation, so rebuilding here would cause churn/flicker.)
        UpdateService.shared.checkIfStale()
    }

    func closePopover(animated: Bool = true, after delay: TimeInterval = 0,
                      completion: (() -> Void)? = nil) {
        if delay <= 0 {
            closePopoverNow(animated: animated, completion: completion)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.closePopoverNow(animated: animated, completion: completion)
        }
    }

    private func closePopoverNow(animated: Bool, completion: (() -> Void)?) {
        guard popover.isShown else {
            completion?()
            return
        }
        if let completion { popoverCloseCompletions.append(completion) }
        guard !popoverIsClosing else { return }
        guard animated, let window = popover.contentViewController?.view.window else {
            finishPopoverClose()
            return
        }

        popoverIsClosing = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = popoverCloseDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            window?.alphaValue = 1
            self?.finishPopoverClose()
        }
    }

    private func animatePopoverOpen(_ window: NSWindow) {
        popoverIsClosing = false
        window.alphaValue = 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = popoverOpenDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        } completionHandler: { [weak self, weak window] in
            guard let self,
                  self.popover.isShown,
                  window === self.popover.contentViewController?.view.window else { return }
            window?.alphaValue = 1
        }
    }

    private func finishPopoverClose() {
        guard popover.isShown else {
            popoverIsClosing = false
            runPopoverCloseCompletions()
            return
        }
        popoverIsClosing = true
        popover.performClose(nil)
        runPopoverCloseCompletions()
    }

    private func runPopoverCloseCompletions() {
        let completions = popoverCloseCompletions
        popoverCloseCompletions.removeAll()
        completions.forEach { $0() }
    }

    // The SwiftUI panel reports which monitor sections are actually visible; the
    // popover callback only handles update freshness.
    func popoverWillShow(_ notification: Notification) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .menuPanelWillShow, object: nil)
        }
        SystemMonitor.shared.suppressGPUReadsForTransientUI()
        if !popoverIsSwitchingAnchor {
            UpdateService.shared.checkIfStale()
        }
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        popoverIsClosing || !PanelInteractionState.shared.keepsPopoverOpen
    }

    func popoverDidClose(_ notification: Notification) {
        if !popoverIsSwitchingAnchor {
            SystemMonitor.shared.setMenuPanelNeeds(.none)
        }
        if !popoverIsSwitchingAnchor {
            MenuPanelFocus.shared.clearMetricFocus()
            ProcessUsageService.shared.clearCachedRows()
            ResponsibleProcess.clearIconCache()
        }
        removePopoverDismissMonitor()
        PanelInteractionState.shared.keepsPopoverOpen = false
        popoverClosedAt = popoverIsSwitchingAnchor ? .distantPast : Date()
        popoverIsClosing = false
        runPopoverCloseCompletions()
    }

    // MARK: - Context menu (right click)

    private func showContextMenu() {
        // The panel uses applicationDefined dismissal, so a right-click while it's
        // open won't close it on its own — and the menu would try to open behind it.
        // Close it first so the context menu always appears.
        if popover.isShown {
            closePopover { [weak self] in self?.presentContextMenu() }
            return
        }

        presentContextMenu()
    }

    private func presentContextMenu() {
        let manager = KeepAwakeManager.shared
        let strings = L10n.shared.s
        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: manager.isActive ? strings.menuDisableAwake : strings.menuEnableAwake,
                                    action: #selector(menuToggleAwake),
                                    keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        if !manager.isActive {
            let durationsItem = NSMenuItem(title: strings.menuActivateFor, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let options: [(String, Int)] = [(strings.minutes15, 15), (strings.minutes30, 30),
                                            (strings.hour1, 60), (strings.hours2, 120),
                                            (strings.hours4, 240), (strings.hours8, 480),
                                            (strings.indefinitely, 0)]
            for (label, minutes) in options {
                let item = NSMenuItem(title: label, action: #selector(menuActivateDuration(_:)), keyEquivalent: "")
                item.target = self
                item.tag = minutes
                submenu.addItem(item)
            }
            durationsItem.submenu = submenu
            menu.addItem(durationsItem)
        }

        let cleaningItem = NSMenuItem(title: strings.cleaningMenuItem,
                                      action: #selector(menuCleaningMode), keyEquivalent: "")
        cleaningItem.target = self
        menu.addItem(cleaningItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: strings.menuSettings, action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: strings.menuAbout, action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let uninstallItem = NSMenuItem(title: strings.uninstallerMenuItem,
                                       action: #selector(menuOpenUninstaller), keyEquivalent: "")
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        if UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) {
            let shelfItem = NSMenuItem(title: strings.shelfMenuItem,
                                       action: #selector(menuOpenShelf), keyEquivalent: "")
            shelfItem.target = self
            menu.addItem(shelfItem)
        }

        let updatesItem = NSMenuItem(title: strings.menuCheckUpdates, action: #selector(menuCheckUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: strings.menuQuit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusController.statusItem.menu = menu
        statusController.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusController.statusItem.menu = nil
        }
    }

    @objc private func menuToggleAwake() {
        KeepAwakeManager.shared.toggle()
    }

    @objc private func menuCleaningMode() {
        CleaningModeManager.shared.activate()
    }

    @objc private func menuActivateDuration(_ sender: NSMenuItem) {
        KeepAwakeManager.shared.activate(minutes: sender.tag)
    }

    @objc private func menuOpenSettings() {
        openSettingsWindow()
    }

    @objc private func menuOpenUninstaller() {
        SettingsRouter.shared.page = .uninstaller
        openSettingsWindow()
    }

    @objc private func menuOpenShelf() {
        ShelfService.shared.summon()
    }

    @objc private func menuCheckUpdates() {
        UpdateService.shared.check(manual: true)
        openSettingsWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: L10n.shared.s.aboutDescription,
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: - Application menu

    /// Builds and installs the standard application menu (App / Edit / Window).
    ///
    /// Because the app runs as an accessory, AppKit never gives it the default main
    /// menu a regular app gets, so `NSApp.mainMenu` stays nil and the standard key
    /// equivalents (which live on menu items) never resolve. That is why nothing
    /// happens for Cmd+H/M/W/Q or Cmd+C/V/X/A inside the Settings window. A minimal
    /// standard menu restores them. The menu bar only appears while one of the
    /// app's own windows is focused; otherwise the app is as invisible as before.
    /// Most items use the responder chain (nil target) so they act on the key
    /// window or the focused text field; About and Settings route to our handlers.
    func installMainMenu() {
        let strings = L10n.shared.s
        let mainMenu = NSMenu()

        // Application menu (the bold, app-named first menu).
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let about = NSMenuItem(title: strings.menuAbout, action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let settings = NSMenuItem(title: strings.menuSettings, action: #selector(menuOpenSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())

        appMenu.addItem(NSMenuItem(title: strings.menuHide,
                                   action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: strings.menuHideOthers,
                                    action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: strings.menuShowAll,
                                   action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: strings.menuQuit,
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Edit menu, so text fields in Settings respond to the editing shortcuts.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: strings.menuEdit)
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: strings.menuUndo, action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: strings.menuRedo, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: strings.menuCut, action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: strings.menuCopy, action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: strings.menuPaste, action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: strings.menuSelectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        // Window menu (Minimize / Zoom / Close). Settings is .miniaturizable so
        // Cmd+M actually minimizes; AppKit manages enabling once windowsMenu is set.
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: strings.menuWindow)
        windowMenuItem.submenu = windowMenu

        windowMenu.addItem(NSMenuItem(title: strings.menuMinimize,
                                      action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: strings.menuZoom,
                                      action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: strings.menuClose,
                                      action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Windows

    func openSettingsWindow() {
        // Intentionally does NOT close the panel: the panel uses applicationDefined
        // dismissal, so it stays open beside Settings for a live preview.
        let createdWindow = settingsWindow == nil
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: host)
            // .miniaturizable so the Window menu's Minimize (Cmd+M) actually works.
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.hidesOnDeactivate = false
            window.canHide = false
            window.delegate = self
            settingsWindow = window
        }
        settingsWindow?.title = L10n.shared.s.settingsTitle
        if let window = settingsWindow {
            positionSettingsWindow(window, force: createdWindow)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.settingsWindow else { return }
            self.positionSettingsWindow(window, force: false)
        }
    }

    private func positionSettingsWindow(_ window: NSWindow, force: Bool) {
        window.contentView?.layoutSubtreeIfNeeded()
        let popoverWindow = popover.contentViewController?.view.window
        let screen = popoverWindow?.screen ?? window.screen ?? NSScreen.withMouse
        let visible = screen.visibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let width = min(max(window.frame.width, 360), availableWidth)
        let height = min(max(window.frame.height, 320), availableHeight)
        var frame = force
            ? NSRect(x: visible.midX - width / 2,
                     y: visible.midY - height / 2,
                     width: width,
                     height: height)
            : NSRect(x: window.frame.minX,
                     y: window.frame.minY,
                     width: width,
                     height: height)

        if let popoverFrame = popoverWindow?.frame,
           visible.intersects(popoverFrame),
           frame.intersects(popoverFrame) {
            frame = settingsFrame(frame, avoiding: popoverFrame, in: visible)
        } else if force {
            frame.origin.x = min(max(frame.origin.x, visible.minX + margin / 2), visible.maxX - width - margin / 2)
            frame.origin.y = min(max(frame.origin.y, visible.minY + margin / 2), visible.maxY - height - margin / 2)
        }
        window.setFrame(frame.integral, display: false)
    }

    private func settingsFrame(_ frame: NSRect, avoiding popoverFrame: NSRect, in visible: NSRect) -> NSRect {
        let gap: CGFloat = 28
        let margin: CGFloat = 20
        var adjusted = frame

        let leftX = popoverFrame.minX - gap - frame.width
        let rightX = popoverFrame.maxX + gap
        if popoverFrame.midX >= visible.midX, leftX >= visible.minX + margin {
            adjusted.origin.x = min(frame.origin.x, leftX)
        } else if popoverFrame.midX < visible.midX,
                  rightX + frame.width <= visible.maxX - margin {
            adjusted.origin.x = max(frame.origin.x, rightX)
        } else {
            let belowY = popoverFrame.minY - gap - frame.height
            let aboveY = popoverFrame.maxY + gap
            if belowY >= visible.minY + margin {
                adjusted.origin.y = min(frame.origin.y, belowY)
            } else if aboveY + frame.height <= visible.maxY - margin {
                adjusted.origin.y = max(frame.origin.y, aboveY)
            }
        }

        adjusted.origin.x = min(max(adjusted.origin.x, visible.minX + margin), visible.maxX - frame.width - margin)
        adjusted.origin.y = min(max(adjusted.origin.y, visible.minY + margin), visible.maxY - frame.height - margin)
        return adjusted
    }

    /// Rebuilds the menu bar item so the icon reappears when the OS has dropped it
    /// from a crowded or notched menu bar. Backs the "Show menu bar icon" button.
    func reshowStatusItem() {
        statusController?.recreateStatusItem()
    }

    /// Quits and reopens the app. Full Disk Access only applies to a fresh
    /// process, so this is how the uninstaller picks up a just-granted grant.
    func relaunchApp() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.3; /usr/bin/open \"$1\"", "vorssaint-relaunch", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    func showOnboarding(mode: OnboardingMode = .full) {
        closePopover()
        if let window = onboardingWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: OnboardingView(mode: mode) { [weak self] in
            self?.markOnboardingComplete()
            Notifier.requestPermission()
            self?.onboardingWindow?.close()
        })
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = mode.title(L10n.shared.s)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerOnboardingWindow(window)
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.onboardingWindow else { return }
            self.centerOnboardingWindow(window)
        }
    }

    /// On launch after an update, do not re-open What's New: every update path
    /// shows the changelog before download. Keep only one-off feature intros.
    private func presentUpdateIntros() {
        if showUpdateShowcaseIntroIfNeeded() { return }
        if showSupportUpdateIntroIfNeeded() { return }
        showDockPreviewIntroIfNeeded()
    }

    private func showUpdateShowcaseIntroIfNeeded() -> Bool {
        guard AppInfo.version == UpdateShowcaseInfo.releaseVersion else {
            UpdateShowcaseInfo.cleanupCache()
            return false
        }
        guard UserDefaults.standard.string(forKey: DefaultsKey.updateShowcaseIntroVersion)
                != UpdateShowcaseInfo.releaseVersion else {
            UpdateShowcaseInfo.cleanupCache()
            return false
        }
        showUpdateShowcaseIntro()
        return true
    }

    private func showUpdateShowcaseIntro() {
        closePopover()
        if let window = updateShowcaseWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: UpdateShowcaseIntroView(
            onClose: { [weak self] in
                self?.markUpdateShowcaseIntroSeen()
                self?.updateShowcaseWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.updateShowcaseTitle
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerUpdateShowcaseWindow(window)
        updateShowcaseWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.updateShowcaseWindow else { return }
            self.centerUpdateShowcaseWindow(window)
        }
    }

    private func showSupportUpdateIntroIfNeeded() -> Bool {
        guard AppInfo.version == SupportUpdateIntroInfo.releaseVersion else { return false }
        guard UserDefaults.standard.string(forKey: DefaultsKey.supportUpdateIntroVersion)
                != SupportUpdateIntroInfo.releaseVersion else { return false }
        showSupportUpdateIntro()
        return true
    }

    private func showSupportUpdateIntro() {
        closePopover()
        if let window = supportIntroWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: UpdateSupportIntroView(
            onClose: { [weak self] in
                self?.markSupportUpdateIntroSeen()
                self?.supportIntroWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.supportIntroTitle
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerSupportIntroWindow(window)
        supportIntroWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.supportIntroWindow else { return }
            self.centerSupportIntroWindow(window)
        }
    }

    /// True on the release that introduced Dock Preview, or any later one.
    private var isAtLeastDockPreviewRelease: Bool {
        let current = AppInfo.version
        let intro = DockPreviewIntroInfo.releaseVersion
        return current == intro || UpdateService.isNewer(current, than: intro)
    }

    private func showDockPreviewIntroIfNeeded() {
        // Show on the Dock Preview release or any later version, so users who
        // skip versions still get it once, and never re-show it once seen.
        guard isAtLeastDockPreviewRelease else { return }
        guard UserDefaults.standard.string(forKey: DefaultsKey.dockPreviewIntroVersion) == nil else { return }
        showDockPreviewIntro()
    }

    private func showDockPreviewIntro() {
        closePopover()
        if let window = dockPreviewIntroWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: DockPreviewIntroView(
            onDismiss: { [weak self] in
                self?.markDockPreviewIntroSeen()
                self?.dockPreviewIntroWindow?.close()
            },
            onEnable: { [weak self] in
                DockPreviewService.shared.syncWithPreferences()
                guard !DockPreviewService.shared.dockMagnification else { return }
                UserDefaults.standard.set(true, forKey: DefaultsKey.dockPreviewEnabled)
                DockPreviewService.shared.syncWithPreferences()
                self?.markDockPreviewIntroSeen()
                self?.dockPreviewIntroWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.dockPreviewName
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerDockPreviewIntroWindow(window)
        dockPreviewIntroWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.dockPreviewIntroWindow else { return }
            self.centerDockPreviewIntroWindow(window)
        }
    }

    private func centerOnboardingWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        let screen = window.screen ?? popover.contentViewController?.view.window?.screen ?? NSScreen.withMouse
        let visible = screen.visibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let width = min(max(window.frame.width, 540), availableWidth)
        let height = min(max(window.frame.height, 600), availableHeight)
        let frame = NSRect(x: visible.midX - width / 2,
                           y: visible.midY - height / 2,
                           width: width,
                           height: height)
        window.setFrame(frame.integral, display: false)
    }

    private func centerDockPreviewIntroWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        let screen = window.screen ?? popover.contentViewController?.view.window?.screen ?? NSScreen.withMouse
        let visible = screen.visibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let width = min(max(window.frame.width, 660), availableWidth)
        let height = min(max(window.frame.height, 600), availableHeight)
        let frame = NSRect(x: visible.midX - width / 2,
                           y: visible.midY - height / 2,
                           width: width,
                           height: height)
        window.setFrame(frame.integral, display: false)
    }

    private func centerWhatsNewWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        let screen = window.screen ?? popover.contentViewController?.view.window?.screen ?? NSScreen.withMouse
        let visible = screen.visibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let width = min(max(window.frame.width, 640), availableWidth)
        let height = min(max(window.frame.height, 600), availableHeight)
        let frame = NSRect(x: visible.midX - width / 2,
                           y: visible.midY - height / 2,
                           width: width,
                           height: height)
        window.setFrame(frame.integral, display: false)
    }

    private func centerSupportIntroWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        let screen = window.screen ?? popover.contentViewController?.view.window?.screen ?? NSScreen.withMouse
        let visible = screen.visibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let width = min(max(window.frame.width, 560), availableWidth)
        let height = min(max(window.frame.height, 430), availableHeight)
        let frame = NSRect(x: visible.midX - width / 2,
                           y: visible.midY - height / 2,
                           width: width,
                           height: height)
        window.setFrame(frame.integral, display: false)
    }

    private func centerUpdateShowcaseWindow(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        let screen = window.screen ?? popover.contentViewController?.view.window?.screen ?? NSScreen.withMouse
        let visible = screen.visibleFrame
        let margin: CGFloat = 40
        let availableWidth = max(1, visible.width - margin)
        let availableHeight = max(1, visible.height - margin)
        let width = min(CGFloat(680), availableWidth)
        let height = min(CGFloat(600), availableHeight)
        let frame = NSRect(x: visible.midX - width / 2,
                           y: visible.midY - height / 2,
                           width: width,
                           height: height)
        window.setFrame(frame.integral, display: false)
    }

    /// The pre-install update preview, shown before any download from BOTH the
    /// Settings install button and the menu panel's update banner (the blue
    /// button most people use), so the changelog is always seen first. In the
    /// Developer build `downloadAndInstall()` is a no-op, so confirming is safe.
    func showUpdatePreview() {
        guard case let .available(version) = UpdateService.shared.state else { return }
        closePopover()
        if let window = updatePreviewWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: UpdatePreviewView(
            version: version,
            notes: UpdateService.shared.availableNotes,
            onUpdate: { [weak self] in
                self?.updatePreviewWindow?.close()
                UpdateService.shared.downloadAndInstall()
            },
            onCancel: { [weak self] in
                self?.updatePreviewWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.tabReleaseNotes
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerWhatsNewWindow(window)
        updatePreviewWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.updatePreviewWindow else { return }
            self.centerWhatsNewWindow(window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            return
        }
        if window === onboardingWindow {
            onboardingWindow = nil
            // Closing the window mid-flow counts as "skip" — but quitting (e.g.
            // the relaunch macOS forces after granting Screen Recording) must NOT,
            // so the flow can resume where it stopped.
            guard !isTerminating else { return }
            markOnboardingComplete()
        }
        if window === dockPreviewIntroWindow {
            dockPreviewIntroWindow = nil
            guard !isTerminating else { return }
            markDockPreviewIntroSeen()
        }
        if window === supportIntroWindow {
            supportIntroWindow = nil
            guard !isTerminating else { return }
            markSupportUpdateIntroSeen()
        }
        if window === updateShowcaseWindow {
            updateShowcaseWindow = nil
            guard !isTerminating else { return }
            markUpdateShowcaseIntroSeen()
        }
        if window === updatePreviewWindow {
            updatePreviewWindow = nil
        }
    }

    /// Marks both the first run and this version's feature tour as seen, so
    /// neither reappears on the next launch.
    private func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.hasOnboarded)
        UserDefaults.standard.set(OnboardingInfo.currentFeatureSet, forKey: DefaultsKey.featuresOnboardingVersion)
        UserDefaults.standard.set(AppInfo.version, forKey: DefaultsKey.lastUpdateIntroVersion)
        markDockPreviewIntroSeenIfCurrentUpdate()
        markSupportUpdateIntroSeenIfCurrentUpdate()
        markUpdateShowcaseIntroSeenIfCurrentUpdate()
    }

    private func markDockPreviewIntroSeenIfCurrentUpdate() {
        // A clean install that just finished onboarding on the Dock Preview
        // release (or later) should not then be shown the intro popup.
        guard isAtLeastDockPreviewRelease else { return }
        markDockPreviewIntroSeen()
    }

    private func markDockPreviewIntroSeen() {
        UserDefaults.standard.set(AppInfo.version, forKey: DefaultsKey.dockPreviewIntroVersion)
    }

    private func markSupportUpdateIntroSeenIfCurrentUpdate() {
        guard AppInfo.version == SupportUpdateIntroInfo.releaseVersion else { return }
        markSupportUpdateIntroSeen()
    }

    private func markSupportUpdateIntroSeen() {
        UserDefaults.standard.set(SupportUpdateIntroInfo.releaseVersion,
                                  forKey: DefaultsKey.supportUpdateIntroVersion)
    }

    private func markUpdateShowcaseIntroSeenIfCurrentUpdate() {
        guard AppInfo.version == UpdateShowcaseInfo.releaseVersion else { return }
        markUpdateShowcaseIntroSeen()
    }

    private func markUpdateShowcaseIntroSeen() {
        UserDefaults.standard.set(UpdateShowcaseInfo.releaseVersion,
                                  forKey: DefaultsKey.updateShowcaseIntroVersion)
    }
}
