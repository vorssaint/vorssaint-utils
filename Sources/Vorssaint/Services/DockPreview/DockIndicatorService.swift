// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class DockIndicatorService {
    static let shared = DockIndicatorService()
    private var timer: Timer?
    private let reader = DispatchQueue(label: "com.vorssaint.dock-indicator.ax", qos: .utility)
    private var reading = false
    private var generation = UUID()
    private var observers: [NSObjectProtocol] = []
    private var panels: [String: NSPanel] = [:]
    private var colors: [String: NSColor] = [:]
    private var windowed = Set<pid_t>()
    private var lastWindowRead: TimeInterval = 0
    private init() {}

    func syncWithPreferences() {
        guard AppFeature.dockIndicator.isAvailable, DockOption.indicatorEnabled.bool,
              Permissions.shared.accessibility, SessionActivity.shared.isActive else { stop(); return }
        if timer == nil {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                         NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
            }
        }
        refresh()
    }
    func stop() {
        timer?.invalidate(); timer = nil
        generation = UUID()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers = []
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll(); colors.removeAll(); windowed.removeAll(); lastWindowRead = 0
    }
    private func refresh() {
        guard AppFeature.dockIndicator.isAvailable, DockOption.indicatorEnabled.bool,
              SessionActivity.shared.isActive, AXIsProcessTrusted() else {
            stop(); return
        }
        guard !reading, let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        reading = true
        let token = generation, pid = dock.processIdentifier, top = NSScreen.screens.first?.frame.maxY ?? 0
        reader.async { [weak self] in
            let items = DockAccessibility.items(dockPID: pid, screenTop: top).filter { $0.subrole == "AXApplicationDockItem" }
            DispatchQueue.main.async {
                guard let self else { return }
                self.reading = false
                guard self.generation == token, self.timer != nil, AppFeature.dockIndicator.isAvailable,
                      DockOption.indicatorEnabled.bool, SessionActivity.shared.isActive, AXIsProcessTrusted() else { return }
                self.render(items)
            }
        }
    }
    private func render(_ items: [DockAccessibility.Item]) {
        let orientation = DockAccessibility.orientation
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier > 0 }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let dots = DockOption.indicatorStyle.string == "dots"
        if dots, ProcessInfo.processInfo.systemUptime - lastWindowRead > 0.75 {
            lastWindowRead = ProcessInfo.processInfo.systemUptime
            let metadata = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            windowed = Set(metadata.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }.compactMap { $0[kCGWindowOwnerPID as String] as? pid_t })
        }
        var wanted = Set<String>()
        let rgb = DockEnhancementSupport.hexRGB(DockOption.indicatorColor.string)
        let color = NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                            green: Double((rgb >> 8) & 255) / 255,
                            blue: Double(rgb & 255) / 255, alpha: 1)
        for item in items {
            guard let app = DockAccessibility.application(for: item, apps: apps), dots || app.processIdentifier == front,
                  let screen = NSScreen.screens.first(where: { $0.frame.intersects(item.frame) }),
                  screen.frame.contains(item.frame.dockCenter) else { continue }
            // Hidden Dock tiles retain AX frames beyond their screen edge.
            // Intersections alone would leave a colored sliver on that edge.
            let key = String(app.processIdentifier)
            wanted.insert(key)
            let thickness = dots ? 4 : DockOption.indicatorThickness.double
            let frame = DockEnhancementSupport.indicatorFrame(icon: item.frame, orientation: orientation,
                thickness: thickness, length: dots ? 4 : DockOption.indicatorLength.double,
                offset: DockOption.indicatorOffset.double)
            let panel = panels[key] ?? makePanel()
            panels[key] = panel
            panel.setFrame(frame, display: true)
            let tint = app.processIdentifier == front ? color : color.withAlphaComponent(0.4)
            let hollow = dots && app.processIdentifier != front && !windowed.contains(app.processIdentifier)
            panel.contentView?.layer?.borderWidth = hollow ? 1 : 0
            panel.contentView?.layer?.borderColor = tint.cgColor
            let fill = hollow ? NSColor.clear : tint
            if colors[key] != fill {
                panel.contentView?.layer?.backgroundColor = fill.cgColor
                colors[key] = fill
            }
            panel.contentView?.layer?.cornerRadius = min(frame.width, frame.height) / 2
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        for key in Array(panels.keys) where !wanted.contains(key) {
            panels.removeValue(forKey: key)?.orderOut(nil); colors.removeValue(forKey: key)
        }
    }
    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.contentView = NSView(); panel.contentView?.wantsLayer = true
        return panel
    }
}
