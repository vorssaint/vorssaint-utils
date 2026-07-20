// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Everything the quick launcher can hold. Raw values are storage ids for
/// the user's order and hidden set.
enum QuickLauncherItem: String, PanelOrderItem, Identifiable {
    // Case order is the default grid order; the cleaner comes second, right
    // after Keep awake, by the owner's decision. Saved orders are untouched
    // (a case added later joins a saved order at the end).
    case keepAwake, cleaner, toggles, micMute, screenOCR, colorPicker, clipboard, windowLayout,
         cleaning, homebrew, media, urlCleaner, uninstaller, screenshot, cameraPreview, scratchpad

    var id: String { rawValue }

    /// The hub feature behind the tile; off in the hub removes it from the
    /// grid, the hidden list and edit mode until it returns.
    var feature: AppFeature {
        switch self {
        case .keepAwake: return .keepAwake
        case .cleaner: return .cleaner
        case .toggles: return .quickToggles
        case .micMute: return .micMute
        case .screenOCR: return .screenOCR
        case .colorPicker: return .colorPicker
        case .clipboard: return .clipboardHistory
        case .windowLayout: return .windowLayout
        case .cleaning: return .cleaningMode
        case .homebrew: return .homebrew
        case .media: return .mediaTools
        case .urlCleaner: return .urlCleaner
        case .uninstaller: return .uninstaller
        case .screenshot: return .screenshot
        case .cameraPreview: return .cameraPreview
        case .scratchpad: return .scratchpad
        }
    }
}

/// The floating quick panel: a small, pretty launcher with the user's
/// favorite tools, summoned from anywhere with a global shortcut (⌃⌘V by
/// default; V for Vorssaint). Fully customizable in place: items can be
/// hidden, brought back and reordered by dragging.
final class QuickLauncherService: ObservableObject {
    static let shared = QuickLauncherService()

    static let columns = 3

    @Published private(set) var shortcutRegistrationFailed = false
    @Published var isEditing = false
    /// The tile whose inline options card is open in edit mode. Lives here
    /// (not in the view) so the Esc key monitor can close the card first,
    /// before leaving edit mode and before hiding the panel.
    @Published var editingOptionsItem: QuickLauncherItem?
    /// A utility view (Homebrew, Uninstaller…) currently hosted INSIDE the
    /// launcher, replacing the grid. Everything happens in this panel; the
    /// menu bar popover is never involved.
    @Published private(set) var activeUtility: QuickLauncherItem?
    @Published private(set) var selectedIndex: Int?
    @Published private(set) var presentationID = UUID()
    @Published private(set) var hiddenItemsRaw: String = UserDefaults.standard.string(
        forKey: DefaultsKey.quickLauncherHiddenItems) ?? ""

