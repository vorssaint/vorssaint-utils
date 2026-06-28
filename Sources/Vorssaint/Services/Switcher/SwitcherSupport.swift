// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct SwitcherCloseState: Equatable {
    let remainingItemIDs: [String]
    let selectedIndex: Int
    let didRemove: Bool
    let shouldEndSession: Bool
}

struct SwitcherActivationPlan: Equatable {
    let activateAllWindows: Bool
    let makeAppFrontmostAfterActivation: Bool
    let restoreSourceWhenTargetMinimizes: Bool
}

struct SwitcherSearchRecord: Equatable {
    let id: String
    let title: String
    let appName: String
}

struct SwitcherAppGroup: Identifiable, Equatable {
    let pid: pid_t
    let appName: String
    let representativeIndex: Int
    let itemIDs: [String]

    var id: pid_t { pid }
    var windowCount: Int { itemIDs.count }
}

struct SwitcherIconRowLayout: Equatable {
    let visibleIconCount: Int
    let appRowContentWidth: CGFloat
    let previewContentWidth: CGFloat
    let panelSize: CGSize

    static var iconSize: CGFloat { 74 * PreviewSizing.scale }
    static var selectedIconSize: CGFloat { 86 * PreviewSizing.scale }
    static var rowHeight: CGFloat { 108 * PreviewSizing.scale }
    static var appTileWidth: CGFloat { max(selectedIconSize + 12, 86 * PreviewSizing.scale) + 12 }
    static var previewCardWidth: CGFloat { 220 * PreviewSizing.scale }
    static var previewCardHeight: CGFloat { 164 * PreviewSizing.scale }
    static var previewHeight: CGFloat { 250 * PreviewSizing.scale }
    static var hintHeight: CGFloat { 28 * PreviewSizing.scale }
    static var hintGap: CGFloat { 10 * PreviewSizing.scale }
    static var padding: CGFloat { 20 * PreviewSizing.scale }
    static var spacing: CGFloat { 12 * PreviewSizing.scale }
    static var previewGap: CGFloat { 14 * PreviewSizing.scale }

    static let empty = SwitcherIconRowLayout(visibleIconCount: 1,
                                             appRowContentWidth: 0,
                                             previewContentWidth: 0,
                                             panelSize: .zero)

    static func compute(appCount rawAppCount: Int,
                        selectedWindowCount rawWindowCount: Int,
                        screenVisibleFrame: CGRect) -> SwitcherIconRowLayout {
        let appCount = max(1, rawAppCount)
        let windowCount = max(1, rawWindowCount)
        let usableWidth = max(320, screenVisibleFrame.width * 0.96)
        let maxContentWidth = max(appTileWidth, usableWidth - padding * 2)
        let naturalAppRowWidth = CGFloat(appCount) * appTileWidth + CGFloat(max(0, appCount - 1)) * spacing
        let naturalPreviewWidth = CGFloat(windowCount) * previewCardWidth
            + CGFloat(max(0, windowCount - 1)) * spacing
        let appRowWidth = min(naturalAppRowWidth, maxContentWidth)
        let previewWidth = min(max(previewCardWidth, naturalPreviewWidth), maxContentWidth)
        let contentWidth = min(max(appRowWidth, previewWidth), maxContentWidth)
        let visibleIconCount = max(1, min(appCount, Int((maxContentWidth + spacing) / (appTileWidth + spacing))))
        let width = contentWidth + padding * 2
        let height = previewHeight + previewGap + rowHeight + hintGap + hintHeight + padding * 2
        return SwitcherIconRowLayout(visibleIconCount: visibleIconCount,
                                     appRowContentWidth: appRowWidth,
                                     previewContentWidth: previewWidth,
                                     panelSize: CGSize(width: width, height: height))
    }

    static func compute(count rawCount: Int, screenVisibleFrame: CGRect) -> SwitcherIconRowLayout {
        compute(appCount: rawCount, selectedWindowCount: 1, screenVisibleFrame: screenVisibleFrame)
    }
}

