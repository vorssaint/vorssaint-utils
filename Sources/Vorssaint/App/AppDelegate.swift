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
    private var isTerminating = false
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

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
        statusController.onLeftClick = { [weak self] in self?.togglePopover() }
        statusController.onRightClick = { [weak self] in self?.showContextMenu() }

        setUpPopover()
        bindManagers()

        HotkeyManager.shared.onActivate = { [weak self] in self?.instantPurge() }
        HotkeyManager.shared.setEnabled(UserDefaults.standard.bool(forKey: DefaultsKey.purgeHotkeyEnabled))
        Notifier.requestPermission()
        MemoryAutoPurger.shared.start()

        KeepAwakeManager.shared.recoverIfNeeded()
        AppActivationTracker.shared.start()
        ScrollInverter.shared.syncWithPreferences()
        AppSwitcher.shared.syncWithPreferences()
        FinderCutPaste.shared.syncWithPreferences()
        AutoQuitService.shared.syncWithPreferences()
        ShelfService.shared.syncWithPreferences()
        AppVolumeMixer.shared.start()
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
                FinderCutPaste.shared.syncWithPreferences()
                AutoQuitService.shared.syncWithPreferences()
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
        } else if defaults.integer(forKey: DefaultsKey.featuresOnboardingVersion) < OnboardingInfo.currentFeatureSet {
            // Updates should stay quiet. Mark the current feature tour as seen so
            // older installs do not get legacy language/support update prompts.
            defaults.set(OnboardingInfo.currentFeatureSet, forKey: DefaultsKey.featuresOnboardingVersion)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        MemoryAutoPurger.shared.stop()
        AppVolumeMixer.shared.stopAll()
        KeepAwakeManager.shared.deactivate(reason: .quit)
    }

    func instantPurge() {
        MemoryPurgeService.purge(mode: .standard, trigger: .manual) { result in
            SystemMonitor.shared.refreshNow()
            if UserDefaults.standard.bool(forKey: DefaultsKey.autoPurgeNotify) {
                Notifier.post(title: "MemoryKill pressure relief", body: result.message)
            }
        }
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
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(rootView: MemoryPanelView())
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        NotificationCenter.default.addObserver(self, selector: #selector(appResignedActive),
                                               name: NSApplication.didResignActiveNotification, object: nil)
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // The click that just transient-dismissed the popover also lands here;
        // reopening would make the panel look impossible to close.
        guard Date().timeIntervalSince(popoverClosedAt) > 0.35 else { return }
        guard let button = statusController.button else { return }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            // Keep the panel alive next to fullscreen apps and on any Space —
            // without this it blinks shut when another display is fullscreen.
            window.collectionBehavior.insert([.fullScreenAuxiliary, .canJoinAllSpaces])
            window.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
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
    }

    private func shouldDismissPopover(forLocalEvent event: NSEvent) -> Bool {
        guard event.window === settingsWindow,
              let settingsFrame = settingsWindow?.frame,
              let popoverFrame = popover.contentViewController?.view.window?.frame else {
            return false
        }
        return settingsFrame.intersects(popoverFrame)
    }

    @objc private func appResignedActive() {
        // Leaving the app entirely (e.g. ⌘Tab) dismisses the panel; switching to
        // our own Settings window keeps the app active, so it stays open.
        if popover.isShown { closePopover() }
    }

    @objc private func appBecameActive() {
        // Coming back to the app is a good moment to surface a fresh release.
        // (Menu bar icon recovery happens on a deliberate reopen, not here: this
        // fires on every activation, so rebuilding here would cause churn/flicker.)
        UpdateService.shared.checkIfStale()
    }

    func closePopover(after delay: TimeInterval = 0) {
        if delay <= 0 {
            popover.performClose(nil)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.popover.performClose(nil)
            }
        }
    }

    // While the panel is on screen the monitor samples everything (temperatures,
    // GPU, graphs); when it closes it keeps going only if a menu bar metric needs it.
    func popoverWillShow(_ notification: Notification) {
        SystemMonitor.shared.panelDidAppear()
        UpdateService.shared.checkIfStale()
    }

    func popoverDidClose(_ notification: Notification) {
        SystemMonitor.shared.panelDidDisappear()
        removePopoverDismissMonitor()
        popoverClosedAt = Date()
    }

    // MARK: - Context menu (right click)

    private func showContextMenu() {
        if popover.isShown { popover.performClose(nil) }

        let menu = NSMenu()

        let purge = NSMenuItem(title: "Standard Pressure Relief", action: #selector(menuPurge), keyEquivalent: "")
        purge.target = self
        menu.addItem(purge)

        let deep = NSMenuItem(title: "Open Panel for Deep Purge", action: #selector(menuDeepPurge), keyEquivalent: "")
        deep.target = self
        menu.addItem(deep)

        let max = NSMenuItem(title: "Open Panel for MAX Purge", action: #selector(menuMaxPurge), keyEquivalent: "")
        max.target = self
        menu.addItem(max)

        let hog = NSMenuItem(title: "Kill Top Memory Hog", action: #selector(menuKillHog), keyEquivalent: "")
        hog.target = self
        menu.addItem(hog)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit MemoryKill", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusController.statusItem.menu = menu
        statusController.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusController.statusItem.menu = nil
        }
    }

    @objc private func menuPurge() { instantPurge() }

    @objc private func menuDeepPurge() { togglePopover() }

    @objc private func menuMaxPurge() { togglePopover() }

    @objc private func menuKillHog() {
        _ = MemoryPurgeService.killTopMemoryHog()
        SystemMonitor.shared.refreshNow()
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
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: host)
            // .miniaturizable so the Window menu's Minimize (Cmd+M) actually works.
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.canHide = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        settingsWindow?.title = L10n.shared.s.settingsTitle
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
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
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.obStepWelcomeTitle
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
    }

    /// Marks both the first run and this version's feature tour as seen, so
    /// neither reappears on the next launch.
    private func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.hasOnboarded)
        UserDefaults.standard.set(OnboardingInfo.currentFeatureSet, forKey: DefaultsKey.featuresOnboardingVersion)
    }
}
