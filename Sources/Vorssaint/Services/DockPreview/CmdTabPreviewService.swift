// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Observes native Command-Tab; it never replaces or consumes the shortcut.
/// AXProcessSwitcherList is a Dock-provided subrole and can disappear at any time.
final class CmdTabPreviewService {
    static let shared = CmdTabPreviewService()
    private var down: Any?, up: Any?
    private var timer: Timer?
    private var appPID: pid_t?
    private var showing = false
    private init() {}
    func start() {
        guard down == nil else { return }
        down = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 48, event.modifierFlags.contains(.command) { self?.begin() }
        }
        up = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if !event.modifierFlags.contains(.command) { self?.end() }
        }
    }
    private func begin() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in self?.refresh() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        refresh()
    }
    private func refresh() {
        guard CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand), SessionActivity.shared.isActive else { end(); return }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.04)
        var queue = [(root, 0)], visited = 0
        while !queue.isEmpty, visited < 100 {
            let (element, depth) = queue.removeFirst(); visited += 1
            if (DockAccessibility.attribute(element, kAXSubroleAttribute) as String?) == "AXProcessSwitcherList" {
                let selected: [AXUIElement] = DockAccessibility.attribute(element, kAXSelectedChildrenAttribute) ?? []
                guard let target = selected.first, let rect = DockAccessibility.frame(target) else { return }
                let item = DockAccessibility.Item(element: target, url: DockAccessibility.attribute(target, kAXURLAttribute),
                    title: DockAccessibility.attribute(target, kAXTitleAttribute) ?? "", frame: DockAccessibility.appKit(rect), subrole: "")
                guard let app = DockAccessibility.application(for: item), app.processIdentifier != appPID else { return }
                appPID = app.processIdentifier; showing = true
                DockPreviewService.shared.show(for: app, anchor: item.frame, external: true, centeredPlacement: true)
                return
            }
            if depth < 6 {
                let children: [AXUIElement] = DockAccessibility.attribute(element, kAXChildrenAttribute) ?? []
                queue.append(contentsOf: children.prefix(40).map { ($0, depth + 1) })
            }
        }
        if showing { end() }
    }
    private func end() {
        timer?.invalidate(); timer = nil; appPID = nil
        if showing { DockPreviewService.shared.closePreviewPanel() }; showing = false
    }
    func stop() {
        end()
        if let down { NSEvent.removeMonitor(down) }; if let up { NSEvent.removeMonitor(up) }
        down = nil; up = nil
    }
}
