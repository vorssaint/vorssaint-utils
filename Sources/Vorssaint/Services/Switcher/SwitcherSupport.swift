// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

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
    let appRowSurfaceWidth: CGFloat
    let previewContentWidth: CGFloat
    let previewSurfaceWidth: CGFloat
    let panelSize: CGSize

    static var scale: CGFloat { min(PreviewSizing.scale, 1.15) }
    static var iconSize: CGFloat { 68 * scale }
    static var selectedIconSize: CGFloat { 78 * scale }
    static var iconLabelWidth: CGFloat { max(selectedIconSize + 12, 86 * scale) }
    static var rowHeight: CGFloat { 108 * scale }
    static var appTileWidth: CGFloat { iconLabelWidth + 12 }
    static var previewCardWidth: CGFloat { 220 * scale }
    static var previewCardHeight: CGFloat { 164 * scale }
    static var previewHeight: CGFloat { previewCardHeight + 76 * scale }
    static var hintHeight: CGFloat { 28 * scale }
    static var hintGap: CGFloat { 8 * scale }
    static var hintBarWidth: CGFloat { 300 * scale }
    static var rowHorizontalPadding: CGFloat { 8 * scale }
    static var previewPanelPadding: CGFloat { 12 * scale }
    static var padding: CGFloat { 20 * scale }
    static var spacing: CGFloat { 12 * scale }
    static var previewGap: CGFloat { 10 * scale }
    static var simpleTitleHeight: CGFloat { 66 * scale }
    static var simpleTitleGap: CGFloat { 10 * scale }
    static var simpleTitleChipMaxWidth: CGFloat { 180 * scale }

    /// App-only mode keeps the same icon and shortcut surfaces, but removes
    /// the entire preview area so no blank space remains where captures were.
    var simplePanelSize: CGSize {
        CGSize(width: max(appRowSurfaceWidth, Self.hintBarWidth) + Self.padding * 2,
               height: Self.simpleTitleHeight + Self.simpleTitleGap
                        + Self.rowHeight + Self.hintGap + Self.hintHeight
                        + Self.padding * 2)
    }

    static let empty = SwitcherIconRowLayout(visibleIconCount: 1,
                                             appRowContentWidth: 0,
                                             appRowSurfaceWidth: 0,
                                             previewContentWidth: 0,
                                             previewSurfaceWidth: 0,
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
        let maxAppContentWidth = max(appTileWidth, maxContentWidth - rowHorizontalPadding * 2)
        let maxPreviewContentWidth = max(previewCardWidth, maxContentWidth - previewPanelPadding * 2)
        let appRowWidth = min(naturalAppRowWidth, maxAppContentWidth)
        let appRowSurfaceWidth = min(appRowWidth + rowHorizontalPadding * 2, maxContentWidth)
        let previewWidth = min(max(previewCardWidth, naturalPreviewWidth), maxPreviewContentWidth)
        let previewSurfaceWidth = min(previewWidth + previewPanelPadding * 2, maxContentWidth)
        let contentWidth = min(max(appRowSurfaceWidth, previewSurfaceWidth, min(hintBarWidth, maxContentWidth)), maxContentWidth)
        let visibleIconCount = max(1, min(appCount, Int((maxAppContentWidth + spacing) / (appTileWidth + spacing))))
        let width = contentWidth + padding * 2
        let height = previewHeight + previewGap + rowHeight + hintGap + hintHeight + padding * 2
        return SwitcherIconRowLayout(visibleIconCount: visibleIconCount,
                                     appRowContentWidth: appRowWidth,
                                     appRowSurfaceWidth: appRowSurfaceWidth,
                                     previewContentWidth: previewWidth,
                                     previewSurfaceWidth: previewSurfaceWidth,
                                     panelSize: CGSize(width: width, height: height))
    }

    static func compute(count rawCount: Int, screenVisibleFrame: CGRect) -> SwitcherIconRowLayout {
        compute(appCount: rawCount, selectedWindowCount: 1, screenVisibleFrame: screenVisibleFrame)
    }
}

struct SwitcherIconRowPreviewPlacement: Equatable {
    let contentWidth: CGFloat
    let leading: CGFloat
}

