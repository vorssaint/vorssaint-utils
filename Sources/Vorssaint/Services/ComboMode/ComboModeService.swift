// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Combo mode: a leader key. The recorded trigger opens a small overlay at
/// the root of the keymap; each typed key opens a group or runs an action.
/// Keys are read by a key panel of this app, so no Accessibility or Input
/// Monitoring permission is involved. Centered, that panel draws the overlay;
/// in the Dynamic Island or the bottom pill it stays unseen and keeps the
/// keyboard while the other surface shows the keys.
final class ComboModeService: ObservableObject {
    static let shared = ComboModeService()

    /// How long the overlay waits for the next key before closing.
    static let idleTimeout: TimeInterval = 5
    /// How long a "nothing on X" or launch failure message stays up.
    static let feedbackDuration: TimeInterval = 0.7

    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var navigator = ComboNavigator(keymap: ComboKeymap())
    /// A short message shown just before the overlay closes.
    @Published private(set) var feedback: String?
    @Published private(set) var presentationID = UUID()
    /// Where the open combo shows; nil while it is closed.
    @Published private(set) var surface: ComboPresentation?

    private let hotkey = QuickToolHotkey(id: 90)
    /// The centered overlay, which reads the keys itself.
    private var panel: NSPanel?
    /// Unseen, it holds the keyboard while the island or the pill shows the keys.
    private var keyPanel: NSPanel?
    /// The pill near the bottom of the screen. Never key.
    private var chipPanel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var idleTimer: Timer?
    private var closeWork: DispatchWorkItem?

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    private var isActive: Bool {
        AppFeature.comboMode.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.comboModeEnabled)
    }

    var trigger: GlobalShortcut? {
        ComboTrigger.shortcut(storedValue: UserDefaults.standard.string(forKey: DefaultsKey.comboModeTrigger))
    }

    /// Registers the trigger only while the feature is installed, switched
    /// on and has a recorded shortcut. Anything else tears everything down.
    func syncWithPreferences() {
        guard isActive, let trigger else {
            hotkey.unregister()
            shortcutRegistrationFailed = false
            hide()
            return
        }
        shortcutRegistrationFailed = !hotkey.sync(enabled: true, shortcut: trigger,
                                                  storageKey: DefaultsKey.comboModeTrigger)
    }

    // MARK: - Keymap storage

    func loadKeymap() -> ComboKeymap {
        ComboKeymap.decode(UserDefaults.standard.data(forKey: DefaultsKey.comboModeKeymap)) ?? ComboKeymap()
    }

    func saveKeymap(_ keymap: ComboKeymap) {
        if keymap.nodes.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.comboModeKeymap)
        } else if let data = keymap.encoded() {
            UserDefaults.standard.set(data, forKey: DefaultsKey.comboModeKeymap)
        }
    }

    // MARK: - Presentation

    var isVisible: Bool { surface != nil }

    /// The panel that holds the keyboard for the open combo.
    private var keyWindow: NSPanel? {
        guard let surface else { return nil }
        return surface.drawsInKeyPanel ? panel : keyPanel
    }

    /// The preference as stored; the island falls back at opening time.
    static var preferredPresentation: ComboPresentation {
        ComboPresentation.stored(UserDefaults.standard.string(forKey: DefaultsKey.comboModePresentation))
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        guard isActive else { return }
        if isVisible { hide() }
        navigator = ComboNavigator(keymap: loadKeymap())
        feedback = nil
        presentationID = UUID()
        closeWork?.cancel()
        var presentation = ComboPresentation.resolved(Self.preferredPresentation,
                                                      islandEnabled: NotchSupport.isEnabled())
        // Set before the island opens, so its view reads the new level and
        // a close reported while it opens finds the combo to end.
        surface = presentation
        if presentation == .island, !NotchService.shared.presentCombo() {
            // The island cannot open here (full screen, another display,
            // capture controls up): centered, as the Command Bar falls back
            // to its window.
            presentation = .centered
            surface = .centered
        }
        let keyHolder: NSPanel
        switch presentation {
        case .centered:
            let panel = ensurePanel()
            position(panel)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
            keyHolder = panel
        case .chip:
            let chip = ensureChipPanel()
            positionChip(chip)
            chip.alphaValue = 0
            chip.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                chip.animator().alphaValue = 1
            }
            keyHolder = ensureKeyPanel()
        case .island:
            keyHolder = ensureKeyPanel()
        }
        if keyHolder === keyPanel {
            // On the pointer's display, where the combo shows, so the system
            // keeps it with the active Space.
            let frame = NSScreen.pointerVisibleFrame
            keyHolder.setFrame(NSRect(x: frame.midX, y: frame.midY, width: 1, height: 1), display: false)
            keyHolder.orderFrontRegardless()
        }
        keyHolder.makeKey()
        installMonitors(for: keyHolder)
        restartIdleTimer()
    }

    func hide() {
        idleTimer?.invalidate()
        idleTimer = nil
        closeWork?.cancel()
        closeWork = nil
        removeMonitors()
        feedback = nil
        // Cleared first, so the island closing under the combo does not end it again.
        let shown = surface
        surface = nil
        if shown == .island { NotchService.shared.dismissCombo() }
        panel?.orderOut(nil)
        keyPanel?.orderOut(nil)
        chipPanel?.orderOut(nil)
    }

    /// The island closed around the combo, from a click away, another app,
    /// a page opened in its place or Dynamic Island being turned off.
    func islandDidClose() {
        guard surface == .island else { return }
        hide()
    }

    // MARK: - Keys

    private func handle(_ event: NSEvent) -> NSEvent? {
        let press = ComboKeyPress.classify(
            keyCode: event.keyCode,
            characters: event.characters,
            isRepeat: event.isARepeat,
            hasCommandOrControl: !event.modifierFlags.intersection([.command, .control]).isEmpty
        )
        if press == .cancel { hide(); return nil }
        // While a closing message is up, only Escape does anything.
        guard feedback == nil else { return nil }
        switch press {
        case .cancel, .ignore:
            break
        case .back:
            if navigator.back() == .cancelled { hide() } else { refit(); restartIdleTimer() }
        case .key(let key):
            switch navigator.press(key) {
            case .descended:
                refit()
                restartIdleTimer()
            case .run(let action, let node):
                run(action, node: node)
            case .noMatch:
                closeWithFeedback(String(format: strings.noMatchFormat, ComboKey.display(key)))
            case .ascended, .cancelled:
                hide()
            }
        case .unusable(let characters):
            closeWithFeedback(String(format: strings.noMatchFormat, ComboKeyPress.displayName(characters)))
        }
        return nil
    }

    private var strings: ComboModeFeatureStrings { FeatureStrings.comboMode(L10n.shared.language) }

    private func run(_ action: ComboAction, node: ComboNode) {
        switch action {
        case .openApplication(let app):
            guard let url = Self.url(for: app) else {
                closeWithFeedback(String(format: strings.launchFailedFormat, Self.name(for: app, label: node.label)))
                return
            }
            hide()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        }
    }

    private func closeWithFeedback(_ message: String) {
        idleTimer?.invalidate()
        feedback = message
        refit()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        closeWork?.cancel()
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.feedbackDuration, execute: work)
    }

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleTimeout, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    // MARK: - Apps

    static func url(for app: ComboAppReference) -> URL? {
        app.resolvedURL(urlForBundleID: InstalledApps.url(for:),
                        fileExists: { FileManager.default.fileExists(atPath: $0) })
    }

    static func icon(for app: ComboAppReference) -> NSImage {
        if let url = url(for: app) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    static func name(for app: ComboAppReference, label: String = "") -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let url = url(for: app) { return FileManager.default.displayName(atPath: url.path) }
        return app.fallbackName
    }

    /// Asks for an application bundle; nil when the dialog is cancelled.
    static func chooseApplication() -> ComboAppReference? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return ComboAppReference(bundleID: Bundle(url: url)?.bundleIdentifier, path: url.path)
    }

    // MARK: - Panel

    private final class KeyableComboPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    /// A 1-point clear panel that only holds the keyboard. It ignores
    /// the mouse, so it never stands in the way of a click.
    private func ensureKeyPanel() -> NSPanel {
        if let keyPanel { return keyPanel }
        let panel = KeyableComboPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered,
                                      defer: false)
        panel.title = "Vorssaint"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // Clear and empty, so nothing shows; left opaque to the window
        // server so it keeps the keyboard like any other key panel.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        keyPanel = panel
        return panel
    }

    private func ensureChipPanel() -> NSPanel {
        if let chipPanel { return chipPanel }
        let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 34),
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
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: ComboModeChipView())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        chipPanel = panel
        return panel
    }

    /// Centered near the bottom of the pointer's display, above the Dock.
    private func positionChip(_ panel: NSPanel) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        let screen = NSScreen.pointerVisibleFrame
        let width = min(size.width, screen.width - 32)
        panel.setFrame(NSRect(x: screen.midX - width / 2, y: screen.minY + 24, width: width, height: size.height),
                       display: true, animate: false)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableComboPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
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
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: ComboModeOverlayView())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 340, height: 200)
        let screen = NSScreen.pointerVisibleFrame
        let x = screen.midX - size.width / 2
        let y = screen.minY + (screen.height - size.height) * 0.62
        panel.setFrame(NSRect(x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                              y: max(screen.minY + 16, y),
                              width: size.width,
                              height: size.height),
                       display: true,
                       animate: false)
    }

    /// Re-fits the visible surface after the level changes: the centered
    /// panel keeps its top edge still, the pill stays centered at the
    /// bottom, and the island measures its own content.
    private func refit() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.surface == .chip, let chip = self.chipPanel, chip.isVisible {
                self.positionChip(chip)
                return
            }
            guard self.surface == .centered, let panel = self.panel, panel.isVisible else { return }
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
            let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
            let screen = NSScreen.pointerVisibleFrame
            var frame = panel.frame
            frame.origin.x = frame.midX - size.width / 2
            frame.origin.y = frame.maxY - size.height
            frame.size = size
            frame.origin.x = max(screen.minX + 16, min(frame.origin.x, screen.maxX - size.width - 16))
            frame.origin.y = max(screen.minY + 16, frame.origin.y)
            panel.setFrame(frame, display: true, animate: false)
        }
    }

    // MARK: - Monitors

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            return self.handle(event)
        }
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            if !self.showsKeys(in: event.window) { self.hide() }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return }
            if event.windowNumber != panel.windowNumber,
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) {
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
                  app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  app.bundleIdentifier != AssistiveKeyboard.bundleID
            else { return }
            self.hide()
        }
    }

    /// Whether a window of this app is where the open combo is drawn, so a
    /// click there is not a click away.
    private func showsKeys(in window: NSWindow?) -> Bool {
        guard let window, let surface else { return false }
        switch surface {
        case .centered: return window === panel
        case .chip: return window === chipPanel
        case .island: return window === NotchService.shared.presentationWindow
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
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }
}
