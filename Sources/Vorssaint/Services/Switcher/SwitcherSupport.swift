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

/// What a letter typed with the panel open does. Anything else goes to search.
enum SwitcherLetterAction: Equatable {
    case closeWindow
    case quitApp
    case pinSearch
}

/// Whether a switcher session lists every app or only the frontmost app's windows.
enum SwitcherSessionScope: Equatable {
    case allApps
    case frontmostApp
}

/// How a key arriving before the asynchronous window list is ready is owned.
enum SwitcherPendingKeyDecision: Equatable {
    case handleActiveSession
    case routeShortcut
    case swallow
    case cancelAndSwallow
}

/// Which running apps earn an entry of their own when they have no window the
/// switcher can show. The switcher lists windows, so an app that closed all of
/// them disappears from it while the system switcher still offers it.
enum SwitcherWindowlessApps: String, CaseIterable, Equatable {
    /// Windows only.
    case off
    /// The desktop app alone, which is always running and often has no window.
    case finder
    /// Every running app, the way the system switcher lists them.
    case all

    static let fallback = SwitcherWindowlessApps.finder

    /// Preferences are stored as plain strings, so an unknown or missing value
    /// resolves to the behavior the app shipped with instead of nothing.
    static func mode(storedValue: String?) -> SwitcherWindowlessApps {
        guard let storedValue, let mode = SwitcherWindowlessApps(rawValue: storedValue) else {
            return fallback
        }
        return mode
    }

    /// The value that carries the old on/off preference over unchanged: the
    /// desktop app kept its entry, anything else stayed windows only.
    static func migrated(showsWindowlessFinder: Bool) -> SwitcherWindowlessApps {
        showsWindowlessFinder ? .finder : .off
    }
}

/// A per-app override for the switcher's regular window and windowless-app
/// choices. Apps without an override keep following `SwitcherWindowlessApps`.
enum SwitcherAppRule: String, CaseIterable, Equatable {
    case showWithoutWindows
    case windowsOnly
    case hidden

    static func rules(storedValue: [String: Any]?) -> [String: SwitcherAppRule] {
        guard let storedValue else { return [:] }
        var rules: [String: SwitcherAppRule] = [:]
        for rawBundleID in storedValue.keys.sorted() {
            let bundleID = rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty,
                  let rawRule = storedValue[rawBundleID] as? String,
                  let rule = SwitcherAppRule(rawValue: rawRule)
            else { continue }
            rules[bundleID] = rule
        }
        return rules
    }

    static func storedValue(_ rules: [String: SwitcherAppRule]) -> [String: String] {
        var stored: [String: String] = [:]
        for (rawBundleID, rule) in rules {
            let bundleID = rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty else { continue }
            stored[bundleID] = rule.rawValue
        }
        return stored
    }
}

/// A running app considered for an entry of its own, with the identity the
/// choice above is decided on.
struct SwitcherAppCandidate: Equatable {
    let pid: pid_t
    let bundleIdentifier: String?
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
    let simpleTitleSurfaceWidth: CGFloat
    let panelSize: CGSize
    let showsShortcutHints: Bool

    static var scale: CGFloat { min(PreviewSizing.scale, 1.15) }
    static var iconSize: CGFloat { 68 * scale }
    static var selectedIconSize: CGFloat { 78 * scale }
    static let iconTileSpacing: CGFloat = 5
    static let iconTitleHeight: CGFloat = 14
    static let iconTileVerticalPadding: CGFloat = 5
    static let iconTileVerticalMargin: CGFloat = 3
    static var iconLabelWidth: CGFloat { max(selectedIconSize + 12, 86 * scale) }
    /// Text and padding stay legible instead of shrinking with preview size, so
    /// the row follows the tile's real height and never clips its selection.
    static var rowHeight: CGFloat {
        selectedIconSize + iconTileSpacing + iconTitleHeight
            + 2 * (iconTileVerticalPadding + iconTileVerticalMargin)
    }
    static var appTileWidth: CGFloat { iconLabelWidth + 12 }
    static var windowLabelWidth: CGFloat { 120 * scale }
    static var windowTileWidth: CGFloat { windowLabelWidth + 12 }
    static var previewCardWidth: CGFloat { 220 * scale }
    static var previewCardHeight: CGFloat { 164 * scale }
    static var appEntryIconSize: CGFloat { 66 * scale }
    static var appEntrySpacing: CGFloat { 7 * scale }
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
    static var simpleTitlePanelPadding: CGFloat { 10 * scale }
    static let simpleTitleSpacing: CGFloat = 6
    static let simpleTitleScrollPadding: CGFloat = 1

