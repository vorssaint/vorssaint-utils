// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WindowSwitchPartitionedCandidates {
    let primary: [SwitcherItem]
    let deferred: [SwitcherItem]
}

enum WindowSwitchCandidatePipeline {
    static func filter(_ items: [SwitcherItem], settings: WindowSwitchSettings) -> [SwitcherItem] {
        items.filter { item in
            if settings.minimizedPlacement == .hidden, item.isMinimized { return false }
            if !settings.showFullscreenWindows, item.isFullscreen { return false }
            return true
        }
    }

    static func partition(_ items: [SwitcherItem], settings: WindowSwitchSettings) -> WindowSwitchPartitionedCandidates {
        guard settings.minimizedPlacement == .end else {
            return WindowSwitchPartitionedCandidates(primary: items, deferred: [])
        }
        var primary: [SwitcherItem] = []
        var deferred: [SwitcherItem] = []
        primary.reserveCapacity(items.count)
        deferred.reserveCapacity(items.count)
        for item in items {
            if item.isMinimized {
                deferred.append(item)
            } else {
                primary.append(item)
            }
        }
        return WindowSwitchPartitionedCandidates(primary: primary, deferred: deferred)
    }

    static func sort(_ items: [SwitcherItem], rankOfPID: (pid_t) -> Int) -> [SwitcherItem] {
        items.enumerated()
            .sorted { lhs, rhs in
                let rankL = rankOfPID(lhs.element.pid)
                let rankR = rankOfPID(rhs.element.pid)
                return rankL != rankR ? rankL < rankR : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func merge(primary: [SwitcherItem], deferred: [SwitcherItem]) -> [SwitcherItem] {
        guard !deferred.isEmpty else { return primary }
        return primary + deferred
    }
}