struct SwitcherShortcutHints: Equatable {
    let apps: String
    let windows: String
}

enum SwitcherSupport {
    static func shortcutHints(for switcherShortcut: GlobalShortcut) -> SwitcherShortcutHints {
        let windowShortcut = GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave),
                                            modifiers: switcherShortcut.modifiers)
        return SwitcherShortcutHints(apps: switcherShortcut.displayString,
                                     windows: windowShortcut.displayString)
    }

    static func appGroups(items: [SwitcherItem]) -> [SwitcherAppGroup] {
        var seen: Set<pid_t> = []
        var groups: [SwitcherAppGroup] = []
        for (index, item) in items.enumerated() where !seen.contains(item.pid) {
            seen.insert(item.pid)
            groups.append(SwitcherAppGroup(pid: item.pid,
                                           appName: item.appName,
                                           representativeIndex: index,
                                           itemIDs: items.filter { $0.pid == item.pid }.map(\.id)))
        }
        return groups
    }

    static func nextAppSelectionIndex(items: [SwitcherItem],
                                      selectedIndex: Int,
                                      delta: Int) -> Int {
        let groups = appGroups(items: items)
        guard !groups.isEmpty else { return 0 }
        guard items.indices.contains(selectedIndex) else {
            return groups[0].representativeIndex
        }

        let selectedID = items[selectedIndex].id
        let currentGroupIndex = groups.firstIndex { $0.itemIDs.contains(selectedID) } ?? 0
        let targetGroupIndex = (currentGroupIndex + delta + groups.count) % groups.count
        return groups[targetGroupIndex].representativeIndex
    }

    static func nextWindowSelectionIndexWithinApp(items: [SwitcherItem],
                                                  selectedIndex: Int,
                                                  delta: Int) -> Int {
        guard items.indices.contains(selectedIndex) else { return 0 }
        let pid = items[selectedIndex].pid
        let indices = items.indices.filter { items[$0].pid == pid }
        guard !indices.isEmpty,
              let current = indices.firstIndex(of: selectedIndex)
        else { return selectedIndex }

        let target = (current + delta + indices.count) % indices.count
        return indices[target]
    }

    static func activationPlan(targetsSpecificWindow: Bool) -> SwitcherActivationPlan {
        SwitcherActivationPlan(
            activateAllWindows: !targetsSpecificWindow,
            makeAppFrontmostAfterActivation: !targetsSpecificWindow,
            restoreSourceWhenTargetMinimizes: targetsSpecificWindow
        )
    }

    static func shouldActivateAllWindows(targetsSpecificWindow: Bool) -> Bool {
        activationPlan(targetsSpecificWindow: targetsSpecificWindow).activateAllWindows
    }

    static func shouldRestoreSourceAfterTargetMinimize(targetPID: pid_t,
                                                       sourcePID: pid_t?,
                                                       frontmostPID: pid_t?,
                                                       targetIsMinimized: Bool,
                                                       ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
                                                       frontmostMatchesTargetBundle: Bool = false,
                                                       frontmostCanBeSystemPromotion: Bool = false) -> Bool {
        guard targetIsMinimized,
              let sourcePID,
              let frontmostPID,
              sourcePID != targetPID else { return false }
        if frontmostPID == sourcePID { return false }
        return frontmostPID == targetPID
            || frontmostPID == ownPID
            || frontmostMatchesTargetBundle
            || frontmostCanBeSystemPromotion
    }

    static func shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: pid_t,
                                                             sourcePID: pid_t?,
                                                             frontmostPID: pid_t?,
                                                             focusedWindowID: UInt32?,
                                                             targetWindowID: UInt32,
                                                             targetIsMinimized: Bool,
                                                             ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
                                                             frontmostMatchesTargetBundle: Bool = false,
                                                             frontmostCanBeSystemPromotion: Bool = false) -> Bool {
        guard let sourcePID,
              sourcePID != targetPID else { return false }
        if frontmostPID == sourcePID { return false }
        if let frontmostPID,
           frontmostPID != targetPID,
           frontmostPID != ownPID,
           !frontmostMatchesTargetBundle,
           !(targetIsMinimized && frontmostCanBeSystemPromotion) {
            return false
        }
        if targetIsMinimized { return true }
        guard let focusedWindowID else { return false }
        return focusedWindowID != targetWindowID
    }

    static func shouldStageSourceBehindTarget(targetPID: pid_t,
                                              sourcePID: pid_t?,
                                              sourceWindowID: UInt32?) -> Bool {
        guard let sourcePID,
              sourcePID != targetPID,
              sourceWindowID != nil else { return false }
        return true
    }

    static func shouldContinueFocusRetry(targetPID: pid_t,
                                         sourcePID: pid_t?,
                                         frontmostPID: pid_t?,
                                         targetIsMinimized: Bool,
                                         ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard !targetIsMinimized else { return false }
        guard let sourcePID,
              let frontmostPID else { return true }
        return frontmostPID == targetPID || frontmostPID == sourcePID || frontmostPID == ownPID
    }

    static func shouldKeepMinimizeRestoreObserver(targetPID: pid_t,
                                                  sourcePID: pid_t,
                                                  activatedPID: pid_t,
                                                  ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
                                                  activatedMatchesTargetBundle: Bool = false) -> Bool {
        activatedPID == targetPID || activatedPID == sourcePID || activatedPID == ownPID || activatedMatchesTargetBundle
    }

    static func closeState(afterRemoving closedItemID: String,
                           itemIDs: [String],
                           selectedIndex: Int) -> SwitcherCloseState {
        guard let removedIndex = itemIDs.firstIndex(of: closedItemID) else {
            return SwitcherCloseState(
                remainingItemIDs: itemIDs,
                selectedIndex: clampedSelection(selectedIndex, count: itemIDs.count),
                didRemove: false,
                shouldEndSession: itemIDs.isEmpty
            )
        }

        let currentIndex = clampedSelection(selectedIndex, count: itemIDs.count)
        let remaining = itemIDs.filter { $0 != closedItemID }
        guard !remaining.isEmpty else {
            return SwitcherCloseState(remainingItemIDs: [],
                                      selectedIndex: 0,
                                      didRemove: true,
                                      shouldEndSession: true)
        }

        let nextIndex: Int
        if removedIndex < currentIndex {
            nextIndex = currentIndex - 1
        } else if removedIndex == currentIndex {
            nextIndex = min(currentIndex, remaining.count - 1)
        } else {
            nextIndex = currentIndex
        }

        return SwitcherCloseState(remainingItemIDs: remaining,
                                  selectedIndex: clampedSelection(nextIndex, count: remaining.count),
                                  didRemove: true,
                                  shouldEndSession: false)
    }

    static func filteredSearchIDs(records: [SwitcherSearchRecord], query: String) -> [String] {
        let tokens = normalizedSearchTokens(query)
        guard !tokens.isEmpty else { return records.map(\.id) }
        return records.compactMap { record in
            let haystack = normalizedSearchText([record.title, record.appName])
            return tokens.allSatisfy { haystack.contains($0) } ? record.id : nil
        }
    }

    static func searchSelectionIndex(itemIDs: [String],
                                     preferredID: String?,
                                     previousIndex: Int) -> Int {
        guard !itemIDs.isEmpty else { return 0 }
        if let preferredID,
           let index = itemIDs.firstIndex(of: preferredID) {
            return index
        }
        return clampedSelection(previousIndex, count: itemIDs.count)
    }

    private static func clampedSelection(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(0, index), count - 1)
    }

    private static func normalizedSearchTokens(_ query: String) -> [String] {
        normalizedSearchText([query])
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func normalizedSearchText(_ parts: [String]) -> String {
        parts.joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