    /// App-only mode keeps the same icon row and shortcut preference, but
    /// removes the entire preview area so no blank space remains where captures were.
    var simplePanelSize: CGSize {
        CGSize(width: max(appRowSurfaceWidth,
                          simpleTitleSurfaceWidth,
                          showsShortcutHints ? Self.hintBarWidth : 0) + Self.padding * 2,
               height: Self.simpleTitleHeight + Self.simpleTitleGap
                        + Self.rowHeight + shortcutHintHeight
                        + Self.padding * 2)
    }

    /// A flat window row names every entry under its icon, so it needs no
    /// separate title strip above the row.
    var simpleWindowPanelSize: CGSize {
        CGSize(width: max(appRowSurfaceWidth,
                          showsShortcutHints ? Self.hintBarWidth : 0) + Self.padding * 2,
               height: Self.rowHeight + shortcutHintHeight + Self.padding * 2)
    }

    private var shortcutHintHeight: CGFloat {
        showsShortcutHints ? Self.hintGap + Self.hintHeight : 0
    }

    static let empty = SwitcherIconRowLayout(visibleIconCount: 1,
                                             appRowContentWidth: 0,
                                             appRowSurfaceWidth: 0,
                                             previewContentWidth: 0,
                                             previewSurfaceWidth: 0,
                                             simpleTitleSurfaceWidth: 0,
                                             panelSize: .zero,
                                             showsShortcutHints: true)

