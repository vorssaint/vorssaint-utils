// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// AppKit state is published on main; the pointer tap only reads a locked copy
/// and the WindowServer list. It never waits for main while handling an event.
final class ScrollWheelTarget {
    static let shared = ScrollWheelTarget()

    private let lock = NSLock()
    private var clickThroughWindowIDs: Set<CGWindowID> = []
    private var observers: [NSObjectProtocol] = []
    private let ownProcessID = ProcessInfo.processInfo.processIdentifier

    private init() {}

    func setEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        guard enabled else {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            lock.withLock { clickThroughWindowIDs.removeAll() }
            return
        }
        refresh()
        guard observers.isEmpty else { return }
        for name in [NSApplication.didUpdateNotification, NSWindow.didChangeOcclusionStateNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in self?.refresh() })
        }
    }

    private func refresh() {
        let ids = Set(NSApp.windows.filter(\.ignoresMouseEvents).compactMap {
            CGWindowID(exactly: $0.windowNumber)
        })
        lock.withLock { clickThroughWindowIDs = ids }
    }

    func contains(_ point: CGPoint) -> Bool {
        if Thread.isMainThread { refresh() }
        let ids = lock.withLock { clickThroughWindowIDs }
        return ScrollWheelSupport.targetsOwnWindow(
            in: WindowServerSupport.onScreenWindowInfo(), at: point,
            ownProcessID: ownProcessID, clickThroughWindowIDs: ids)
    }
}
