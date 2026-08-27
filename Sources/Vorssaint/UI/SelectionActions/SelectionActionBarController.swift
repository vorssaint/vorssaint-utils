// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The floating bar shown next to a text selection. One controller instance
/// per presentation, like `ScreenshotQuickPreviewController` — not a
/// persistent singleton panel, since it appears and disappears constantly
/// while the feature is on and there is nothing worth keeping warm between
/// selections.
final class SelectionActionBarController {
    private var panel: SelectionActionBarPanel?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var dismissWork: DispatchWorkItem?
    private var closed = false

    private let autoDismissDuration: TimeInterval = 6

    func show(snapshot: SelectionSnapshot,
             actions: [SelectionAction],
             maxVisible: Int,
             onSelect: @escaping (SelectionAction) -> Void) {
        guard !closed else { return }
        let strings = FeatureStrings.selectionActions(L10n.shared.language)
        let displayStyle = SelectionActionsDisplayStyle.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.selectionActionsDisplayStyle))

        let content = SelectionActionBarView(
            actions: actions,
            displayStyle: displayStyle,
            strings: strings,
            maxVisible: maxVisible,
            onSelect: { [weak self] action in
                self?.close()
                onSelect(action)
            },
            hoverChanged: { [weak self] inside in
                if inside {
                    self?.dismissWork?.cancel()
                    self?.dismissWork = nil
                } else {
                    self?.scheduleAutoDismiss()
                }
            })
        let host = NSHostingController(rootView: content)
        host.sizingOptions = .preferredContentSize

        let panel = self.panel ?? SelectionActionBarPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.contentViewController = host
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.panel = panel

        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 40, height: 34)
        let anchor = snapshot.boundsInScreen ?? fallbackAnchor()
        let pointer = NSEvent.mouseLocation
        let screens = NSScreen.screens.map { (frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let visibleFrame = SelectionActionBarSupport.visibleFrame(
            anchor: anchor, pointer: pointer, screens: screens, fallback: NSScreen.pointerVisibleFrame)
        let frame = SelectionActionBarSupport.frame(
            size: size, anchor: anchor, pointer: pointer, visibleFrame: visibleFrame)
        panel.setFrame(frame, display: false)

        installMonitors(for: panel)
        panel.orderFrontRegardless()
        scheduleAutoDismiss()
    }

    func close() {
        guard !closed else { return }
        closed = true
        dismissWork?.cancel()
        dismissWork = nil
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    /// A one-point rect at the pointer: used only when Accessibility could
    /// not hand back a bounding rectangle for the selection (some apps never
    /// answer `AXBoundsForRange`), so the bar still lands somewhere sensible.
    private func fallbackAnchor() -> CGRect {
        let pointer = NSEvent.mouseLocation
        return CGRect(x: pointer.x, y: pointer.y, width: 1, height: 1)
    }

    private func scheduleAutoDismiss() {
        guard !closed else { return }
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissDuration, execute: work)
    }

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        // The panel never becomes key (see `SelectionActionBarPanel`), so
        // the app the person is typing into keeps every keystroke — this
        // only has to notice that typing happened, not intercept it, which
        // is exactly what a *global* monitor sees and a local one cannot.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.close()
        }
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) {
            [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel) {
                self.close()
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
            self.close()
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
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
}

private final class SelectionActionBarPanel: NSPanel {
    // Never key: the app the person is typing into must never lose a
    // keystroke to this panel. A `.nonactivatingPanel` already dispatches
    // clicks straight to its controls without needing to activate first, so
    // buttons work normally without ever taking key status.
    override var canBecomeKey: Bool { false }
}
