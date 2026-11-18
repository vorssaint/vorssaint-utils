// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// The picker's floating panel: placed at the pointer, keyboard-driven, and
/// gone on Escape, a click elsewhere or a switch to another app. It never
/// activates this app, so the app the link came from stays in front.
final class BrowserPickerPanel {
    private final class KeyPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private unowned let service: BrowserPickerService
    private var panel: KeyPanel?
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private var changes: AnyCancellable?

    init(service: BrowserPickerService) {
        self.service = service
        // The list can change while the picker is up, when the browsers read
        // in the background differ from the ones it opened with.
        changes = service.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.fitToContent() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let wasVisible = panel.isVisible
        fitToContent()
        if !wasVisible { position(panel) }
        installMonitors()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        removeMonitors()
        panel?.orderOut(nil)
    }

    /// Keeps the edge next to the pointer where it is, so rows grow away from it.
    private func fitToContent() {
        guard let panel, let view = panel.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        guard size != panel.frame.size else { return }
        let y = service.opensAbovePointer ? panel.frame.minY : panel.frame.maxY - size.height
        panel.setFrame(NSRect(x: panel.frame.minX, y: y, width: size.width, height: size.height), display: true)
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: BrowserPickerView(service: service))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        return panel
    }

    /// Below and right of the pointer, flipped at the screen's edges.
    private func position(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let visible = NSScreen.pointerVisibleFrame.insetBy(dx: 8, dy: 8)
        let size = panel.frame.size
        var x = pointer.x + 4
        var y = pointer.y - 4 - size.height
        if x + size.width > visible.maxX { x = pointer.x - 4 - size.width }
        service.opensAbovePointer = y < visible.minY
        if service.opensAbovePointer { y = pointer.y + 4 }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        y = min(max(y, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }) { monitors.append(keys) }
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.service.cancelPicker()
        }) { monitors.append(outside) }
        if let inside = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if event.window !== self?.panel { self?.service.cancelPicker() }
            return event
        }) { monitors.append(inside) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.service.otherAppDidActivate(app?.bundleIdentifier)
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    /// Return opens the highlighted choice and 1–9 a numbered one; holding ⌥
    /// also remembers the choice for the link's site.
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "c" {
            service.copyPendingLink()
            return true
        }
        guard modifiers.isSubset(of: .option) else { return false }
        let remember = modifiers == .option
        let count = service.choices.count
        switch Int(event.keyCode) {
        case kVK_Escape:
            service.cancelPicker()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            service.choose(service.highlighted, remember: remember)
        // Arrows follow the screen: above the pointer the list runs upward.
        case kVK_UpArrow where count > 0:
            let step = service.opensAbovePointer ? 1 : -1
            service.highlighted = (service.highlighted + step + count) % count
        case kVK_DownArrow where count > 0:
            let step = service.opensAbovePointer ? -1 : 1
            service.highlighted = (service.highlighted + step + count) % count
        default:
            guard let digit = Self.digits.firstIndex(of: Int(event.keyCode)) else { return false }
            service.choose(digit, remember: remember)
        }
        return true
    }

    private static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                 kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
}