struct SwitcherShortcutHints: Equatable {
    let apps: String
    let windows: String
}

enum SwitcherSupport {
    /// Grid resolution used to classify window captures.
    static let captureAlphaGridSize = 8

    static func usesIconRowLayout(iconRowMode: Bool, simpleMode: Bool) -> Bool {
        iconRowMode || simpleMode
    }

    static func capturesPreviews(simpleMode: Bool) -> Bool {
        !simpleMode
    }

    static func needsScreenRecording(switcherEnabled: Bool,
                                     simpleMode: Bool,
                                     dockPreviewEnabled: Bool) -> Bool {
        dockPreviewEnabled || (switcherEnabled && capturesPreviews(simpleMode: simpleMode))
    }

    /// Resolves the foreground surface a session is measured against: the
    /// window the user is looking at right now. It can legitimately not exist
    /// (the app in front was left with no windows, or all of them are
    /// minimized or parked on another Space), and nil says exactly that
    /// instead of mistaking an older off-screen window for the source. The
    /// session opens either way; `initialSelectionPosition` handles the
    /// sourceless case.
    static func sessionSourceItem(frontmostPID: pid_t?,
                                  focusedWindowID: CGWindowID?,
                                  items: [SwitcherItem]) -> SwitcherItem? {
        guard let frontmostPID else { return nil }
        let appPID = appPID(forFrontmost: frontmostPID, items: items)
        let candidates = items.filter { $0.pid == appPID }
        if let focusedWindowID,
           let focused = candidates.first(where: { $0.windowID == focusedWindowID }) {
            return focused
        }
        return candidates.first(where: { $0.isOnScreen && !$0.isMinimized })
            ?? candidates.first(where: { $0.windowID == nil })
    }

    /// The regular app behind the process holding the keyboard. Multi-process
    /// apps render their windows in an embedded helper, so the front process
    /// is not always the one the entries are filed under.
    static func appPID(forFrontmost frontmostPID: pid_t, items: [SwitcherItem]) -> pid_t {
        items.first(where: { $0.windowOwnerPID == frontmostPID })?.pid ?? frontmostPID
    }

    /// Whether a process looks like a compatibility layer hosting a program
    /// built for another platform. Those processes own real on-screen windows
    /// but run from a bare loader executable with no bundle identity: either
    /// the loader's own name, or a per-app "winetemp-" copy that bottle
    /// managers create so the process carries the hosted program's name and
    /// icon. They need special handling in the switcher because their windows
    /// expose no standard Accessibility subrole (issue #274).
    static func isCompatibilityLayerApp(bundleIdentifier: String?,
                                        executablePath: String?,
                                        localizedName: String?) -> Bool {
        guard bundleIdentifier == nil else { return false }
        if let executablePath, !executablePath.isEmpty {
            let components = executablePath.split(separator: "/")
            guard let leaf = components.last else { return false }
            return leaf.hasPrefix("wine")
                || components.contains { $0.hasPrefix("winetemp-") }
        }
        guard let localizedName else { return false }
        return localizedName.hasPrefix("wine")
    }

    /// Finds the regular app that contains an accessory helper bundle.
    static func embeddedHostPID(helperBundlePath: String,
                                regularBundlePaths: [pid_t: String]) -> pid_t? {
        let helperPath = URL(fileURLWithPath: helperBundlePath).standardizedFileURL.path
        return regularBundlePaths
            .filter { _, hostPath in
                let normalizedHost = URL(fileURLWithPath: hostPath).standardizedFileURL.path
                return helperPath.hasPrefix(normalizedHost + "/")
            }
            .max { lhs, rhs in lhs.value.count < rhs.value.count }?
            .key
    }

