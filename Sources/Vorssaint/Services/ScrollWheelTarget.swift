// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// AppKit state is published on main; the pointer tap only reads the cache
/// and occasionally the WindowServer list. It never waits for main.
final class ScrollWheelTarget {
    static let shared = ScrollWheelTarget()

    private let cache = ScrollWheelTargetCache(ownProcessID: ProcessInfo.processInfo.processIdentifier)
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func setEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        cache.setEnabled(enabled)
        guard enabled else {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            return
        }
        refresh()
        guard observers.isEmpty else { return }
        for name in [NSApplication.didUpdateNotification, NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in self?.refresh() })
        }
    }

    private func refresh() {
        let windows = NSApp.windows.compactMap { window -> ScrollWheelTargetCache.OwnWindow? in
            guard let id = CGWindowID(exactly: window.windowNumber) else { return nil }
            return .init(id: id, frame: window.frame, visible: window.isVisible && !window.isMiniaturized,
                         alpha: Double(window.alphaValue), ignoresMouseEvents: window.ignoresMouseEvents,
                         level: window.level.rawValue)
        }.sorted { $0.id < $1.id }
        cache.update(ownWindows: windows, orderedWindowIDs: NSApp.orderedWindows.compactMap {
            CGWindowID(exactly: $0.windowNumber)
        })
    }

    func contains(_ point: CGPoint) -> Bool {
        cache.contains(point)
    }
}
