// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The snippet library: a small floating panel, summoned by its own global
/// shortcut, that shows the snippets marked for it grouped by folder. Typing
/// filters, Enter (or a click) types the snippet into the app that was
/// active, Esc closes. The panel never activates Vorssaint, so the target
/// app keeps focus the whole time. The hotkey only lives while the library
/// toggle is on. Requires Accessibility (the synthesized typing).
final class SnippetLibraryService: ObservableObject {
    static let shared = SnippetLibraryService()

    @Published private(set) var shortcutRegistrationFailed = false
    @Published var query = "" {
        didSet { resetSelectionForQueryChange() }
    }
    @Published private(set) var selectedID: UUID?
    @Published private(set) var presentationID = UUID()
    @Published private(set) var snippets: [TextSnippet] = []

    private let hotkey = QuickToolHotkey(id: 19)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    /// The permission prompt fires at most once per launch; later attempts
    /// without Accessibility beep instead of nagging (PastePlain's pattern).
    private var promptedForAccessibility = false

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.textSnippets.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.snippetLibraryEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.snippetLibraryShortcut,
                                            fallback: .snippetLibraryDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
        if !enabled { hide() }
        if isVisible {
            reloadSnippets()
            // Edits made in Settings can flip the panel between its list and
            // empty states, which have different heights.
            refreshPanelLayout()
        }
    }

    func suspend() {
        hotkey.unregister()
        hide()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    // MARK: - Content

    var sections: [TextSnippetSupport.LibrarySection] {
        TextSnippetSupport.librarySections(snippets, query: query)
    }

    var rows: [TextSnippet] {
        TextSnippetSupport.libraryRows(sections)
    }

    /// Whether there is anything to put in the library at all, search aside;
    /// drives the empty state that points at the snippets settings.
    var hasLibraryContent: Bool {
        snippets.contains { $0.enabled && $0.showsInLibrary }
    }

    private func reloadSnippets() {
        snippets = TextSnippetSupport.decode(
            UserDefaults.standard.data(forKey: DefaultsKey.textSnippets))
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
        reloadSnippets()
        let panel = ensurePanel()
        presentationID = UUID()
        query = ""
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
        removeMonitors()
        panel?.orderOut(nil)
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
    }

    // MARK: - Insertion

    func insertSelection() {
        guard let snippet = rows.first(where: { $0.id == selectedID }) else { return }
        insert(snippet)
    }

    func insert(at index: Int) {
        let rows = rows
        guard rows.indices.contains(index) else { return }
        insert(rows[index])
    }

    func insert(_ snippet: TextSnippet) {
        hide()
        // The panel never activates, so focus normally sits in the target
        // app. When Vorssaint itself is frontmost (its Settings window, for
        // example), the synthetic typing would land in our own fields.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier {
            NSSound.beep()
            return
        }
        guard AXIsProcessTrusted() else {
            if promptedForAccessibility {
                NSSound.beep()
            } else {
                promptedForAccessibility = true
                Permissions.shared.requestAccessibility()
            }
            return
        }
        let text = TextSnippetSupport.expand(snippet.replacement,
                                             date: Date(),
                                             clipboard: NSPasteboard.general.string(forType: .string))
        // A beat for the panel to leave the screen; the target app kept focus
        // (the panel never activates), so the caret is exactly where the user
        // left it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.postWhenModifiersReleased(text: text, attempt: 0)
        }
    }

    /// Typing while ⌘ (or any modifier of ⌘1/Enter) is still physically down
    /// turns every character into a shortcut in the target app, so wait for a
    /// clean keyboard first: every 15 ms for up to ~1.5 s, plus a settle beat
    /// (PastePlain's proven dance). Secure input means a password field:
    /// nothing may be typed there.
    private func postWhenModifiersReleased(text: String, attempt: Int) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        // A modifier still pinned after ~1.5 s means the keyboard never came
        // clean; typing anyway would turn every character into a shortcut in
        // the target app. Give up audibly instead.
        if attempt >= 100 {
            NSSound.beep()
            return
        }
        guard held.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
                self?.postWhenModifiersReleased(text: text, attempt: attempt + 1)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard !IsSecureEventInputEnabled() else {
                NSSound.beep()
                return
            }
            TextSnippetService.postExpansion(deleteCount: 0,
                                             text: text,
                                             trailingKeyCode: nil,
                                             trailingFlags: [])
        }
    }

    // MARK: - Panel

    /// Borderless panels refuse key status by default, and the library needs
    /// it for the search field, arrows and Esc.
    private final class KeyableLibraryPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableLibraryPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
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
        let host = NSHostingController(rootView: SnippetLibraryView())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    /// Spotlight-style placement, same as the quick launcher: centered on the
    /// screen with the mouse, a bit above the middle.
    private func position(_ panel: NSPanel) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 460, height: 420)
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

    /// The list area is fixed-height inside the view, but the empty states
    /// swap heights; keep the panel snug after content changes.
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
            switch Int(event.keyCode) {
            case kVK_Escape:
                self.hide()
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.insertSelection()
                return nil
            case kVK_UpArrow:
                self.moveSelection(by: -1)
                return nil
            case kVK_DownArrow:
                self.moveSelection(by: 1)
                return nil
            default:
                // Plain digits belong to the search text; only ⌘1…⌘9 insert
                // by position.
                if event.modifierFlags.contains(.command),
                   let index = Self.digitIndex(for: event.keyCode) {
                    self.insert(at: index)
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
