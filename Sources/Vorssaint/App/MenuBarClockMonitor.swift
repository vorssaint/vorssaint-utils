// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Lift assessment mode before a clock click reaches Notification Center.
/// AX discovery stays off the main thread; pointer events only compare frames.
final class MenuBarClockMonitor {
    var onChange: ((Bool) -> Void)?
    private let catalog = MenuBarItemCatalog()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var frames: [CGRect] = []
    private var overClock = false
    private var generation = 0
    private var refreshing = false

    func start() {
        stop()
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.update()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.update()
            return event
        }
        refreshFrames()
    }

    func stop() {
        generation += 1
        for monitor in [globalMonitor, localMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        globalMonitor = nil
        localMonitor = nil
        frames = []
        overClock = false
        refreshing = false
    }

    func refreshFrames() {
        guard !refreshing, globalMonitor != nil || localMonitor != nil else { return }
        refreshing = true
        let request = generation
        catalog.scanClockFrames { [weak self] frames in
            guard let self, self.generation == request else { return }
            self.refreshing = false
            self.frames = frames
            self.update()
        }
    }

    private func update() {
        let location = NSEvent.mouseLocation
        let next = frames.contains { $0.contains(location) }
        guard next != overClock else { return }
        overClock = next
        onChange?(next)
    }
}