    private let hotkey = QuickToolHotkey(id: 14)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.quickLauncher.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.quickLauncherShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.quickLauncherShortcut,
                                            fallback: .quickLauncherDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
    }

    func suspend() {
        hotkey.unregister()
        hide()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    // MARK: - Items

    var visibleItems: [QuickLauncherItem] {
        let hidden = QuickToolsSupport.hiddenIDs(from: hiddenItemsRaw)
        return orderedItems.filter { !hidden.contains($0.rawValue) }
    }

    var hiddenItems: [QuickLauncherItem] {
        let hidden = QuickToolsSupport.hiddenIDs(from: hiddenItemsRaw)
        return orderedItems.filter { hidden.contains($0.rawValue) }
    }

    private var orderedItems: [QuickLauncherItem] {
        PanelLayout.itemOrder(QuickLauncherItem.self, key: DefaultsKey.quickLauncherItemOrder)
            .filter { $0.feature.isAvailable }
    }

    var itemOrderBinding: Binding<[QuickLauncherItem]> {
        Binding {
            self.orderedItems
        } set: { newValue in
            PanelLayout.setItemOrder(newValue, key: DefaultsKey.quickLauncherItemOrder)
            self.objectWillChange.send()
        }
    }

    func setHidden(_ item: QuickLauncherItem, _ hidden: Bool) {
        var ids = QuickToolsSupport.hiddenIDs(from: hiddenItemsRaw)
        if hidden {
            ids.insert(item.rawValue)
            // Hiding the tile whose options card is open would orphan the
            // card below a grid that no longer shows its owner.
            if editingOptionsItem == item { editingOptionsItem = nil }
        } else {
            ids.remove(item.rawValue)
        }
        hiddenItemsRaw = QuickToolsSupport.serializeHiddenIDs(ids)
        UserDefaults.standard.set(hiddenItemsRaw, forKey: DefaultsKey.quickLauncherHiddenItems)
        clampSelection()
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
        let panel = ensurePanel()
        presentationID = UUID()
        isEditing = false
        editingOptionsItem = nil
        activeUtility = nil
        selectedIndex = visibleItems.isEmpty ? nil : 0
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
        isEditing = false
        editingOptionsItem = nil
        activeUtility = nil
        panel?.orderOut(nil)
    }

    func closeUtility() {
        activeUtility = nil
    }

    /// Hands key focus back after a modal dialog ran on top of the launcher
    /// (choosing a file in Media, for example), so Esc and the keyboard
    /// shortcuts keep working without an extra click.
    func refocusAfterModal() {
        guard let panel, panel.isVisible else { return }
        panel.makeKey()
    }

    /// The single owner of the dismissal policy: the bare grid behaves like a
    /// transient HUD, but with a utility hosted inside the launcher is a
    /// working window that must survive its own dialogs, admin prompts and
    /// clicks in other apps (dragging a file into Media). Every dismissal
    /// trigger consults this, so a future one cannot forget the rule.
    private var dismissesOnOutsideInteraction: Bool {
        // Edit mode counts as a working window too: the clamshell toggle in
        // the Keep awake options card can raise an admin password prompt,
        // and that prompt's activation must not tear the launcher down.
        activeUtility == nil && !isEditing
    }

    /// Re-fits the panel to its content when the grid gives way to a hosted
    /// utility (and back), keeping the top edge and horizontal center still.
    func refreshPanelLayout() {
        guard let panel, panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
            let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
            let screen = NSScreen.pointerVisibleFrame
            var frame = panel.frame
            frame.origin.x = frame.midX - size.width / 2
            frame.origin.y = frame.maxY - size.height
            frame.size = size
            frame.origin.x = max(screen.minX + 16, min(frame.origin.x, screen.maxX - size.width - 16))
            frame.origin.y = max(screen.minY + 16, frame.origin.y)
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    // MARK: - Actions

    func activateSelection() {
        guard let selectedIndex, visibleItems.indices.contains(selectedIndex) else { return }
        run(visibleItems[selectedIndex])
    }

    func activate(at index: Int) {
        guard visibleItems.indices.contains(index) else { return }
        run(visibleItems[index])
    }

    func moveSelection(_ direction: QuickToolsSupport.GridDirection) {
        let count = visibleItems.count
        guard count > 0 else { return }
        selectedIndex = QuickToolsSupport.gridIndex(after: selectedIndex ?? 0,
                                                    count: count,
                                                    columns: Self.columns,
                                                    direction: direction)
    }

    func select(_ item: QuickLauncherItem) {
        selectedIndex = visibleItems.firstIndex(of: item)
    }

    func run(_ item: QuickLauncherItem) {
        guard !isEditing else { return }
        switch item {
        case .keepAwake:
            KeepAwakeManager.shared.toggle()
        case .micMute:
            MicMuteService.shared.toggle()
        case .screenOCR:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ScreenTextService.shared.capture()
            }
        case .screenshot:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ScreenshotService.shared.capture()
            }
        case .colorPicker:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ColorSamplerService.shared.pick()
            }
        case .cameraPreview:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                CameraPreviewService.shared.show()
            }
        case .scratchpad:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ScratchpadService.shared.show()
            }
        case .clipboard:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ClipboardHistoryService.shared.showHistoryWindow()
            }
        case .cleaning:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                CleaningModeManager.shared.activate()
            }
        case .windowLayout, .homebrew, .media, .urlCleaner, .uninstaller, .cleaner, .toggles:
            activeUtility = item
        }
    }

    private func clampSelection() {
        let count = visibleItems.count
        guard count > 0 else {
            selectedIndex = nil
            return
        }
        selectedIndex = min(selectedIndex ?? 0, count - 1)
    }

    // MARK: - Panel

    /// Borderless panels refuse key status by default, and the launcher needs
    /// it for arrows, digits and Esc. Borderless also removes the invisible
    /// title-bar strip that would swallow clicks on the header controls.
    private final class KeyableLauncherPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableLauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered,
                                         defer: false)
        panel.title = "Vorssaint"
        panel.isReleasedWhenClosed = false
        // Item drag-to-reorder needs the mouse drag for itself; a background-
        // movable window would win the gesture and drag the whole panel.
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: QuickLauncherView())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    /// Spotlight-style placement: centered on the screen with the mouse,
    /// a bit above the middle so the eyes land on it naturally.
    private func position(_ panel: NSPanel) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 420, height: 380)
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

    // MARK: - Monitors

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                if self.activeUtility != nil {
                    self.activeUtility = nil
                } else if self.editingOptionsItem != nil {
                    // An open options card closes first; a second Esc then
                    // leaves edit mode, and a third hides the panel.
                    self.editingOptionsItem = nil
                } else if self.isEditing {
                    self.isEditing = false
                } else {
                    self.hide()
                }
                return nil
            }
            guard !self.isEditing, self.activeUtility == nil else { return event }
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.activateSelection()
                return nil
            case kVK_LeftArrow:
                self.moveSelection(.left)
                return nil
            case kVK_RightArrow:
                self.moveSelection(.right)
                return nil
            case kVK_UpArrow:
                self.moveSelection(.up)
                return nil
            case kVK_DownArrow:
                self.moveSelection(.down)
                return nil
            default:
                if let index = Self.digitIndex(for: event.keyCode) {
                    self.activate(at: index)
                    return nil
                }
                return event
            }
        }
        // With a utility hosted inside (Media, Homebrew, Uninstaller…) the
        // launcher is a small working window, not a transient HUD: it must
        // survive its own file dialogs and admin prompts, and clicks in other
        // apps to drag a file onto its drop zones. Only the bare grid keeps
        // the Spotlight-like dismiss-on-outside-click behavior.
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideInteraction else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hide()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideInteraction else { return }
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
                  self.dismissesOnOutsideInteraction,
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