    /// Downsamples a capture into a small alpha grid for classification.
    static func alphaGrid(of image: CGImage, gridSize: Int = captureAlphaGridSize) -> [Double]? {
        guard gridSize > 0 else { return nil }
        let bytesPerPixel = 4
        var data = [UInt8](repeating: 0, count: gridSize * gridSize * bytesPerPixel)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: gridSize,
                                          height: gridSize,
                                          bitsPerComponent: 8,
                                          bytesPerRow: gridSize * bytesPerPixel,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(gridSize), height: CGFloat(gridSize)))
            return true
        }
        guard drawn else { return nil }
        return (0..<(gridSize * gridSize)).map { Double(data[$0 * bytesPerPixel + 3]) / 255.0 }
    }

    /// Whether a window capture looks like Stage Manager's strip rendering
    /// instead of real window content. Parked windows are captured as a sheared
    /// snapshot whose bounding box leaves fully transparent wedges in at least
    /// two corner/edge probes of the downsampled grid; a real window capture is
    /// opaque edge to edge (rounded corners only shave sub-cell slivers at this
    /// resolution, alpha stays well above the threshold).
    static func captureLooksTransformed(alphaGrid: [Double],
                                        gridSize: Int = captureAlphaGridSize) -> Bool {
        guard gridSize >= 4, alphaGrid.count == gridSize * gridSize else { return false }
        let last = gridSize - 1
        let mid = gridSize / 2
        let probes = [
            (0, 0), (0, last), (last, 0), (last, last),
            (0, mid), (last, mid), (mid, 0), (mid, last),
        ]
        let transparent = probes.filter { alphaGrid[$0.0 * gridSize + $0.1] < 0.05 }.count
        return transparent >= 2
    }

    /// How far the two axes of a capture may disagree before it counts as a
    /// slice of a window instead of the whole window.
    static let captureCoverageTolerance = 0.08

    /// Whether a capture holds the whole window or only the part of it that
    /// was inside a display. The window server clips a window capture to the
    /// visible region, so a window hanging over a screen edge comes back as a
    /// thin band of real content while still reporting its full size. Measured
    /// with a 620 by 452 point window: fully visible it captures 2.00 by 2.00
    /// pixels per point, hanging over the bottom edge 2.00 by 0.32, hanging
    /// past the side edge 0.19 by 2.00. Comparing the two axes catches that
    /// without caring about the display scale, so a plain screen and a Retina
    /// screen both score the same. A window with nothing to measure passes,
    /// because there is no evidence either way.
    static func captureCoversWindow(imageWidth: Int,
                                    imageHeight: Int,
                                    windowSize: CGSize,
                                    tolerance: Double = captureCoverageTolerance) -> Bool {
        guard windowSize.width.isFinite, windowSize.height.isFinite,
              windowSize.width > 1, windowSize.height > 1
        else { return true }
        let horizontal = Double(imageWidth) / Double(windowSize.width)
        let vertical = Double(imageHeight) / Double(windowSize.height)
        guard horizontal > 0, vertical > 0 else { return true }
        return max(horizontal, vertical) / min(horizontal, vertical) <= 1 + tolerance
    }

    /// Corners of the opaque quadrilateral in a capture, in top-left-origin
    /// pixel coordinates. Stage Manager's strip artwork is the real window
    /// content under a mild perspective transform; these corners feed the
    /// perspective correction that recovers an upright preview.
    struct CaptureQuadCorners: Equatable {
        var topLeft: CGPoint
        var topRight: CGPoint
        var bottomRight: CGPoint
        var bottomLeft: CGPoint
    }

    /// Finds the extreme opaque pixels of a capture's alpha channel (one byte
    /// per pixel, rows from the top). Returns nil when the opaque region is too
    /// small or degenerate to be window content.
    static func opaqueQuadCorners(alpha: [UInt8],
                                  width: Int,
                                  height: Int,
                                  threshold: UInt8 = 250) -> CaptureQuadCorners? {
        guard width > 16, height > 16, alpha.count == width * height else { return nil }
        var topLeft = (score: Int.max, x: 0, y: 0)
        var topRight = (score: Int.min, x: 0, y: 0)
        var bottomRight = (score: Int.min, x: 0, y: 0)
        var bottomLeft = (score: Int.max, x: 0, y: 0)
        var opaqueCount = 0
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where alpha[row + x] >= threshold {
                opaqueCount += 1
                let sum = x + y
                let diff = x - y
                if sum < topLeft.score { topLeft = (sum, x, y) }
                if diff > topRight.score { topRight = (diff, x, y) }
                if sum > bottomRight.score { bottomRight = (sum, x, y) }
                if diff < bottomLeft.score { bottomLeft = (diff, x, y) }
            }
        }
        guard opaqueCount >= (width * height) / 10 else { return nil }
        let spanX = max(topRight.x, bottomRight.x) - min(topLeft.x, bottomLeft.x)
        let spanY = max(bottomLeft.y, bottomRight.y) - min(topLeft.y, topRight.y)
        guard spanX >= width / 2, spanY >= height / 2 else { return nil }
        return CaptureQuadCorners(topLeft: CGPoint(x: topLeft.x, y: topLeft.y),
                                  topRight: CGPoint(x: topRight.x, y: topRight.y),
                                  bottomRight: CGPoint(x: bottomRight.x, y: bottomRight.y),
                                  bottomLeft: CGPoint(x: bottomLeft.x, y: bottomLeft.y))
    }

    /// Least-recently-used cache entries beyond `limit`, never counting ids the
    /// caller is actively refreshing as victims.
    static func staleCacheVictims(ids: Set<CGWindowID>,
                                  active: Set<CGWindowID>,
                                  lastTouched: [CGWindowID: TimeInterval],
                                  limit: Int) -> [CGWindowID] {
        let overflow = ids.count - limit
        guard overflow > 0 else { return [] }
        return ids.filter { !active.contains($0) }
            .sorted { (lastTouched[$0] ?? 0) < (lastTouched[$1] ?? 0) }
            .prefix(overflow)
            .map { $0 }
    }

    /// Least-recently-used entries to evict until the cache's total bytes fit
    /// the budget, never counting ids the caller is actively refreshing. Big
    /// thumbnails (large windows on Retina screens) would otherwise let a
    /// count-limited cache hold far more memory than intended.
    static func cacheByteBudgetVictims(sizes: [CGWindowID: Int],
                                       active: Set<CGWindowID>,
                                       lastTouched: [CGWindowID: TimeInterval],
                                       budget: Int) -> [CGWindowID] {
        var total = sizes.values.reduce(0, +)
        guard total > budget else { return [] }
        var victims: [CGWindowID] = []
        let evictable = sizes.keys.filter { !active.contains($0) }
            .sorted { (lastTouched[$0] ?? 0) < (lastTouched[$1] ?? 0) }
        for id in evictable {
            guard total > budget else { break }
            total -= sizes[id] ?? 0
            victims.append(id)
        }
        return victims
    }

    static func shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: Bool,
                                                   wasShiftHeld: Bool,
                                                   isShiftHeld: Bool) -> Bool {
        shiftIsNavigationModifier && isShiftHeld && !wasShiftHeld
    }

    static func updatedMRU(afterActivating activatedID: String,
                           previousID: String?,
                           existing: [String],
                           limit: Int = 64) -> [String] {
        var list = existing
        list.removeAll { $0 == activatedID }
        list.insert(activatedID, at: 0)
        if let previousID, previousID != activatedID {
            list.removeAll { $0 == previousID }
            list.insert(previousID, at: 1)
        }
        if list.count > limit {
            list.removeLast(list.count - limit)
        }
        return list
    }

    static func selectedPreviewPlacement(appCount rawAppCount: Int,
                                         selectedAppIndex rawSelectedAppIndex: Int,
                                         selectedWindowIndex _: Int,
                                         selectedWindowCount _: Int,
                                         visibleIconCount rawVisibleIconCount: Int,
                                         appRowContentWidth: CGFloat,
                                         appRowSurfaceWidth: CGFloat,
                                         previewContentWidth _: CGFloat,
                                         previewSurfaceWidth: CGFloat) -> SwitcherIconRowPreviewPlacement {
        let appCount = max(1, rawAppCount)
        let visibleIconCount = max(1, rawVisibleIconCount)
        let selectedAppIndex = min(max(0, rawSelectedAppIndex), appCount - 1)
        let contentWidth = max(appRowSurfaceWidth, previewSurfaceWidth)
        guard previewSurfaceWidth < contentWidth else {
            return SwitcherIconRowPreviewPlacement(contentWidth: contentWidth, leading: 0)
        }

        let rowLeading = max(0, (contentWidth - appRowSurfaceWidth) / 2) + SwitcherIconRowLayout.rowHorizontalPadding
        let selectedCenterInRow: CGFloat
        if appCount > visibleIconCount {
            selectedCenterInRow = rowLeading + appRowContentWidth / 2
        } else {
            selectedCenterInRow = rowLeading + SwitcherIconRowLayout.appTileWidth / 2
                + CGFloat(selectedAppIndex) * (SwitcherIconRowLayout.appTileWidth + SwitcherIconRowLayout.spacing)
        }

        let rawLeading = selectedCenterInRow - previewSurfaceWidth / 2
        let clampedLeading = min(max(0, rawLeading), contentWidth - previewSurfaceWidth)
        return SwitcherIconRowPreviewPlacement(contentWidth: contentWidth, leading: clampedLeading)
    }

    static func shortcutHints(for switcherShortcut: GlobalShortcut,
                              windowShortcut: GlobalShortcut) -> SwitcherShortcutHints {
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

    /// Where a session starts. `pids` is the list in display order, one entry
    /// per position the shortcut steps through: one per window in the grid,
    /// one per app in the icon row.
    ///
    /// The foreground window always sits first, so the selection starts one
    /// step past it and a single press already switches. When there is no
    /// foreground window the list holds nothing the user is looking at, except
    /// windows the front app left minimized or on another Space; those are
    /// skipped for the same reason, so one press still lands somewhere else.
    static func initialSelectionPosition(pids: [pid_t],
                                         hasForegroundEntry: Bool,
                                         frontmostPID: pid_t?,
                                         reversed: Bool) -> Int {
        guard !pids.isEmpty else { return 0 }
        if reversed { return pids.count - 1 }
        guard hasForegroundEntry else {
            return pids.firstIndex { $0 != frontmostPID } ?? 0
        }
        return pids.count > 1 ? 1 : 0
    }

    /// Moves between rows without wrapping. When the row below is shorter,
    /// Down lands on that row's last item instead of leaving the selection in
    /// place because the same column is missing.
    static func gridSelectionIndex(after selectedIndex: Int,
                                   itemCount: Int,
                                   columns: Int,
                                   movingDown: Bool) -> Int {
        guard itemCount > 0 else { return 0 }
        let current = min(max(0, selectedIndex), itemCount - 1)
        let safeColumns = max(1, columns)

        guard movingDown else {
            let target = current - safeColumns
            return target >= 0 ? target : current
        }

        let nextRowStart = (current / safeColumns + 1) * safeColumns
        guard nextRowStart < itemCount else { return current }
        return min(current + safeColumns, itemCount - 1)
    }

    /// With wrapping off (key held on autorepeat, like the system switcher)
    /// the selection stops at either end instead of cycling around.
    static func nextAppSelectionIndex(items: [SwitcherItem],
                                      selectedIndex: Int,
                                      delta: Int,
                                      wrapping: Bool = true) -> Int {
        let groups = appGroups(items: items)
        guard !groups.isEmpty else { return 0 }
        guard items.indices.contains(selectedIndex) else {
            return groups[0].representativeIndex
        }

        let selectedID = items[selectedIndex].id
        let currentGroupIndex = groups.firstIndex { $0.itemIDs.contains(selectedID) } ?? 0
        let unwrapped = currentGroupIndex + delta
        if !wrapping, !groups.indices.contains(unwrapped) {
            return groups[currentGroupIndex].representativeIndex
        }
        let targetGroupIndex = (unwrapped + groups.count) % groups.count
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

    static func shouldContinueAppActivationRetry(targetPID: pid_t,
                                                 sourcePID: pid_t?,
                                                 frontmostPID: pid_t?,
                                                 targetWasObservedFrontmost: Bool,
                                                 ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        if frontmostPID == targetPID { return true }
        guard !targetWasObservedFrontmost else { return false }
        guard let frontmostPID else { return true }
        return frontmostPID == sourcePID || frontmostPID == ownPID
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
