// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The code palette: a small floating panel on its own global shortcut
/// listing the accounts with their live codes. Typing filters, Return uses
/// the selected code (types or copies, per the setting), ⌘Return does the
/// other, ⌥Return shows the next code, Esc closes. The panel never activates
/// Vorssaint, so the app the person was in keeps focus (the snippet
/// library's pattern).
final class AuthenticatorPaletteService: ObservableObject {
    static let shared = AuthenticatorPaletteService()

    @Published private(set) var shortcutRegistrationFailed = false
    @Published var query = "" {
        didSet { resetSelectionForQueryChange() }
    }
    @Published private(set) var selectedID: UUID?
    @Published private(set) var presentationID = UUID()
    /// The account whose next code is being shown instead of the current one.
    @Published private(set) var peekingID: UUID?

    private let hotkey = QuickToolHotkey(id: 59)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.authenticator.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.authenticatorPaletteEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.authenticatorPaletteShortcut,
                                            fallback: .authenticatorPaletteDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
        if !AppFeature.authenticator.isAvailable { hide() }
        if isVisible { refreshPanelLayout() }
    }

    func suspend() {
        hotkey.unregister()
        hide()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    // MARK: - Content

    var rows: [OTPAccount] {
        AuthenticatorService.shared.matching(query)
    }

    /// Return types when the setting says so, copies otherwise.
    var returnTypes: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.authenticatorTypesCodes)
    }

    // MARK: - Presentation

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard AppFeature.authenticator.isAvailable else { return }
        AuthenticatorService.shared.syncWithPreferences()
        let wasVisible = isVisible
        let panel = ensurePanel()
        // Showing an already open palette must not subscribe to the clock
        // twice, or one hide would leave the timer running for good.
        if !wasVisible { AuthenticatorClock.shared.begin() }
        presentationID = UUID()
        query = ""
        peekingID = nil
        selectedID = rows.first?.id
        position(panel)
        installMonitors(for: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        removeMonitors()
        panel.orderOut(nil)
        AuthenticatorClock.shared.end()
    }

    // MARK: - Selection

    func select(_ id: UUID) {
        selectedID = id
    }

    func moveSelection(by offset: Int) {
        let rows = rows
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + offset, 0), rows.count - 1)
        selectedID = rows[next].id
    }

    private func resetSelectionForQueryChange() {
        selectedID = rows.first?.id
        peekingID = nil
    }

    // MARK: - Actions

    func performPrimary() {
        guard let selectedID else { return }
        use(selectedID, typing: returnTypes)
    }

    func performSecondary() {
        guard let selectedID else { return }
        use(selectedID, typing: !returnTypes)
    }

    func use(at index: Int) {
        let rows = rows
        guard rows.indices.contains(index) else { return }
        use(rows[index].id, typing: returnTypes)
    }

    func use(_ id: UUID, typing: Bool) {
        hide()
        if typing {
            AuthenticatorService.shared.typeCode(for: id)
        } else {
            AuthenticatorService.shared.copyCode(for: id)
        }
    }

    func togglePeek() {
        guard let selectedID else { return }
        peekingID = peekingID == selectedID ? nil : selectedID
    }

    /// Touch ID or the password, with the panel out of the way of the prompt.
    func unlock() {
        hide()
        AuthenticatorService.shared.unlock { [weak self] in self?.show() }
    }

    func scan() {
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AuthenticatorService.shared.scanScreen()
        }
    }

    // MARK: - Panel

    private final class KeyablePalettePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyablePalettePanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
                                        styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered,
                                        defer: false)
        panel.title = "Vorssaint"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: AuthenticatorPaletteView())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 440, height: 400)
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

    func refreshPanelLayout() {
        guard let panel, panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
            let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
            var frame = panel.frame
            frame.origin.y = frame.maxY - size.height
            frame.size = size
            panel.setFrame(frame, display: true, animate: false)
        }
    }

    // MARK: - Monitors

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
                return event
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch Int(event.keyCode) {
            case kVK_Escape:
                self.hide()
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if flags.contains(.option) {
                    self.togglePeek()
                } else if flags.contains(.command) {
                    self.performSecondary()
                } else {
                    self.performPrimary()
                }
                return nil
            case kVK_UpArrow:
                self.moveSelection(by: -1)
                return nil
            case kVK_DownArrow:
                self.moveSelection(by: 1)
                return nil
            case kVK_ANSI_C where flags == .command:
                guard let selectedID = self.selectedID else { return event }
                self.use(selectedID, typing: false)
                return nil
            case kVK_ANSI_Comma where flags == .command:
                self.hide()
                AuthenticatorService.shared.openSettings()
                return nil
            default:
                if flags == .command, let index = Self.digitIndex(for: event.keyCode) {
                    self.use(at: index)
                    return nil
                }
                return event
            }
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
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
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