    static func compute(appCount rawAppCount: Int,
                        selectedWindowCount rawWindowCount: Int,
                        screenVisibleFrame: CGRect,
                        showsShortcutHints: Bool = true,
                        tileWidth: CGFloat = appTileWidth) -> SwitcherIconRowLayout {
        let appCount = max(1, rawAppCount)
        let windowCount = max(1, rawWindowCount)
        let usableWidth = max(320, screenVisibleFrame.width * 0.96)
        let maxContentWidth = max(tileWidth, usableWidth - padding * 2)
        let naturalAppRowWidth = CGFloat(appCount) * tileWidth + CGFloat(max(0, appCount - 1)) * spacing
        let naturalPreviewWidth = CGFloat(windowCount) * previewCardWidth
            + CGFloat(max(0, windowCount - 1)) * spacing
        let maxAppContentWidth = max(tileWidth, maxContentWidth - rowHorizontalPadding * 2)
        let maxPreviewContentWidth = max(previewCardWidth, maxContentWidth - previewPanelPadding * 2)
        let appRowWidth = min(naturalAppRowWidth, maxAppContentWidth)
        let appRowSurfaceWidth = min(appRowWidth + rowHorizontalPadding * 2, maxContentWidth)
        let previewWidth = min(max(previewCardWidth, naturalPreviewWidth), maxPreviewContentWidth)
        let previewSurfaceWidth = min(previewWidth + previewPanelPadding * 2, maxContentWidth)
        let naturalSimpleTitleWidth = CGFloat(windowCount) * simpleTitleChipMaxWidth
            + CGFloat(max(0, windowCount - 1)) * simpleTitleSpacing
            + simpleTitleScrollPadding * 2
            + simpleTitlePanelPadding * 2
        let simpleTitleSurfaceWidth = min(naturalSimpleTitleWidth, maxContentWidth)
        let hintWidth = showsShortcutHints ? min(hintBarWidth, maxContentWidth) : 0
        let contentWidth = min(max(appRowSurfaceWidth, previewSurfaceWidth, hintWidth), maxContentWidth)
        let visibleIconCount = max(1, min(appCount, Int((maxAppContentWidth + spacing) / (tileWidth + spacing))))
        let width = contentWidth + padding * 2
        let shortcutHintHeight = showsShortcutHints ? hintGap + hintHeight : 0
        let height = previewHeight + previewGap + rowHeight + shortcutHintHeight + padding * 2
        return SwitcherIconRowLayout(visibleIconCount: visibleIconCount,
                                     appRowContentWidth: appRowWidth,
                                     appRowSurfaceWidth: appRowSurfaceWidth,
                                     previewContentWidth: previewWidth,
                                     previewSurfaceWidth: previewSurfaceWidth,
                                     simpleTitleSurfaceWidth: simpleTitleSurfaceWidth,
                                     panelSize: CGSize(width: width, height: height),
                                     showsShortcutHints: showsShortcutHints)
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

    static func firstValuesByPID<Value>(_ pairs: [(pid_t, Value)]) -> [pid_t: Value] {
        Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    static func usesIconRowLayout(iconRowMode: Bool, simpleMode: Bool) -> Bool {
        iconRowMode || simpleMode
    }

    static func capturesPreviews(simpleMode: Bool) -> Bool {
        !simpleMode
    }

    /// The simple switcher follows the existing one-entry-per-app choice.
    /// With grouping off, its icon row represents windows directly.
    static func usesWindowRow(simpleMode: Bool, mergeWindowsByApp: Bool) -> Bool {
        simpleMode && !mergeWindowsByApp
    }

    static func usesAppGroupsForMainShortcut(iconRowLayout: Bool,
                                              windowRow: Bool) -> Bool {
        iconRowLayout && !windowRow
    }

    static func shouldPausePreviewCapture(frontmostBundleIdentifier: String?,
                                          excludedBundleIdentifiers: [String]) -> Bool {
        guard let frontmostBundleIdentifier else { return false }
        return excludedBundleIdentifiers.contains(frontmostBundleIdentifier)
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

    /// Keeps only the windows belonging to the app that owns the keyboard.
    static func frontmostAppWindows(allItems: [SwitcherItem], frontmostPID: pid_t) -> [SwitcherItem] {
        let appPID = appPID(forFrontmost: frontmostPID, items: allItems)
        return allItems.filter { $0.pid == appPID }
    }

    /// Where a window-scoped session starts. The foreground window sits first,
    /// so index 1 is the next window to switch to; a lone window stays at 0.
    static func initialWindowScopedSelectionIndex(itemCount: Int,
                                                  hasForegroundItem: Bool,
                                                  reversed: Bool) -> Int {
        guard itemCount > 0 else { return 0 }
        if reversed { return itemCount - 1 }
        guard hasForegroundItem else { return 0 }
        return itemCount > 1 ? 1 : 0
    }

    /// Shift means backward only for a physical-key match. Some keyboard
    /// layouts need Shift merely to type the shortcut's displayed character.
    static func windowNavigationDelta(positionalMatch: Bool,
                                      shiftIsNavigationModifier: Bool,
                                      shiftHeld: Bool) -> Int {
        positionalMatch && shiftIsNavigationModifier && shiftHeld ? -1 : 1
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

    /// Some professional media apps expose their main surface as a floating
    /// Accessibility window instead of a standard macOS window. Match bundle
    /// prefixes because recent releases append version or application suffixes.
    static func isSupportedMediaFloatingWindow(bundleIdentifier: String?, subrole: String?) -> Bool {
        guard subrole == "AXFloatingWindow", let bundleIdentifier else { return false }
        return bundleIdentifier.hasPrefix("com.adobe.Audition")
            || bundleIdentifier.hasPrefix("com.adobe.AfterEffects")
            || bundleIdentifier.hasPrefix("com.adobe.PremierePro")
    }

    /// Some full-screen playback surfaces keep a nonstandard Accessibility
    /// subrole. A screen-sized AX window is still a real switch target, while
    /// smaller utility surfaces remain filtered. Compatibility-hosted windows
    /// retain their existing role-based exception at every size.
    static func isSwitchableNonstandardWindow(role: String?,
                                              subrole: String?,
                                              fillsScreen: Bool,
                                              acceptsUndescribedSubroles: Bool) -> Bool {
        guard role == "AXWindow" else { return false }
        if acceptsUndescribedSubroles && subrole == "AXUnknown" { return true }
        return fillsScreen && (subrole == "AXUnknown" || subrole == "AXFloatingWindow")
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

    /// Picks the processes queried through Accessibility when the switcher
    /// opens. Every embedded helper stays eligible because Accessibility can be
    /// the only source for its fullscreen window on another desktop; the
    /// enumerator overlaps these remote queries so slow helpers do not stack.
    static func accessibilityPIDs(regularAppPIDs: Set<pid_t>,
                                  embeddedHostPIDs: [pid_t: pid_t],
                                  ownPID: pid_t,
                                  filterPID: pid_t?) -> Set<pid_t> {
        if let filterPID {
            let embeddedPIDs = embeddedHostPIDs.compactMap { ownerPID, hostPID in
                hostPID == filterPID ? ownerPID : nil
            }
            return Set([filterPID] + embeddedPIDs)
        }
        return regularAppPIDs.union(embeddedHostPIDs.keys).subtracting([ownPID])
    }

    /// Picks the running apps that earn an entry of their own because the
    /// window list has nothing for them.
    ///
    /// Only a total absence counts. An app whose windows exist but were left
    /// out on purpose keeps its absence: showing the app anyway would undo the
    /// choice the user just made, which is what the current-desktop option
    /// (issue #337) would suffer from otherwise. Order follows the candidate
    /// list, so the caller keeps ranking these entries the same way it ranks
    /// windows.
    static func windowlessAppPIDs(mode: SwitcherWindowlessApps,
                                  candidates: [SwitcherAppCandidate],
                                  pidsWithWindows: Set<pid_t>,
                                  pidsWithWithheldWindows: Set<pid_t>,
                                  desktopAppBundleIdentifier: String,
                                  appRules: [String: SwitcherAppRule] = [:]) -> [pid_t] {
        return candidates.compactMap { candidate in
            guard !pidsWithWindows.contains(candidate.pid),
                  !pidsWithWithheldWindows.contains(candidate.pid)
            else { return nil }
            if let bundleIdentifier = candidate.bundleIdentifier,
               let rule = appRules[bundleIdentifier] {
                switch rule {
                case .showWithoutWindows:
                    return candidate.pid
                case .windowsOnly, .hidden:
                    return nil
                }
            }
            switch mode {
            case .off:
                return nil
            case .finder:
                return candidate.bundleIdentifier == desktopAppBundleIdentifier ? candidate.pid : nil
            case .all:
                return candidate.pid
            }
        }
    }

    static func hidesApp(bundleIdentifier: String?,
                         appRules: [String: SwitcherAppRule]) -> Bool {
        guard let bundleIdentifier else { return false }
        return appRules[bundleIdentifier] == .hidden
    }

    /// When Accessibility does not match a hidden app's WindowServer surface,
    /// its Space assignment distinguishes a real window from a leftover.
    static func isConfirmedHiddenAppWindow(appIsHidden: Bool,
                                           windowSpaces: [UInt64]) -> Bool {
        appIsHidden && !windowSpaces.isEmpty
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
                                              sourceWindowID: UInt32?,
                                              ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard let sourcePID,
              sourcePID != targetPID,
              sourcePID != ownPID,
              sourceWindowID != nil else { return false }
        return true
    }

    static func shouldContinueFocusRetry(targetPID: pid_t,
                                         sourcePID: pid_t?,
                                         frontmostPID: pid_t?,
                                         targetIsMinimized: Bool,
                                         targetStartedMinimized: Bool,
                                         targetWasObservedRestored: Bool = false,
                                         ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard !targetIsMinimized
                || (targetStartedMinimized && !targetWasObservedRestored)
        else { return false }
        guard let sourcePID,
              let frontmostPID else { return true }
        return frontmostPID == targetPID || frontmostPID == sourcePID || frontmostPID == ownPID
    }

    /// Async results belong only to the still-pending shortcut press. A key
    /// release may turn that pending start into an immediate commit, while a
    /// teardown or a newer press clears/replaces the generation entirely.
    static func isCurrentSessionStart(generation: UInt64,
                                      pendingGeneration: UInt64?) -> Bool {
        pendingGeneration == generation
    }

    static func pendingKeyDecision(sessionIsActive: Bool,
                                   hasPendingStart: Bool,
                                   commitWhenReady: Bool,
                                   matchesShortcut: Bool) -> SwitcherPendingKeyDecision {
        if sessionIsActive { return .handleActiveSession }
        guard hasPendingStart, !matchesShortcut else { return .routeShortcut }
        return commitWhenReady ? .cancelAndSwallow : .swallow
    }

    static func isCurrentActivationGeneration(_ scheduled: UInt64,
                                              current: UInt64) -> Bool {
        scheduled == current
    }

    static func shouldRestoreHiddenApp(revealGeneration: UInt64,
                                       currentGeneration: UInt64,
                                       appWasReactivated: Bool) -> Bool {
        revealGeneration == currentGeneration && !appWasReactivated
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

    /// Which entry a release should raise while windows are already closing:
    /// the highlight lands where the grid settles once they are gone, so
    /// letting go right after closing one never raises it again. With nothing
    /// left to raise, the release only dismisses the panel.
    static func commitTargetID(itemIDs: [String],
                               selectedIndex: Int,
                               closingItemIDs: Set<String>) -> String? {
        guard itemIDs.indices.contains(selectedIndex) else { return nil }
        let selected = itemIDs[selectedIndex]
        guard closingItemIDs.contains(selected) else { return selected }
        let remaining = itemIDs.filter { !closingItemIDs.contains($0) }
        guard !remaining.isEmpty else { return nil }
        let position = itemIDs[..<selectedIndex].filter { !closingItemIDs.contains($0) }.count
        return remaining[clampedSelection(position, count: remaining.count)]
    }

    /// Whether a click ends the session. The panel floats above everything and
    /// never takes the keyboard from the app in front, so clicking another
    /// window is what most people try when they want it gone, and a session
    /// opened with no key held down has no release coming to close it either
    /// (issue #384). Anything on the panel still belongs to the panel.
    static func shouldDismissForClick(panelIsVisible: Bool,
                                      panelFrame: CGRect,
                                      location: CGPoint) -> Bool {
        panelIsVisible && !panelFrame.contains(location)
    }

    /// The letters the panel acts on: W closes the highlighted window, Q quits
    /// its app, and, when `pinSearchEnabled`, S pins the search field open so
    /// it no longer needs the session's modifier held to stay on screen — that
    /// modifier is what turns some keys into special characters instead of
    /// plain letters, e.g. ⌥S types "ß". S is opt-in: existing users who type it as
    /// the first letter of a search keep filtering by "s" until they turn the
    /// preference on. A keyboard answers by the letter it types, so all three
    /// keys stay where they are printed even on layouts that move them
    /// (measured: French and Italian put W elsewhere, Turkish moves both).
    /// Layouts that type no Latin letter at all, like Cyrillic and Greek, go
    /// by the key's position instead, which is exactly where macOS resolves
    /// their command shortcuts (measured: with Command held both translate
    /// that key to "w").
    static func letterAction(typedCharacter: String?, keyCode: Int64, pinSearchEnabled: Bool) -> SwitcherLetterAction? {
        guard let letter = latinLetter(in: typedCharacter) else {
            switch keyCode {
            case USKeyPosition.w: return .closeWindow
            case USKeyPosition.q: return .quitApp
            case USKeyPosition.s where pinSearchEnabled: return .pinSearch
            default: return nil
            }
        }
        switch letter {
        case "w": return .closeWindow
        case "q": return .quitApp
        case "s" where pinSearchEnabled: return .pinSearch
        default:
            // ⌥ turns S into "ß", and adding Caps Lock on top turns it into
            // "Í" instead — a real, differently-accented letter that folds to
            // an unrelated "i" rather than failing to fold at all, so the S
            // case above never sees it. Fall back to the key position only when
            // the original typed character is non-ASCII, to avoid triggering on
            // remapped Latin layouts where the US-S key types another ASCII letter.
            if pinSearchEnabled,
               keyCode == USKeyPosition.s,
               let typed = typedCharacter,
               !typed.unicodeScalars.allSatisfy({ $0.isASCII }) {
                return .pinSearch
            }
            return nil
        }
    }

    /// Key positions on the US keyboard, the fallback for layouts with no
    /// Latin letters of their own.
    private enum USKeyPosition {
        static let q: Int64 = 12
        static let w: Int64 = 13
        static let s: Int64 = 1
    }

    /// The plain letter a keystroke typed, when it typed one. Accents fold
    /// away, so a letter of a Latin alphabet is never mistaken for one of the
    /// keys above.
    private static func latinLetter(in text: String?) -> Character? {
        guard let folded = text?.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                         locale: .current),
              folded.count == 1,
              let letter = folded.first,
              letter.isASCII,
              letter.isLetter
        else { return nil }
        return letter
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
