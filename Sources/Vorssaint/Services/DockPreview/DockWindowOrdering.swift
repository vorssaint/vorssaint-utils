// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum DockWindowOrdering {
    static func sessionItems(_ items: [SwitcherItem], currentID: String?) -> [SwitcherItem] {
        SwitcherSupport.orderedForSession(ordered(items), currentID: currentID)
    }
    static func ordered(_ items: [SwitcherItem]) -> [SwitcherItem] {
        let filtered = items.filter { !DockEnhancementSupport.titleIsExcluded($0.title, filters: DockOption.windowTitleFilters.string) }
        switch DockOption.sortOrder.string {
        case "title": return filtered.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        case "app": return filtered.sorted {
            let comparison = $0.appName.localizedStandardCompare($1.appName)
            return comparison == .orderedSame ? $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending : comparison == .orderedAscending
        }
        case "creation": return filtered.sorted { ($0.windowID ?? 0) < ($1.windowID ?? 0) }
        default: return filtered
        }
    }
    static func windows(for pid: pid_t) -> [SwitcherItem] {
        guard DockOption.groupInstances.bool,
              let url = NSRunningApplication(processIdentifier: pid)?.bundleURL else {
            return ordered(WindowEnumerator.listWindowsForDockPreview(for: pid))
        }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL == url && !$0.isTerminated }
        return ordered(apps.flatMap { WindowEnumerator.listWindowsForDockPreview(for: $0.processIdentifier) }).prefix(48).map { $0 }
    }
}

enum DockPreviewLayout {
    static func compact(_ count: Int) -> Bool {
        DockEnhancementSupport.isCompact(count: count, forced: DockOption.compact.bool,
            threshold: DockOption.compactThreshold.int, canCapture: Permissions.shared.screenRecording)
    }
    static var spacing: CGFloat { DockEnhancementSupport.bounded(DockOption.spacing.double, fallback: 8, range: 0...40) * PreviewSizing.scale }
    static var radius: CGFloat { DockEnhancementSupport.bounded(DockOption.cornerRadius.double, fallback: 18, range: 0...40) }
    static func lanes(_ count: Int, orientation: DockPreviewOrientation, isPinned: Bool) -> Int {
        let vertical = DockPreviewSupport.stacksVertically(orientation: orientation, isPinned: isPinned)
        let option = vertical ? DockOption.maxColumns.int : DockOption.maxRows.int
        let available = NSScreen.screens.map { vertical ? $0.visibleFrame.width : $0.visibleFrame.height }.min() ?? 800
        return DockEnhancementSupport.usableLanes(requested: option, count: count, available: available,
            cardSize: vertical ? DockPreviewSupport.cardWidth : DockPreviewSupport.cardHeight,
            spacing: spacing, padding: DockPreviewSupport.panelPadding,
            header: !vertical && isPinned ? DockPreviewSupport.panelHeaderHeight : 0)
    }
    static func panelSize(itemCount: Int, screenVisibleFrame: CGRect, isPinned: Bool,
                          orientation: DockPreviewOrientation = .bottom) -> CGSize {
        let header = isPinned ? DockPreviewSupport.panelHeaderHeight : 0
        let pad = DockPreviewSupport.panelPadding * 2
        if compact(itemCount) {
            return CGSize(width: min(420, screenVisibleFrame.width - pad), height: min(CGFloat(max(1, itemCount)) * 36 + pad + header, screenVisibleFrame.height * 0.8))
        }
        let lanes = lanes(itemCount, orientation: orientation, isPinned: isPinned)
        guard lanes > 1 else {
            return DockPreviewSupport.panelSize(itemCount: itemCount, screenVisibleFrame: screenVisibleFrame, isPinned: isPinned, orientation: orientation, spacing: spacing)
        }
        let vertical = DockPreviewSupport.stacksVertically(orientation: orientation, isPinned: isPinned)
        let across = CGFloat(lanes), along = CGFloat((max(1, itemCount) + lanes - 1) / lanes)
        let cols = vertical ? across : along, rows = vertical ? along : across
        return CGSize(width: min(cols * DockPreviewSupport.cardWidth + (cols - 1) * spacing + pad, screenVisibleFrame.width * 0.9),
                      height: min(rows * DockPreviewSupport.cardHeight + (rows - 1) * spacing + pad + header, screenVisibleFrame.height * 0.9))
    }
    static func spaceLabel(_ item: SwitcherItem) -> String? {
        guard DockOption.spaceNumbers.bool, let id = item.windowID,
              let topology = SpaceWindowBridge.topology() else { return nil }
        let all = topology.displays.flatMap(\.spaces)
        let unique = all.reduce(into: [UInt64]()) { if !$0.contains($1) { $0.append($1) } }
        let spaces = SpaceWindowBridge.spaces(of: id)
        let numbers = unique.enumerated().filter { spaces.contains($0.element) }.map { String($0.offset + 1) }
        return numbers.isEmpty ? nil : numbers.joined(separator: ",")
    }
}
