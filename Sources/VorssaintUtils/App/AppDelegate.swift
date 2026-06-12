import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusController: StatusItemController!
    private let popover = NSPopover()
    private var popoverClosedAt = Date.distantPast
    private var isTerminating = false
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var uninstallerWindow: NSWindow?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusController = StatusItemController()
        statusController.onLeftClick = { [weak self] in self?.togglePopover() }
        statusController.onRightClick = { [weak self] in self?.showContextMenu() }

        setUpPopover()
        bindManagers()

        HotkeyManager.shared.onActivate = { KeepAwakeManager.shared.toggle() }
        HotkeyManager.shared.setEnabled(UserDefaults.standard.bool(forKey: DefaultsKey.hotkeyEnabled))

        KeepAwakeManager.shared.recoverIfNeeded()
        AppActivationTracker.shared.start()
        ScrollInverter.shared.syncWithPreferences()
        AppSwitcher.shared.syncWithPreferences()
        FinderCutPaste.shared.syncWithPreferences()
        AutoQuitService.shared.syncWithPreferences()
        ShelfService.shared.syncWithPreferences()
        AppVolumeMixer.shared.start()
        UpdateService.shared.startAutomaticChecks()

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

        if !UserDefaults.standard.bool(forKey: DefaultsKey.hasOnboarded) {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        AppVolumeMixer.shared.stopAll()
        KeepAwakeManager.shared.deactivate(reason: .quit)
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
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(rootView: MenuPanelView())
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
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

    // The system monitor only ticks while the panel is on screen.
    func popoverWillShow(_ notification: Notification) {
        SystemMonitor.shared.start()
    }

    func popoverDidClose(_ notification: Notification) {
        SystemMonitor.shared.stop()
        popoverClosedAt = Date()
    }

    // MARK: - Context menu (right click)

    private func showContextMenu() {
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

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: strings.menuSettings, action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: strings.menuAbout, action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        if UserDefaults.standard.bool(forKey: DefaultsKey.uninstallerEnabled) {
            let uninstallItem = NSMenuItem(title: strings.uninstallerMenuItem,
                                           action: #selector(menuOpenUninstaller), keyEquivalent: "")
            uninstallItem.target = self
            menu.addItem(uninstallItem)
        }

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

    @objc private func menuActivateDuration(_ sender: NSMenuItem) {
        KeepAwakeManager.shared.activate(minutes: sender.tag)
    }

    @objc private func menuOpenSettings() {
        openSettingsWindow()
    }

    @objc private func menuOpenUninstaller() {
        openUninstallerWindow()
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

    // MARK: - Windows

    func openSettingsWindow() {
        closePopover()
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.title = L10n.shared.s.settingsTitle
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func openUninstallerWindow() {
        closePopover()
        AppUninstaller.shared.reset()
        if uninstallerWindow == nil {
            let host = NSHostingController(rootView: UninstallerView())
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            uninstallerWindow = window
        }
        uninstallerWindow?.title = L10n.shared.s.uninstallerWindowTitle
        NSApp.activate(ignoringOtherApps: true)
        uninstallerWindow?.makeKeyAndOrderFront(nil)
    }

    func closeUninstallerWindow() {
        uninstallerWindow?.close()
    }

    func showOnboarding() {
        closePopover()
        if let window = onboardingWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: OnboardingView { [weak self] in
            UserDefaults.standard.set(true, forKey: DefaultsKey.hasOnboarded)
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
        guard let window = notification.object as? NSWindow, window === onboardingWindow else { return }
        onboardingWindow = nil
        // Closing the window mid-flow counts as "skip" — but quitting (e.g.
        // the relaunch macOS forces after granting Screen Recording) must NOT,
        // so the flow can resume where it stopped.
        guard !isTerminating else { return }
        UserDefaults.standard.set(true, forKey: DefaultsKey.hasOnboarded)
    }
}
