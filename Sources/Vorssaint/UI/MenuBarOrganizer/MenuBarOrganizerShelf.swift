// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The shelf: a panel that drops down under the collapser and lists the hidden
/// icons while the bar stays collapsed. Picking one hands it to `onSelect`,
/// which opens that icon's menu. It closes like a menu: Esc, a click anywhere
/// else, another app coming to the front. Main thread only.
final class MenuBarOrganizerShelf {
    static let width: CGFloat = 300
    /// Between the bottom of the menu bar and the top of the shelf.
    private static let gap: CGFloat = 6

    var onSelect: ((MenuBarItemIdentity) -> Void)?
    var onClosed: (() -> Void)?
    /// The window the collapser's clicks arrive in. Its own click toggles the
    /// shelf, so it must not also count as a click outside.
    var collapserWindow: (() -> NSWindow?)?
    private(set) var isOpen = false

    private var panel: NSPanel?
    /// Where the collapser sat when the shelf opened, in screen coordinates.
    private var anchor: NSRect?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    func toggle(anchor: NSRect?) {
        if isOpen {
            close()
        } else {
            open(anchor: anchor)
        }
    }

    func open(anchor: NSRect?) {
        let panel = ensurePanel()
        self.anchor = anchor
        position(panel, under: anchor)
        installMonitors(for: panel)
        isOpen = true
        panel.orderFrontRegardless()
        // Key, so Esc reaches it; a non-activating panel takes that without
        // pulling the app in front.
        panel.makeKey()
    }

    func close() {
        removeMonitors()
        panel?.orderOut(nil)
        guard isOpen else { return }
        isOpen = false
        anchor = nil
        onClosed?()
    }

    private final class KeyableShelfPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.title = FeatureStrings.menuBarOrganizer(L10n.shared.language).title
        panel.isReleasedWhenClosed = false
        // Opened from the menu bar while another app is in front; a panel that
        // hides on deactivate would never show.
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: MenuBarOrganizerShelfView { [weak self] identity in
            self?.close()
            self?.onSelect?(identity)
        })
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    /// Hangs the shelf below the menu bar of the collapser's screen, its right
    /// edge under the collapser's. Without an anchor it goes under the bar of
    /// the pointer's screen, its right edge at the pointer.
    private func position(_ panel: NSPanel, under anchor: NSRect?) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        let pointer = NSEvent.mouseLocation
        let screen = anchor.flatMap { anchor in NSScreen.screens.first { $0.frame.intersects(anchor) } }
            ?? NSScreen.withMouse ?? NSScreen.main
        guard let screen else { return }
        // Below the bar and the camera housing, also while the bar hides itself.
        let barBottom = screen.frame.maxY - max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        let top = min(screen.visibleFrame.maxY, barBottom) - Self.gap
        let right = anchor?.maxX ?? pointer.x
        let frame = StatusItemAnchorSupport.pinnedPanelFrame(size: size, anchorMidX: right - size.width / 2,
                                                             anchorTop: top, visibleFrame: screen.visibleFrame)
        panel.setFrame(frame, display: true, animate: false)
    }

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard event.window === panel, Int(event.keyCode) == kVK_Escape else { return event }
            self?.close()
            return nil
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
                guard let self, event.window !== panel else { return event }
                // The collapser's own click toggles the shelf on mouse-up.
                if event.window == nil || event.window !== self.collapserWindow?() { self.close() }
                return event
            }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self else { return }
                // On macOS 27 the bar belongs to the menu bar agent, so a click
                // on the collapser arrives here first; its mouse-up toggles.
                if let anchor = self.anchor, anchor.contains(NSEvent.mouseLocation) { return }
                self.close()
            }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier != Bundle.main.bundleIdentifier,
                      app.bundleIdentifier != AssistiveKeyboard.bundleID
                else { return }
                self?.close()
            }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        keyMonitor = nil
        localClickMonitor = nil
        globalClickMonitor = nil
        activationObserver = nil
    }
}

/// The shelf's content: what the last collapse hid, as a grid of app icons
/// and names. Several icons of one app are told apart as in the editor.
struct MenuBarOrganizerShelfView: View {
    fileprivate static let entryHeight: CGFloat = 64
    private static let spacing: CGFloat = 4
    /// More rows than this scroll.
    private static let visibleRows = 4

    let onSelect: (MenuBarItemIdentity) -> Void

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = MenuBarOrganizerService.shared
    @AppStorage(DefaultsKey.menuBarOrganizerShelfMonochrome) private var monochrome = true

    private var strings: MenuBarOrganizerFeatureStrings { FeatureStrings.menuBarOrganizer(l10n.language) }

    var body: some View {
        AppLocalizedView { localizedContent }
    }

    @ViewBuilder
    private var localizedContent: some View {
        let entries = service.lastHidden.map(\.identity)
        let presentation = MenuBarOrganizerItemPresentation(inventory: service.inventory,
                                                            lastHidden: service.lastHidden,
                                                            neverShown: service.neverShown, strings: strings)
        Group {
            if entries.isEmpty {
                Text(strings.shelfEmpty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                let columns = entries.count > 9 ? 4 : 3
                let rows = (entries.count + columns - 1) / columns
                let shown = CGFloat(min(rows, Self.visibleRows))
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: columns),
                              spacing: Self.spacing) {
                        ForEach(entries, id: \.self) { identity in
                            MenuBarOrganizerShelfEntry(name: presentation.name(identity, among: entries),
                                                       monochrome: monochrome) {
                                onSelect(identity)
                            } icon: {
                                presentation.icon(identity)
                            }
                        }
                    }
                }
                .frame(height: shown * Self.entryHeight + (shown - 1) * Self.spacing)
            }
        }
        .padding(12)
        .frame(width: MenuBarOrganizerShelf.width)
        .background(HUDBackdrop(cornerRadius: 16))
    }
}

private struct MenuBarOrganizerShelfEntry<Icon: View>: View {
    let name: String
    let monochrome: Bool
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                icon()
                    .font(.system(size: 18))
                    .frame(width: 24, height: 24)
                    .saturation(monochrome ? 0 : 1)
                Text(name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: MenuBarOrganizerShelfView.entryHeight)
            .background(hovered ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(name)
        .accessibilityLabel(name)
    }
}
