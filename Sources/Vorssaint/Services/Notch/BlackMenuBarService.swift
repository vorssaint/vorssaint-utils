// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Paints a black strip on every display just above the wallpaper and below
/// all windows. macOS tints the menu bar from what is behind it, so a black
/// strip there turns the bar black without touching the wallpaper file or
/// covering any menu. The strips are click-through and follow the displays.
final class BlackMenuBarService {
    static let shared = BlackMenuBarService()

    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var observing = false

    /// Points added to, or taken from, the menu bar's own height.
    static let heightRange = -8.0...8.0

    static func heightAdjustment(in defaults: UserDefaults = .standard) -> CGFloat {
        let value = defaults.double(forKey: DefaultsKey.blackMenuBarHeight)
        return value.isFinite ? CGFloat(min(heightRange.upperBound, max(heightRange.lowerBound, value)).rounded()) : 0
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.blackMenuBar)
    }

    func syncWithPreferences() {
        guard Self.isEnabled() else { stop(); return }
        if !observing {
            observing = true
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(displaysChanged),
                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displaysChanged),
                                                              name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        }
        refresh()
    }

    func stop() {
        if observing {
            observing = false
            NotificationCenter.default.removeObserver(self)
            NSWorkspace.shared.notificationCenter.removeObserver(self)
        }
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    @objc private func displaysChanged() { refresh() }

    private func refresh() {
        var live: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            live.insert(id)
            // The menu bar's own height, which the setting nudges either way.
            let bar = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            let height = max(1, bar + Self.heightAdjustment())
            let frame = CGRect(x: screen.frame.minX, y: screen.frame.maxY - height,
                               width: screen.frame.width, height: height)
            let panel = panels[id] ?? makePanel()
            panels[id] = panel
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            panel.orderFrontRegardless()
        }
        for (id, panel) in panels where !live.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        // Above the wallpaper and the desktop icons' backdrop, below every window.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }
}
